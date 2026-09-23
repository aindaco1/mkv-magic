import Foundation

/// Private, review-bound queue state. Never included in portable recipes or reports.
public enum MediaQueueReviewedEdit: Codable, Hashable, Sendable {
    case tagRemoval(sourceSHA256: Data, tagCount: Int)
    case chapters(sourceSHA256: Data, desired: MatroskaChapterDocument)
    case subtitleCleanup(
        format: ExternalTextSubtitleFormat, sourceSHA256: Data,
        outputSHA256: Data, restoringIDs: [Int])
    case trackMetadata(sourceSHA256: Data, edits: [TrackMetadataEdit])
    case subtitleExtraction(
        trackUID: UInt64, format: ExternalTextSubtitleFormat, outputSHA256: Data)
    case fastTrim(requested: MediaTrimRange, adjusted: MediaTrimRange, sourceChapterSHA256: Data)

    public var workflowID: UUID {
        switch self {
        case .tagRemoval: BuiltInWorkflowCatalog.tagRemoval
        case .chapters: BuiltInWorkflowCatalog.chapterEdit
        case .trackMetadata: BuiltInWorkflowCatalog.trackMetadata
        case .subtitleExtraction: BuiltInWorkflowCatalog.textSubtitleExtraction
        case .fastTrim: BuiltInWorkflowCatalog.fastTrim
        case .subtitleCleanup(let format, _, _, _):
            format == .subRip
                ? BuiltInWorkflowCatalog.subtitleCleanup
                : BuiltInWorkflowCatalog.advancedSubtitleCleanup
        }
    }

    public var name: String {
        switch self {
        case .tagRemoval: "Remove Matroska tags"
        case .chapters: "Apply reviewed chapters"
        case .trackMetadata: "Edit matching track metadata"
        case .subtitleExtraction: "Extract text subtitle"
        case .fastTrim: "Fast trim reviewed boundaries"
        case .subtitleCleanup(let format, _, _, _): "Clean \(format.displayName) subtitle"
        }
    }

    public var outputExtension: String {
        switch self {
        case .tagRemoval, .chapters, .trackMetadata, .fastTrim: "mkv"
        case .subtitleExtraction(_, let format, _): format.filenameExtension
        case .subtitleCleanup(let format, _, _, _): format.filenameExtension
        }
    }

    public var hasCanonicalStructure: Bool {
        switch self {
        case .tagRemoval(let digest, let count):
            digest.count == 32 && count > 0 && count <= 1_000_000
        case .chapters(let digest, let desired):
            digest.count == 32 && (try? desired.validated()) != nil
        case .trackMetadata(let digest, let edits):
            digest.count == 32 && !edits.isEmpty && edits.count <= 1_024
                && Set(edits.map(\.trackUID)).count == edits.count
                && edits.allSatisfy {
                    $0.trackUID != 0 && ($0.name?.utf8.count ?? 0) <= 4_096
                        && $0.name?.contains("\0") != true
                        && !$0.language.isEmpty && $0.language.utf8.count <= 35
                        && (try? ChapterLanguage.canonical($0.language)) != nil
                }
        case .subtitleExtraction(let uid, _, let digest): uid != 0 && digest.count == 32
        case .fastTrim(let requested, let adjusted, let digest):
            digest.count == 32 && requested.start >= .zero && requested.end > requested.start
                && adjusted.start >= requested.start && adjusted.end >= requested.end
                && adjusted.end > adjusted.start
        case .subtitleCleanup(_, let source, let output, let restoringIDs):
            source.count == 32 && output.count == 32
                && MediaQueueExternalSubtitleReview.validCleanupChangeIDs(restoringIDs)
        }
    }
}
