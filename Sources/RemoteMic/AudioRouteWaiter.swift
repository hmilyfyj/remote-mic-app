import Foundation

/// Runs on the caller's serial executor (the main run loop in the audio output).
enum AudioRouteWaiter {
    // Core Audio can reset the output more than once after an input switch.
    // Leave room for recovery within the session's 3s wait and 5s PCM buffer.
    static let timeout: TimeInterval = 2.5

    struct Environment {
        var now: () -> TimeInterval
        var unavailableReason: () -> String?
        var healthy: () -> Bool
        var restart: () -> Bool
        var schedule: (TimeInterval, @escaping () -> Void) -> Void
        var log: (String) -> Void
    }

    static func wait(environment: Environment, completion: @escaping (Bool) -> Void) -> () -> Void {
        let started = environment.now()
        var finished = false
        var stableSince: TimeInterval?
        var attempts = 0
        environment.log("phase=requested timeout_ms=\(Int(timeout * 1000))")
        func complete(_ ready: Bool, reason: String) {
            finished = true
            let elapsed = Int((environment.now() - started) * 1000)
            environment.log("phase=completed result=\(reason) attempts=\(attempts) elapsed_ms=\(elapsed)")
            completion(ready)
        }
        func check() {
            guard !finished else { return }
            let now = environment.now()
            if let reason = environment.unavailableReason() {
                complete(false, reason: reason)
                return
            }
            guard now - started < timeout else {
                complete(false, reason: "timed_out")
                return
            }
            if environment.healthy() {
                if let stableSince, now - stableSince >= 0.15 {
                    complete(true, reason: "ready")
                    return
                }
                if stableSince == nil { stableSince = now }
            } else {
                stableSince = nil
                attempts += 1
                guard environment.restart() else {
                    complete(false, reason: "restart_failed")
                    return
                }
            }
            environment.schedule(0.025, check)
        }
        check()
        return {
            guard !finished else { return }
            finished = true
            let elapsed = Int((environment.now() - started) * 1000)
            environment.log("phase=completed result=cancelled attempts=\(attempts) elapsed_ms=\(elapsed)")
        }
    }
}
