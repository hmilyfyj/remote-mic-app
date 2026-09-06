import Foundation

/// Serialized on the main run loop, including injected callbacks and timers.
final class SourceMicrophoneSessionController {
    enum Mode { case hold, tap }
    enum Phase: String { case idle, switching, waiting, starting, active, draining, stopping, restoring }

    struct RecoveryRecord: Codable, Equatable {
        let previousUID: String
        let targetUID: String
    }

    struct Playback {
        let pendingSamples: Int
        let interruptedSamples: Int
        let healthy: Bool
    }

    struct Environment {
        var currentInput: () -> String?
        var availableInputs: () -> [String]
        var fallbackInput: (String) -> String?
        var selectInput: (String) -> Bool
        var readRecovery: () -> RecoveryRecord?
        var writeRecovery: (RecoveryRecord?) -> Bool
        var setFn: (Bool) -> Bool
        var enqueue: ([Int16]) -> Bool
        var playback: () -> Playback
        var interruptAudio: () -> Void
        var waitForDestination: (@escaping (Bool) -> Void) -> (() -> Void)
        var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        var schedule: (TimeInterval, @escaping () -> Void) -> (() -> Void) = { delay, operation in
            let item = DispatchWorkItem(block: operation)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return { item.cancel() }
        }
        var log: (String) -> Void
        var finished: (String) -> Void
    }

    private let environment: Environment
    private(set) var phase: Phase = .idle
    private(set) var generation = 0
    private var owner: UUID?
    private var mode: Mode = .hold
    private var record: RecoveryRecord?
    private var restoreUID: String?
    private var restoreAllowed = true
    private var remoteEnded = false
    private var fnDown = false
    private var toolStarted = false
    private var toolStateUncertain = false
    private var switchConfirmed = false
    private var preRoll: [Int16] = []
    private var receivedSamples = 0
    private var scheduledSamples = 0
    private var interruptedAtStart = 0
    private var startedAt: TimeInterval = 0
    private var deadline: TimeInterval = 0
    private var finalReason = "completed"
    private var cancellations: [() -> Void] = []
    private let maximumPreRollSamples = 80_000
    private struct PendingSession {
        let device: UUID
        let targetUID: String
        let mode: Mode
        var samples: [Int16] = []
        var ended = false
    }
    private var pendingSession: PendingSession?

    var isBusy: Bool { phase != .idle }
    var hasPendingVoice: Bool { pendingSession != nil }

    init(environment: Environment) { self.environment = environment }

    func owns(_ device: UUID) -> Bool { owner == device && isBusy }

    @discardableResult
    func start(device: UUID, targetUID: String, mode: Mode, externalVoiceBusy: Bool) -> Bool {
        if isBusy, owner == device, remoteEnded, pendingSession == nil,
           finalReason == "completed", !externalVoiceBusy {
            pendingSession = PendingSession(device: device, targetUID: targetUID, mode: mode)
            log("phase=queued source=remote reason=previous_session_finishing")
            return true
        }
        guard !isBusy, !fnDown, !toolStateUncertain, !externalVoiceBusy else {
            log("phase=rejected reason=source_busy source=remote")
            return false
        }
        // An unresolved restore is retried before taking another microphone lease.
        guard environment.readRecovery() == nil else {
            recoverAfterLaunch()
            log("phase=rejected reason=recovery_pending source=remote")
            return false
        }
        guard let previousUID = environment.currentInput(),
              environment.availableInputs().contains(targetUID) else {
            log("phase=rejected reason=input_unavailable source=remote")
            return false
        }
        generation += 1
        owner = device
        self.mode = mode
        record = RecoveryRecord(previousUID: previousUID, targetUID: targetUID)
        restoreAllowed = true
        remoteEnded = false
        toolStarted = false
        switchConfirmed = false
        receivedSamples = 0
        scheduledSamples = 0
        interruptedAtStart = environment.playback().interruptedSamples
        startedAt = environment.now()
        deadline = startedAt + 1
        finalReason = "completed"
        phase = .switching
        log("phase=requested source=remote mode=\(mode == .tap ? "tap" : "hold")")
        guard environment.writeRecovery(record) else {
            finalReason = "recovery_write_failed"
            finish()
            return true
        }
        guard previousUID == targetUID || environment.selectInput(targetUID) else {
            cancel(reason: "switch_failed")
            return true
        }
        confirmSwitch()
        later(after: 120) { $0.cancel(reason: "session_timeout") }
        return true
    }

