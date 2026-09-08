import Foundation
import Testing
@testable import RemoteMic

struct SourceMicrophoneSettingsTests {
    @Test @MainActor func restorationPreferencesPersistAndDefaultToPrevious() throws {
        let name = "RemoteMic.RestorationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.sourceMicrophoneRestoreMode == .previous)
        #expect(settings.sourceMicrophoneRestoration.preferredUID == nil)
        #expect(settings.sourceMicrophoneRestoration.delay == 0)
        settings.sourceMicrophoneRestoreMode = .specified
        settings.sourceMicrophoneRestoreDeviceUID = "usb"
        settings.setSourceMicrophoneRestoreDelay(2.3)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.sourceMicrophoneRestoration.preferredUID == "usb")
        #expect(reloaded.sourceMicrophoneRestoration.delay == 2.3)
        defaults.set("unknown", forKey: "sourceMicrophoneRestoreMode")
        defaults.set(99, forKey: "sourceMicrophoneRestoreDelay")
        let invalid = AppSettings(defaults: defaults)
        #expect(invalid.sourceMicrophoneRestoreMode == .previous)
        #expect(invalid.sourceMicrophoneRestoreDelay == 10)
        invalid.setSourceMicrophoneRestoreDelay(-1)
        #expect(invalid.sourceMicrophoneRestoreDelay == 0)
    }

    @Test func delayIsBoundedAndFinite() {
        for (input, expected) in [(-1.0, 0.0), (0, 0), (2.3, 2.3), (11, 10), (.infinity, 0), (.nan, 0)] {
            #expect(SourceMicrophoneSessionController.Restoration(delay: input).delay == expected)
        }
    }
}
