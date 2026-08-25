import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

public enum SavedWorkflowVideoConversionExecutionError: Error, Equatable, Sendable {
    case missingReviewedConversion
    case sourceChangedSinceReview
}

extension SavedWorkflowVideoConversionExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingReviewedConversion:
            "The reviewed workflow does not contain one resolved video conversion."
        case .sourceChangedSinceReview:
            "The source changed after workflow review. Review the workflow again."
        }
    }
}

/// Applies all packet-copy and metadata work to a private verified intermediate,
/// then performs exactly one complete-file video encode into the user destination.
/// A conversion-only workflow skips the intermediate entirely.
public struct SavedWorkflowVideoConversionExecutor<
    Runner: CommandRunning & CommandLineDigesting,
    Inspector: MediaInspecting
>: Sendable {
    private let savedWorkflowExecutor: SavedWorkflowExecutor<Runner, Inspector>
    private let exactTrimExecutor: ExactTrimExecutor<Runner, Inspector>

    public init(
        ffmpegURL: URL,
        ffprobeURL: URL,
        mkvmergeURL: URL,
        mkvextractURL: URL,
        mkvpropeditURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        savedWorkflowExecutor = SavedWorkflowExecutor(
            mkvmergeURL: mkvmergeURL,
            mkvpropeditURL: mkvpropeditURL,
            mkvextractURL: mkvextractURL,
            runner: runner,
            inspector: inspector
        )
        exactTrimExecutor = ExactTrimExecutor(
            ffmpegURL: ffmpegURL,
            ffprobeURL: ffprobeURL,
            mkvextractURL: mkvextractURL,
            mkvpropeditURL: mkvpropeditURL,
            runner: runner,
            inspector: inspector
        )
    }

    public func execute(
        source: MediaAsset,
        workflow: CompiledSavedWorkflow,
        externalSubtitlePayload: ExternalSubtitleMuxPayload? = nil,
        capabilities: FFmpegEncodingCapabilities,
        expectedSourceRevision: MediaFileRevision? = nil,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard let choice = workflow.videoConversionChoice else {
            throw SavedWorkflowVideoConversionExecutionError.missingReviewedConversion
        }
        let validateReviewedSource = try mediaFileRevisionValidator(
            sourceURL: source.sourceURL,
            expectedRevision: expectedSourceRevision,
            changedError: SavedWorkflowVideoConversionExecutionError.sourceChangedSinceReview
        )

        if workflow.hasDeterministicMediaOperations {
            return try await PrivateTemporaryDirectory.withDirectory(
                prefix: "mkv-magic-workflow-conversion"
            ) { directory in
                let intermediateURL = directory.appendingPathComponent("prepared.mkv")
                let prepared = try await savedWorkflowExecutor.execute(
                    source: source,
                    trackRemoval: workflow.trackRemoval,
                    attachmentRemoval: workflow.attachmentRemoval,
                    removesSegmentTitle: workflow.removesSegmentTitle,
                    clearsAllTags: workflow.clearsAllTags,
                    externalSubtitleInput: workflow.externalSubtitleInput,
                    externalSubtitlePayload: externalSubtitlePayload,
                    createsUnchangedCopy: false,
                    expectedSourceRevision: expectedSourceRevision,
                    destinationURL: intermediateURL
                )
                let preview = try await conversionPreview(
                    source: prepared,
                    choice: choice,
                    capabilities: capabilities
                )
                return try await exactTrimExecutor.execute(
                    preview: preview,
                    destinationURL: destinationURL,
                    validateReviewedSource: validateReviewedSource,
                    onStage: onStage
                )
            }
        }

        guard externalSubtitlePayload == nil else {
            throw SavedWorkflowExecutionError.mismatchedExternalSubtitleInput
        }
        let preview = try await conversionPreview(
            source: source,
            choice: choice,
            capabilities: capabilities
        )
        return try await exactTrimExecutor.execute(
            preview: preview,
            destinationURL: destinationURL,
            validateReviewedSource: validateReviewedSource,
            onStage: onStage
        )
    }

    private func conversionPreview(
        source: MediaAsset,
        choice: ExactTrimChoice,
        capabilities: FFmpegEncodingCapabilities
    ) async throws -> ExactTrimPreview {
        guard let duration = source.duration else {
            throw ExactTrimPlanningError.invalidDuration
        }
        return try await exactTrimExecutor.preview(
            source: source,
            range: MediaTrimRange(start: .zero, end: duration),
            choice: choice,
            operation: .transcode,
            capabilities: capabilities
        )
    }

}
