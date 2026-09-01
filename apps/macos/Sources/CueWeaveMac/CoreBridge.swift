import Foundation

enum CoreBridgeError: LocalizedError {
    case cliMissing
    case failed(Int32, String)
    case invalidResponse(String)
    case core(String, String)

    var errorDescription: String? {
        switch self {
        case .cliMissing:
            L10n.shared.t("error.cliMissing")
        case let .failed(code, message):
            L10n.shared.t("error.coreExit", String(code), message)
        case let .invalidResponse(message):
            L10n.shared.t("error.invalidResponse", message)
        case let .core(code, message):
            L10n.shared.t("error.core", code, message)
        }
    }
}

enum CoreBridge {
    private static let processes = ProcessRegistry()

    static func call(_ command: String, payload: [String: Any] = [:]) async throws {
        let requestID = UUID().uuidString
        let request = try JSONSerialization.data(withJSONObject: [
            "protocol_version": 1,
            "request_id": requestID,
            "command": command,
            "payload": payload,
        ])
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = try executableURL()
            process.arguments = ["rpc"]
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            processes.attach(process)
            defer { processes.detach(process) }
            try input.fileHandleForWriting.write(contentsOf: request)
            try input.fileHandleForWriting.close()
            let stdout = output.fileHandleForReading.readDataToEndOfFile()
            let stderr = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                throw CoreBridgeError.failed(process.terminationStatus, message)
            }
            guard let envelope = try JSONSerialization.jsonObject(with: stdout) as? [String: Any],
                  envelope["request_id"] as? String == requestID,
                  let ok = envelope["ok"] as? Bool
            else { throw CoreBridgeError.invalidResponse("envelope mismatch") }
            if !ok {
                let error = envelope["error"] as? [String: Any]
                throw CoreBridgeError.core(
                    error?["code"] as? String ?? "unknown",
                    error?["message"] as? String ?? "Unknown Core error"
                )
            }
        }.value
    }

    static func cancelActive() {
        processes.cancel()
    }

    private static func executableURL() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["CUEWEAVE_CLI"] {
            let url = URL(fileURLWithPath: configured)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/cueweave-cli")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0 ..< 6 {
            for relative in ["target/debug/cueweave-cli", "target/release/cueweave-cli"] {
                let candidate = directory.appendingPathComponent(relative)
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            }
            directory.deleteLastPathComponent()
        }
        throw CoreBridgeError.cliMissing
    }
}

private final class ProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private weak var process: Process?

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func detach(_ process: Process) {
        lock.lock()
        if self.process === process { self.process = nil }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let running = process
        lock.unlock()
        if running?.isRunning == true { running?.terminate() }
    }
}
