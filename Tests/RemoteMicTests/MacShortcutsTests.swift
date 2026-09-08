import Foundation
import Testing
@testable import RemoteMic

@Suite("Mac Shortcuts")
struct MacShortcutsTests {
    private let first = MacShortcut(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, name: "Work (Mac)")

    @Test func parsesNamesDuplicatesAndMultilineNames() throws {
        let secondID = UUID()
        let text = "Work (Mac) (\(first.id))\nSame name (\(secondID))\nWork (Mac) (\(first.id))\n"
        let parsed = try MacShortcutsCommand.parseList(Data(text.utf8))
        #expect(parsed.count == 2)
        #expect(parsed.contains(first))
        let multiline = "Line one\nLine two (\(first.id))\n"
        #expect(try MacShortcutsCommand.parseList(Data(multiline.utf8)).first?.name == "Line one\nLine two")
        #expect(try MacShortcutsCommand.parseList(Data()).isEmpty)
        #expect(throws: MacShortcutsError.self) {
            try MacShortcutsCommand.parseList(Data("unexpected CLI output".utf8))
        }
    }

    @Test func usesOnlyStableIdentifierInArguments() {
        let renamed = MacShortcut(id: first.id, name: "$(touch /tmp/should-never-exist); \"name\"")
        #expect(MacShortcutsCommand.arguments(for: renamed) == ["run", first.id.uuidString])
        #expect(!ButtonAction.runMacShortcut.allowsRepeat)
    }

    @Test func persistenceExportAndDeviceIsolation() throws {
        let suite = "MacShortcutsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let profileID = settings.registerBluetoothRemote(identifier: UUID())
        settings.updateRemoteProfile(profileID, model: .rc003, customName: "Test")
        settings.selectRemoteProfile(profileID)
        for trigger in ButtonTrigger.allCases {
            settings.setAction(.runMacShortcut, for: .ok, trigger: trigger)
            settings.setMacShortcut(first, for: .ok, trigger: trigger)
        }
        let export = try settings.exportedConfigurationData()
        let secondProfileID = settings.registerBluetoothRemote(identifier: UUID())
        settings.selectRemoteProfile(secondProfileID)
        let second = MacShortcut(id: UUID(), name: "Other")
        settings.setMacShortcut(second, for: .ok, trigger: .singleClick)
        let reloaded = AppSettings(defaults: defaults)
        for trigger in ButtonTrigger.allCases {
            #expect(reloaded.configuredAction(for: .ok, trigger: trigger, profileID: profileID).macShortcut == first)
        }
        #expect(reloaded.configuredAction(for: .ok, trigger: .singleClick).macShortcut == second)
        try reloaded.importConfiguration(from: export)
        for trigger in ButtonTrigger.allCases {
            #expect(reloaded.configuredAction(for: .ok, trigger: trigger).macShortcut == first)
        }
        reloaded.setAction(.escape, for: .ok, trigger: .longPress)
        reloaded.setAction(.runMacShortcut, for: .ok, trigger: .longPress)
        #expect(reloaded.configuredAction(for: .ok, trigger: .longPress).macShortcut == first)
        reloaded.resetBindings()
        #expect(reloaded.configuredAction(for: .ok, trigger: .singleClick).macShortcut == nil)
    }

    @Test func oldConfigurationAndPowerBackupRemainCompatible() throws {
        let emptyMappings = RemoteDeviceMappings(buttonBindings: [:], buttonShortcuts: [:], secondaryButtonBindings: [:])
        let legacyMappings = Data(#"{"buttonBindings":{},"buttonShortcuts":{},"secondaryButtonBindings":{}}"#.utf8)
        #expect(try JSONDecoder().decode(RemoteDeviceMappings.self, from: legacyMappings) == emptyMappings)
        let old = Data(#"{"action":"escape"}"#.utf8)
        #expect(try JSONDecoder().decode(ConfiguredButtonAction.self, from: old).macShortcut == nil)
        let suite = "MacShortcutsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.setAction(.runMacShortcut, for: .power)
        settings.setMacShortcut(first, for: .power, trigger: .singleClick)
        let configuration = try settings.exportedConfigurationData()
        var object = try #require(JSONSerialization.jsonObject(with: configuration) as? [String: Any])
        object.removeValue(forKey: "buttonMacShortcuts")
        object["buttonBindings"] = ["power": "escape"]
        try settings.importConfiguration(from: JSONSerialization.data(withJSONObject: object))
        #expect(settings.configuredAction(for: .power, trigger: .singleClick).macShortcut == nil)
        try settings.importConfiguration(from: configuration)
        settings.setExperimentalContinuousRecordingEnabled(true)
        settings.setExperimentalContinuousRecordingEnabled(false)
        #expect(settings.configuredAction(for: .power, trigger: .singleClick).macShortcut == first)
    }

    @Test @MainActor func duplicateRunsAreSuppressedAndHostDispatchPreservesBinding() async throws {
        var commands: [[String]] = []
        let service = MacShortcutsService { arguments, _ in
            commands.append(arguments)
            try await Task.sleep(nanoseconds: 50_000_000)
            return Data()
        }
        let suite = "MacShortcutsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BridgeAppModel(settings: AppSettings(defaults: defaults), macShortcuts: service)
        let action = ConfiguredButtonAction(action: .runMacShortcut, shortcut: nil, macShortcut: first)
        #expect(model.performExternalConfiguredAction(action))
        #expect(model.performExternalConfiguredAction(action))
        for _ in 0..<100 {
            if service.states[first.id] == .succeeded { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(service.states[first.id] == .succeeded)
        #expect(commands == [["run", first.id.uuidString]])
    }

    @Test(arguments: [MacShortcutsError.failed, .timedOut, .unavailable])
    @MainActor func displaysExecutionFailures(error: MacShortcutsError) async throws {
        let service = MacShortcutsService { _, _ in throw error }
        #expect(service.run(first))
        for _ in 0..<100 {
            if service.states[first.id] != .running { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let expected: MacShortcutsService.RunState
        switch error {
        case .timedOut: expected = .timedOut
        case .unavailable: expected = .unavailable
        default: expected = .failed
        }
        #expect(service.states[first.id] == expected)
    }

    @Test @MainActor func refreshKeepsPreviousListOnFailure() async throws {
        var shouldFail = false
        let service = MacShortcutsService { _, _ in
            if shouldFail { throw MacShortcutsError.failed }
            return Data("Work (Mac) (\(first.id))\n".utf8)
        }
        await service.refresh()
        #expect(service.shortcuts == [first])
        shouldFail = true
        await service.refresh()
        #expect(service.shortcuts == [first])
        #expect(service.listError != nil)
        #expect(!service.isLoading)
    }

    @Test func subprocessDrainsOutputAndDiscardsRunResults() async throws {
        let output = try await MacShortcutsCommand.executeProcess(
            ["%s", "test (value)"], timeout: 2, executableURL: URL(fileURLWithPath: "/usr/bin/printf"), capturesOutput: true
        )
        #expect(String(data: output, encoding: .utf8) == "test (value)")
        let discarded = try await MacShortcutsCommand.executeProcess(
            ["private result"], timeout: 2, executableURL: URL(fileURLWithPath: "/usr/bin/printf"), capturesOutput: false
        )
        #expect(discarded.isEmpty)
    }

    @Test func subprocessTimeoutAndOutputLimitAreBounded() async throws {
        let start = Date()
        await #expect(throws: MacShortcutsError.self) {
            try await MacShortcutsCommand.executeProcess(
                ["5"], timeout: 0.05, executableURL: URL(fileURLWithPath: "/bin/sleep"), capturesOutput: false
            )
        }
        #expect(Date().timeIntervalSince(start) < 2)
        await #expect(throws: MacShortcutsError.self) {
            try await MacShortcutsCommand.executeProcess(
                ["fixture"], timeout: 2, executableURL: URL(fileURLWithPath: "/usr/bin/yes"), capturesOutput: true
            )
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["REMOTE_MIC_TEST_SHORTCUTS_LIST"] == "1"))
    func readsInstalledShortcutsThroughPublicCLI() async throws {
        let output = try await MacShortcutsCommand.execute(["list", "--show-identifiers"], timeout: 15)
        let shortcuts = try MacShortcutsCommand.parseList(output)
        #expect(Set(shortcuts.map(\.id)).count == shortcuts.count)
    }
}
