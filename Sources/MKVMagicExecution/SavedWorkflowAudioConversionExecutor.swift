import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

public enum SavedWorkflowAudioConversionExecutionError: Error, Equatable, Sendable {
    case missingReviewedConversion
    case unexpectedVideoConversion
    case sourceChangedSinceReview
}

extension SavedWorkflowAudioConversionExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingReviewedConversion:
            "The reviewed workflow does not contain one resolved audio conversion."
        case .unexpectedVideoConversion:
            "A workflow with video conversion must use the fused video/audio executor."
        case .sourceChangedSinceReview:
            "The source changed after workflow review. Review the workflow again."
        }
    }
}

/// Applies packet-copy and metadata work to one private verified intermediate,
/// then converts every audio track exactly once while independently proving that
/// copied video and subtitle packets match the reviewed source.
public struct SavedWorkflowAudioConversionExecutor<
    Runner: CommandRunning & CommandLineDigesting,
    Inspector: MediaInspecting
>: Sendable {
    private let savedWorkflowExecutor: SavedWorkflowExecutor<Runner, Inspector>
    private let audioConversionExecutor: CompleteAudioConversionExecutor<Runner, Inspector>

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
        audioConversionExecutor = CompleteAudioConversionExecutor(
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
        guard workflow.videoConversionChoice == nil else {
            throw SavedWorkflowAudioConversionExecutionError.unexpectedVideoConversion
        }
        guard let preset = workflow.audioConversionPreset else {
            throw SavedWorkflowAudioConversionExecutionError.missingReviewedConversion
        }
        let validateReviewedSource = try mediaFileRevisionValidator(
            sourceURL: source.sourceURL,
            expectedRevision: expectedSourceRevision,
            changedError: SavedWorkflowAudioConversionExecutionError.sourceChangedSinceReview
        )

        if workflow.hasDeterministicMediaOperations {
            return try await PrivateTemporaryDirectory.withDirectory(
                prefix: "mkv-magic-workflow-audio-conversion"
            ) { directory in
                let intermediateURL = directory.appendingPathComponent("prepared.mkv")
                let prepared = try await savedWorkflowExecutor.execute(
                    source: source,
                    trackRemoval: workflow.trackRemoval,
                    removesSegmentTitle: workflow.removesSegmentTitle,
                    externalSubtitleInput: workflow.externalSubtitleInput,
                    externalSubtitlePayload: externalSubtitlePayload,
                    createsUnchangedCopy: false,
                    expectedSourceRevision: expectedSourceRevision,
                    destinationURL: intermediateURL
                )
                let preview = try await audioConversionExecutor.preview(
                    source: prepared,
                    preset: preset,
                    capabilities: capabilities
                )
                return try await audioConversionExecutor.execute(
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
        let preview = try await audioConversionExecutor.preview(
            source: source,
            preset: preset,
            capabilities: capabilities
        )
        return try await audioConversionExecutor.execute(
            preview: preview,
            destinationURL: destinationURL,
            validateReviewedSource: validateReviewedSource,
            onStage: onStage
        )
    }

}
