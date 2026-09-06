import Foundation
import Testing
@testable import RemoteMic

private final class MicrophoneHarness {
    final class Timer {
        let deadline: TimeInterval
        let action: () -> Void
        var cancelled = false
        init(deadline: TimeInterval, action: @escaping () -> Void) {
            self.deadline = deadline
            self.action = action
        }
    }

    let remote = UUID()
    var now: TimeInterval = 0
    var timers: [Timer] = []
    var input: String? = "built_in"
    var inputs = ["built_in", "usb", "virtual"]
    var recovery: SourceMicrophoneSessionController.RecoveryRecord?
    var pending = 0
    var interrupted = 0
    var healthy = true
    var selections: [String] = []
    var fn: [Bool] = []
    var audio: [Int16] = []
    var events: [String] = []
    var results: [String] = []
    var logs: [String] = []
    var selectionFails = Set<String>()
    var deferSelection = false
    var failUp = 0
    var failDown = 0
    var enqueueFails = false
    var recoveryWriteFails = false
    var waitForDestination = false
    var destination: ((Bool) -> Void)?

    lazy var controller = SourceMicrophoneSessionController(environment: .init(
        currentInput: { self.input },
        availableInputs: { self.inputs },
        fallbackInput: { excluded in self.inputs.first { $0 != excluded } },
        selectInput: { uid in
            self.selections.append(uid)
            self.events.append("select_\(uid)")
            if self.selectionFails.contains(uid) { return false }
            if !self.deferSelection { self.input = uid }
            return true
        },
        readRecovery: { self.recovery },
        writeRecovery: {
            guard !self.recoveryWriteFails else { return false }
            self.recovery = $0
            return true
        },
        setFn: { down in
            if down, self.failDown > 0 { self.failDown -= 1; return false }
            if !down, self.failUp > 0 { self.failUp -= 1; return false }
            self.fn.append(down)
            self.events.append(down ? "fn_down" : "fn_up")
            return true
        },
        enqueue: { samples in
            if self.enqueueFails { return false }
            self.audio.append(contentsOf: samples)
            self.pending += samples.count
            self.events.append("audio")
            return true
        },
        playback: { .init(pendingSamples: self.pending, interruptedSamples: self.interrupted, healthy: self.healthy) },
        interruptAudio: {
            self.interrupted += self.pending
            self.pending = 0
            self.events.append("interrupt")
        },
        waitForDestination: { completion in
            self.destination = completion
            if !self.waitForDestination { completion(true) }
            return {}
        },
        now: { self.now },
        schedule: { delay, action in
            let timer = Timer(deadline: self.now + delay, action: action)
            self.timers.append(timer)
            return { timer.cancelled = true }
        },
        log: { self.logs.append($0) },
        finished: { self.results.append($0) }
    ))

    @discardableResult
    func start(mode: SourceMicrophoneSessionController.Mode = .hold, externalBusy: Bool = false) -> Bool {
        controller.start(device: remote, targetUID: "virtual", mode: mode, externalVoiceBusy: externalBusy)
    }

    func advance(_ duration: TimeInterval) {
        let end = now + duration
        var count = 0
        while let timer = timers.filter({ !$0.cancelled && $0.deadline <= end }).min(by: { $0.deadline < $1.deadline }) {
            timer.cancelled = true
            now = timer.deadline
            timer.action()
            count += 1
            precondition(count < 100_000)
        }
        now = end
    }

    func completePlayback() {
        pending = 0
        events.append("played_back")
        advance(0.02)
    }
}

struct SourceMicrophoneSessionTests {
    @Test func holdWaitsForRouteThenPlaybackThenReleaseAndRestore() {
        let h = MicrophoneHarness()
        h.deferSelection = true
        #expect(h.start())
        h.controller.receive([1, 2, 3], device: h.remote)
        #expect(h.fn.isEmpty)
        #expect(h.audio.isEmpty)
        h.input = "virtual"
        h.deferSelection = false
        h.advance(0.02)
        #expect(h.fn == [true])
        #expect(h.audio == [1, 2, 3])
        h.controller.stop(device: h.remote)
        #expect(h.controller.phase == .draining)
        #expect(h.input == "virtual")
        h.completePlayback()
        #expect(h.fn == [true, false])
        #expect(h.input == "built_in")
        #expect(h.recovery == nil)
        #expect(h.results == ["completed"])
        #expect(h.events == ["select_virtual", "fn_down", "audio", "played_back", "fn_up", "select_built_in"])
    }

