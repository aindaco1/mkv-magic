import Foundation

/// A reusable workflow stores intent only. It deliberately contains no media path,
/// Matroska track identifier, or other fact tied to one inspected file.
public struct SavedWorkflow: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 5

    public let id: UUID
    public var schemaVersion: Int
    public var name: String
    public var steps: [SavedWorkflowStep]

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = SavedWorkflow.currentSchemaVersion,
        name: String,
        steps: [SavedWorkflowStep]
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.steps = steps
    }
}

public struct SavedWorkflowStep: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var isEnabled: Bool
    public var action: SavedWorkflowAction

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        action: SavedWorkflowAction
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.action = action
    }
}

public enum SavedWorkflowAction: String, Codable, CaseIterable, Hashable, Sendable {
    case englishLibraryCleanup
    case removeNonEnglishSubtitles
    case removeRedundantEnglishSDH
    case removeSegmentTitle
    case normalizeFilename
    case addExternalSubtitle
    case cleanExternalSubtitleText
    case convertVideoRecommended
    case convertVideoAV1
    case convertVideoHEVC
    case convertVideoH264
    case convertVideoProRes

    public var isVideoConversion: Bool {
        switch self {
        case .convertVideoRecommended, .convertVideoAV1, .convertVideoHEVC,
            .convertVideoH264, .convertVideoProRes:
            true
        default:
            false
        }
    }

    public var displayName: String {
        switch self {
        case .englishLibraryCleanup: "English Library Cleanup"
        case .removeNonEnglishSubtitles: "If present: Remove non-English subtitles"
        case .removeRedundantEnglishSDH: "If redundant: Remove English SDH subtitles"
        case .removeSegmentTitle: "If present: Remove segment title"
        case .normalizeFilename: "If useful: Clean up the output filename"
        case .addExternalSubtitle: "Add one external text subtitle"
        case .cleanExternalSubtitleText: "Clean the added subtitle text"
        case .convertVideoRecommended: "Convert video: Recommended for this Mac"
        case .convertVideoAV1: "Convert video: AV1 10-bit"
        case .convertVideoHEVC: "Convert video: HEVC 10-bit"
        case .convertVideoH264: "Convert video: H.264 8-bit"
        case .convertVideoProRes: "Convert video: ProRes 10-bit"
        }
    }

    public var explanation: String {
        switch self {
        case .englishLibraryCleanup:
            "Suggest removable subtitle tracks while preserving audio, commentary, signs, and unknown languages."
        case .removeNonEnglishSubtitles:
            "Remove subtitle tracks explicitly labeled as non-English; preserve English, unknown, commentary, and signs/songs tracks."
        case .removeRedundantEnglishSDH:
            "Remove an English SDH track only when another preferred English subtitle track remains."
        case .removeSegmentTitle:
            "Remove the Matroska segment title without encoding video or audio."
        case .normalizeFilename:
            "Suggest a simple Title (Year) output name for common release-style filenames. You can review or replace it before saving."
        case .addExternalSubtitle:
            "Ask for one SRT, ASS, or SSA file at preview time, confirm its track details, and add it last without encoding."
        case .cleanExternalSubtitleText:
            "Review deterministic ad, whitespace, and English OCR suggestions for the added subtitle, then feed only accepted edits into the same remux."
        case .convertVideoRecommended:
            "Choose the first compatible encoder recommended by this Mac's verified capability check and optional Encoding Test. Copy audio and subtitles exactly, preserve HDR10 when present, and encode video once."
        case .convertVideoAV1:
            "Encode video once as compact 10-bit AV1 when the bundled encoder passes its local check. Copy audio and subtitles exactly and preserve HDR10 when present."
        case .convertVideoHEVC:
            "Encode video once as 10-bit HEVC with VideoToolbox when it passes its local check. This is the faster choice for many Intel Macs. Copy audio and subtitles exactly."
        case .convertVideoH264:
            "Encode video once as broadly compatible 8-bit H.264 when it passes its local check. This step is limited to SDR sources and copies audio and subtitles exactly."
        case .convertVideoProRes:
            "Encode video once as edit-friendly 10-bit ProRes when it passes its local check. This step is limited to SDR sources and copies audio and subtitles exactly."
        }
    }
}

public enum SavedWorkflowMigrationError: Error, Equatable, Sendable {
    case unsupportedSchema
}

public struct SavedWorkflowMigrator: Sendable {
    public init() {}

    public func migrate(_ workflow: SavedWorkflow) throws -> SavedWorkflow {
        switch workflow.schemaVersion {
        case SavedWorkflow.currentSchemaVersion:
            return workflow
        case 4:
            guard workflow.steps.allSatisfy({ !$0.action.isVideoConversion }) else {
                throw SavedWorkflowMigrationError.unsupportedSchema
            }
            var migrated = workflow
            migrated.schemaVersion = SavedWorkflow.currentSchemaVersion
            return migrated
        case 3:
            guard
                workflow.steps.allSatisfy({
                    $0.action != .normalizeFilename && !$0.action.isVideoConversion
                })
            else {
                throw SavedWorkflowMigrationError.unsupportedSchema
            }
            var migrated = workflow
            migrated.schemaVersion = SavedWorkflow.currentSchemaVersion
            return migrated
        case 2:
            guard
                workflow.steps.allSatisfy({
                    $0.action != .cleanExternalSubtitleText && $0.action != .normalizeFilename
                        && !$0.action.isVideoConversion
                })
            else {
                throw SavedWorkflowMigrationError.unsupportedSchema
            }
            var migrated = workflow
            migrated.schemaVersion = SavedWorkflow.currentSchemaVersion
            return migrated
        case 1:
            guard
                workflow.steps.allSatisfy({
                    $0.action != .addExternalSubtitle
                        && $0.action != .cleanExternalSubtitleText
                        && $0.action != .normalizeFilename
                        && !$0.action.isVideoConversion
                })
            else {
                throw SavedWorkflowMigrationError.unsupportedSchema
            }
            var migrated = workflow
            migrated.schemaVersion = SavedWorkflow.currentSchemaVersion
            return migrated
        default:
            throw SavedWorkflowMigrationError.unsupportedSchema
        }
    }
}
