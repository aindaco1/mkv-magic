import Foundation
import MKVMagicSystem

enum BundledToolVerification {
    static func arguments(for tool: BundledTool) -> [String] {
        switch tool {
        case .ffmpeg, .ffprobe:
            ["-hide_banner", "-version"]
        case .mkvmerge, .mkvpropedit, .mkvextract:
            ["--version"]
        }
    }

    static func firstOutputLine(from result: CommandResult) -> String? {
        let combined = result.standardOutput.text + "\n" + result.standardError.text
        return combined.split(whereSeparator: \Character.isNewline).first.map(String.init)
    }
}

struct BundledToolVerifier {
    private let runner: any CommandRunning

    init(runner: any CommandRunning = FoundationCommandRunner()) {
        self.runner = runner
    }

    func verify(toolRoot: URL) async throws -> [String] {
        let catalog = try ToolCatalog(rootURL: toolRoot)
        var summaries: [String] = []
        for tool in BundledTool.allCases {
            let result = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: tool),
                    arguments: BundledToolVerification.arguments(for: tool),
                    timeout: 20,
                    outputLimit: 65_536
                ))
            guard result.exitCode == 0,
                let line = BundledToolVerification.firstOutputLine(from: result),
                !line.isEmpty
            else {
                throw VerificationError.toolFailed(tool, result.exitCode)
            }
            summaries.append("\(tool.rawValue): \(line)")
        }
        return summaries
    }

    enum VerificationError: Error, Equatable {
        case toolFailed(BundledTool, Int32)
    }
}
