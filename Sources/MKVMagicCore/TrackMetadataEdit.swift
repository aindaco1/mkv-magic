import Foundation

public struct TrackMetadataEdit: Codable, Equatable, Hashable, Sendable {
    public let trackUID: UInt64
    public let name: String?
    public let language: String
    public let isDefault: Bool
    public let isForced: Bool
    public let isEnabled: Bool
    public let isCommentary: Bool
    public let isHearingImpaired: Bool
    public let isVisualImpaired: Bool
    public let isOriginal: Bool
    public let isTextDescription: Bool

    public init(
        trackUID: UInt64,
        name: String?,
        language: String,
        isDefault: Bool,
        isForced: Bool,
        isEnabled: Bool,
        isCommentary: Bool,
        isHearingImpaired: Bool,
        isVisualImpaired: Bool,
        isOriginal: Bool,
        isTextDescription: Bool
    ) {
        self.trackUID = trackUID
        self.name = name
        self.language = language
        self.isDefault = isDefault
        self.isForced = isForced
        self.isEnabled = isEnabled
        self.isCommentary = isCommentary
        self.isHearingImpaired = isHearingImpaired
        self.isVisualImpaired = isVisualImpaired
        self.isOriginal = isOriginal
        self.isTextDescription = isTextDescription
    }
}

extension TrackMetadataEdit {
    public init(track: MediaTrack) throws {
        guard let trackUID = track.uid else {
            throw TrackMetadataEditValidationError.missingTrackUID
        }
        self.init(
            trackUID: trackUID,
            name: track.title,
            language: track.language ?? "und",
            isDefault: track.isDefault,
            isForced: track.isForced,
            isEnabled: track.isEnabled,
            isCommentary: track.isCommentary,
            isHearingImpaired: track.isHearingImpaired,
            isVisualImpaired: track.isVisualImpaired,
            isOriginal: track.isOriginal,
            isTextDescription: track.isTextDescription
        )
    }
}

public enum TrackMetadataEditValidationError: Error, Equatable, Sendable {
    case missingTrackUID
}

extension TrackMetadataEditValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingTrackUID:
            "This track has no stable Matroska UID and cannot be edited safely."
        }
    }
}
