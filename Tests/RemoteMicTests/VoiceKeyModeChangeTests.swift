import Foundation
import Testing
@testable import RemoteMic

private final class ModeChangeHarness {
    var current: VoiceKeyMode = .microphoneOnly
    var busy = false
    var deferPreparation = false
    var callbacks: [(Bool) -> Void] = []
    var applied: [VoiceKeyMode] = []
    var visiblePending: VoiceKeyMode?
    var failed = false
    lazy var controller = VoiceKeyModeChangeController(environment: .init(
        current: { self.current }, isBusy: { self.busy },
        prepare: { callback in
            if self.deferPreparation { self.callbacks.append(callback) }
            else { callback(true) }
        },
        apply: { self.current = $0; self.applied.append($0); return true },
        changed: { self.visiblePending = $0; self.failed = $1 }, log: { _ in }
    ))
}

struct VoiceKeyModeChangeTests {
    @Test @MainActor func modelKeepsEffectiveModeAndPublishesRequestedSelection() throws {
        let suite = "RemoteMicTests.queuedMode.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.voiceKeyMode = .microphoneOnly
        let model = BridgeAppModel(settings: settings, voiceKeyModeBusyOverride: { true })
        model.setVoiceKeyMode(.function)
        #expect(settings.voiceKeyMode == .microphoneOnly)
        #expect(model.pendingVoiceKeyMode == .function)
        model.setVoiceKeyMode(.microphoneOnly)
        #expect(model.pendingVoiceKeyMode == nil)
        #expect(!model.voiceKeyModeChangeFailed)
    }

    @Test func cleanupCompletionIsConsumedOnceEvenAfterANewRequest() {
        let h = ModeChangeHarness()
        h.deferPreparation = true
        h.controller.request(.function)
        let oldCallback = h.callbacks.removeFirst()
        oldCallback(true)
        h.controller.request(.leftCommand)
        oldCallback(true)
        #expect(h.applied == [.function])
        h.callbacks.removeFirst()(true)
        oldCallback(true)
        #expect(h.applied == [.function, .leftCommand])
    }

    @Test func selectionDuringRestorationAppliesAfterSessionEnds() {
        let h = ModeChangeHarness()
        h.busy = true
        h.controller.request(.function)
        #expect(h.current == .microphoneOnly)
        #expect(h.visiblePending == .function)
        h.controller.applyWhenIdle()
        #expect(h.applied.isEmpty)
        h.busy = false
        h.controller.applyWhenIdle()
        h.controller.applyWhenIdle()
        #expect(h.current == .function)
        #expect(h.applied == [.function])
        #expect(h.visiblePending == nil)
    }

    @Test func latestSelectionWinsAndCurrentSelectionCancels() {
        let h = ModeChangeHarness()
        h.busy = true
        h.controller.request(.function)
        h.controller.request(.leftCommand)
        h.busy = false
        h.controller.applyWhenIdle()
        #expect(h.applied == [.leftCommand])
        h.busy = true
        h.controller.request(.function)
        h.controller.request(.leftCommand)
        h.busy = false
        h.controller.applyWhenIdle()
        #expect(h.applied == [.leftCommand])
        #expect(h.visiblePending == nil)
    }

    @Test func newVoiceDuringCleanupDefersCommit() {
        let h = ModeChangeHarness()
        h.deferPreparation = true
        h.controller.request(.function)
        h.busy = true
        h.callbacks.removeFirst()(true)
        #expect(h.applied.isEmpty)
        #expect(h.visiblePending == .function)
        h.busy = false
        h.controller.applyWhenIdle()
        h.callbacks.removeFirst()(true)
        #expect(h.applied == [.function])
    }

    @Test func staleCleanupCannotOverwriteLatestSelection() {
        let h = ModeChangeHarness()
        h.deferPreparation = true
        h.controller.request(.function)
        h.controller.request(.rightCommand)
        h.callbacks.removeFirst()(true)
        #expect(h.applied.isEmpty)
        h.callbacks.removeFirst()(true)
        #expect(h.applied == [.rightCommand])
    }

    @Test func cancelledRequestIgnoresLateCleanupAndFailureIsVisible() {
        let h = ModeChangeHarness()
        h.deferPreparation = true
        h.controller.request(.function)
        h.controller.cancel()
        h.callbacks.removeFirst()(true)
        #expect(h.applied.isEmpty)
        #expect(h.visiblePending == nil)
        h.controller.request(.function)
        h.callbacks.removeFirst()(false)
        #expect(h.failed)
        #expect(h.current == .microphoneOnly)
        #expect(h.visiblePending == nil)
    }
}
