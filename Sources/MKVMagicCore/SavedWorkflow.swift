import Foundation

/// A reusable workflow stores intent only. It deliberately contains no media path,
/// Matroska track identifier, or other fact tied to one inspected file.
public struct SavedWorkflow: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 7

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
    case convertVideoIfNotAV1OrHEVC
    case convertVideoRecommended
    case convertVideoAV1
    case convertVideoHEVC
    case convertVideoH264
    case convertVideoProRes
    case convertAudioAAC
    case convertAudioOpus
    case convertAudioAC3
    case convertAudioEAC3
    case convertAudioFLAC

    public var isVideoConversion: Bool {
        switch self {
        case .convertVideoIfNotAV1OrHEVC, .convertVideoRecommended, .convertVideoAV1,
            .convertVideoHEVC,
            .convertVideoH264, .convertVideoProRes:
            true
        default:
            false
        }
    }

    public var isAudioConversion: Bool {
        audioTranscodePreset != nil
    }

    public var audioTranscodePreset: AudioTranscodePreset? {
        switch self {
        case .convertAudioAAC: .aacCompatibility
        case .convertAudioOpus: .opusQuality
        case .convertAudioAC3: .ac3Compatibility
        case .convertAudioEAC3: .eac3Compatibility
        case .convertAudioFLAC: .flacLossless
        default: nil
        }
    }

    public func videoConversionApplies(to asset: MediaAsset) -> Bool {
        guard isVideoConversion else { return false }
        guard self == .convertVideoIfNotAV1OrHEVC else { return true }
        let videoTracks = asset.tracks.filter { $0.kind == .video }
        guard videoTracks.count == 1, let codec = videoTracks.first?.codec else {
            return true
        }
        switch codec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "av1", "hevc", "h265", "h.265": return false
        default: return true
        }
    }

    public var minimumSchemaVersion: Int {
        switch self {
        case .addExternalSubtitle: 2
        case .cleanExternalSubtitleText: 3
        case .normalizeFilename: 4
        case .convertVideoRecommended, .convertVideoAV1, .convertVideoHEVC,
            .convertVideoH264, .convertVideoProRes:
            5
        case .convertAudioAAC, .convertAudioOpus, .convertAudioAC3,
            .convertAudioEAC3, .convertAudioFLAC:
            6
        case .convertVideoIfNotAV1OrHEVC: 7
        default: 1
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
        case .convertVideoIfNotAV1OrHEVC:
            "If needed: Convert video unless it is already AV1 or HEVC"
        case .convertVideoRecommended: "Convert video: Recommended for this Mac"
        case .convertVideoAV1: "Convert video: AV1 10-bit"
        case .convertVideoHEVC: "Convert video: HEVC 10-bit"
        case .convertVideoH264: "Convert video: H.264 8-bit"
        case .convertVideoProRes: "Convert video: ProRes 10-bit"
        case .convertAudioAAC: "With video conversion: Convert audio to AAC"
        case .convertAudioOpus: "With video conversion: Convert audio to Opus"
        case .convertAudioAC3: "With video conversion: Convert audio to AC-3"
        case .convertAudioEAC3: "With video conversion: Convert audio to E-AC-3"
        case .convertAudioFLAC: "With video conversion: Convert audio to FLAC"
        }
    }

    public var explanation: String {
        if let preset = audioTranscodePreset {
            return
                "During the same reviewed full-file video conversion, encode every retained audio track once as \(preset.displayName) while preserving each known channel layout."
        }
        return switch self {
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
        case .convertVideoIfNotAV1OrHEVC:
            "Packet-copy video that is already AV1 or HEVC. Otherwise choose the first compatible locally verified encoder, preserve HDR10 when present, and encode video once."
        case .convertVideoRecommended:
            "Choose the first compatible encoder recommended by this Mac's verified capability check and optional Encoding Test. Encode video once, preserve HDR10 when present, and packet-copy audio and subtitles unless an explicit audio card is added."
        case .convertVideoAV1:
            "Encode video once as compact 10-bit AV1 when the bundled encoder passes its local check. Preserve HDR10 when present and packet-copy audio and subtitles unless an explicit audio card is added."
        case .convertVideoHEVC:
            "Encode video once as 10-bit HEVC with VideoToolbox when it passes its local check. This is the faster choice for many Intel Macs. Packet-copy audio and subtitles unless an explicit audio card is added."
        case .convertVideoH264:
            "Encode video once as broadly compatible 8-bit H.264 when it passes its local check. This step is limited to SDR sources and packet-copies audio and subtitles unless an explicit audio card is added."
        case .convertVideoProRes:
            "Encode video once as edit-friendly 10-bit ProRes when it passes its local check. This step is limited to SDR sources and packet-copies audio and subtitles unless an explicit audio card is added."
        case .convertAudioAAC, .convertAudioOpus, .convertAudioAC3,
            .convertAudioEAC3, .convertAudioFLAC:
            preconditionFailure("Audio actions return their shared explanation above")
        }
    }
}

public enum SavedWorkflowMigrationError: Error, Equatable, Sendable {
    case unsupportedSchema
}

public struct SavedWorkflowMigrator: Sendable {
    public init() {}

    public func migrate(_ workflow: SavedWorkflow) throws -> SavedWorkflow {
        guard (1...SavedWorkflow.currentSchemaVersion).contains(workflow.schemaVersion),
            workflow.steps.allSatisfy({
                $0.action.minimumSchemaVersion <= workflow.schemaVersion
            })
        else {
            throw SavedWorkflowMigrationError.unsupportedSchema
        }
        guard workflow.schemaVersion != SavedWorkflow.currentSchemaVersion else {
            return workflow
        }
        var migrated = workflow
        migrated.schemaVersion = SavedWorkflow.currentSchemaVersion
        return migrated
    }
}
