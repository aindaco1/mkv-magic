import Foundation

/// Only explicitly chosen fields change. Each track keeps its own other values.
public struct BulkTrackMetadataChange: Equatable, Sendable {
    public let kind: MediaTrackKind
    /// nil leaves names unchanged; an empty string clears them.
    public let name: String?
    public let language: String?
    public let flags: [TrackMetadataFlag: Bool]

    public init(
        kind: MediaTrackKind, name: String? = nil, language: String? = nil,
        flags: [TrackMetadataFlag: Bool] = [:]
    ) {
        self.kind = kind
        self.name = name
        self.language = language
        self.flags = flags
    }

    public var hasChanges: Bool { name != nil || language != nil || !flags.isEmpty }

    public func edits(in tracks: [MediaTrack]) throws -> [TrackMetadataEdit] {
        try tracks.filter { $0.kind == kind }.compactMap { track in
            let original = try TrackMetadataEdit(track: track)
            let edit = TrackMetadataEdit(
                trackUID: original.trackUID,
                name: name.map { $0.isEmpty ? nil : $0 } ?? original.name,
                language: language ?? original.language,
                isDefault: flags[.defaultTrack] ?? original.isDefault,
                isForced: flags[.forced] ?? original.isForced,
                isEnabled: flags[.enabled] ?? original.isEnabled,
                isCommentary: flags[.commentary] ?? original.isCommentary,
                isHearingImpaired: flags[.hearingImpaired] ?? original.isHearingImpaired,
                isVisualImpaired: flags[.visualImpaired] ?? original.isVisualImpaired,
                isOriginal: flags[.original] ?? original.isOriginal,
                isTextDescription: flags[.textDescription] ?? original.isTextDescription)
            return edit == original ? nil : edit
        }
    }
}

public enum TrackMetadataFlag: String, CaseIterable, Hashable, Sendable {
    case defaultTrack, forced, enabled, commentary, hearingImpaired, visualImpaired, original,
        textDescription

    public var title: String {
        switch self {
        case .defaultTrack: "Default"
        case .forced: "Forced"
        case .enabled: "Enabled"
        case .commentary: "Commentary"
        case .hearingImpaired: "Hearing impaired / SDH"
        case .visualImpaired: "Audio description"
        case .original: "Original language"
        case .textDescription: "Text descriptions"
        }
    }

    public func value(in edit: TrackMetadataEdit) -> Bool {
        switch self {
        case .defaultTrack: edit.isDefault
        case .forced: edit.isForced
        case .enabled: edit.isEnabled
        case .commentary: edit.isCommentary
        case .hearingImpaired: edit.isHearingImpaired
        case .visualImpaired: edit.isVisualImpaired
        case .original: edit.isOriginal
        case .textDescription: edit.isTextDescription
        }
    }
}