    @Test(arguments: [false, true]) func ultraFastReleasePreservesPreRoll(tap: Bool) {
        let h = MicrophoneHarness()
        h.waitForDestination = true
        #expect(h.start(mode: tap ? .tap : .hold))
        h.controller.receive([10, 20], device: h.remote)
        h.controller.stop(device: h.remote)
        #expect(h.fn.isEmpty)
        h.destination?(true)
        h.advance(0.13)
        #expect(h.audio == [10, 20])
        #expect(h.controller.phase == .draining)
        h.completePlayback()
        h.advance(0.13)
        #expect(h.fn == (tap ? [true, false, true, false] : [true, false]))
        #expect(h.results == ["completed"])
    }

    @Test func tapRestoresOnlyAfterStopTapCompletes() {
        let h = MicrophoneHarness()
        h.start(mode: .tap)
        h.controller.receive([1], device: h.remote)
        h.advance(0.13)
        h.controller.stop(device: h.remote)
        h.completePlayback()
        #expect(h.controller.phase == .stopping)
        #expect(h.input == "virtual")
        h.advance(0.13)
        #expect(h.fn == [true, false, true, false])
        #expect(h.input == "built_in")
    }

    @Test(arguments: ["built_in", "usb"]) func twentyAlternatingSessions(original: String) {
        let h = MicrophoneHarness()
        h.input = original
        for index in 0..<20 {
            #expect(h.start())
            h.controller.receive([Int16(index)], device: h.remote)
            h.controller.stop(device: h.remote)
            h.completePlayback()
            #expect(h.input == original)
            #expect(!h.start(externalBusy: true))
            #expect(h.input == original)
        }
        #expect(h.results.count == 20)
        #expect(h.fn.count == 40)
        #expect(h.audio == (0..<20).map(Int16.init))
        #expect(h.interrupted == 0)
    }

    @Test func foreignDeviceAndBusySessionCannotInterfere() {
        let h = MicrophoneHarness()
        h.start()
        let other = UUID()
        #expect(!h.controller.start(device: other, targetUID: "virtual", mode: .tap, externalVoiceBusy: false))
        h.controller.receive([99], device: other)
        h.controller.stop(device: other)
        #expect(h.controller.phase == .active)
        #expect(h.audio.isEmpty)
        h.controller.receive([1], device: h.remote)
        h.controller.stop(device: h.remote)
        h.completePlayback()
        #expect(h.results == ["completed"])
    }

    @Test func oldCallbacksCannotStopNewSession() {
        let h = MicrophoneHarness()
        h.waitForDestination = true
        h.start()
        let destination = h.destination
        let oldTimers = h.timers
        h.controller.cancel(reason: "cancelled")
        h.waitForDestination = false
        #expect(h.start())
        oldTimers.forEach { $0.action() }
        destination?(true)
        #expect(h.controller.phase == .active)
        #expect(h.input == "virtual")
        #expect(h.fn == [true])
    }

    @Test(arguments: [false, true]) func rapidNextSessionBuffersWhilePreviousDrains(tap: Bool) {
        let h = MicrophoneHarness()
        h.start(mode: tap ? .tap : .hold)
        h.controller.receive([1, 2], device: h.remote)
        h.advance(0.13)
        h.controller.stop(device: h.remote)
        #expect(h.start(mode: tap ? .tap : .hold))
        #expect(!h.start())
        h.controller.receive([3, 4], device: h.remote)
        h.controller.stop(device: h.remote)
        #expect(h.audio == [1, 2])
        h.completePlayback()
        h.advance(0.3)
        #expect(h.audio == [1, 2, 3, 4])
        h.completePlayback()
        h.advance(0.2)
        #expect(h.fn == (tap ? [true, false, true, false, true, false, true, false] : [true, false, true, false]))
        #expect(h.results == ["completed", "completed"])
        #expect(h.selections == ["virtual", "built_in", "virtual", "built_in"])
        #expect(h.interrupted == 0)
    }

    @Test func manualInputChangeRemainsSelected() {
        let h = MicrophoneHarness()
        h.start()
        h.controller.receive([1, 2], device: h.remote)
        h.input = "usb"
        h.controller.inputChanged()
        #expect(h.input == "usb")
        #expect(h.recovery == nil)
        #expect(h.results == ["input_changed"])
        #expect(h.fn == [true, false])
        h.input = "virtual"
        h.advance(130)
        #expect(h.input == "virtual")
        #expect(h.results.count == 1)
    }

    @Test func originalUnpluggedUsesAvailableFallback() {
        let h = MicrophoneHarness()
        h.input = "usb"
        h.start()
        h.inputs.removeAll { $0 == "usb" }
        h.controller.stop(device: h.remote)
        #expect(h.input == "built_in")
        #expect(h.results == ["fallback_restored"])
    }

