import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

public enum SavedWorkflowExecutionError: Error, Equatable, Sendable {
    case unsupportedContainer
    case noOperations
    case missingExternalSubtitleInput
    case mismatchedExternalSubtitleInput
    case sourceChangedSinceReview
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension SavedWorkflowExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedContainer:
            "Saved workflows currently require a Matroska file."
        case .noOperations:
            "This workflow has no applicable changes for the selected file."
        case .missingExternalSubtitleInput:
            "This workflow requires the reviewed external subtitle input."
        case .mismatchedExternalSubtitleInput:
            "The external subtitle changed between workflow preview and execution."
        case .sourceChangedSinceReview:
            "The source changed after review. Review the workflow again."
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified copy was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct SavedWorkflowExecutor<Runner: CommandRunning, Inspector: MediaInspecting>: Sendable {
    private let remover: MKVTrackRemover<Runner>
    private let attachmentRemover: MKVAttachmentRemover<Runner>
    private let editor: MKVPropertyEditor<Runner>
    private let externalSubtitleExecutor: ExternalSubtitleMuxExecutor<Runner, Inspector>
    private let inspector: Inspector

    public init(
        mkvmergeURL: URL,
        mkvpropeditURL: URL,
        mkvextractURL: URL? = nil,
        runner: Runner,
        inspector: Inspector
    ) {
        remover = MKVTrackRemover(executableURL: mkvmergeURL, runner: runner)
        attachmentRemover = MKVAttachmentRemover(executableURL: mkvmergeURL, runner: runner)
        editor = MKVPropertyEditor(executableURL: mkvpropeditURL, runner: runner)
        externalSubtitleExecutor = ExternalSubtitleMuxExecutor(
            mkvmergeURL: mkvmergeURL,
            mkvpropeditURL: mkvpropeditURL,
            mkvextractURL: mkvextractURL,
            runner: runner,
            inspector: inspector
        )
        self.inspector = inspector
    }

    public func execute(
        source: MediaAsset,
        trackRemoval: TrackRemoval?,
        attachmentRemoval: MatroskaAttachmentRemoval? = nil,
        removesSegmentTitle: Bool,
        clearsAllTags: Bool = false,
        externalSubtitleInput: SavedWorkflowExternalSubtitleInput? = nil,
        externalSubtitlePreview: ExternalSubtitleFilePreview? = nil,
        externalSubtitlePayload: ExternalSubtitleMuxPayload? = nil,
        createsUnchangedCopy: Bool = false,
        expectedSourceRevision: MediaFileRevision? = nil,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard MatroskaEditingPolicy.supports(source) else {
            throw SavedWorkflowExecutionError.unsupportedContainer
        }
        let hasMediaOperations =
            trackRemoval != nil || attachmentRemoval != nil || removesSegmentTitle || clearsAllTags
            || externalSubtitleInput != nil
        guard hasMediaOperations || createsUnchangedCopy else {
            throw SavedWorkflowExecutionError.noOperations
        }
        guard !createsUnchangedCopy || !hasMediaOperations else {
            throw SavedWorkflowExecutionError.noOperations
        }
        guard externalSubtitlePreview == nil || externalSubtitlePayload == nil else {
            throw SavedWorkflowExecutionError.mismatchedExternalSubtitleInput
        }
        let resolvedPayload =
            externalSubtitlePayload
            ?? externalSubtitlePreview.map(ExternalSubtitleMuxPayload.original)
        if let externalSubtitleInput {
            guard let resolvedPayload else {
                throw SavedWorkflowExecutionError.missingExternalSubtitleInput
            }
            guard
                resolvedPayload.sourceURL.standardizedFileURL
                    == externalSubtitleInput.sourceURL.standardizedFileURL,
                resolvedPayload.format == externalSubtitleInput.format,
                resolvedPayload.reviewedCleanupChangeCount
                    == externalSubtitleInput.reviewedCleanupChangeCount
            else {
                throw SavedWorkflowExecutionError.mismatchedExternalSubtitleInput
            }
            return try await externalSubtitleExecutor.execute(
                source: source,
                subtitlePayload: resolvedPayload,
                metadata: externalSubtitleInput.metadata,
                trackRemoval: trackRemoval,
                attachmentRemoval: attachmentRemoval,
                removesSegmentTitle: removesSegmentTitle,
                clearsAllTags: clearsAllTags,
                destinationURL: destinationURL,
                onStage: onStage
            )
        }
        guard resolvedPayload == nil else {
            throw SavedWorkflowExecutionError.mismatchedExternalSubtitleInput
        }

        let validateSource = try mediaFileRevisionValidator(
            sourceURL: source.sourceURL,
            expectedRevision: expectedSourceRevision,
            changedError: SavedWorkflowExecutionError.sourceChangedSinceReview
        )

        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: source,
            destinationURL: destinationURL,
            preparation: trackRemoval == nil && attachmentRemoval == nil ? .clone : .empty,
            produce: { outputURL in
                if let trackRemoval {
                    try await remover.removeTracks(
                        from: source,
                        removal: trackRemoval,
                        attachmentRemoval: attachmentRemoval,
                        outputURL: outputURL
                    )
                } else if let attachmentRemoval {
                    try await attachmentRemover.removeAttachments(
                        from: source,
                        removal: attachmentRemoval,
                        outputURL: outputURL
                    )
                }
                if removesSegmentTitle {
                    try await editor.editSegmentTitle(
                        at: outputURL,
                        title: nil,
                        clearAllTags: clearsAllTags
                    )
                } else if clearsAllTags {
                    try await editor.clearAllTags(at: outputURL)
                }
            },
            verify: { output in
                if let trackRemoval {
                    try TrackRemovalOutputVerifier().verify(
                        original: source,
                        output: output,
                        removal: trackRemoval,
                        attachmentRemoval: attachmentRemoval,
                        segmentTitle: removesSegmentTitle ? .set(nil) : .preserve,
                        tags: clearsAllTags ? .removeAll : .preserve
                    )
                } else if let attachmentRemoval {
                    try MatroskaAttachmentRemovalOutputVerifier().verify(
                        original: source,
                        output: output,
                        removal: attachmentRemoval,
                        segmentTitle: removesSegmentTitle ? .set(nil) : .preserve,
                        tags: clearsAllTags ? .removeAll : .preserve
                    )
                } else if clearsAllTags {
                    try MatroskaTagRemovalOutputVerifier().verify(
                        original: source,
                        output: output,
                        segmentTitle: removesSegmentTitle ? .set(nil) : .preserve
                    )
                } else if removesSegmentTitle {
                    try SegmentTitleOutputVerifier().verify(
                        original: source,
                        output: output,
                        expectedTitle: nil
                    )
                } else if createsUnchangedCopy {
                    try UnchangedCopyOutputVerifier().verify(
                        original: source,
                        output: output
                    )
                }
            },
            validateSource: validateSource,
            committedAuditError: { outputURL, reason in
                SavedWorkflowExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }
}
