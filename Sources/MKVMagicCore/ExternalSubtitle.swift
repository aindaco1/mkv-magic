import Foundation

public struct ExternalSubtitleTrackMetadata: Codable, Equatable, Sendable {
    public let language: String
    public let name: String?
    public let isDefault: Bool
    public let isForced: Bool
    public let isHearingImpaired: Bool

    public init(
        language: String,
        name: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isHearingImpaired: Bool = false
    ) {
        self.language = language
        self.name = name
        self.isDefault = isDefault
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
    }
}

public enum ExternalTextSubtitleFormat: String, Codable, CaseIterable, Sendable {
    case subRip
    case ass
    case ssa

    public var filenameExtension: String {
        switch self {
        case .subRip: "srt"
        case .ass: "ass"
        case .ssa: "ssa"
        }
    }

    public var displayName: String { filenameExtension.uppercased() }
}

public enum ExternalSubtitleMatchConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
}

public enum ExternalSubtitleMatchReason: String, Codable, CaseIterable, Hashable, Sendable {
    case exactBasename
    case normalizedTitleAndYear
    case episodeIdentifier
    case durationCompatible
    case languageInFilename
    case forcedInFilename
    case hearingImpairedInFilename
}

public struct ExternalSubtitleMatch: Equatable, Sendable {
    public let subtitleURL: URL
    public let score: Int
    public let confidence: ExternalSubtitleMatchConfidence
    public let reasons: Set<ExternalSubtitleMatchReason>
    public let suggestedMetadata: ExternalSubtitleTrackMetadata
    public let subtitleEnd: SubRipTimestamp
    public let durationDifferenceMilliseconds: Int64?
    public let isDurationCompatible: Bool?

    public init(
        subtitleURL: URL,
        score: Int,
        confidence: ExternalSubtitleMatchConfidence,
        reasons: Set<ExternalSubtitleMatchReason>,
        suggestedMetadata: ExternalSubtitleTrackMetadata,
        subtitleEnd: SubRipTimestamp,
        durationDifferenceMilliseconds: Int64?,
        isDurationCompatible: Bool?
    ) {
        self.subtitleURL = subtitleURL
        self.score = score
        self.confidence = confidence
        self.reasons = reasons
        self.suggestedMetadata = suggestedMetadata
        self.subtitleEnd = subtitleEnd
        self.durationDifferenceMilliseconds = durationDifferenceMilliseconds
        self.isDurationCompatible = isDurationCompatible
    }
}

public struct ExternalSubtitleMatcher: Sendable {
    public init() {}

    public func match(
        media: MediaAsset,
        subtitleURL: URL,
        subtitle: SubRipDocument
    ) -> ExternalSubtitleMatch {
        match(
            media: media,
            subtitleURL: subtitleURL,
            subtitleEnd: subtitle.cues.map(\.end).max() ?? SubRipTimestamp(milliseconds: 0)
        )
    }

    public func match(
        media: MediaAsset,
        subtitleURL: URL,
        subtitle: AdvancedSubStationAlphaDocument
    ) -> ExternalSubtitleMatch {
        match(
            media: media,
            subtitleURL: subtitleURL,
            subtitleEnd: subtitle.events.map(\.end).max() ?? SubRipTimestamp(milliseconds: 0)
        )
    }

