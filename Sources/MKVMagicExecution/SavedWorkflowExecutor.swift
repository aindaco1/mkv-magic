import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum SavedWorkflowExecutionError: Error, Equatable, Sendable {
    case unsupportedContainer
    case noOperations
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension SavedWorkflowExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedContainer:
            "Saved workflows currently require a Matroska file."
        case .noOperations:
            "This workflow has no applicable changes for the selected file."
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified copy was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct SavedWorkflowExecutor<Runner: CommandRunning, Inspector: MediaInspecting>: Sendable {
    private let remover: MKVTrackRemover<Runner>
    private let editor: MKVPropertyEditor<Runner>
    private let inspector: Inspector

    public init(
        mkvmergeURL: URL,
        mkvpropeditURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        remover = MKVTrackRemover(executableURL: mkvmergeURL, runner: runner)
        editor = MKVPropertyEditor(executableURL: mkvpropeditURL, runner: runner)
        self.inspector = inspector
    }

    public func execute(
        source: MediaAsset,
        trackRemoval: TrackRemoval?,
        removesSegmentTitle: Bool,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard MatroskaEditingPolicy.supports(source) else {
            throw SavedWorkflowExecutionError.unsupportedContainer
        }
        guard trackRemoval != nil || removesSegmentTitle else {
            throw SavedWorkflowExecutionError.noOperations
        }

        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: source,
            destinationURL: destinationURL,
            preparation: trackRemoval == nil ? .clone : .empty,
            produce: { outputURL in
                if let trackRemoval {
                    try await remover.removeTracks(
                        from: source,
                        removal: trackRemoval,
                        outputURL: outputURL
                    )
                }
                if removesSegmentTitle {
                    try await editor.editSegmentTitle(at: outputURL, title: nil)
                }
            },
            verify: { output in
                if let trackRemoval {
                    try TrackRemovalOutputVerifier().verify(
                        original: source,
                        output: output,
                        removal: trackRemoval,
                        segmentTitle: removesSegmentTitle ? .set(nil) : .preserve
                    )
                } else if removesSegmentTitle {
                    try SegmentTitleOutputVerifier().verify(
                        original: source,
                        output: output,
                        expectedTitle: nil
                    )
                }
            },
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
