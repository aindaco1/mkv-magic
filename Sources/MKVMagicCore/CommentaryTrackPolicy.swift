import Foundation

public enum CommentaryTrackPolicyError: Error, Equatable, Sendable {
    case unstableTrackIdentity
}

extension CommentaryTrackPolicyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unstableTrackIdentity:
            "A clearly named commentary track has no unique Matroska UID."
        }
    }
}

/// Produces per-run metadata edits only for clearly named commentary tracks.
/// Saved workflows persist the policy action, never these file-specific UIDs.
public enum CommentaryTrackPolicy {
    public static func metadataEdits(in asset: MediaAsset) throws -> [TrackMetadataEdit] {
        let candidates = asset.tracks.filter { track in
            (track.kind == .audio || track.kind == .subtitle)
                && !track.isCommentary
                && titleIdentifiesCommentary(track.title)
        }
        guard candidates.allSatisfy({ $0.uid != nil }),
            Set(candidates.compactMap(\.uid)).count == candidates.count
        else {
            throw CommentaryTrackPolicyError.unstableTrackIdentity
        }
        return try candidates.map { track in
            let original = try TrackMetadataEdit(track: track)
            return TrackMetadataEdit(
                trackUID: original.trackUID,
                name: original.name,
                language: original.language,
                isDefault: original.isDefault,
                isForced: original.isForced,
                isEnabled: original.isEnabled,
                isCommentary: true,
                isHearingImpaired: original.isHearingImpaired,
                isVisualImpaired: original.isVisualImpaired,
                isOriginal: original.isOriginal,
                isTextDescription: original.isTextDescription
            )
        }
    }

    public static func titleIdentifiesCommentary(_ title: String?) -> Bool {
        guard let title else { return false }
        return title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains("commentary")
    }
}
