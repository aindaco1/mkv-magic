import Foundation
import MKVMagicCore
import MKVMagicExecution

enum BatchMediaEditOperation {
    case metadata(BulkTrackMetadataChange)
    case subtitles
    case trim(BatchTrimAmounts)

    var title: String {
        switch self {
        case .metadata: "Review Track Edits"
        case .subtitles: "Review Subtitle Extractions"
        case .trim: "Review Batch Trims"
        }
    }

    var explanation: String {
        switch self {
        case .metadata:
            "All matching tracks receive only the chosen changes. Review the details and exclude any file you do not want. Each included file becomes one verified copy."
        case .subtitles:
            "Each supported SRT, ASS, or SSA track becomes its own subtitle file in its original format. Exclude any tracks you do not want. Image subtitles are not converted."
        case .trim:
            "Review the actual retained range for every file. Fast trim aligns to keyframes without encoding, so removal amounts may differ. Chapters are clipped and rebased; every original stays unchanged."
        }
    }
}

struct BatchMediaEditPreparation {
    var items = [(id: UUID, edit: ReviewedBatchEdit)]()
    var presentations = [BatchReviewItemPresentation]()
    static let maximumOutputs = 1_024
    static let maximumPreviewBytes = 64 * 1_024 * 1_024

    @MainActor
    static func prepare(
        assets: [MediaAsset], operation: BatchMediaEditOperation, model: AppModel,
        onProgress: (Int, String) -> Void = { _, _ in }
    ) async throws -> Self {
        guard assets.count <= ExternalSubtitleBatchMatcher.maximumInputCount else {
            throw BatchMediaPreparationError.tooManyFiles
        }
        var result = Self()
        var previewBytes = 0
        for (index, selected) in assets.enumerated() {
            try Task.checkCancellation()
            onProgress(
                index,
                "Reviewing \(index + 1) of \(assets.count): \(selected.sourceURL.lastPathComponent)"
            )
            do {
                guard MatroskaEditingPolicy.supports(selected) else {
                    throw MatroskaMetadataExecutionError.unsupportedContainer
                }
                let (source, revision) = try await model.inspectBatchSource(selected.sourceURL)
                let sourceBytes = try JSONEncoder().encode(source).count
                guard sourceBytes <= maximumPreviewBytes - previewBytes else {
                    throw BatchMediaPreparationError.reviewLimit
                }
                previewBytes += sourceBytes
                switch operation {
                case .metadata(let change):
                    // Normalize through the same single-track editor comparison,
                    // so en/eng (for example) cannot become a failing no-op job.
                    let edits = try change.edits(in: source.tracks).filter { edit in
                        guard let track = source.tracks.first(where: { $0.uid == edit.trackUID })
                        else {
                            throw MKVPropertyEditError.missingTrack
                        }
                        return try edit != TrackEditorPresentation.normalizedEdit(for: track)
                    }
                    guard !edits.isEmpty else { throw MKVPropertyEditError.noChanges }
                    let preview = ReviewedTrackMetadata(
                        source: source, edits: edits, sourceRevision: revision)
                    try result.append(.trackMetadata(preview))
                case .trim(let amounts):
                    let requested = try amounts.retainedRange(duration: source.duration)
                    let preview = try await model.previewBatchFastTrim(in: source, range: requested)
                    try result.append(.fastTrim(preview))
                case .subtitles:
                    let tracks = source.tracks.filter { $0.kind == .subtitle }
                    guard !tracks.isEmpty else { throw MKVPropertyEditError.noChanges }
                    let supported = EmbeddedTextSubtitlePolicy.extractableTracks(in: source)
                    for track in tracks {
                        try Task.checkCancellation()
                        do {
                            guard result.presentations.count < maximumOutputs,
                                previewBytes < maximumPreviewBytes
                            else { throw BatchMediaPreparationError.reviewLimit }
                            guard supported.contains(track), let uid = track.uid else {
                                throw MatroskaTextSubtitleExtractionError.unsupportedSource
                            }
                            let preview = try await model.previewMatroskaTextSubtitleExtraction(
                                in: source, trackUID: uid)
                            guard preview.byteCount <= maximumPreviewBytes - previewBytes else {
                                throw BatchMediaPreparationError.reviewLimit
                            }
                            previewBytes += preview.byteCount
                            try result.append(.subtitleExtraction(preview))
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch BatchMediaPreparationError.reviewLimit {
                            throw BatchMediaPreparationError.reviewLimit
                        } catch {
                            result.blocked(
                                source,
                                detail: "\(TrackEditorPresentation.label(track))\n"
                                    + UserFacingErrorPresentation.shortReason(error))
                        }
                        if result.presentations.count > maximumOutputs {
                            throw BatchMediaPreparationError.reviewLimit
                        }
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch BatchMediaPreparationError.reviewLimit {
                throw BatchMediaPreparationError.reviewLimit
            } catch MKVPropertyEditError
                .noChanges
            {
                result.presentations.append(
                    BatchReviewItemPresentation(
                        id: UUID(), inputName: selected.sourceURL.lastPathComponent,
                        outputName: "—", status: .noChanges,
                        detail: "No matching tracks need this change.",
                        sourceURL: selected.sourceURL))
            } catch {
                result.blocked(selected, detail: UserFacingErrorPresentation.shortReason(error))
            }
            onProgress(index + 1, "Reviewed \(index + 1) of \(assets.count) files.")
            if result.presentations.count > maximumOutputs {
                throw BatchMediaPreparationError.reviewLimit
            }
        }
        return result
    }

    private mutating func append(_ edit: ReviewedBatchEdit) throws {
        guard try edit.reviewedIntent().hasCanonicalStructure else {
            throw BatchMediaPreparationError.invalidReview
        }
        _ = try edit.validatedSourceRevision()
        let id = UUID()
        items.append((id, edit))
        presentations.append(
            BatchReviewItemPresentation(
                id: id, inputName: edit.sourceURL.lastPathComponent,
                outputName: edit.outputFilename, status: .ready, detail: try edit.reviewDetail(),
                sourceURL: edit.sourceURL))
    }

    private mutating func blocked(_ source: MediaAsset, detail: String) {
        presentations.append(
            BatchReviewItemPresentation(
                id: UUID(), inputName: source.sourceURL.lastPathComponent,
                outputName: "—", status: .blocked, detail: detail, sourceURL: source.sourceURL))
    }
}

enum BatchMediaPreparationError: Error, LocalizedError {
    case tooManyFiles, reviewLimit, invalidReview
    var errorDescription: String? {
        switch self {
        case .tooManyFiles: "Choose at most 500 files per batch. Nothing was queued."
        case .reviewLimit:
            "This batch exceeds 1,024 outputs or 64 MB of review data. Choose fewer files."
        case .invalidReview:
            "The proposed changes could not be safely bound to this source. Inspect it again."
        }
    }
}
