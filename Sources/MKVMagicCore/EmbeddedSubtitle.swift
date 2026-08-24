import Foundation

public enum EmbeddedTextSubtitlePolicy {
    public static func format(for track: MediaTrack) -> ExternalTextSubtitleFormat? {
        guard track.kind == .subtitle else { return nil }
        return switch track.codecID?.uppercased() {
        case "S_TEXT/UTF8": .subRip
        case "S_TEXT/ASS": .ass
        case "S_TEXT/SSA": .ssa
        default: nil
        }
    }

    public static func editableTracks(in asset: MediaAsset) -> [MediaTrack] {
        asset.tracks.filter { track in
            track.uid != nil && format(for: track) != nil
        }
    }

    public static func extractableTracks(in asset: MediaAsset) -> [MediaTrack] {
        guard MatroskaEditingPolicy.supports(asset) else { return [] }
        let stableTrackIDs = asset.tracks.filter { $0.id >= 0 }.map(\.id)
        guard Set(stableTrackIDs).count == stableTrackIDs.count else { return [] }
        let stableTrackUIDs = asset.tracks.compactMap(\.uid)
        guard Set(stableTrackUIDs).count == stableTrackUIDs.count else { return [] }
        let tracks = asset.tracks.filter { track in
            track.id >= 0 && track.uid != nil && format(for: track) != nil
        }
        return tracks.sorted { $0.id < $1.id }
    }

    public static func appliesEnglishOCRRules(to track: MediaTrack) -> Bool {
        let language = (track.language ?? "und")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !language.isEmpty,
            language.unicodeScalars.allSatisfy({
                $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-")
            })
        else { return false }
        let primary = language.split(separator: "-", maxSplits: 1).first
        return language == "und" || primary == "en" || primary == "eng"
    }
}
