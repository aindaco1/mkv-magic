import Foundation

/// Bounded discovery for MP4-family timed text that FFmpeg can explicitly
/// convert to an editable ASS sidecar. This does not claim that the surrounding
/// media is eligible for remuxing or transcoding.
public enum TimedTextSubtitleConversionPolicy {
    public static func convertibleTracks(in asset: MediaAsset) -> [MediaTrack] {
        guard supportsContainer(asset) else { return [] }
        let tracks = asset.tracks.filter {
            $0.kind == .subtitle
                && $0.id >= 0
                && MediaCodecFamily(codec: $0.codec, kind: .subtitle) == .timedText
        }
        let stableTrackIDs = asset.tracks.filter { $0.id >= 0 }.map(\.id)
        guard Set(stableTrackIDs).count == stableTrackIDs.count else { return [] }
        return tracks.sorted { $0.id < $1.id }
    }

    public static func canOffer(for asset: MediaAsset) -> Bool {
        !convertibleTracks(in: asset).isEmpty
    }

    private static func supportsContainer(_ asset: MediaAsset) -> Bool {
        let fileExtension = asset.sourceURL.pathExtension.lowercased()
        guard ["mp4", "m4v", "mov"].contains(fileExtension) else { return false }
        let containers = Set(
            asset.container.lowercased().split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        return !containers.isDisjoint(with: ["mov", "mp4"])
    }
}
