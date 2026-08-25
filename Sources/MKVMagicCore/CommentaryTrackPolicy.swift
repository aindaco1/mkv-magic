import Foundation

public enum TrackRolePolicyError: Error, Equatable, Sendable {
    case unstableTrackIdentity
}

extension TrackRolePolicyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unstableTrackIdentity:
            "A recognized track has no unique Matroska UID."
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
            throw TrackRolePolicyError.unstableTrackIdentity
        }
        return try candidates.map { track in
            try roleMetadataEdit(for: track, isCommentary: true)
        }
    }

    public static func titleIdentifiesCommentary(_ title: String?) -> Bool {
        titleContainsDistinctToken("commentary", in: title)
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
                throw TrackRolePolicyError.unstableTrackIdentity
            }
            edits.append(
                contentsOf: try changes.map { index, track in
                    try roleMetadataEdit(for: track, name: normalizedName(at: index))
                }
            )
        }
        return edits
    }

    private static func normalizedName(at index: Int) -> String {
        index == 0 ? "Commentary" : "Commentary #\(index + 1)"
    }
}

/// Produces per-run edits only for clearly named, currently unforced subtitles.
public enum ForcedSubtitlePolicy {
    public static func metadataEdits(in asset: MediaAsset) throws -> [TrackMetadataEdit] {
        let stableTrackUIDs = uniqueTrackUIDs(in: asset.tracks)
        let candidates = asset.tracks.filter { track in
            track.kind == .subtitle
                && !track.isForced
                && titleContainsDistinctToken("forced", in: track.title)
        }
        guard candidates.allSatisfy({ $0.uid.map(stableTrackUIDs.contains) == true }) else {
            throw TrackRolePolicyError.unstableTrackIdentity
        }
        return try candidates.map { track in
            try roleMetadataEdit(for: track, isForced: true)
        }
    }
}

/// Produces per-run edits only for clearly named, currently unmarked SDH tracks.
public enum HearingImpairedSubtitlePolicy {
    public static func metadataEdits(in asset: MediaAsset) throws -> [TrackMetadataEdit] {
        let stableTrackUIDs = uniqueTrackUIDs(in: asset.tracks)
        let candidates = asset.tracks.filter { track in
            track.kind == .subtitle
                && !track.isHearingImpaired
                && titleIdentifiesHearingImpairedSubtitles(track.title)
        }
        guard candidates.allSatisfy({ $0.uid.map(stableTrackUIDs.contains) == true }) else {
            throw TrackRolePolicyError.unstableTrackIdentity
        }
        return try candidates.map { track in
            try roleMetadataEdit(for: track, isHearingImpaired: true)
        }
    }

    private static func titleIdentifiesHearingImpairedSubtitles(_ title: String?) -> Bool {
        let tokens = normalizedTitleTokens(title)
        if tokens.contains("sdh") || tokens.contains("cc") || tokens.contains("hearingimpaired") {
            return true
        }
        return tokens.enumerated().contains { index, token in
            token == "hearing" && index + 1 < tokens.count && tokens[index + 1] == "impaired"
        }
    }
}

private func uniqueTrackUIDs(in tracks: [MediaTrack]) -> Set<UInt64> {
    let counts = tracks.compactMap(\.uid).reduce(into: [UInt64: Int]()) { counts, uid in
        counts[uid, default: 0] += 1
    }
    return Set(counts.compactMap { uid, count in count == 1 ? uid : nil })
}

private func titleContainsDistinctToken(_ token: String, in title: String?) -> Bool {
    normalizedTitleTokens(title).contains(Substring(token))
}

private func normalizedTitleTokens(_ title: String?) -> [Substring] {
    guard let title else { return [] }
    return title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
}

private func roleMetadataEdit(
    for track: MediaTrack,
    name: String? = nil,
    isForced: Bool? = nil,
    isCommentary: Bool? = nil,
    isHearingImpaired: Bool? = nil
) throws -> TrackMetadataEdit {
    let original = try TrackMetadataEdit(track: track)
    return TrackMetadataEdit(
        trackUID: original.trackUID,
        name: name ?? original.name,
        language: original.language,
        isDefault: original.isDefault,
        isForced: isForced ?? original.isForced,
        isEnabled: original.isEnabled,
        isCommentary: isCommentary ?? original.isCommentary,
        isHearingImpaired: isHearingImpaired ?? original.isHearingImpaired,
        isVisualImpaired: original.isVisualImpaired,
        isOriginal: original.isOriginal,
        isTextDescription: original.isTextDescription
    )
}