    func receive(_ samples: [Int16], device: UUID) {
        if pendingSession?.device == device {
            guard pendingSession?.ended == false else { return }
            guard (pendingSession?.samples.count ?? 0) + samples.count <= maximumPreRollSamples else {
                cancel(reason: "pending_voice_overflow", additionalInterruptedSamples: samples.count)
                return
            }
            pendingSession?.samples.append(contentsOf: samples)
            return
        }
        guard owns(device), !remoteEnded, !samples.isEmpty else { return }
        receivedSamples += samples.count
        if receivedSamples == samples.count {
            log("phase=first_pcm session_start_to_first_pcm_ms=\(elapsedMilliseconds) trigger_down_to_first_pcm_ms=unknown trigger_down_to_first_transcript_observation_ms=unknown")
        }
        switch phase {
        case .switching, .waiting, .starting:
            guard preRoll.count + samples.count <= maximumPreRollSamples else {
                cancel(reason: "pre_roll_overflow")
                return
            }
            preRoll.append(contentsOf: samples)
        case .active:
            output(samples)
        default:
            break
        }
    }

    func stop(device: UUID) {
        if pendingSession?.device == device {
            pendingSession?.ended = true
            return
        }
        guard owns(device), !remoteEnded else { return }
        remoteEnded = true
        log("phase=remote_stopped")
        if phase == .active { beginDrain() }
    }

    /// Called on a default-input/device-list notification, and during active polling.
    func inputChanged() {
        guard isBusy, let record, phase != .restoring else { return }
        let current = environment.currentInput()
        if current == record.targetUID { return }
        if phase == .switching, current == record.previousUID { return }
        if current == nil, !environment.availableInputs().contains(record.targetUID) {
            cancel(reason: "target_unavailable")
            return
        }
        // Retain the user's new default even when it happens to return to the target later.
        restoreAllowed = false
        _ = environment.writeRecovery(nil)
        cancel(reason: "input_changed")
    }

    func cancel(reason: String, additionalInterruptedSamples: Int = 0) {
        guard isBusy else { return }
        if phase == .restoring {
            let queued = (pendingSession?.samples.count ?? 0) + additionalInterruptedSamples
            pendingSession = nil
            finalReason = reason
            log("phase=queued_cancelled completion=forced reason=\(reason) audio_interrupted_samples=\(queued)")
            return
        }
        finalReason = reason
        cancelTasks()
        let pending = environment.playback().pendingSamples
        let queued = pendingSession?.samples.count ?? 0
        pendingSession = nil
        log("phase=cancelled completion=forced reason=\(reason) audio_interrupted_samples=\(max(0, receivedSamples - scheduledSamples) + pending + queued + additionalInterruptedSamples)")
        preRoll.removeAll()
        if pending > 0 { environment.interruptAudio() }
        stopTool()
    }

    /// Termination cannot wait for the run loop. Preserve an unconfirmed restore for launch.
    func shutdown() {
        guard isBusy || fnDown else { return }
        cancelTasks()
        finalReason = "app_stop"
        let queued = pendingSession?.samples.count ?? 0
        pendingSession = nil
        log("phase=cancelled completion=forced reason=app_stop audio_interrupted_samples=\(max(0, receivedSamples - scheduledSamples) + environment.playback().pendingSamples + queued)")
        environment.interruptAudio()
        if fnDown {
            fnDown = !environment.setFn(false)
            if mode == .tap, phase == .starting { toolStarted = true }
            if mode == .tap, phase == .stopping { toolStarted = false }
        }
        if mode == .tap, toolStarted {
            let down = environment.setFn(true)
            let up = environment.setFn(false)
            if !down || !up { finalReason = "stop_failed" }
        }
        if let record, restoreAllowed, environment.currentInput() == record.targetUID,
           let target = restorationTarget(record) {
            _ = environment.selectInput(target)
            if environment.currentInput() == target { _ = environment.writeRecovery(nil) }
        } else if phase != .restoring {
            _ = environment.writeRecovery(nil)
        }
        finish()
    }

    func recoverAfterLaunch() {
        guard !isBusy, let record = environment.readRecovery() else { return }
        guard environment.currentInput() == record.targetUID else {
            _ = environment.writeRecovery(nil)
            log("phase=recovered reason=current_input_preserved")
            return
        }
        generation += 1
        self.record = record
        switchConfirmed = true
        restoreAllowed = true
        finalReason = "launch_recovery"
        startedAt = environment.now()
        beginRestore()
    }

