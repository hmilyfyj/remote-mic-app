import Foundation

/// Serialized with voice lifecycle callbacks on the main run loop.
final class VoiceKeyModeChangeController {
    struct Environment {
        var current: () -> VoiceKeyMode
        var isBusy: () -> Bool
        var prepare: (@escaping (Bool) -> Void) -> Void
        var apply: (VoiceKeyMode) -> Bool
        var changed: (VoiceKeyMode?, Bool) -> Void
        var log: (String) -> Void
    }

    private let environment: Environment
    private var generation = 0
    private var preparing = false
    private var preparationID = 0
    private(set) var pending: VoiceKeyMode?

    init(environment: Environment) { self.environment = environment }

    func request(_ mode: VoiceKeyMode) {
        if pending != nil {
            environment.log("phase=completed request_id=\(generation) result=superseded")
        }
        generation += 1
        pending = mode == environment.current() ? nil : mode
        environment.changed(pending, false)
        environment.log("phase=requested request_id=\(generation) target=\(mode.rawValue)")
        if pending != nil, environment.isBusy() {
            environment.log("phase=waiting request_id=\(generation) reason=voice_active")
        } else if pending == nil {
            environment.log("phase=completed request_id=\(generation) result=unchanged")
        }
        applyWhenIdle()
    }

    func cancel() {
        if pending != nil {
            environment.log("phase=completed request_id=\(generation) result=cancelled")
        }
        generation += 1
        pending = nil
        environment.changed(nil, false)
    }

    func applyWhenIdle() {
        guard let mode = pending, !preparing, !environment.isBusy() else { return }
        preparing = true
        let request = generation
        preparationID += 1
        let preparation = preparationID
        environment.prepare { [weak self] ready in
            guard let self, self.preparing, self.preparationID == preparation else { return }
            self.preparationID += 1
            self.preparing = false
            guard self.generation == request else {
                self.applyWhenIdle()
                return
            }
            guard ready else {
                self.pending = nil
                self.environment.changed(nil, true)
                self.environment.log("phase=completed request_id=\(request) result=release_failed")
                return
            }
            guard !self.environment.isBusy() else {
                self.environment.log("phase=waiting request_id=\(request) reason=voice_active")
                return
            }
            self.preparing = true
            let applied = self.environment.apply(mode)
            self.preparing = false
            guard self.generation == request else {
                self.applyWhenIdle()
                return
            }
            self.pending = nil
            self.environment.changed(nil, !applied)
            self.environment.log("phase=completed request_id=\(request) target=\(mode.rawValue) result=\(applied ? "applied" : "mapping_failed")")
        }
    }
}
