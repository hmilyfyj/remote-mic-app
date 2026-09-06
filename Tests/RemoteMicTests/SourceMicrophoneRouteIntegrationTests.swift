import Foundation
import Testing
@testable import RemoteMic

struct SourceMicrophoneRouteIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REMOTE_MIC_TEST_AUDIO_ROUTE"] == "1"))
    @MainActor func inputSwitchRetainsVirtualOutputAndDrains() async throws {
        let original = try #require(CoreAudioDeviceCatalog.defaultInputDevice())
        let target = try #require(CoreAudioDeviceCatalog.inputDevices().first { $0.uid == "MiRemoteV2ch_UID" })
        let output = VirtualAudioOutput()
        defer {
            output.stop()
            #expect(CoreAudioDeviceCatalog.setDefaultInputDevice(original) == 0)
        }
        #expect(output.configure(deviceUID: target.uid))
        for _ in 0..<10 {
            for input in [target, original] {
                #expect(CoreAudioDeviceCatalog.setDefaultInputDevice(input) == 0)
                let ready = await withCheckedContinuation { continuation in
                    _ = output.waitForOutputAfterInputChange { continuation.resume(returning: $0) }
                }
                try #require(ready)
                // Check beyond the settling window for delayed Core Audio route changes.
                try await Task.sleep(nanoseconds: 300_000_000)
                try #require(output.isConfigurationHealthyForDiagnostics)
                let before = output.diagnosticSnapshot().counters.playedSamples
                let accepted = output.enqueue(samples: Array(repeating: 0, count: 1600))
                try #require(accepted)
                for _ in 0..<30 {
                    if output.diagnosticSnapshot().pendingSamples == 0 { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                let snapshot = output.diagnosticSnapshot()
                try #require(snapshot.pendingSamples == 0)
                #expect(snapshot.counters.playedSamples == before + 1600)
                #expect(snapshot.counters.interruptedSamples == 0)
            }
        }
    }
}
