public enum MatroskaPacketCopyPolicy {
    public static func supports(_ track: MediaTrack) -> Bool {
        let family = MediaCodecFamily(codec: track.codec, kind: track.kind)
        switch track.kind {
        case .video:
            return supportedVideoFamilies.contains(family)
        case .audio:
            return supportedAudioFamilies.contains(family)
        case .subtitle:
            return supportedSubtitleFamilies.contains(family)
        case .data, .attachment, .unknown:
            return false
        }
    }

    private static let supportedVideoFamilies = Set<MediaCodecFamily>([
        .av1, .h264, .hevc, .proRes, .vp8, .vp9, .mpegVideo,
    ])
    private static let supportedAudioFamilies = Set<MediaCodecFamily>([
        .aac, .ac3, .eac3, .opus, .vorbis, .flac, .alac, .pcm, .mp3, .dts, .trueHD,
    ])
    private static let supportedSubtitleFamilies = Set<MediaCodecFamily>([
        .subRip, .ass, .ssa, .pgs, .vobSub, .webVTT,
    ])
}
