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
        let stableTrackUIDs = uniqueTrackUIDs(in: asset.tracks)
        let candidates = asset.tracks.filter { track in
            (track.kind == .audio || track.kind == .subtitle)
                && !track.isCommentary
                && titleIdentifiesCommentary(track.title)
        }
        guard candidates.allSatisfy({ $0.uid.map(stableTrackUIDs.contains) == true }) else {
            throw CommentaryTrackPolicyError.unstableTrackIdentity
        }
        return try candidates.map { track in
            try commentaryMetadataEdit(for: track, isCommentary: true)
        }
    }

    public static func titleIdentifiesCommentary(_ title: String?) -> Bool {
        guard let title else { return false }
        return title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains("commentary")
    }
}

/// Produces reviewed, per-run name edits for recognized commentary tracks.
/// Audio and subtitle numbering are intentionally independent, matching the
/// user-facing `Commentary`, `Commentary #2`, ... convention.
public enum CommentaryNamePolicy {
    public static func metadataEdits(in asset: MediaAsset) throws -> [TrackMetadataEdit] {
        let stableTrackUIDs = uniqueTrackUIDs(in: asset.tracks)
        var edits = [TrackMetadataEdit]()
        for kind in [MediaTrackKind.audio, .subtitle] {
            let candidates = asset.tracks.filter { track in
                track.kind == kind
                    && (track.isCommentary
                        || CommentaryTrackPolicy.titleIdentifiesCommentary(track.title))
            }
            let changes = candidates.enumerated().filter { index, track in
                track.title != normalizedName(at: index)
            }
            guard changes.allSatisfy({ $0.element.uid.map(stableTrackUIDs.contains) == true })
            else {
                throw CommentaryTrackPolicyError.unstableTrackIdentity
            }
            edits.append(
                contentsOf: try changes.map { index, track in
                    try commentaryMetadataEdit(for: track, name: normalizedName(at: index))
                }
            )
        }
        return edits
    }

    private static func normalizedName(at index: Int) -> String {
        index == 0 ? "Commentary" : "Commentary #\(index + 1)"
    }
}

private func uniqueTrackUIDs(in tracks: [MediaTrack]) -> Set<UInt64> {
    let counts = tracks.compactMap(\.uid).reduce(into: [UInt64: Int]()) { counts, uid in
        counts[uid, default: 0] += 1
    }
    return Set(counts.compactMap { uid, count in count == 1 ? uid : nil })
}

private func commentaryMetadataEdit(
    for track: MediaTrack,
    name: String? = nil,
    isCommentary: Bool? = nil
) throws -> TrackMetadataEdit {
    let original = try TrackMetadataEdit(track: track)
    return TrackMetadataEdit(
        trackUID: original.trackUID,
        name: name ?? original.name,
        language: original.language,
        isDefault: original.isDefault,
        isForced: original.isForced,
        isEnabled: original.isEnabled,
        isCommentary: isCommentary ?? original.isCommentary,
        isHearingImpaired: original.isHearingImpaired,
        isVisualImpaired: original.isVisualImpaired,
        isOriginal: original.isOriginal,
        isTextDescription: original.isTextDescription
    )
}
