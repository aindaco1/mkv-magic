import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

public enum CommonFormatJoinExecutionStage: Equatable, Sendable {
    case normalizing
    case assembling
    case verifying
    case committing
}

/// Runs the reviewed common-format join as one private pipeline. Encoded lanes
/// are created once in a verified temporary stream bundle, compatible lanes are
/// packet-copied during final assembly, and the private bundle is always removed.
public struct CommonFormatJoinExecutor<
    Runner: CommandRunning & CommandLineDigesting,
    Inspector: MediaInspecting
>: Sendable {
    private let ffmpegURL: URL
    private let ffprobeURL: URL
    private let mkvmergeURL: URL
    private let mkvextractURL: URL
    private let runner: Runner
    private let inspector: Inspector

    public init(
        ffmpegURL: URL,
        ffprobeURL: URL,
        mkvmergeURL: URL,
        mkvextractURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
        self.mkvmergeURL = mkvmergeURL
        self.mkvextractURL = mkvextractURL
        self.runner = runner
        self.inspector = inspector
    }

    public func execute(
        normalizationPreview: JoinNormalizationPreview,
        resolvedPlan: ResolvedJoinNormalizationPlan,
        chapters: JoinedChapterComposition,
        destinationURL: URL,
        onStage: @escaping @Sendable (CommonFormatJoinExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        guard normalizationPreview.resolvedPlan == resolvedPlan else {
            throw JoinFinalAssemblyExecutionError.staleInput
        }
        return try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-common-join"
        ) { directory in
            try Task.checkCancellation()
            try await onStage(.normalizing)
            let normalized = try await JoinNormalizationExecutor(
                ffmpegURL: ffmpegURL,
                runner: runner,
                inspector: inspector
            ).execute(
                preview: normalizationPreview,
                destinationURL: directory.appendingPathComponent(
                    "verified-normalized-streams.mkv"
                )
            )
            try Task.checkCancellation()
            try await onStage(.assembling)
            let finalExecutor = JoinFinalAssemblyExecutor(
                ffmpegURL: ffmpegURL,
                ffprobeURL: ffprobeURL,
                mkvmergeURL: mkvmergeURL,
                mkvextractURL: mkvextractURL,
                runner: runner,
                inspector: inspector
            )
            let finalPreview = try await finalExecutor.preview(
                sources: normalizationPreview.sources,
                resolvedPlan: resolvedPlan,
                normalizedBundle: normalized,
                chapters: chapters
            )
            return try await finalExecutor.execute(
                preview: finalPreview,
                destinationURL: destinationURL,
                onStage: { stage in
                    switch stage {
                    case .verifying: try await onStage(.verifying)
                    case .committing: try await onStage(.committing)
                    }
                }
            )
        }
    }
}
