import Foundation

public struct CleanMKVTrackSuggestion: Equatable, Hashable, Sendable {
    public enum Reason: Equatable, Hashable, Sendable {
        case nonEnglishSubtitle(language: String)
        case redundantSDH
    }

    public let trackUID: UInt64
    public let reason: Reason

    public init(trackUID: UInt64, reason: Reason) {
        self.trackUID = trackUID
        self.reason = reason
    }
}

public enum EnglishLibraryCleanupPolicy {
    public static func trackSuggestions(for asset: MediaAsset) -> [CleanMKVTrackSuggestion] {
        let subtitles = asset.tracks.filter { $0.kind == .subtitle && $0.uid != nil }
        let englishOrUnknown = subtitles.filter { track in
            let language = normalizedLanguage(track.language)
            return language == "en" || language == "und"
        }
        let hasPreferredNonSDH = englishOrUnknown.contains { track in
            !isSDH(track) && !mustPreserve(track)
        }

        return subtitles.compactMap { track in
            guard let uid = track.uid, !mustPreserve(track) else { return nil }
            let language = normalizedLanguage(track.language)
            if language != "en" && language != "und" {
                return CleanMKVTrackSuggestion(
                    trackUID: uid,
                    reason: .nonEnglishSubtitle(language: language)
                )
            }
            if isSDH(track), englishOrUnknown.count > 1, hasPreferredNonSDH {
                return CleanMKVTrackSuggestion(trackUID: uid, reason: .redundantSDH)
            }
            return nil
        }
    }

    private static func normalizedLanguage(_ value: String?) -> String {
        guard let value else { return "und" }
        let primary = value.lowercased().split(separator: "-").first.map(String.init) ?? "und"
        if primary.count == 3, primary >= "qaa", primary <= "qtz" { return "und" }
        return switch primary {
        case "eng": "en"
        case "und", "mis", "mul", "zxx", "": "und"
        default: primary
        }
    }

    private static func mustPreserve(_ track: MediaTrack) -> Bool {
        guard let title = track.title?.lowercased() else { return track.isCommentary }
        return track.isCommentary || title.contains("commentary")
            || (title.contains("sign") && title.contains("song"))
    }

    private static func isSDH(_ track: MediaTrack) -> Bool {
        track.isHearingImpaired
            || track.title?.localizedCaseInsensitiveContains("sdh") == true
    }
}