    public func match(
        media: MediaAsset,
        subtitleURL: URL,
        subtitleEnd: SubRipTimestamp
    ) -> ExternalSubtitleMatch {
        let mediaName = media.sourceURL.deletingPathExtension().lastPathComponent
        let subtitleName = subtitleURL.deletingPathExtension().lastPathComponent
        let mediaTokens = Self.tokens(mediaName)
        let subtitleTokens = Self.tokens(subtitleName)
        let isExactBasename = Self.canonical(mediaName) == Self.canonical(subtitleName)
        let subtitleSuffix = isExactBasename ? [] : Self.metadataSuffix(in: subtitleTokens)
        let language = subtitleSuffix.compactMap { Self.languageTokens[$0] }.first ?? "und"
        let isForced = subtitleSuffix.contains { Self.forcedTokens.contains($0) }
        let isHearingImpaired = subtitleSuffix.contains {
            Self.hearingImpairedTokens.contains($0)
        }
        let name: String?
        switch (isForced, isHearingImpaired) {
        case (true, true): name = "Forced SDH"
        case (true, false): name = "Forced"
        case (false, true): name = "SDH"
        case (false, false): name = nil
        }

        var score = 0
        var reasons = Set<ExternalSubtitleMatchReason>()
        if isExactBasename {
            score += 120
            reasons.insert(.exactBasename)
        } else {
            let normalizedMedia = Self.normalizedContentTokens(mediaTokens)
            let normalizedSubtitle = Self.normalizedContentTokens(
                Array(subtitleTokens.dropLast(subtitleSuffix.count))
            )
            if !normalizedMedia.isEmpty, normalizedMedia == normalizedSubtitle {
                score += 80
                reasons.insert(.normalizedTitleAndYear)
            }
        }

        let mediaEpisode = Self.episodeIdentifier(in: mediaTokens)
        let subtitleEpisode = Self.episodeIdentifier(in: subtitleTokens)
        if let mediaEpisode, mediaEpisode == subtitleEpisode {
            score += 40
            reasons.insert(.episodeIdentifier)
        }
        if language != "und" {
            score += 5
            reasons.insert(.languageInFilename)
        }
        if isForced {
            score += 3
            reasons.insert(.forcedInFilename)
        }
        if isHearingImpaired {
            score += 3
            reasons.insert(.hearingImpairedInFilename)
        }

        let durationDifference: Int64?
        let durationCompatible: Bool?
        if let duration = media.duration {
            let mediaMilliseconds = duration.nanoseconds / 1_000_000
            let difference = subtitleEnd.milliseconds.subtractingReportingOverflow(
                mediaMilliseconds)
            durationDifference = difference.overflow ? Int64.max : difference.partialValue
            let tolerance = max(30_000, duration.nanoseconds / 1_000_000 * 15 / 100)
            let magnitude =
                durationDifference == Int64.min ? Int64.max : abs(durationDifference ?? 0)
            durationCompatible = !difference.overflow && magnitude <= tolerance
            if durationCompatible == true {
                score += 20
                reasons.insert(.durationCompatible)
            }
        } else {
            durationDifference = nil
            durationCompatible = nil
        }

        let confidence: ExternalSubtitleMatchConfidence
        if score >= 80 {
            confidence = .high
        } else if score >= 45 {
            confidence = .medium
        } else {
            confidence = .low
        }
        return ExternalSubtitleMatch(
            subtitleURL: subtitleURL.standardizedFileURL,
            score: score,
            confidence: confidence,
            reasons: reasons,
            suggestedMetadata: ExternalSubtitleTrackMetadata(
                language: language,
                name: name,
                isForced: isForced,
                isHearingImpaired: isHearingImpaired
            ),
            subtitleEnd: subtitleEnd,
            durationDifferenceMilliseconds: durationDifference,
            isDurationCompatible: durationCompatible
        )
    }

    private static func canonical(_ value: String) -> String {
        tokens(value).joined(separator: " ")
    }

    private static func tokens(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map { String(String.UnicodeScalarView($0)).lowercased() }
    }

    private static func metadataSuffix(in tokens: [String]) -> [String] {
        var suffix = [String]()
        for token in tokens.reversed() {
            guard
                languageTokens[token] != nil
                    || forcedTokens.contains(token)
                    || hearingImpairedTokens.contains(token)
            else { break }
            suffix.append(token)
        }
        return suffix.reversed()
    }

    private static func normalizedContentTokens(_ tokens: [String]) -> [String] {
        tokens.filter { !releaseTokens.contains($0) }
    }

    private static func episodeIdentifier(in tokens: [String]) -> String? {
        tokens.first { token in
            token.range(of: #"^s\d{1,2}e\d{1,3}$"#, options: .regularExpression) != nil
        }
    }

    private static let forcedTokens: Set<String> = ["forced", "force"]
    private static let hearingImpairedTokens: Set<String> = ["cc", "sdh", "hearingimpaired"]
    private static let releaseTokens: Set<String> = [
        "480p", "576p", "720p", "1080p", "2160p", "4k", "av1", "bluray", "brrip",
        "dts", "h264", "h265", "hdr", "hevc", "web", "webdl", "webrip", "x264", "x265",
    ]
    private static let languageTokens: [String: String] = [
        "ara": "ar", "arabic": "ar", "chi": "zh", "chinese": "zh", "cs": "cs",
        "czech": "cs", "danish": "da", "de": "de", "deu": "de", "dut": "nl",
        "dutch": "nl", "el": "el", "ell": "el", "en": "en", "eng": "en",
        "english": "en", "es": "es", "fin": "fi", "finnish": "fi", "fr": "fr",
        "fra": "fr", "fre": "fr", "french": "fr", "ger": "de", "german": "de",
        "greek": "el", "heb": "he", "hebrew": "he", "hi": "hi", "hin": "hi",
        "hindi": "hi", "hu": "hu", "hun": "hu", "hungarian": "hu", "id": "id",
        "ind": "id", "indonesian": "id", "it": "it", "ita": "it", "italian": "it",
        "ja": "ja", "japanese": "ja", "jpn": "ja", "ko": "ko", "kor": "ko",
        "korean": "ko", "nl": "nl", "no": "no", "nor": "no", "norwegian": "no",
        "pl": "pl", "pol": "pl", "polish": "pl", "por": "pt", "portuguese": "pt",
        "pt": "pt", "ro": "ro", "ron": "ro", "rum": "ro", "romanian": "ro",
        "ru": "ru", "rus": "ru", "russian": "ru", "spa": "es", "spanish": "es",
        "sv": "sv", "swe": "sv", "swedish": "sv", "th": "th", "tha": "th",
        "thai": "th", "tr": "tr", "tur": "tr", "turkish": "tr", "uk": "uk",
        "ukr": "uk", "ukrainian": "uk", "vi": "vi", "vie": "vi", "vietnamese": "vi",
        "zh": "zh", "zho": "zh",
    ]
}
