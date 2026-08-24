import Foundation

public enum MediaContainerFamily: String, Codable, CaseIterable, Hashable, Sendable {
    case matroska
    case isoBaseMedia
    case mpegTransportStream
    case avi
    case textSubtitle
    case other
    case unknown
}

public enum MediaSizeBucket: String, Codable, CaseIterable, Hashable, Sendable {
    case unknown
    case under100MiB
    case from100MiBTo1GiB
    case from1GiBTo10GiB
    case over10GiB

    public init(byteCount: Int64?) {
        guard let byteCount, byteCount >= 0 else {
            self = .unknown
            return
        }
        switch byteCount {
        case ..<104_857_600: self = .under100MiB
        case ..<1_073_741_824: self = .from100MiBTo1GiB
        case ..<10_737_418_240: self = .from1GiBTo10GiB
        default: self = .over10GiB
        }
    }
}

public enum MediaDurationBucket: String, Codable, CaseIterable, Hashable, Sendable {
    case unknown
    case under5Minutes
    case from5To30Minutes
    case from30To120Minutes
    case over120Minutes

    public init(duration: MediaTime?) {
        guard let duration, duration.nanoseconds >= 0 else {
            self = .unknown
            return
        }
        switch duration.nanoseconds {
        case ..<300_000_000_000: self = .under5Minutes
        case ..<1_800_000_000_000: self = .from5To30Minutes
        case ..<7_200_000_000_000: self = .from30To120Minutes
        default: self = .over120Minutes
        }
    }
}

public enum MediaCodecFamily: String, Codable, CaseIterable, Hashable, Sendable {
    case av1
    case h264
    case hevc
    case proRes
    case vp8
    case vp9
    case mpegVideo
    case aac
    case ac3
    case eac3
    case opus
    case vorbis
    case flac
    case alac
    case pcm
    case mp3
    case dts
    case trueHD
    case subRip
    case ass
    case ssa
    case pgs
    case vobSub
    case webVTT
    case timedText
    case other

    public init(codec rawValue: String, kind: MediaTrackKind) {
        let normalized =
            rawValue.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        self =
            switch normalized {
            case "av1", "a_av1", "v_av1": .av1
            case "h264", "avc", "avc1", "v_mpeg4_iso_avc": .h264
            case "hevc", "h265", "hev1", "hvc1", "v_mpegh_iso_hevc": .hevc
            case let value where value.contains("prores"): .proRes
            case "vp8", "v_vp8": .vp8
            case "vp9", "v_vp9": .vp9
            case "aac", "a_aac": .aac
            case "ac3", "ac_3", "a_ac3": .ac3
            case "eac3", "e_ac_3", "a_eac3": .eac3
            case "opus", "a_opus": .opus
            case "vorbis", "a_vorbis": .vorbis
            case "flac", "a_flac": .flac
            case "alac", "a_alac": .alac
            case let value where value.contains("pcm"): .pcm
            case "mp3", "a_mpeg_l3": .mp3
            case let value where value.contains("dts"): .dts
            case let value where value.contains("truehd"): .trueHD
            case "srt", "subrip", "s_text_utf8": .subRip
            case "ass", "s_text_ass": .ass
            case "ssa", "s_text_ssa": .ssa
            case let value where value.contains("pgs") || value.contains("hdmv_pgs"): .pgs
            case let value where value.contains("vobsub") || value.contains("dvd_subtitle"):
                .vobSub
            case "webvtt", "vtt", "s_text_webvtt": .webVTT
            case "tx3g", "mov_text", "timed_text": .timedText
            case let value where value.contains("mpeg") && kind == .video: .mpegVideo
            default: .other
            }
    }
}

public struct MediaTrackCountFacts: Codable, Hashable, Sendable {
    public let video: Int
    public let audio: Int
    public let subtitle: Int
    public let data: Int
    public let attachment: Int
    public let unknown: Int

    public init(
        video: Int = 0,
        audio: Int = 0,
        subtitle: Int = 0,
        data: Int = 0,
        attachment: Int = 0,
        unknown: Int = 0
    ) {
        self.video = max(0, video)
        self.audio = max(0, audio)
        self.subtitle = max(0, subtitle)
        self.data = max(0, data)
        self.attachment = max(0, attachment)
        self.unknown = max(0, unknown)
    }
}

