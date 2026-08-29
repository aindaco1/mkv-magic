import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum TrackRemovalExecutionError: Error, Equatable, Sendable {
    case unsupportedContainer
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension TrackRemovalExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedContainer:
            "Track removal currently requires a Matroska file."
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified copy was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public typealias TrackRemovalExecutionStage = VerifiedOutputExecutionStage

public struct TrackRemovalExecutor<Runner: CommandRunning, Inspector: MediaInspecting>: Sendable {
    private let remover: MKVTrackRemover<Runner>
    private let inspector: Inspector
    private let verifier = TrackRemovalOutputVerifier()

    public init(mkvmergeURL: URL, runner: Runner, inspector: Inspector) {
        remover = MKVTrackRemover(executableURL: mkvmergeURL, runner: runner)
        self.inspector = inspector
    }

    public func execute(
        source: MediaAsset,
        removal: TrackRemoval,
        destinationURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (TrackRemovalExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard MatroskaEditingPolicy.supports(source) else {
            throw TrackRemovalExecutionError.unsupportedContainer
        }
        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: source,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                try await remover.removeTracks(
                    from: source,
                    removal: removal,
                    outputURL: outputURL,
                    onProgress: onProgress
                )
            },
            verify: { output in
                try verifier.verify(original: source, output: output, removal: removal)
            },
            committedAuditError: { outputURL, reason in
                TrackRemovalExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }
}
