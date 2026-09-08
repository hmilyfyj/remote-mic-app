import Foundation
import Testing
#if !REMOTE_MIC_LOCAL_ONLY
@testable import SayAllMacRemoteCore
#endif
@testable import RemoteMic

@Suite("Apple Watch BLE voice journey")
struct WatchBluetoothVoiceJourneyTests {
    #if !REMOTE_MIC_LOCAL_ONLY
    @Test func firstVoiceAttemptWaitsForMacPreparationBeforeVoiceReady() throws {
        let server = WatchBluetoothRemoteServer()
        var macVoicePrepared = false
        server.onVoiceStartResult = { completion in
            macVoicePrepared = true
            completion(.started)
        }
        server._testConfigureSession(approved: true, voiceActive: false)

        server._testHandleMessage(WatchBluetoothMessage(type: "voiceStart"))

        #expect(macVoicePrepared)
        #expect(server._testSessionState().voiceActive)
        #expect(server._testPendingNotifications().map(\.type) == ["voiceReady"])

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridgeSource = try String(
            contentsOf: root.appendingPathComponent("Sources/RemoteMic/BridgeAppModel.swift"),
            encoding: .utf8
        )
        #expect(bridgeSource.contains(
            "requestPhoneVoiceStart(\n                    source: .nearbyWatch"
        ))
        #expect(bridgeSource.contains("MOBILE VOICE audio source="))
        #expect(bridgeSource.contains("MOBILE VOICE audio_summary source="))
        #expect(bridgeSource.contains("accepted=\\(accepted)"))
    }

    #endif

    @Test func sameWatchCanRestartAfterStopBeginsWithoutBeingReportedBusy() {
        #expect(MobileVoiceRestartPolicy.startDisposition(
            requested: .nearbyWatch,
            active: .nearbyWatch,
            stopping: .nearbyWatch
        ) == .deferUntilStopped)
        #expect(MobileVoiceRestartPolicy.startDisposition(
            requested: .nearbyWatch,
            active: nil,
            stopping: nil
        ) == .startNow)
    }

    @Test func anotherMobileSourceCannotTakeOverWhileVoiceIsStopping() {
        #expect(MobileVoiceRestartPolicy.startDisposition(
            requested: .nearbyPhone,
            active: .nearbyWatch,
            stopping: .nearbyWatch
        ) == .busy)
        #expect(MobileVoiceRestartPolicy.startDisposition(
            requested: .web,
            active: .nearbyPhone,
            stopping: nil
        ) == .busy)
    }

    @Test func stopBeforeVoiceReadyCancelsOnlyTheMatchingPendingRestart() {
        #expect(MobileVoiceRestartPolicy.shouldCancelPendingRestart(
            stopped: .nearbyWatch,
            pending: .nearbyWatch
        ))
        #expect(!MobileVoiceRestartPolicy.shouldCancelPendingRestart(
            stopped: .nearbyPhone,
            pending: .nearbyWatch
        ))
    }
}