    private func confirmSwitch() {
        guard phase == .switching, let record else { return }
        if environment.currentInput() == record.targetUID {
            switchConfirmed = true
            phase = .waiting
            log("phase=switched elapsed_ms=\(elapsedMilliseconds)")
            let operation = generation
            let cancelWait = environment.waitForDestination { [weak self] ready in
                guard let self, self.generation == operation, self.phase == .waiting else { return }
                guard ready else { self.cancel(reason: "destination_cancelled"); return }
                self.startTool()
            }
            cancellations.append(cancelWait)
            later(after: 3) { controller in
                if controller.phase == .waiting { controller.cancel(reason: "destination_timeout") }
            }
        } else if environment.now() >= deadline {
            cancel(reason: "switch_timeout")
        } else {
            inputChanged()
            if phase == .switching { later(after: 0.01) { $0.confirmSwitch() } }
        }
    }

    private func startTool() {
        inputChanged()
        guard phase == .waiting else { return }
        phase = .starting
        guard environment.setFn(true) else { cancel(reason: "start_failed"); return }
        fnDown = true
        log("phase=trigger_submitted external_capture=unknown")
        if mode == .tap {
            later(after: 0.12) { controller in
                guard controller.phase == .starting else { return }
                guard controller.environment.setFn(false) else {
                    controller.cancel(reason: "start_release_failed")
                    return
                }
                controller.fnDown = false
                controller.toolStarted = true
                controller.activate()
            }
        } else {
            toolStarted = true
            activate()
        }
    }

    private func activate() {
        guard phase == .starting else { return }
        inputChanged()
        guard phase == .starting else { return }
        phase = .active
        let samples = preRoll
        preRoll.removeAll()
        if !samples.isEmpty { output(samples) }
        guard phase == .active else { return }
        if remoteEnded { beginDrain() } else { monitorActiveSession() }
    }

    private func output(_ samples: [Int16]) {
        guard environment.enqueue(samples) else { cancel(reason: "enqueue_failed"); return }
        scheduledSamples += samples.count
    }

    private func monitorActiveSession() {
        guard phase == .active else { return }
        inputChanged()
        guard phase == .active else { return }
        guard playbackHealthy else { cancel(reason: "audio_interrupted"); return }
        later(after: 0.05) { $0.monitorActiveSession() }
    }

    private func beginDrain() {
        phase = .draining
        deadline = environment.now() + 6
        log("phase=draining audio_received_samples=\(receivedSamples) audio_scheduled_samples=\(scheduledSamples)")
        checkDrain()
    }

    private func checkDrain() {
        guard phase == .draining else { return }
        inputChanged()
        guard phase == .draining else { return }
        guard playbackHealthy else { cancel(reason: "audio_interrupted"); return }
        if environment.playback().pendingSamples == 0 {
            log("phase=drained audio_pending_samples=0 audio_interrupted_samples=0")
            stopTool()
        } else if environment.now() >= deadline {
            cancel(reason: "drain_timeout")
        } else {
            later(after: 0.01) { $0.checkDrain() }
        }
    }

    private var playbackHealthy: Bool {
        let state = environment.playback()
        return state.healthy && state.interruptedSamples == interruptedAtStart
    }

    private func stopTool() {
        let previousPhase = phase
        phase = .stopping
        if fnDown {
            let released = environment.setFn(false)
            fnDown = !released
            if !released {
                later(after: 0.05) { controller in
                    controller.fnDown = !controller.environment.setFn(false)
                    if controller.fnDown {
                        controller.finalReason = "stop_failed"
                        controller.beginRestore()
                    } else {
                        if controller.mode == .tap, previousPhase == .starting { controller.toolStarted = true }
                        if controller.mode == .tap, previousPhase == .stopping { controller.toolStarted = false }
                        controller.stopTool()
                    }
                }
                return
            }
            if mode == .tap, previousPhase == .starting { toolStarted = true }
            if mode == .tap, previousPhase == .stopping { toolStarted = false }
        }
        if mode == .tap, toolStarted {
            guard environment.setFn(true) else {
                finalReason = "stop_failed"
                beginRestore()
                return
            }
            fnDown = true
            later(after: 0.12) { controller in
                guard controller.phase == .stopping else { return }
                controller.fnDown = !controller.environment.setFn(false)
                if controller.fnDown {
                    controller.finalReason = "stop_failed"
                    controller.fnDown = !controller.environment.setFn(false)
                }
                controller.toolStarted = false
                controller.beginRestore()
            }
        } else {
            toolStarted = false
            beginRestore()
        }
    }

