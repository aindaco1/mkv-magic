import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum ExternalSubtitleMuxError: Error, Equatable, Sendable {
    case unsupportedSource
    case unsupportedDestination
    case invalidTrackName
    case sourceAndSubtitleAreSame
    case toolFailed(exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension ExternalSubtitleMuxError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "This first subtitle-muxing slice requires an inspected Matroska source."
        case .unsupportedDestination:
            "External subtitle muxing currently creates an MKV file."
        case .invalidTrackName:
            "The subtitle track name is too large or contains an unsupported null character."
        case .sourceAndSubtitleAreSame:
            "The external subtitle must be a different file from the video source."
        case .toolFailed(let exitCode, let message):
            "mkvmerge could not add the subtitle (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public typealias ExternalSubtitleMuxExecutionStage = VerifiedOutputExecutionStage

public struct MKVExternalSubtitleMuxer<Runner: CommandRunning>: Sendable {
    private let executableURL: URL
    private let runner: Runner

    public init(executableURL: URL, runner: Runner) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public func mux(
        source: MediaAsset,
        subtitleURL: URL,
        metadata: ExternalSubtitleTrackMetadata,
        outputURL: URL
    ) async throws {
        let arguments = try Self.arguments(
            source: source,
            subtitleURL: subtitleURL,
            metadata: metadata,
            outputURL: outputURL
        )
        let result = try await runner.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: arguments,
                timeout: 24 * 60 * 60,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0 else {
            let combined =
                [result.standardError.text, result.standardOutput.text]
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                ?? "Unknown tool error"
            throw ExternalSubtitleMuxError.toolFailed(
                exitCode: result.exitCode,
                message: String(
                    combined.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
            )
        }
    }

    public static func arguments(
        source: MediaAsset,
        subtitleURL: URL,
        metadata: ExternalSubtitleTrackMetadata,
        outputURL: URL
    ) throws -> [String] {
        let language = try TrackLanguageTag.canonical(metadata.language)
        if let name = metadata.name {
            guard !name.contains("\0"), name.utf8.count <= 4_096 else {
                throw ExternalSubtitleMuxError.invalidTrackName
            }
        }
        var arguments = [
            "--output", outputURL.path,
            "--abort-on-warnings",
            "--normalize-language-ietf", "canonical",
            "--disable-track-statistics-tags",
            source.sourceURL.path,
            "--language", "0:\(language)",
            "--default-track-flag", "0:\(metadata.isDefault ? "yes" : "no")",
            "--forced-display-flag", "0:\(metadata.isForced ? "yes" : "no")",
            "--hearing-impaired-flag", "0:\(metadata.isHearingImpaired ? "yes" : "no")",
        ]
        if let name = metadata.name {
            arguments.append(contentsOf: ["--track-name", "0:\(name)"])
        }
        arguments.append(subtitleURL.path)
        let sourceTracks = source.tracks.filter { $0.kind != .attachment }
        let trackOrder = (sourceTracks.map { "0:\($0.id)" } + ["1:0"]).joined(separator: ",")
        arguments.append(contentsOf: ["--track-order", trackOrder])
        return arguments
    }
}

public struct ExternalSubtitleMuxExecutor<Runner: CommandRunning, Inspector: MediaInspecting>:
    Sendable
{
    private let muxer: MKVExternalSubtitleMuxer<Runner>
    private let inspector: Inspector
    private let verifier = ExternalSubtitleMuxOutputVerifier()

    public init(mkvmergeURL: URL, runner: Runner, inspector: Inspector) {
        muxer = MKVExternalSubtitleMuxer(executableURL: mkvmergeURL, runner: runner)
        self.inspector = inspector
    }

    public func execute(
        source: MediaAsset,
        subtitlePreview: SubtitleCleanupFilePreview,
        metadata: ExternalSubtitleTrackMetadata,
        destinationURL: URL,
        onStage: @escaping @Sendable (ExternalSubtitleMuxExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        guard MatroskaEditingPolicy.supports(source) else {
            throw ExternalSubtitleMuxError.unsupportedSource
        }
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw ExternalSubtitleMuxError.unsupportedDestination
        }
        guard
            source.sourceURL.standardizedFileURL
                != subtitlePreview.sourceURL.standardizedFileURL
        else {
            throw ExternalSubtitleMuxError.sourceAndSubtitleAreSame
        }
        try SubtitleCleanupExecutor().validateCurrent(subtitlePreview)
        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: source,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                let normalizedSubtitleURL = outputURL.deletingLastPathComponent()
                    .appendingPathComponent("external-subtitle.srt")
                let normalizedSubtitle = Data(
                    SubRipCodec().serialize(subtitlePreview.cleanup.original).utf8
                )
                try normalizedSubtitle.write(
                    to: normalizedSubtitleURL, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: normalizedSubtitleURL) }
                try await muxer.mux(
                    source: source,
                    subtitleURL: normalizedSubtitleURL,
                    metadata: metadata,
                    outputURL: outputURL
                )
            },
            verify: { output in
                try verifier.verify(
                    original: source,
                    output: output,
                    expectedMetadata: metadata,
                    subtitleEnd: subtitlePreview.cleanup.original.cues.map(\.end).max()
                        ?? SubRipTimestamp(milliseconds: 0)
                )
            },
            committedAuditError: { outputURL, reason in
                ExternalSubtitleMuxError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }
}
