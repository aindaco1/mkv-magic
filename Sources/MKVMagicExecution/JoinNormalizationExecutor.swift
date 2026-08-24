import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

public enum JoinNormalizationExecutionError: Error, Equatable, Sendable {
    case unsupportedDestination
    case insufficientSources
    case invalidSourcePath(sourceIndex: Int)
    case unsupportedSourceDuration(sourceIndex: Int)
    case unsupportedSourceTimeline
    case staleSource
    case toolFailed(exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension JoinNormalizationExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedDestination:
            "Join normalization currently creates an internal Matroska MKV stream bundle."
        case .insufficientSources:
            "Join normalization needs at least two inspected sources."
        case .invalidSourcePath(let sourceIndex):
            "Part \(sourceIndex + 1) is not a safe regular source file."
        case .unsupportedSourceDuration(let sourceIndex):
            "Part \(sourceIndex + 1) needs a known positive duration before normalization."
        case .unsupportedSourceTimeline:
            "The joined source timeline is too large to normalize safely."
        case .staleSource:
            "A source changed after the join normalization preview was created."
        case .toolFailed(let exitCode, let message):
            "FFmpeg could not create the normalized stream bundle (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified stream bundle was saved as \(outputURL.lastPathComponent), but its "
                + "final reopen audit failed: \(reason)"
        }
    }
}

public enum JoinNormalizationVerificationError: Error, Equatable, Sendable {
    case emptyOutput
    case wrongContainer
    case wrongDuration
    case wrongTrackCount
    case unexpectedStructure
    case videoMismatch(laneIndex: Int)
    case audioMismatch(laneIndex: Int)
}

extension JoinNormalizationVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyOutput:
            "The normalized stream bundle is empty."
        case .wrongContainer:
            "The normalized stream bundle is not Matroska."
        case .wrongDuration:
            "The normalized stream bundle does not match the reviewed joined duration."
        case .wrongTrackCount:
            "The normalized stream bundle does not contain exactly the encoded lanes."
        case .unexpectedStructure:
            "The normalized stream bundle unexpectedly contains chapters or attachments."
        case .videoMismatch(let laneIndex):
            "Normalized video lane \(laneIndex + 1) does not match its reviewed target."
        case .audioMismatch(let laneIndex):
            "Normalized audio lane \(laneIndex + 1) does not match its reviewed target."
        }
    }
}

public struct JoinNormalizationPreview: Equatable, Sendable {
    public let sources: [MediaAsset]
    public let resolvedPlan: ResolvedJoinNormalizationPlan
    public let capabilities: FFmpegEncodingCapabilities
    public let sourceRevisions: [JoinNormalizationSourceRevision]

    init(
        sources: [MediaAsset],
        resolvedPlan: ResolvedJoinNormalizationPlan,
        capabilities: FFmpegEncodingCapabilities,
        sourceRevisions: [JoinNormalizationSourceRevision]
    ) {
        self.sources = sources
        self.resolvedPlan = resolvedPlan
        self.capabilities = capabilities
        self.sourceRevisions = sourceRevisions
    }
}

public struct JoinNormalizationOutputVerifier: Sendable {
    public init() {}

