import Foundation

/// A reusable workflow stores intent only. It deliberately contains no media path,
/// Matroska track identifier, or other fact tied to one inspected file.
public struct SavedWorkflow: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

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

    public var displayName: String {
        switch self {
        case .englishLibraryCleanup: "English Library Cleanup"
        case .removeNonEnglishSubtitles: "If present: Remove non-English subtitles"
        case .removeRedundantEnglishSDH: "If redundant: Remove English SDH subtitles"
        case .removeSegmentTitle: "If present: Remove segment title"
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
        }
    }
}
