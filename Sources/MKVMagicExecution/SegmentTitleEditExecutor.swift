import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum SegmentTitleExecutionError: Error, Equatable, Sendable {
    case unsupportedContainer
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

public enum SegmentTitleExecutionStage: Equatable, Sendable {
    case verifying
    case committing
}

extension SegmentTitleExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedContainer:
            "Segment-title editing currently requires a Matroska file."
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified copy was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct SegmentTitleEditExecutor<Runner: CommandRunning, Inspector: MediaInspecting>:
    Sendable
{
    private let editor: MKVPropertyEditor<Runner>
    private let inspector: Inspector
    private let verifier = SegmentTitleOutputVerifier()

    public init(mkvpropeditURL: URL, runner: Runner, inspector: Inspector) {
        editor = MKVPropertyEditor(executableURL: mkvpropeditURL, runner: runner)
        self.inspector = inspector
    }

    public func execute(
        source: MediaAsset,
        title: String?,
        destinationURL: URL,
        onStage: @escaping @Sendable (SegmentTitleExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard MatroskaEditingPolicy.supports(source) else {
            throw SegmentTitleExecutionError.unsupportedContainer
        }
        let transaction = VerifiedOutputTransaction(
            sourceURL: source.sourceURL,
            destinationURL: destinationURL
        )
        do {
            let temporaryOutput = try await transaction.prepareClone()
            try await editor.editSegmentTitle(at: temporaryOutput, title: title)
            try await onStage(.verifying)
            let temporaryAsset = try await inspector.inspect(temporaryOutput)
            try verifier.verify(original: source, output: temporaryAsset, expectedTitle: title)
            try await transaction.markVerified()
            try await onStage(.committing)
            let committedURL = try await transaction.commit()
            do {
                let committedAsset = try await inspector.inspect(committedURL)
                try verifier.verify(original: source, output: committedAsset, expectedTitle: title)
                return committedAsset
            } catch {
                throw SegmentTitleExecutionError.committedOutputAuditFailed(
                    outputURL: committedURL,
                    reason: error.localizedDescription
                )
            }
        } catch {
            await transaction.cancel()
            throw error
        }
    }

}
