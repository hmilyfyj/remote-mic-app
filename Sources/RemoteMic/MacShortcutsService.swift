import Combine
import Darwin
import Foundation

enum MacShortcutsError: Error {
    case unavailable
    case failed
    case timedOut
    case invalidList
}

enum MacShortcutsCommand {
    static func parseList(_ data: Data) throws -> [MacShortcut] {
        guard let text = String(data: data, encoding: .utf8) else { throw MacShortcutsError.invalidList }
        let pattern = #"(?ms)^(.+?) \(([0-9A-Fa-f-]{36})\)\r?$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var seen = Set<UUID>()
        let shortcuts = matches.compactMap { match -> MacShortcut? in
            guard let nameRange = Range(match.range(at: 1), in: text),
                  let idRange = Range(match.range(at: 2), in: text),
                  let id = UUID(uuidString: String(text[idRange])),
                  seen.insert(id).inserted else { return nil }
            return MacShortcut(id: id, name: String(text[nameRange]))
        }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !shortcuts.isEmpty else {
            throw MacShortcutsError.invalidList
        }
        return shortcuts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func arguments(for shortcut: MacShortcut) -> [String] {
        ["run", shortcut.id.uuidString]
    }

    static func execute(_ arguments: [String], timeout: TimeInterval) async throws -> Data {
        try await executeProcess(arguments, timeout: timeout,
                                 executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
                                 capturesOutput: arguments.first == "list")
    }

    static func executeProcess(
        _ arguments: [String], timeout: TimeInterval, executableURL: URL, capturesOutput: Bool
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            // Process and pipe ownership stay on one worker. Output is bounded and never logged.
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try executeBlocking(arguments, timeout: timeout,
                                                                        executableURL: executableURL,
                                                                        capturesList: capturesOutput)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func executeBlocking(
        _ arguments: [String], timeout: TimeInterval, executableURL: URL, capturesList: Bool
    ) throws -> Data {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = capturesList ? output : FileHandle.nullDevice
        defer {
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }
        let descriptor = output.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else { throw MacShortcutsError.unavailable }
        do { try process.run() } catch { throw MacShortcutsError.unavailable }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        func drain() throws {
            guard capturesList else { return }
            // Limit each drain pass so a busy writer cannot bypass the deadline.
            for _ in 0..<128 {
                let count = read(descriptor, &buffer, buffer.count)
                guard count > 0 else { break }
                guard data.count + count <= 1_048_576 else { throw MacShortcutsError.invalidList }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        do {
            while process.isRunning {
                try drain()
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw MacShortcutsError.timedOut }
                usleep(20_000)
            }
            try drain()
        } catch {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MacShortcutsError.failed }
        return data
    }
}

@MainActor
final class MacShortcutsService: ObservableObject {
    typealias Executor = ([String], TimeInterval) async throws -> Data
    enum RunState: Equatable {
        case running, succeeded, failed, timedOut, unavailable

        var localizationKey: String {
            switch self {
            case .running: return "mac_shortcuts.running"
            case .succeeded: return "mac_shortcuts.succeeded"
            case .failed: return "mac_shortcuts.failed"
            case .timedOut: return "mac_shortcuts.timed_out"
            case .unavailable: return "mac_shortcuts.unavailable"
            }
        }
    }

    @Published private(set) var shortcuts: [MacShortcut] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var listError: String?
    @Published private(set) var states: [UUID: RunState] = [:]
    private let executor: Executor

    nonisolated init(executor: @escaping Executor = MacShortcutsCommand.execute) {
        self.executor = executor
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            shortcuts = try MacShortcutsCommand.parseList(await executor(["list", "--show-identifiers"], 15))
            hasLoaded = true
            listError = nil
        } catch {
            listError = "mac_shortcuts.list_failed"
        }
    }

    @discardableResult
    func run(_ shortcut: MacShortcut?) -> Bool {
        guard let shortcut else { return true }
        guard states[shortcut.id] != .running else { return true }
        states[shortcut.id] = .running
        Task {
            do {
                _ = try await executor(MacShortcutsCommand.arguments(for: shortcut), 120)
                states[shortcut.id] = .succeeded
            } catch MacShortcutsError.timedOut {
                states[shortcut.id] = .timedOut
            } catch MacShortcutsError.unavailable {
                states[shortcut.id] = .unavailable
            } catch {
                states[shortcut.id] = .failed
            }
        }
        return true
    }
}
