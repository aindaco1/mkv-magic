import Foundation
import MKVMagicSystem

public enum MKVPropertyEditError: Error, Equatable, Sendable {
    case invalidTitle
    case toolFailed(exitCode: Int32, message: String)
}

extension MKVPropertyEditError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidTitle:
            "The segment title is too large or contains an unsupported null character."
        case .toolFailed(let exitCode, let message):
            "mkvpropedit could not edit the temporary output (code \(exitCode)): \(message)"
        }
    }
}

public struct MKVPropertyEditor<Runner: CommandRunning>: Sendable {
    private let executableURL: URL
    private let runner: Runner

    public init(executableURL: URL, runner: Runner) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public func editSegmentTitle(at fileURL: URL, title: String?) async throws {
        if let title {
            guard !title.contains("\0"), title.utf8.count <= 4_096 else {
                throw MKVPropertyEditError.invalidTitle
            }
        }
        var arguments = [fileURL.path, "--edit", "info"]
        if let title {
            arguments.append(contentsOf: ["--set", "title=\(title)"])
        } else {
            arguments.append(contentsOf: ["--delete", "title"])
        }
        let result = try await runner.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: arguments,
                timeout: 120,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0 else {
            let combined =
                [result.standardError.text, result.standardOutput.text]
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                ?? "Unknown tool error"
            let message = combined.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MKVPropertyEditError.toolFailed(
                exitCode: result.exitCode,
                message: String(message.prefix(240))
            )
        }
    }
}
