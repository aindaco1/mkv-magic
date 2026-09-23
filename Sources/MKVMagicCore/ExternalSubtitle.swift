import Foundation

public struct ExternalSubtitleTrackMetadata: Codable, Equatable, Hashable, Sendable {
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

public enum ExternalTextSubtitleFormat: String, Codable, CaseIterable, Hashable, Sendable {
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
    case similarTitle
}

/// One filename-language vocabulary for media and sidecar subtitle defaults.
/// Only a trailing metadata suffix is considered, so language words elsewhere
/// in a title do not become track metadata accidentally.
public enum FilenameLanguageInference {
    public static func language(in url: URL) -> String? {
        language(inStem: url.deletingPathExtension().lastPathComponent)
    }

    public static func language(inStem stem: String) -> String? {
        let suffix = metadataSuffix(in: tokens(stem))
        guard let token = suffix.first(where: { languageTokens[$0] != nil }) else { return nil }
        // A language word in a plain title ("The English") is not a tag.
        guard
            token.count <= 3
                || stem.range(of: #"[._\[\]-]|\d{4}"#, options: .regularExpression) != nil
        else { return nil }
        return languageTokens[token]
    }

    static func tokens(_ value: String) -> [String] {
        value.replacingOccurrences(
            of: #"(?i)\b(aac|ddp|dd|dts)[ ._-]?([257])[.]([01])\b"#,
            with: "$1$2$3", options: .regularExpression
        )
        .folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .unicodeScalars
        .split { !CharacterSet.alphanumerics.contains($0) }
        .map { String(String.UnicodeScalarView($0)).lowercased() }
    }

    static func metadataSuffix(in tokens: [String]) -> [String] {
        var suffix = [String]()
        for token in tokens.reversed() {
            guard
                languageTokens[token] != nil
                    || forcedTokens.contains(token)
                    || hearingImpairedTokens.contains(token)
                    || technicalSuffixTokens.contains(token)
            else { break }
            suffix.append(token)
        }
        return suffix.reversed()
    }

    static let forcedTokens: Set<String> = ["forced", "force"]
    static let hearingImpairedTokens: Set<String> = ["cc", "sdh", "hearingimpaired"]
    static let technicalSuffixTokens: Set<String> = [
        "480p", "576p", "720p", "1080p", "2160p", "4k", "av1", "bluray", "brrip",
        "dts", "h264", "h265", "hdr", "hevc", "web", "webdl", "webrip", "x264", "x265",
        "aac", "ac3", "eac3", "flac", "opus", "10bit", "yts", "yify", "rarbg",
        "aac20", "aac51", "aac71", "dd20", "dd51", "ddp51", "ddp71", "dts51", "dts71",
    ]
    static let languageTokens: [String: String] = [
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
        let mediaTokens = FilenameLanguageInference.tokens(mediaName)
        let subtitleTokens = FilenameLanguageInference.tokens(subtitleName)
        let isExactBasename = Self.canonical(mediaName) == Self.canonical(subtitleName)
        let subtitleSuffix =
            isExactBasename && FilenameLanguageInference.language(inStem: subtitleName) == nil
            ? [] : FilenameLanguageInference.metadataSuffix(in: subtitleTokens)
        let language =
            subtitleSuffix.compactMap {
                FilenameLanguageInference.languageTokens[$0]
            }.first ?? "und"
        let isForced = subtitleSuffix.contains {
            FilenameLanguageInference.forcedTokens.contains($0)
        }
        let isHearingImpaired = subtitleSuffix.contains {
            FilenameLanguageInference.hearingImpairedTokens.contains($0)
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
            let mediaSuffix =
                FilenameLanguageInference.language(inStem: mediaName) == nil
                ? [] : FilenameLanguageInference.metadataSuffix(in: mediaTokens)
            let normalizedMedia = Self.normalizedContentTokens(
                Array(mediaTokens.dropLast(mediaSuffix.count)))
            let normalizedSubtitle = Self.normalizedContentTokens(
                Array(subtitleTokens.dropLast(subtitleSuffix.count))
            )
            if !normalizedMedia.isEmpty, normalizedMedia == normalizedSubtitle {
                score += 80
                reasons.insert(.normalizedTitleAndYear)
            } else if Self.compatibleIdentifiers(mediaTokens, subtitleTokens) {
                let mediaTitle = Self.titleTokens(media.sourceURL)
                let subtitleTitle = Self.titleTokens(subtitleURL)
                if !mediaTitle.isEmpty, mediaTitle == subtitleTitle {
                    // Output naming can discard an unknown suffix after the
                    // year. That is useful for ranking, never proof that two
                    // differently named cuts are interchangeable.
                    score += 45
                    reasons.insert(.similarTitle)
                } else {
                    let lhs = Set(mediaTitle), rhs = Set(subtitleTitle)
                    let union = lhs.union(rhs)
                    if lhs.count >= 2, rhs.count >= 2, !union.isEmpty,
                        Double(lhs.intersection(rhs).count) / Double(union.count) >= 0.65
                    {
                        score += 45
                        reasons.insert(.similarTitle)
                    }
                }
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
        let strongIdentity =
            reasons.contains(.exactBasename) || reasons.contains(.normalizedTitleAndYear)
        if !strongIdentity && durationCompatible == false {
            confidence = .low
        } else if reasons.contains(.similarTitle) {
            confidence = .medium
        } else if score >= 80 {
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
        FilenameLanguageInference.tokens(value).joined(separator: " ")
    }

    private static func normalizedContentTokens(_ tokens: [String]) -> [String] {
        tokens.filter { !FilenameLanguageInference.technicalSuffixTokens.contains($0) }
    }

    private static func titleTokens(_ url: URL) -> [String] {
        let filename =
            MediaFilenameNormalizationPolicy.suggestedFilename(for: url) ?? url.lastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        let tokens = FilenameLanguageInference.tokens(stem)
        let suffix = FilenameLanguageInference.metadataSuffix(in: tokens)
        return normalizedContentTokens(Array(tokens.dropLast(suffix.count)))
    }

    private static func compatibleIdentifiers(_ lhs: [String], _ rhs: [String]) -> Bool {
        func identifiers(_ tokens: [String]) -> [String] {
            var result = tokens.filter {
                $0.range(
                    of: #"^(?:19|20)\d{2}$|^s\d+e\d+$|^(?:part|pt|disc)\d+$"#,
                    options: .regularExpression) != nil
                    || ["extended", "theatrical", "unrated", "directors", "remastered"].contains($0)
            }
            for pair in zip(tokens, tokens.dropFirst())
            where ["part", "pt", "disc"].contains(pair.0) {
                if Int(pair.1) != nil { result.append("\(pair.0)\(pair.1)") }
            }
            // Date-based episodes must not collapse to a shared title/year in
            // the filename normalizer (for example a daily programme).
            for index in tokens.indices where index + 2 < tokens.count {
                if let year = Int(tokens[index]), (1900...2099).contains(year),
                    let month = Int(tokens[index + 1]), (1...12).contains(month),
                    let day = Int(tokens[index + 2]), (1...31).contains(day)
                {
                    result.append("date:\(year)-\(month)-\(day)")
                }
            }
            return result
        }
        return identifiers(lhs) == identifiers(rhs)
    }

    private static func episodeIdentifier(in tokens: [String]) -> String? {
        tokens.first { token in
            token.range(of: #"^s\d{1,2}e\d{1,3}$"#, options: .regularExpression) != nil
        }
    }

}
