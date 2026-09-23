import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum MatroskaMetadataEdit: Equatable, Sendable {
    case segmentTitle(String?)
    case track(TrackMetadataEdit)
    case tracks([TrackMetadataEdit])
}

public enum MatroskaMetadataExecutionError: Error, Equatable, Sendable {
    case unsupportedContainer
    case committedOutputAuditFailed(outputURL: URL, reason: String)
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
        expectedSourceRevision: MediaFileRevision? = nil,
        onStage: @escaping @Sendable (MatroskaMetadataExecutionStage) async throws -> Void = { _ in
        }
    ) async throws -> MediaAsset {
        guard MatroskaEditingPolicy.supports(source) else {
            throw MatroskaMetadataExecutionError.unsupportedContainer
        }
        let validateSource: @Sendable () throws -> Void
        if let expectedSourceRevision {
            validateSource = try mediaFileRevisionValidator(
                sourceURL: source.sourceURL, expectedRevision: expectedSourceRevision,
                changedError: SavedWorkflowExecutionError.sourceChangedSinceReview)
        } else {
            validateSource = {}
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
            validateSource: validateSource,
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
            try await apply(.tracks([trackEdit]), to: outputURL, source: source)
        case .tracks(let edits):
            try await editor.editWorkflowProperties(
                at: outputURL, originalTracks: source.tracks, edits: edits,
                removesSegmentTitle: false, clearAllTags: false)
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
            try verify(.tracks([trackEdit]), original: original, output: output)
        case .tracks(let edits):
            try TrackMetadataOutputVerifier().verify(
                original: original,
                output: output,
                expectedEdits: edits
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