    public func verify(
        sources: [MediaAsset],
        resolvedPlan: ResolvedJoinNormalizationPlan,
        output: MediaAsset
    ) throws {
        guard output.fileSize ?? 0 > 0 else {
            throw JoinNormalizationVerificationError.emptyOutput
        }
        guard output.container.localizedCaseInsensitiveContains("matroska") else {
            throw JoinNormalizationVerificationError.wrongContainer
        }
        try verifyDuration(sources: sources, output: output)
        guard output.attachments.isEmpty,
            output.tracks.allSatisfy({ $0.kind != .attachment }),
            output.chapters.isEmpty,
            output.chapterEntryCount == nil || output.chapterEntryCount == 0
        else {
            throw JoinNormalizationVerificationError.unexpectedStructure
        }

        let videoLaneIndices = resolvedPlan.proposal.videoLanes.filter(\.encodesVideo)
            .map(\.laneIndex).sorted()
        let audioLaneIndices = resolvedPlan.proposal.audioLanes.filter(\.encodesAudio)
            .map(\.laneIndex).sorted()
        let outputTracks = output.tracks.filter { $0.kind != .attachment }
        let expectedTrackCount = videoLaneIndices.count + audioLaneIndices.count
        guard outputTracks.count == expectedTrackCount,
            outputTracks.allSatisfy({ $0.kind == .video || $0.kind == .audio })
        else {
            throw JoinNormalizationVerificationError.wrongTrackCount
        }

        let videoTracks = Array(outputTracks.prefix(videoLaneIndices.count))
        for (track, laneIndex) in zip(videoTracks, videoLaneIndices) {
            guard let choice = resolvedPlan.choices.videoTargetsByLane[laneIndex],
                track.kind == .video,
                normalized(track.codec) == expectedCodec(for: choice.preset),
                track.dimensions == choice.canvas,
                track.displayDimensions == choice.canvas,
                track.bitDepth == expectedBitDepth(for: choice.preset)
            else {
                throw JoinNormalizationVerificationError.videoMismatch(
                    laneIndex: laneIndex
                )
            }
            let matchesDynamicRange =
                switch choice.dynamicRange {
                case .sdr:
                    MediaHDR10Signal.isBT709SDR(track)
                case .hdr10:
                    reviewedHDR10Signal(
                        sources: sources,
                        resolvedPlan: resolvedPlan,
                        laneIndex: laneIndex
                    ).map { MediaHDR10Signal(track: track) == $0 } ?? false
                }
            guard matchesDynamicRange else {
                throw JoinNormalizationVerificationError.videoMismatch(
                    laneIndex: laneIndex
                )
            }
        }

        let audioTracks = outputTracks.dropFirst(videoLaneIndices.count)
        for (track, laneIndex) in zip(audioTracks, audioLaneIndices) {
            guard let choice = resolvedPlan.choices.audioTargetsByLane[laneIndex],
                track.kind == .audio,
                normalized(track.codec) == choice.preset.codecName,
                track.channels == choice.channels,
                track.sampleRate == choice.sampleRate,
                normalizedAudioLayout(track.channelLayout)
                    == normalizedAudioLayout(choice.channelLayout)
            else {
                throw JoinNormalizationVerificationError.audioMismatch(
                    laneIndex: laneIndex
                )
            }
        }
    }

    private func verifyDuration(sources: [MediaAsset], output: MediaAsset) throws {
        var expectedNanoseconds: Int64 = 0
        for source in sources {
            guard let duration = source.duration, duration.nanoseconds > 0 else {
                throw JoinNormalizationVerificationError.wrongDuration
            }
            let addition = expectedNanoseconds.addingReportingOverflow(duration.nanoseconds)
            guard !addition.overflow else {
                throw JoinNormalizationVerificationError.wrongDuration
            }
            expectedNanoseconds = addition.partialValue
        }
        guard let outputDuration = output.duration, outputDuration.nanoseconds > 0 else {
            throw JoinNormalizationVerificationError.wrongDuration
        }
        let difference = outputDuration.nanoseconds.subtractingReportingOverflow(
            expectedNanoseconds
        )
        let scaledTolerance = Int64(sources.count).multipliedReportingOverflow(by: 50_000_000)
        guard !difference.overflow, !scaledTolerance.overflow,
            difference.partialValue.magnitude
                <= UInt64(max(100_000_000, scaledTolerance.partialValue))
        else {
            throw JoinNormalizationVerificationError.wrongDuration
        }
    }

    private func expectedCodec(for preset: VideoPreset) -> String {
        switch preset {
        case .av1Quality: "av1"
        case .hevcCompatibility: "hevc"
        case .h264Compatibility: "h264"
        case .proRes: "prores"
        }
    }

    private func expectedBitDepth(for preset: VideoPreset) -> Int {
        switch preset {
        case .h264Compatibility: 8
        case .av1Quality, .hevcCompatibility, .proRes: 10
        }
    }

    private func reviewedHDR10Signal(
        sources: [MediaAsset],
        resolvedPlan: ResolvedJoinNormalizationPlan,
        laneIndex: Int
    ) -> MediaHDR10Signal? {
        let mapping = resolvedPlan.proposal.report.mapping
        guard mapping.lanes.indices.contains(laneIndex) else { return nil }
        let lane = mapping.lanes[laneIndex]
        let signals = sources.indices.compactMap { sourceIndex -> MediaHDR10Signal? in
            guard lane.trackIDsBySource.indices.contains(sourceIndex),
                let trackID = lane.trackIDsBySource[sourceIndex],
                let track = sources[sourceIndex].tracks.first(where: { $0.id == trackID })
            else { return nil }
            return MediaHDR10Signal(track: track)
        }
        guard signals.count == sources.count, let first = signals.first,
            signals.allSatisfy({ $0 == first })
        else { return nil }
        return first
    }

