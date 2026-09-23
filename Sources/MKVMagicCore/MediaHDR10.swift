import Foundation

/// A validated, static HDR10 signal that can be carried through one reviewed
/// encode. Dynamic HDR10+, HLG, and Dolby Vision deliberately do not fit this
/// contract.
public struct MediaHDR10Signal: Hashable, Sendable {
    public let masteringDisplayMetadata: MediaMasteringDisplayMetadata?
    public let contentLightLevelMetadata: MediaContentLightLevelMetadata?

    public init?(track: MediaTrack) {
        guard track.kind == .video, (track.bitDepth ?? 0) >= 10,
            Self.isBT2020PQ(track.colorInfo)
        else {
            return nil
        }
        let formats = Set(track.hdrFormats.map(Self.normalized).filter { !$0.isEmpty })
        let allowedFormats: Set<String> = ["hdr10 metadata"]
        guard formats.isSubset(of: allowedFormats) else { return nil }
        if formats.contains("hdr10 metadata"), track.masteringDisplayMetadata == nil,
            track.contentLightLevelMetadata == nil
        {
            return nil
        }
        guard Self.valid(track.masteringDisplayMetadata),
            Self.valid(track.contentLightLevelMetadata)
        else {
            return nil
        }
        masteringDisplayMetadata = track.masteringDisplayMetadata
        contentLightLevelMetadata = track.contentLightLevelMetadata
    }

    public static func isBT709SDR(_ track: MediaTrack) -> Bool {
        guard track.hdrFormats.isEmpty, track.masteringDisplayMetadata == nil,
            track.contentLightLevelMetadata == nil,
            let color = track.colorInfo
        else {
            return false
        }
        return normalized(color.range) == "tv"
            && normalized(color.primaries) == "bt709"
            && normalized(color.transfer) == "bt709"
            && normalized(color.matrix) == "bt709"
    }

    /// Returns true only for the narrow AVC case where older tools commonly omit
    /// SDR color labels. This is deliberately a review candidate, not a claim
    /// that the source carried an authoritative BT.709 signal.
    public static func isUntaggedHDAVCSDRCandidate(_ track: MediaTrack) -> Bool {
        guard !isBT709SDR(track), track.kind == .video, track.hdrFormats.isEmpty,
            track.masteringDisplayMetadata == nil,
            track.contentLightLevelMetadata == nil,
            let dimensions = track.dimensions,
            dimensions.width >= 1_280 || dimensions.height >= 720,
            isAVC(track), isPlainEightBit420(track)
        else {
            return false
        }

        guard let color = track.colorInfo else { return true }
        return isAbsentOrAllowed(color.range, allowed: ["tv", "mpeg", "limited"])
            && isAbsentOrAllowed(color.primaries, allowed: ["bt709"])
            && isAbsentOrAllowed(color.transfer, allowed: ["bt709"])
            && isAbsentOrAllowed(color.matrix, allowed: ["bt709"])
    }

    private static func isBT2020PQ(_ color: MediaColorInfo?) -> Bool {
        guard let color else { return false }
        return normalized(color.range) == "tv"
            && normalized(color.primaries) == "bt2020"
            && normalized(color.transfer) == "smpte2084"
            && normalized(color.matrix) == "bt2020nc"
    }

    private static func valid(_ metadata: MediaMasteringDisplayMetadata?) -> Bool {
        guard let metadata else { return true }
        let coordinates = [
            metadata.redX, metadata.redY,
            metadata.greenX, metadata.greenY,
            metadata.blueX, metadata.blueY,
            metadata.whitePointX, metadata.whitePointY,
        ]
        return coordinates.allSatisfy { (0...50_000).contains($0) }
            && (1...1_000_000_000).contains(metadata.maxLuminance)
            && (0...metadata.maxLuminance).contains(metadata.minLuminance)
    }

    private static func valid(_ metadata: MediaContentLightLevelMetadata?) -> Bool {
        guard let metadata else { return true }
        return (0...65_535).contains(metadata.maxContentLightLevel)
            && (0...65_535).contains(metadata.maxFrameAverageLightLevel)
    }

    private static func isAVC(_ track: MediaTrack) -> Bool {
        let facts = [track.codec, track.codecID].compactMap { value -> String? in
            let fact = normalized(value)
            return fact.isEmpty ? nil : fact
        }
        guard !facts.isEmpty else { return false }
        return facts.allSatisfy {
            $0 == "h264" || $0 == "avc" || $0 == "avc1"
                || $0 == "v_mpeg4/iso/avc"
        }
    }

    private static func isPlainEightBit420(_ track: MediaTrack) -> Bool {
        if let bitDepth = track.bitDepth, bitDepth != 8 { return false }
        switch normalized(track.pixelFormat) {
        case "yuv420p", "nv12":
            return true
        default:
            return false
        }
    }

    private static func isAbsentOrAllowed(_ value: String?, allowed: Set<String>) -> Bool {
        let fact = normalized(value)
        return fact.isEmpty || fact == "unknown" || fact == "unspecified"
            || fact == "reserved" || allowed.contains(fact)
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