    @Test func noFallbackPersistsRecoveryForRetry() {
        let h = MicrophoneHarness()
        h.start()
        h.inputs = ["virtual"]
        h.controller.stop(device: h.remote)
        #expect(h.results == ["restore_unavailable"])
        #expect(h.recovery != nil)
        h.inputs.append("built_in")
        #expect(!h.start())
        #expect(h.input == "built_in")
        #expect(h.recovery == nil)
        #expect(h.start())
    }

    @Test func switchFailureAndTimeoutNeverTriggerFn() {
        let failure = MicrophoneHarness()
        failure.selectionFails = ["virtual"]
        failure.start()
        #expect(failure.fn.isEmpty)
        #expect(failure.results == ["switch_failed"])
        let timeout = MicrophoneHarness()
        timeout.deferSelection = true
        timeout.start()
        timeout.controller.receive([1], device: timeout.remote)
        timeout.advance(1.1)
        #expect(timeout.fn.isEmpty)
        #expect(timeout.results == ["switch_timeout"])
        #expect(timeout.logs.contains { $0.contains("audio_interrupted_samples=1") })
    }

    @Test func restoreConfirmationAndUserOverride() {
        let h = MicrophoneHarness()
        h.start()
        h.deferSelection = true
        h.controller.stop(device: h.remote)
        #expect(h.controller.phase == .restoring)
        #expect(!h.controller.start(device: UUID(), targetUID: "virtual", mode: .hold, externalVoiceBusy: false))
        h.input = "usb"
        h.advance(0.02)
        #expect(h.input == "usb")
        #expect(h.recovery == nil)
        #expect(!h.controller.isBusy)
    }

    @Test(arguments: ["disconnect", "system_suspended", "setting_changed", "cancelled"])
    func cancellationRestoresInputAndReleasesFn(reason: String) {
        let h = MicrophoneHarness()
        h.start()
        h.controller.receive([1, 2, 3], device: h.remote)
        h.controller.cancel(reason: reason)
        #expect(h.input == "built_in")
        #expect(h.fn == [true, false])
        #expect(h.interrupted == 3)
        #expect(h.results == [reason])
        #expect(h.logs.contains { $0.contains("completion=forced") })
    }

    @Test func launchRecoveryProtectsLaterUserChoice() {
        let h = MicrophoneHarness()
        h.recovery = .init(previousUID: "built_in", targetUID: "virtual")
        h.input = "usb"
        h.controller.recoverAfterLaunch()
        #expect(h.input == "usb")
        #expect(h.selections.isEmpty)
        #expect(h.recovery == nil)
        h.recovery = .init(previousUID: "built_in", targetUID: "virtual")
        h.input = "virtual"
        h.controller.recoverAfterLaunch()
        #expect(h.input == "built_in")
        #expect(h.fn.isEmpty)
        #expect(h.recovery == nil)
    }

    @Test func overflowReportsForcedCompletionWithoutDroppingHeadSilently() {
        let h = MicrophoneHarness()
        h.waitForDestination = true
        h.start()
        h.controller.receive(Array(repeating: 1, count: 80_001), device: h.remote)
        #expect(h.results == ["pre_roll_overflow"])
        #expect(h.fn.isEmpty)
        #expect(h.audio.isEmpty)
        #expect(h.input == "built_in")
        #expect(h.logs.contains { $0.contains("audio_interrupted_samples=80001") })
    }

    @Test func drainTimeoutIsForcedAndThreeSecondPauseKeepsSession() {
        let h = MicrophoneHarness()
        h.start()
        h.controller.receive([1], device: h.remote)
        h.completePlayback()
        h.advance(3)
        #expect(h.controller.phase == .active)
        #expect(h.fn == [true])
        h.controller.receive([2], device: h.remote)
        h.controller.stop(device: h.remote)
        h.advance(6.1)
        #expect(h.results == ["drain_timeout"])
        #expect(h.interrupted == 1)
        #expect(h.input == "built_in")
    }

    @Test func destinationTimeoutAndEnqueueFailureRestore() {
        let h = MicrophoneHarness()
        h.waitForDestination = true
        h.start()
        h.advance(3.1)
        #expect(h.results == ["destination_timeout"])
        #expect(h.fn.isEmpty)
        h.waitForDestination = false
        h.enqueueFails = true
        h.start()
        h.controller.receive([1], device: h.remote)
        #expect(h.results.last == "enqueue_failed")
        #expect(h.fn == [true, false])
        #expect(h.input == "built_in")
    }

    @Test func failedFnDownAndFailedFnUpRestoreAndReport() {
        let h = MicrophoneHarness()
        h.failDown = 1
        h.start()
        #expect(h.results == ["start_failed"])
        h.start()
        h.failUp = 2
        h.controller.stop(device: h.remote)
        h.advance(0.1)
        #expect(h.results.last == "stop_failed")
        #expect(h.input == "built_in")
        #expect(!h.start())
    }

