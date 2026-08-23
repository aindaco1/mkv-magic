import Foundation
import MKVMagicCore

public enum FastTrimCommandError: Error, Equatable, Sendable {
    case invalidPath
    case existingOutput
    case invalidPlan
}

extension FastTrimCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPath: "Fast Trim needs safe absolute source and output paths."
        case .existingOutput: "Fast Trim refuses to overwrite an existing output."
        case .invalidPlan: "The reviewed keyframe-aligned trim plan is inconsistent."
        }
    }
}

public struct FastTrimMKVCommand: Equatable, Sendable {
    public let arguments: [String]
    public let outputURL: URL

    public init(arguments: [String], outputURL: URL) {
        self.arguments = arguments
        self.outputURL = outputURL
    }
}

public struct FastTrimCommandBuilder: Sendable {
    public init() {}

    public func build(
        sourceURL rawSourceURL: URL,
        plan: FastTrimPlan,
        outputURL rawOutputURL: URL
    ) throws -> FastTrimMKVCommand {
        let sourceURL = rawSourceURL.standardizedFileURL
        let outputURL = rawOutputURL.standardizedFileURL
        guard safeAbsoluteFile(sourceURL), safeAbsoluteFile(outputURL),
            sourceURL != outputURL,
            sourceURL.pathExtension.lowercased() == "mkv",
            outputURL.pathExtension.lowercased() == "mkv"
        else {
            throw FastTrimCommandError.invalidPath
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw FastTrimCommandError.existingOutput
        }
        guard plan.adjusted.start >= .zero,
            plan.adjusted.end > plan.adjusted.start,
            plan.adjusted.start >= plan.requested.start,
            plan.adjusted.end >= plan.requested.end
        else {
            throw FastTrimCommandError.invalidPlan
        }
        let part = "parts:\(timestamp(plan.adjusted.start))-\(timestamp(plan.adjusted.end))"
        return FastTrimMKVCommand(
            arguments: [
                "--abort-on-warnings",
                "--flush-on-close",
                "--normalize-language-ietf", "canonical",
                "--disable-track-statistics-tags",
                "--output", outputURL.path,
                "--split", part,
                "--no-chapters",
                sourceURL.path,
            ],
            outputURL: outputURL
        )
    }

    private func timestamp(_ time: MediaTime) -> String {
        let totalSeconds = time.nanoseconds / 1_000_000_000
        let nanoseconds = time.nanoseconds % 1_000_000_000
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(
            format: "%02lld:%02lld:%02lld.%09lld",
            hours,
            minutes,
            seconds,
            nanoseconds
        )
    }

    private func safeAbsoluteFile(_ url: URL) -> Bool {
        url.isFileURL && url.path.hasPrefix("/") && !url.path.contains("\0")
    }
}
