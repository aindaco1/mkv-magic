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
