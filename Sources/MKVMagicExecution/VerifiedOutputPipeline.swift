import Foundation
import MKVMagicCore
import MKVMagicMedia

enum VerifiedOutputPreparation: Sendable {
    case clone
    case empty
}

struct VerifiedOutputPipeline<Inspector: MediaInspecting>: Sendable {
    let inspector: Inspector

    func execute(
        source: MediaAsset,
        destinationURL: URL,
        preparation: VerifiedOutputPreparation,
        produce: @escaping @Sendable (URL) async throws -> Void,
        verify: @escaping @Sendable (MediaAsset) throws -> Void,
        committedAuditError: @escaping @Sendable (URL, String) -> any Error,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void
    ) async throws -> MediaAsset {
        let transaction = VerifiedOutputTransaction(
            sourceURL: source.sourceURL,
            destinationURL: destinationURL
        )
        do {
            let temporaryOutput =
                switch preparation {
                case .clone: try await transaction.prepareClone()
                case .empty: try await transaction.prepareEmptyOutput()
                }
            try await produce(temporaryOutput)
            try await onStage(.verifying)
            let temporaryAsset = try await inspector.inspect(temporaryOutput)
            try verify(temporaryAsset)
            try await transaction.markVerified()
            try await onStage(.committing)
            let committedURL = try await transaction.commit()
            do {
                let committedAsset = try await inspector.inspect(committedURL)
                try verify(committedAsset)
                return committedAsset
            } catch {
                throw committedAuditError(committedURL, error.localizedDescription)
            }
        } catch {
            await transaction.cancel()
            throw error
        }
    }
}