    @Test func tapCancellationDuringStartCompletesStartThenStops() {
        let h = MicrophoneHarness()
        h.start(mode: .tap)
        h.controller.cancel(reason: "cancelled")
        h.advance(0.13)
        #expect(h.fn == [true, false, true, false])
        #expect(h.input == "built_in")
    }

    @Test func transientStartReleaseFailureStillSendsStopTap() {
        let h = MicrophoneHarness()
        h.start(mode: .tap)
        h.failUp = 2
        h.advance(0.4)
        #expect(h.fn == [true, false, true, false])
        #expect(h.input == "built_in")
        #expect(h.results == ["start_release_failed"])
    }

    @Test func removedVirtualInputRestoresAvailableOriginal() {
        let h = MicrophoneHarness()
        h.start()
        h.inputs.removeAll { $0 == "virtual" }
        h.input = nil
        h.controller.inputChanged()
        #expect(h.input == "built_in")
        #expect(h.results == ["target_unavailable"])
        #expect(h.recovery == nil)
    }

    @Test func restoreFailuresPersistAndFailedStopBlocksFurtherToggles() {
        let h = MicrophoneHarness()
        h.start()
        h.selectionFails = ["built_in"]
        h.controller.stop(device: h.remote)
        #expect(h.results == ["restore_failed"])
        #expect(h.recovery != nil)
        let tap = MicrophoneHarness()
        tap.start(mode: .tap)
        tap.advance(0.13)
        tap.failDown = 1
        tap.controller.stop(device: tap.remote)
        #expect(tap.results == ["stop_failed"])
        #expect(!tap.start())
        #expect(tap.input == "built_in")
    }

    @Test func shutdownDuringStopTapDoesNotToggleAgain() {
        let h = MicrophoneHarness()
        h.start(mode: .tap)
        h.advance(0.13)
        h.controller.stop(device: h.remote)
        #expect(h.fn == [true, false, true])
        h.controller.shutdown()
        h.advance(1)
        #expect(h.fn == [true, false, true, false])
        #expect(h.input == "built_in")
        #expect(h.results == ["app_stop"])
    }

    @Test func logsDoNotExposeDeviceIdentityOrContents() {
        let h = MicrophoneHarness()
        h.input = "private_device_uid"
        h.inputs.append("private_device_uid")
        h.start()
        h.controller.stop(device: h.remote)
        let log = h.logs.joined(separator: "\n")
        #expect(!log.contains("private_device_uid"))
        #expect(!log.contains(h.remote.uuidString))
        #expect(log.contains("external_capture=unknown"))
        #expect(h.logs.filter { $0.contains("phase=completed") }.count == 1)
    }

    @Test func sourceClassificationAndSuppressedEdgesStayPaired() {
        var state = SourceMicrophoneFnState()
        let syntheticSuppressed = state.handle(pressed: true, synthetic: true, remoteBusy: true, tapMode: false)
        #expect(!syntheticSuppressed)
        #expect(!state.externalVoiceBusy)
        let externalDownSuppressed = state.handle(pressed: true, synthetic: false, remoteBusy: false, tapMode: false)
        #expect(!externalDownSuppressed)
        #expect(state.externalVoiceBusy)
        let externalUpSuppressed = state.handle(pressed: false, synthetic: false, remoteBusy: false, tapMode: false)
        #expect(!externalUpSuppressed)
        #expect(!state.externalVoiceBusy)
        let conflictDown = state.handle(pressed: true, synthetic: false, remoteBusy: true, tapMode: false)
        let conflictUp = state.handle(pressed: false, synthetic: false, remoteBusy: false, tapMode: false)
        #expect(conflictDown && conflictUp)
        #expect(!state.externalVoiceBusy)
        _ = state.handle(pressed: true, synthetic: false, remoteBusy: false, tapMode: true)
        _ = state.handle(pressed: false, synthetic: false, remoteBusy: false, tapMode: true)
        #expect(state.externalVoiceBusy)
        _ = state.handle(pressed: true, synthetic: false, remoteBusy: false, tapMode: true)
        _ = state.handle(pressed: false, synthetic: false, remoteBusy: false, tapMode: true)
        #expect(!state.externalVoiceBusy)
    }

    @Test func recoveryMustBePersistedBeforeSwitching() {
        let h = MicrophoneHarness()
        h.recoveryWriteFails = true
        h.start()
        #expect(h.selections.isEmpty)
        #expect(h.fn.isEmpty)
        #expect(h.results == ["recovery_write_failed"])
    }
}