public struct MediaJobInputFacts: Codable, Hashable, Sendable {
    public let container: MediaContainerFamily
    public let size: MediaSizeBucket
    public let duration: MediaDurationBucket
    public let tracks: MediaTrackCountFacts
    public let codecs: [MediaCodecFamily]
    public let maximumAudioChannels: Int?
    public let hasHDR: Bool
    public let chapterCount: Int
    public let attachmentCount: Int
    public let hasTags: Bool
    public let warningCount: Int

    public init(
        container: MediaContainerFamily,
        size: MediaSizeBucket,
        duration: MediaDurationBucket,
        tracks: MediaTrackCountFacts,
        codecs: [MediaCodecFamily],
        maximumAudioChannels: Int?,
        hasHDR: Bool,
        chapterCount: Int,
        attachmentCount: Int,
        hasTags: Bool,
        warningCount: Int
    ) {
        self.container = container
        self.size = size
        self.duration = duration
        self.tracks = tracks
        self.codecs = Array(Set(codecs)).sorted { $0.rawValue < $1.rawValue }
        self.maximumAudioChannels = maximumAudioChannels.map { max(0, $0) }
        self.hasHDR = hasHDR
        self.chapterCount = max(0, chapterCount)
        self.attachmentCount = max(0, attachmentCount)
        self.hasTags = hasTags
        self.warningCount = max(0, warningCount)
    }

    public init(asset: MediaAsset) {
        let trackCounts = Dictionary(grouping: asset.tracks, by: \.kind).mapValues(\.count)
        let chapterCount = asset.chapterEntryCount ?? Self.chapterCount(asset.chapters)
        self.init(
            container: Self.containerFamily(asset),
            size: MediaSizeBucket(byteCount: asset.fileSize),
            duration: MediaDurationBucket(duration: asset.duration),
            tracks: MediaTrackCountFacts(
                video: trackCounts[.video, default: 0],
                audio: trackCounts[.audio, default: 0],
                subtitle: trackCounts[.subtitle, default: 0],
                data: trackCounts[.data, default: 0],
                attachment: trackCounts[.attachment, default: 0],
                unknown: trackCounts[.unknown, default: 0]
            ),
            codecs: asset.tracks.map { MediaCodecFamily(codec: $0.codec, kind: $0.kind) },
            maximumAudioChannels: asset.tracks.filter { $0.kind == .audio }.compactMap(\.channels)
                .max(),
            hasHDR: asset.tracks.contains { !$0.hdrFormats.isEmpty },
            chapterCount: chapterCount,
            attachmentCount: asset.attachments.count,
            hasTags: (asset.globalTagCount ?? 0) > 0 || (asset.trackTagCount ?? 0) > 0
                || !asset.metadata.isEmpty || asset.tracks.contains { !$0.tags.isEmpty },
            warningCount: asset.warnings.count
        )
    }

    public static func textSubtitle(fileSize: Int64?, pathExtension: String) -> Self {
        Self(
            container: .textSubtitle,
            size: MediaSizeBucket(byteCount: fileSize),
            duration: .unknown,
            tracks: MediaTrackCountFacts(subtitle: 1),
            codecs: [MediaCodecFamily(codec: pathExtension, kind: .subtitle)],
            maximumAudioChannels: nil,
            hasHDR: false,
            chapterCount: 0,
            attachmentCount: 0,
            hasTags: false,
            warningCount: 0
        )
    }

    private static func containerFamily(_ asset: MediaAsset) -> MediaContainerFamily {
        let value = (asset.container + " " + asset.sourceURL.pathExtension).lowercased()
        if value.contains("matroska") || value.contains("webm") || value.contains("mkv") {
            return .matroska
        }
        if value.contains("mov") || value.contains("mp4") || value.contains("m4v") {
            return .isoBaseMedia
        }
        if value.contains("mpegts") || value.contains("mpeg-ts") || value.contains("m2ts") {
            return .mpegTransportStream
        }
        if value.contains("avi") { return .avi }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unknown : .other
    }