    private func beginRestore() {
        phase = .restoring
        cancelTasks()
        guard let record else { finish(); return }
        let current = environment.currentInput()
        let inputWasLost = current == nil && !environment.availableInputs().contains(record.targetUID)
        let switchUnconfirmed = !switchConfirmed && current == record.previousUID
        guard restoreAllowed, current == record.targetUID || inputWasLost || switchUnconfirmed else {
            _ = environment.writeRecovery(nil)
            log("phase=restore_skipped reason=current_input_preserved")
            finish()
            return
        }
        guard let target = restorationTarget(record) else {
            finalReason = "restore_unavailable"
            finish()
            return
        }
        restoreUID = target
        deadline = environment.now() + 1
        if target != record.previousUID { log("phase=restoring reason=original_unavailable fallback=true") }
        guard environment.selectInput(target) else {
            finalReason = "restore_failed"
            finish()
            return
        }
        confirmRestore()
    }

    private func confirmRestore() {
        guard phase == .restoring, let record, let restoreUID else { return }
        let current = environment.currentInput()
        if current == restoreUID {
            _ = environment.writeRecovery(nil)
            log("phase=restored fallback=\(restoreUID != record.previousUID)")
            if restoreUID != record.previousUID, finalReason == "completed" { finalReason = "fallback_restored" }
            finish()
        } else if let current, current != record.targetUID {
            _ = environment.writeRecovery(nil)
            log("phase=restore_skipped reason=current_input_preserved")
            finalReason = "input_changed"
            finish()
        } else if environment.now() >= deadline {
            finalReason = "restore_timeout"
            finish()
        } else {
            later(after: 0.01) { $0.confirmRestore() }
        }
    }

    private func restorationTarget(_ record: RecoveryRecord) -> String? {
        environment.availableInputs().contains(record.previousUID)
            ? record.previousUID : environment.fallbackInput(record.targetUID)
    }

    private func finish() {
        cancelTasks()
        if finalReason == "stop_failed" { toolStateUncertain = true }
        if finalReason != "completed", finalReason != "fallback_restored", let pendingSession {
            log("phase=queued_cancelled completion=forced reason=previous_session_failed audio_interrupted_samples=\(pendingSession.samples.count)")
            self.pendingSession = nil
        }
        log("phase=completed result=\(finalReason) completion=\(finalReason == "completed" || finalReason == "fallback_restored" ? "normal" : "forced") elapsed_ms=\(elapsedMilliseconds) external_capture=unknown")
        phase = .idle
        owner = nil
        record = nil
        restoreUID = nil
        preRoll.removeAll()
        environment.finished(finalReason)
        if let pendingSession {
            self.pendingSession = nil
            if start(device: pendingSession.device, targetUID: pendingSession.targetUID, mode: pendingSession.mode, externalVoiceBusy: false) {
                if isBusy {
                    receive(pendingSession.samples, device: pendingSession.device)
                    if pendingSession.ended { stop(device: pendingSession.device) }
                } else {
                    log("phase=queued_cancelled completion=forced reason=queued_start_failed audio_interrupted_samples=\(pendingSession.samples.count)")
                }
            } else {
                log("phase=queued_cancelled completion=forced reason=queued_start_rejected audio_interrupted_samples=\(pendingSession.samples.count)")
                environment.finished("queued_start_rejected")
            }
        }
    }

    private var elapsedMilliseconds: Int { max(0, Int((environment.now() - startedAt) * 1_000)) }

    private func later(after delay: TimeInterval, _ operation: @escaping (SourceMicrophoneSessionController) -> Void) {
        let operationGeneration = generation
        cancellations.append(environment.schedule(delay) { [weak self] in
            guard let self, self.generation == operationGeneration, self.isBusy else { return }
            operation(self)
        })
    }

    private func cancelTasks() {
        let tasks = cancellations
        cancellations.removeAll()
        tasks.forEach { $0() }
    }

    private func log(_ fields: String) {
        environment.log("AUDIO SOURCE_SESSION operation_id=\(generation) \(fields)")
    }
}
