import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import MKVMagicSystem

struct ReviewedQueueEditRetry {
    let edit: ReviewedBatchEdit
    let sourceAccess: SecurityScopedResourceAccess?
}

/// Prepared previews shared by initial batch admission and Review Again.
enum ReviewedBatchEdit {
    case tagRemoval(MatroskaTagPreview)
    case chapters(ChapterEditPreview, MatroskaChapterDocument)
    case subtitleCleanup(ExternalSubtitleFilePreview, restoringIDs: Set<Int>)
    case trackMetadata(ReviewedTrackMetadata)
    case subtitleExtraction(MatroskaTextSubtitleExtractionPreview)
    case fastTrim(FastTrimPreview)

    var sourceURL: URL {
        switch self {
        case .tagRemoval(let preview): preview.source.sourceURL
        case .chapters(let preview, _): preview.source.sourceURL
        case .subtitleCleanup(let preview, _): preview.sourceURL
        case .trackMetadata(let preview): preview.source.sourceURL
        case .subtitleExtraction(let preview): preview.source.sourceURL
        case .fastTrim(let preview): preview.source.sourceURL
        }
    }

    var outputFilename: String {
        switch self {
        case .tagRemoval: OutputNamingPolicy.tagsRemovedFilename(for: sourceURL)
        case .chapters: OutputNamingPolicy.chaptersAddedFilename(for: sourceURL)
        case .subtitleCleanup: OutputNamingPolicy.cleanedSubtitleFilename(for: sourceURL)
        case .trackMetadata: OutputNamingPolicy.suggestedFilename(for: sourceURL)
        case .subtitleExtraction(let preview):
            OutputNamingPolicy.extractedSubtitleFilename(
                for: sourceURL, track: preview.track, format: preview.format,
                trackCount: EmbeddedTextSubtitlePolicy.extractableTracks(in: preview.source).count)
        case .fastTrim: OutputNamingPolicy.trimmedFilename(for: sourceURL)
        }
    }

    func reviewDetail() throws -> String {
        switch self {
        case .trackMetadata(let preview): return preview.detail
        case .subtitleExtraction(let preview):
            return
                "\(TrackEditorPresentation.label(preview.track))\n\(preview.itemCount) text events. Preserve \(preview.format.displayName) text, styles, and timing. Original MKV unchanged."
        case .fastTrim(let preview):
            guard let duration = preview.source.duration else {
                throw TrimPlanningError.invalidDuration
            }
            let requested = preview.plan.requested, actual = preview.plan.adjusted
            return
                "Requested removal: beginning \(ChapterTimestamp.format(requested.start, digits: 3)), end \(ChapterTimestamp.format(duration - requested.end, digits: 3)).\n"
                + "Actual removal: beginning \(ChapterTimestamp.format(actual.start, digits: 3)), end \(ChapterTimestamp.format(duration - actual.end, digits: 3)).\n"
                + "Retain \(ChapterTimestamp.format(actual.start, digits: 3))–\(ChapterTimestamp.format(actual.end, digits: 3)).\n"
                + "\(preview.trimmedChapters.chapterCount) chapters retained. No encoding."
        default:
            return try ReviewedEditPlanner().plan(reviewedIntent()).stages.map(\.summary).joined(
                separator: "\n")
        }
    }

    func reviewedIntent() throws -> MediaQueueReviewedEdit {
        switch self {
        case .tagRemoval(let preview):
            return .tagRemoval(
                sourceSHA256: preview.digest, tagCount: preview.document.counts.total)
        case .chapters(let preview, let desired):
            let desired = try desired.validated(mediaDuration: preview.source.duration)
            guard desired != preview.original else { throw ChapterEditExecutionError.noChanges }
            return .chapters(sourceSHA256: preview.canonicalSHA256, desired: desired)
        case .subtitleCleanup(let preview, let restoringIDs):
            let payload = ExternalSubtitleMuxPayload.reviewedCleanup(
                preview, restoringIDs: restoringIDs)
            try payload.validateForReview()
            return .subtitleCleanup(
                format: preview.format, sourceSHA256: preview.sourceSHA256,
                outputSHA256: payload.normalizedSHA256, restoringIDs: restoringIDs.sorted())
        case .trackMetadata(let preview): return try preview.intent()
        case .subtitleExtraction(let preview):
            guard let uid = preview.track.uid else { throw MKVPropertyEditError.missingTrack }
            return .subtitleExtraction(
                trackUID: uid, format: preview.format, outputSHA256: preview.outputSHA256)
        case .fastTrim(let preview):
            return .fastTrim(
                requested: preview.plan.requested, adjusted: preview.plan.adjusted,
                sourceChapterSHA256: preview.sourceChapterSHA256)
        }
    }

    func validatedSourceRevision() throws -> MediaFileRevision {
        let current = try MediaFileRevisionReader().read(sourceURL)
        let matches: Bool
        switch self {
        case .trackMetadata(let preview): matches = current == preview.sourceRevision
        case .subtitleExtraction(let preview): matches = current == preview.sourceRevision
        case .fastTrim(let preview): matches = current == preview.sourceRevision
        case .tagRemoval(let preview): matches = current == preview.sourceRevision
        case .chapters(let preview, _):
            let reviewed = preview.sourceRevision
            matches =
                current.fileSize == reviewed.fileSize
                && current.modificationDate == reviewed.modificationDate
                && current.fileNumber == reviewed.fileNumber
                && current.systemNumber == reviewed.systemNumber
        case .subtitleCleanup:
            _ = try reviewedIntent()
            matches = try MediaFileRevisionReader().read(sourceURL) == current
        }
        guard matches else { throw SavedWorkflowExecutionError.sourceChangedSinceReview }
        return current
    }

    @MainActor
    func execute(
        using model: AppModel, destinationURL: URL,
        onStage: @escaping @MainActor @Sendable (VerifiedOutputExecutionStage) -> Void
    ) async throws {
        switch self {
        case .trackMetadata(let preview):
            _ = try await model.editTrackMetadata(
                in: preview.source, edits: preview.edits, destinationURL: destinationURL,
                expectedSourceRevision: preview.sourceRevision, onStage: onStage)
        case .subtitleExtraction(let preview):
            _ = try await model.executeMatroskaTextSubtitleExtraction(
                preview: preview, destinationURL: destinationURL, onStage: onStage)
        case .fastTrim(let preview):
            _ = try await model.executeTrim(
                preview: .fast(preview), destinationURL: destinationURL, onStage: onStage)
        case .tagRemoval(let preview):
            _ = try await model.executeMatroskaTagRemoval(
                preview: preview, destinationURL: destinationURL, onStage: onStage)
        case .chapters(let preview, let desired):
            _ = try await model.editChapters(
                preview: preview, desired: desired, destinationURL: destinationURL, onStage: onStage
            )
        case .subtitleCleanup(.subRip(let preview), let restoringIDs):
            _ = try await model.cleanSubtitle(
                preview: preview, restoringCueIDs: restoringIDs,
                destinationURL: destinationURL, onStage: onStage)
        case .subtitleCleanup(.advanced(let preview), let restoringIDs):
            _ = try await model.cleanAdvancedSubtitle(
                preview: preview, restoringEventIDs: restoringIDs,
                destinationURL: destinationURL, onStage: onStage)
        }
    }
}
