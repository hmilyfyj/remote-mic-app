import Foundation
import Testing
@testable import RemoteMic

@Suite("Local Mac build")
struct LocalOnlyBuildTests {
    @Test func pcmMetricsHandleSilenceFullScaleAndBatchBoundaries() {
        var metrics = AudioSignalMetrics()
        #expect(metrics.rms == 0)
        metrics.append([0, .min])
        metrics.append([.max, 0])
        #expect(metrics.sampleCount == 4)
        #expect(metrics.nonZeroSampleCount == 2)
        #expect(metrics.peak == 32768)
        #expect(metrics.rms == 23170)

        var singleBatch = AudioSignalMetrics()
        singleBatch.append([0, .min, .max, 0])
        #expect(singleBatch.rms == metrics.rms)
    }

    #if REMOTE_MIC_LOCAL_ONLY
    @Test @MainActor func mobileResumeReturnsToSourceSelectionAndPreservesOtherSettings() throws {
        for method in [OnboardingControlMethod.iPhoneApp, .webRemote] {
            let name = "RemoteMic.LocalOnlyTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let settings = AppSettings(defaults: defaults)
            settings.restartOnboarding()
            settings.setOnboardingVoiceTool(.typeless)
            settings.selectedAudioDeviceUID = "MiRemoteV2ch_UID"
            settings.sourceMicrophoneSwitchingEnabled = true
            settings.setOnboardingRemoteAvailability(.noRemote)
            settings.setOnboardingControlMethod(method)
            settings.setOnboardingStep(.remote)

            settings.prepareAvailableOnboardingSources()

            #expect(settings.onboardingStep == .remoteAvailability)
            #expect(settings.onboardingControlMethod == .unselected)
            #expect(settings.onboardingRemoteAvailability == .unselected)
            #expect(settings.onboardingVoiceTool == .typeless)
            #expect(settings.selectedAudioDeviceUID == "MiRemoteV2ch_UID")
            #expect(settings.sourceMicrophoneSwitchingEnabled)
            #expect(!settings.isOnboardingComplete)
            #expect(OnboardingRemoteAvailability.availableChoices == [.hasRemote])
        }
    }

    @Test @MainActor func unsupportedConnectionsStayDisabled() throws {
        let name = "RemoteMic.LocalOnlyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = BridgeAppModel(settings: AppSettings(defaults: defaults))
        model.enablePhoneRemoteConnection()
        model.enableWatchRemoteConnection()
        model.enableWebRemoteConnection()
        #expect(!model.isPhoneRemoteConnectionEnabled)
        #expect(!model.isPhoneRemoteConnected)
        #expect(!model.isWatchRemoteConnected)
    }
    #endif
}
