import Foundation
import Testing
@testable import RemoteMic

struct VoiceModeButtonActionTests {
    @Test(arguments: [ButtonAction.toggleVoiceMode, .useMicrophoneOnly, .useFnVoiceInput])
    func keyboardSenderDoesNotEmitAnyEventsForModeActions(action: ButtonAction) {
        var events = 0
        var permissionChecks = 0
        #expect(KeyboardInjector.send(action,
            accessibilityTrusted: { permissionChecks += 1; return false },
            keyPoster: { _, _ in events += 1 },
            keyStatePoster: { _, _, _ in events += 1; return false },
            scrollPoster: { _ in events += 1 }))
        #expect(events == 0)
        #expect(permissionChecks == 0)
    }

    @Test func targetsRespectPendingSelectionAndBothFixedModes() {
        #expect(ButtonAction.toggleVoiceMode.voiceKeyModeTarget(current: .function, pending: nil) == .microphoneOnly)
        #expect(ButtonAction.toggleVoiceMode.voiceKeyModeTarget(current: .microphoneOnly, pending: .function) == .microphoneOnly)
        #expect(ButtonAction.toggleVoiceMode.voiceKeyModeTarget(current: .leftCommand, pending: nil) == .microphoneOnly)
        #expect(ButtonAction.useFnVoiceInput.voiceKeyModeTarget(current: .microphoneOnly, pending: .microphoneOnly) == .function)
        #expect(ButtonAction.useMicrophoneOnly.voiceKeyModeTarget(current: .function, pending: .function) == .microphoneOnly)
        #expect(ButtonAction.escape.voiceKeyModeTarget(current: .function, pending: nil) == nil)
    }

    @Test func bindingsRoundTripForAllThreeGestures() throws {
        let suite = "RemoteMicTests.modeBindings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.setAction(.toggleVoiceMode, for: .menu, trigger: .singleClick)
        settings.setAction(.useMicrophoneOnly, for: .menu, trigger: .doubleClick)
        settings.setAction(.useFnVoiceInput, for: .menu, trigger: .longPress)
        let data = try settings.exportedConfigurationData()
        settings.setAction(.disabled, for: .menu, trigger: .singleClick)
        try settings.importConfiguration(from: data)
        #expect(settings.configuredAction(for: .menu, trigger: .singleClick).action == .toggleVoiceMode)
        #expect(settings.configuredAction(for: .menu, trigger: .doubleClick).action == .useMicrophoneOnly)
        #expect(settings.configuredAction(for: .menu, trigger: .longPress).action == .useFnVoiceInput)
        #expect(AppSettings(defaults: defaults).configuredAction(for: .menu, trigger: .singleClick).action == .toggleVoiceMode)
    }

    @Test(arguments: [ButtonAction.toggleVoiceMode, .useMicrophoneOnly, .useFnVoiceInput])
    func modeActionsAreInternalAndNeverRepeat(action: ButtonAction) {
        #expect(action.isAppInternal)
        #expect(!action.allowsRepeat)
        #expect(action.category == .voiceModes)
        #expect(action.isEnabled(experimentalContinuousRecordingEnabled: false))
    }

    @Test @MainActor func remoteRequestsUseLatestPendingModeAndCanCancel() throws {
        let suite = "RemoteMicTests.remoteMode.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.voiceKeyMode = .microphoneOnly
        settings.sourceMicrophoneSwitchingEnabled = true
        let model = BridgeAppModel(settings: settings, voiceKeyModeBusyOverride: { true })
        #expect(model.performInternalAction(.toggleVoiceMode))
        #expect(model.pendingVoiceKeyMode == .function)
        #expect(settings.voiceKeyMode == .microphoneOnly)
        #expect(model.performInternalAction(.toggleVoiceMode))
        #expect(model.pendingVoiceKeyMode == nil)
        #expect(model.performInternalAction(.useFnVoiceInput))
        #expect(model.pendingVoiceKeyMode == .function)
        #expect(model.performInternalAction(.useMicrophoneOnly))
        #expect(model.pendingVoiceKeyMode == nil)
        #expect(settings.voiceKeyMode == .microphoneOnly)
    }
}
