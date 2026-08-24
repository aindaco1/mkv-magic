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
        verify: @escaping @Sendable (MediaAsset) async throws -> Void,
        validateSource: @escaping @Sendable () throws -> Void = {},
        committedAuditError: @escaping @Sendable (URL, String) -> any Error,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void
    ) async throws -> MediaAsset {
        try Task.checkCancellation()
        try validateSource()
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
            try Task.checkCancellation()
            try validateSource()
            try await onStage(.verifying)
            try Task.checkCancellation()
            let temporaryAsset = try await inspector.inspect(temporaryOutput)
            try Task.checkCancellation()
            try await verify(temporaryAsset)
            try Task.checkCancellation()
            try validateSource()
            try await transaction.markVerified()
            try await onStage(.committing)
            try Task.checkCancellation()
            try validateSource()
            let committedURL = try await transaction.commit()
            do {
                let committedAsset = try await inspector.inspect(committedURL)
                try Task.checkCancellation()
                try await verify(committedAsset)
                try validateSource()
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
