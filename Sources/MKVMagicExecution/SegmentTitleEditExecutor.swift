import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum MatroskaMetadataEdit: Equatable, Sendable {
    case segmentTitle(String?)
    case track(TrackMetadataEdit)
}

public enum MatroskaMetadataExecutionError: Error, Equatable, Sendable {
    case unsupportedContainer
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

public enum VerifiedOutputExecutionStage: Equatable, Sendable {
    case verifying
    case committing
}

public typealias MatroskaMetadataExecutionStage = VerifiedOutputExecutionStage

extension MatroskaMetadataExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedContainer:
            "Metadata editing currently requires a Matroska file."
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified copy was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct MatroskaMetadataEditExecutor<Runner: CommandRunning, Inspector: MediaInspecting>:
    Sendable
{
    private let editor: MKVPropertyEditor<Runner>
    private let inspector: Inspector

    public init(mkvpropeditURL: URL, runner: Runner, inspector: Inspector) {
        editor = MKVPropertyEditor(executableURL: mkvpropeditURL, runner: runner)
        self.inspector = inspector
    }

    public func execute(
        source: MediaAsset,
        edit: MatroskaMetadataEdit,
        destinationURL: URL,
        onStage: @escaping @Sendable (MatroskaMetadataExecutionStage) async throws -> Void = { _ in
        }
    ) async throws -> MediaAsset {
        guard MatroskaEditingPolicy.supports(source) else {
            throw MatroskaMetadataExecutionError.unsupportedContainer
        }
        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: source,
            destinationURL: destinationURL,
            preparation: .clone,
            produce: { outputURL in
                try await apply(edit, to: outputURL, source: source)
            },
            verify: { output in
                try verify(edit, original: source, output: output)
            },
            committedAuditError: { outputURL, reason in
                MatroskaMetadataExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }

    private func apply(
        _ edit: MatroskaMetadataEdit,
        to outputURL: URL,
        source: MediaAsset
    ) async throws {
        switch edit {
        case .segmentTitle(let title):
            try await editor.editSegmentTitle(at: outputURL, title: title)
        case .track(let trackEdit):
            guard let track = source.tracks.first(where: { $0.uid == trackEdit.trackUID }) else {
                throw MKVPropertyEditError.missingTrack
            }
            try await editor.editTrackMetadata(
                at: outputURL,
                originalTrack: track,
                edit: trackEdit
            )
        }
    }

    private func verify(
        _ edit: MatroskaMetadataEdit,
        original: MediaAsset,
        output: MediaAsset
    ) throws {
        switch edit {
        case .segmentTitle(let title):
            try SegmentTitleOutputVerifier().verify(
                original: original,
                output: output,
                expectedTitle: title
            )
        case .track(let trackEdit):
            try TrackMetadataOutputVerifier().verify(
                original: original,
                output: output,
                expectedEdit: trackEdit
            )
        }
    }
}

public typealias SegmentTitleExecutionError = MatroskaMetadataExecutionError
public typealias SegmentTitleExecutionStage = MatroskaMetadataExecutionStage

public struct SegmentTitleEditExecutor<Runner: CommandRunning, Inspector: MediaInspecting>:
    Sendable
{
    private let executor: MatroskaMetadataEditExecutor<Runner, Inspector>

    public init(mkvpropeditURL: URL, runner: Runner, inspector: Inspector) {
        executor = MatroskaMetadataEditExecutor(
            mkvpropeditURL: mkvpropeditURL,
            runner: runner,
            inspector: inspector
        )
    }

    public func execute(
        source: MediaAsset,
        title: String?,
        destinationURL: URL,
        onStage: @escaping @Sendable (SegmentTitleExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        try await executor.execute(
            source: source,
            edit: .segmentTitle(title),
            destinationURL: destinationURL,
            onStage: onStage
        )
    }
}