    private func normalizedAudioLayout(_ value: String?) -> String {
        normalized(value)
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

public struct JoinNormalizationExecutor<Runner: CommandRunning, Inspector: MediaInspecting>:
    Sendable
{
    private let ffmpegURL: URL
    private let runner: Runner
    private let inspector: Inspector
    private let commandBuilder = JoinNormalizationCommandBuilder()
    private let verifier = JoinNormalizationOutputVerifier()

    public init(ffmpegURL: URL, runner: Runner, inspector: Inspector) {
        self.ffmpegURL = ffmpegURL
        self.runner = runner
        self.inspector = inspector
    }

    public func preview(
        sources: [MediaAsset],
        resolvedPlan: ResolvedJoinNormalizationPlan,
        capabilities: FFmpegEncodingCapabilities
    ) throws -> JoinNormalizationPreview {
        guard sources.count >= 2 else {
            throw JoinNormalizationExecutionError.insufficientSources
        }
        var timelineNanoseconds: Int64 = 0
        let revisions = try sources.enumerated().map { sourceIndex, source in
            guard let duration = source.duration, duration.nanoseconds > 0 else {
                throw JoinNormalizationExecutionError.unsupportedSourceDuration(
                    sourceIndex: sourceIndex
                )
            }
            let addition = timelineNanoseconds.addingReportingOverflow(duration.nanoseconds)
            guard !addition.overflow else {
                throw JoinNormalizationExecutionError.unsupportedSourceTimeline
            }
            timelineNanoseconds = addition.partialValue
            let revision: JoinNormalizationSourceRevision
            do {
                revision = try JoinNormalizationSourceRevision.read(source.sourceURL)
            } catch {
                throw JoinNormalizationExecutionError.invalidSourcePath(
                    sourceIndex: sourceIndex
                )
            }
            guard source.fileSize == nil || source.fileSize == revision.fileSize else {
                throw JoinNormalizationExecutionError.staleSource
            }
            return revision
        }
        return JoinNormalizationPreview(
            sources: sources,
            resolvedPlan: resolvedPlan,
            capabilities: capabilities,
            sourceRevisions: revisions
        )
    }

    public func execute(
        preview: JoinNormalizationPreview,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw JoinNormalizationExecutionError.unsupportedDestination
        }
        try Task.checkCancellation()
        try validateCurrent(preview)
        guard let firstSource = preview.sources.first else {
            throw JoinNormalizationExecutionError.insufficientSources
        }
        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: firstSource,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                try Task.checkCancellation()
                try validateCurrent(preview)
                let command = try commandBuilder.build(
                    sources: preview.sources,
                    resolvedPlan: preview.resolvedPlan,
                    capabilities: preview.capabilities,
                    outputURL: outputURL
                )
                let result = try await runner.run(
                    CommandRequest(
                        executableURL: ffmpegURL,
                        arguments: command.arguments,
                        timeout: 24 * 60 * 60,
                        outputLimit: 1_048_576
                    )
                )
                guard result.exitCode == 0 else {
                    throw JoinNormalizationExecutionError.toolFailed(
                        exitCode: result.exitCode,
                        message: conciseMessage(result)
                    )
                }
                try Task.checkCancellation()
                try validateCurrent(preview)
            },
            verify: { output in
                try Task.checkCancellation()
                try validateCurrent(preview)
                try verifier.verify(
                    sources: preview.sources,
                    resolvedPlan: preview.resolvedPlan,
                    output: output
                )
            },
            committedAuditError: { outputURL, reason in
                JoinNormalizationExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }

    public func validateCurrent(_ preview: JoinNormalizationPreview) throws {
        guard preview.sources.count == preview.sourceRevisions.count else {
            throw JoinNormalizationExecutionError.staleSource
        }
        for (source, expected) in zip(preview.sources, preview.sourceRevisions) {
            guard
                (try? JoinNormalizationSourceRevision.read(source.sourceURL)) == expected
            else {
                throw JoinNormalizationExecutionError.staleSource
            }
        }
    }

    private func conciseMessage(_ result: CommandResult) -> String {
        let message =
            [result.standardError.text, result.standardOutput.text]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Unknown tool error"
        return String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }
}