    private static func chapterCount(_ chapters: [ChapterNode]) -> Int {
        chapters.reduce(0) { $0 + 1 + chapterCount($1.children) }
    }
}

public struct MediaJobPlanFacts: Codable, Hashable, Sendable {
    public let videoEncodeGenerations: UInt
    public let audioTracksEncoded: UInt

    public init(videoEncodeGenerations: UInt, audioTracksEncoded: UInt) {
        self.videoEncodeGenerations = videoEncodeGenerations
        self.audioTracksEncoded = audioTracksEncoded
    }
}

public enum BuiltInWorkflowKind: String, Codable, CaseIterable, Hashable, Sendable {
    case segmentTitle
    case trackMetadata
    case trackRemoval
    case englishLibraryCleanup
    case subtitleCleanup
    case externalSubtitleMux
    case embeddedSubtitleCleanup
    case chapterEdit
    case losslessJoin
    case commonFormatJoin
    case fastTrim
    case exactTrim
    case videoTranscode
    case remuxToMKV
    case timedTextSubtitleConversion
}

public enum BuiltInWorkflowCatalog {
    public static let segmentTitle = UUID(uuidString: "6A2D7635-AB6D-4C7A-AE02-1561631121F0")!
    public static let trackMetadata = UUID(uuidString: "842C095A-A70A-4B81-BD33-E2857F9B87CD")!
    public static let trackRemoval = UUID(uuidString: "6F67B5AB-BB34-45BF-B159-E98F0C26FA3E")!
    public static let englishLibraryCleanup = UUID(
        uuidString: "853C0788-5994-491F-AC13-A0A47319CD0E"
    )!
    public static let subtitleCleanup = UUID(uuidString: "7062274D-C993-42BF-903E-3DD817424EBF")!
    public static let advancedSubtitleCleanup = UUID(
        uuidString: "A15A085C-F68E-433F-A6D8-486EF1AB2F95"
    )!
    public static let externalSubtitleMux = UUID(
        uuidString: "5CB3529A-967E-4B11-81E2-E5D932F1B395"
    )!
    public static let embeddedSubtitleCleanup = UUID(
        uuidString: "C3A2A7DD-8C17-4A91-A9BC-9750F35A9C6F"
    )!
    public static let chapterEdit = UUID(uuidString: "01898D29-C2C9-44C4-A87D-B72A3AB90FF8")!
    public static let losslessJoin = UUID(uuidString: "1329034D-8DA4-4D8F-82B6-C3BC42A4E4FA")!
    public static let commonFormatJoin = UUID(
        uuidString: "754EEC4F-8989-442A-98C2-A4B17622489D"
    )!
    public static let fastTrim = UUID(uuidString: "7E551E9E-039C-46DB-A14D-E43E338A5E2A")!
    public static let exactTrim = UUID(uuidString: "CA62AB88-34D1-44E0-B410-FB9DAA2FE3ED")!
    public static let videoTranscode = UUID(
        uuidString: "64FBC4F1-5764-4F44-89A4-E6B6A4A68940"
    )!
    public static let remuxToMKV = UUID(
        uuidString: "17A7AC0B-5184-42D7-ABAF-33269767A597"
    )!
    public static let timedTextSubtitleConversion = UUID(
        uuidString: "C37188E7-8636-43F4-918F-216FF865E041"
    )!

    public static func kind(for id: UUID) -> BuiltInWorkflowKind? {
        switch id {
        case segmentTitle: .segmentTitle
        case trackMetadata: .trackMetadata
        case trackRemoval: .trackRemoval
        case englishLibraryCleanup: .englishLibraryCleanup
        case subtitleCleanup, advancedSubtitleCleanup: .subtitleCleanup
        case externalSubtitleMux: .externalSubtitleMux
        case embeddedSubtitleCleanup: .embeddedSubtitleCleanup
        case chapterEdit: .chapterEdit
        case losslessJoin: .losslessJoin
        case commonFormatJoin: .commonFormatJoin
        case fastTrim: .fastTrim
        case exactTrim: .exactTrim
        case videoTranscode: .videoTranscode
        case remuxToMKV: .remuxToMKV
        case timedTextSubtitleConversion: .timedTextSubtitleConversion
        default: nil
        }
    }
}
