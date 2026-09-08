import Foundation
import Testing
@testable import RemoteMic

private final class RouteWaitHarness {
    var now: TimeInterval = 0
    var tasks: [(TimeInterval, () -> Void)] = []
    var health: (TimeInterval) -> Bool = { _ in true }
    var unavailable: String?
    var restartSucceeds = true
    var restartCount = 0
    var results: [Bool] = []
    var logs: [String] = []

    func start() -> () -> Void {
        AudioRouteWaiter.wait(environment: .init(
            now: { self.now }, unavailableReason: { self.unavailable },
            healthy: { self.health(self.now) },
            restart: { self.restartCount += 1; return self.restartSucceeds },
            schedule: { self.tasks.append((self.now + $0, $1)) },
            log: { self.logs.append($0) }
        ), completion: { self.results.append($0) })
    }

    func advance(to end: TimeInterval) {
        while let next = tasks.first, next.0 <= end {
            tasks.removeFirst()
            now = next.0
            next.1()
        }
        now = end
    }
}

struct AudioRouteWaiterTests {
    @Test func healthyRouteRetainsFastPathAndCompletesOnce() {
        let h = RouteWaitHarness()
        let cancel = h.start()
        h.advance(to: 0.14)
        #expect(h.results.isEmpty)
        h.advance(to: 0.18)
        #expect(h.results == [true])
        #expect(h.restartCount == 0)
        cancel()
        h.advance(to: 4)
        #expect(h.logs.filter { $0.contains("phase=completed") }.count == 1)
    }

    @Test func delayedConfigurationResetRestartsStabilityWindow() {
        let h = RouteWaitHarness()
        h.health = { $0 < 0.10 || $0 >= 1.2 }
        _ = h.start()
        h.advance(to: 1.3)
        #expect(h.results.isEmpty)
        h.advance(to: 1.5)
        #expect(h.results == [true])
        #expect(h.restartCount > 0)
    }

    @Test func permanentlyUnhealthyRouteTimesOut() {
        let h = RouteWaitHarness()
        h.health = { _ in false }
        _ = h.start()
        h.advance(to: 2.4)
        #expect(h.results.isEmpty)
        h.advance(to: 2.6)
        #expect(h.results == [false])
        #expect(h.logs.last?.contains("result=timed_out") == true)
    }

    @Test func delayedPollStillHonorsOverallDeadline() {
        let h = RouteWaitHarness()
        _ = h.start()
        h.now = 3
        h.tasks.removeFirst().1()
        #expect(h.results == [false])
        #expect(h.logs.last?.contains("result=timed_out") == true)
    }

    @Test(arguments: ["generation_changed", "audio_pending", "output_missing"])
    func invalidOutputStopsBeforeRestart(reason: String) {
        let h = RouteWaitHarness()
        _ = h.start()
        h.unavailable = reason
        h.advance(to: 0.2)
        #expect(h.results == [false])
        #expect(h.restartCount == 0)
        #expect(h.logs.last?.contains("result=\(reason)") == true)
    }

    @Test func restartFailureAndCancellationHaveSingleTerminalResult() {
        let failed = RouteWaitHarness()
        failed.health = { _ in false }
        failed.restartSucceeds = false
        let cancelFailed = failed.start()
        cancelFailed()
        #expect(failed.results == [false])
        #expect(failed.logs.last?.contains("result=restart_failed") == true)
        #expect(failed.logs.filter { $0.contains("phase=completed") }.count == 1)

        let h = RouteWaitHarness()
        h.health = { _ in false }
        let cancel = h.start()
        h.advance(to: 0.1)
        cancel()
        cancel()
        let restarts = h.restartCount
        h.advance(to: 5)
        #expect(h.results.isEmpty)
        #expect(h.restartCount == restarts)
        #expect(h.logs.filter { $0.contains("result=cancelled") }.count == 1)
    }
}
