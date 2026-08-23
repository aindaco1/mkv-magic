import Foundation

public enum EnglishOCRCorrectionConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case reviewRequired
}

public struct EnglishOCRCorrection: Equatable, Sendable {
    public let before: String
    public let after: String
    public let confidence: EnglishOCRCorrectionConfidence
    public let utf16Location: Int
    public let utf16Length: Int

    public init(
        before: String,
        after: String,
        confidence: EnglishOCRCorrectionConfidence,
        utf16Location: Int,
        utf16Length: Int
    ) {
        self.before = before
        self.after = after
        self.confidence = confidence
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
    }
}

public struct EnglishOCRTextReview: Equatable, Sendable {
    public let originalText: String
    public let corrections: [EnglishOCRCorrection]

    public init(originalText: String, corrections: [EnglishOCRCorrection]) {
        self.originalText = originalText
        self.corrections = corrections
    }

    public func text(applying confidences: Set<EnglishOCRCorrectionConfidence>) -> String {
        let result = NSMutableString(string: originalText)
        for correction in corrections.reversed() where confidences.contains(correction.confidence) {
            result.replaceCharacters(
                in: NSRange(
                    location: correction.utf16Location,
                    length: correction.utf16Length
                ),
                with: correction.after
            )
        }
        return result as String
    }

    public var automaticallyCorrectedText: String {
        text(applying: [.high])
    }

    public var fullySuggestedText: String {
        text(applying: Set(EnglishOCRCorrectionConfidence.allCases))
    }
}

/// A deliberately bounded English OCR policy. Glyph-based corrections are automatic only when
/// they resolve to one word in the embedded common-word lexicon. Letter-only confusions remain
/// explicit review suggestions. No network, model, or system spell-check service is used.
public struct EnglishOCRCorrectionPolicy: Sendable {
    public init() {}

    public func review(_ text: String) -> EnglishOCRTextReview {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let protected = Self.protectedExpression.matches(in: text, range: fullRange).map(\.range)
        let tokens = Self.tokenExpression.matches(in: text, range: fullRange)
        var corrections = [EnglishOCRCorrection]()
        var protectedIndex = 0
        for tokenMatch in tokens {
            let range = tokenMatch.range
            while protected.indices.contains(protectedIndex),
                NSMaxRange(protected[protectedIndex]) <= range.location
            {
                protectedIndex += 1
            }
            if protected.indices.contains(protectedIndex),
                NSIntersectionRange(protected[protectedIndex], range).length > 0
            {
                continue
            }
            guard let swiftRange = Range(range, in: text) else { continue }
            let original = String(text[swiftRange])
            guard let candidate = Self.correction(for: original), candidate.after != original else {
                continue
            }
            corrections.append(
                EnglishOCRCorrection(
                    before: original,
                    after: candidate.after,
                    confidence: candidate.confidence,
                    utf16Location: range.location,
                    utf16Length: range.length
                )
            )
        }
        return EnglishOCRTextReview(originalText: text, corrections: corrections)
    }

    private static func correction(
        for original: String
    ) -> (after: String, confidence: EnglishOCRCorrectionConfidence)? {
        guard original.utf16.count <= 40 else { return nil }
        let canonical = original.replacingOccurrences(of: "’", with: "'").lowercased()
        if let replacement = highConfidenceContractions[canonical] {
            let cased = contractionCase(replacement, like: original)
            return (preservingApostrophe(cased, from: original), .high)
        }
        if let replacement = reviewPairs[canonical] {
            return (preservingCase(replacement, from: original), .reviewRequired)
        }
        guard canonical.contains(where: { $0.isNumber || $0 == "|" }),
            canonical.contains(where: \.isLetter)
        else { return nil }
        let matches = glyphCandidates(for: canonical).filter(commonWords.contains)
        guard matches.count == 1, let replacement = matches.first else { return nil }
        return (preservingCase(replacement, from: original), .high)
    }

    private static func glyphCandidates(for value: String) -> Set<String> {
        var candidates: Set<String> = [""]
        for character in value {
            let replacements = glyphAlternatives[character] ?? [String(character)]
            var next = Set<String>()
            for prefix in candidates {
                for replacement in replacements where next.count < 64 {
                    next.insert(prefix + replacement)
                }
            }
            candidates = next
            if candidates.isEmpty { break }
        }
        candidates.remove(value)
        return candidates
    }

    private static func preservingCase(_ replacement: String, from original: String) -> String {
        let letters = original.filter(\.isLetter)
        guard !letters.isEmpty else { return replacement }
        if letters == letters.uppercased() {
            return replacement.uppercased()
        }
        if original.first?.isUppercase == true {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    private static func contractionCase(_ replacement: String, like original: String) -> String {
        let letters = original.filter(\.isLetter)
        return letters == letters.uppercased() ? replacement.uppercased() : replacement
    }

    private static func preservingApostrophe(_ replacement: String, from original: String) -> String
    {
        original.contains("’")
            ? replacement.replacingOccurrences(of: "'", with: "’") : replacement
    }

    private static let highConfidenceContractions: [String: String] = [
        "l'd": "I'd", "l'll": "I'll", "l'm": "I'm", "l've": "I've",
        "1'd": "I'd", "1'll": "I'll", "1'm": "I'm", "1've": "I've",
        "|'d": "I'd", "|'ll": "I'll", "|'m": "I'm", "|'ve": "I've",
    ]

    private static let reviewPairs: [String: String] = [
        "bave": "have",
        "bim": "him",
        "modem": "modern",
        "otber": "other",
        "tbat": "that",
        "tbe": "the",
        "tbeir": "their",
        "tben": "then",
        "tbere": "there",
        "tbey": "they",
        "tbis": "this",
        "wben": "when",
        "wbere": "where",
        "wbat": "what",
        "wbich": "which",
        "witb": "with",
    ]

    private static let glyphAlternatives: [Character: [String]] = [
        "0": ["o"],
        "1": ["i", "l"],
        "2": ["z"],
        "3": ["e"],
        "4": ["a"],
        "5": ["s"],
        "6": ["g"],
        "7": ["t"],
        "8": ["b"],
        "9": ["g"],
        "|": ["i", "l"],
    ]

    private static let commonWords: Set<String> = Set(
        """
        about after again against all also always am an and another any anyone anything are
        around as ask at away back be because been before being believe best better between big
        both boy bring brother but by call came can cannot care come could day did do does doing
        done down each enough even ever every everyone everything family far father feel few find
        first for found friend from get girl give go going gone good got great had happen has have
        he hear hello help her here him his home hope how i if in into is it its just keep kind know
        last later leave left let life like little live long look lost love made make man many may
        me mean might mind more morning mother move much must my name need never new next night no
        not nothing now of off oh old on once one only or other our out over own people place please
        put really right said same saw say see she should show sister so some someone something
        sorry still stop sure take talk tell than thank that the their them then there these they
        thing think this those thought through time to today together too try two understand up us
        very wait want was way we well went were what when where which while who why will with
        without woman work world would yes you young your
        """
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
    )

    private static let protectedExpression = try! NSRegularExpression(
        pattern:
            #"\{[^}]*\}|<[^>]*>|(?i:\b(?:https?://|www\.)\S+|\b[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}\b)"#
    )
    private static let tokenExpression = try! NSRegularExpression(
        pattern:
            #"(?<![\p{L}\p{N}_])[\p{L}\p{N}|]+(?:['’][\p{L}\p{N}|]+)*(?![\p{L}\p{N}_])"#
    )
}

public enum EnglishSubtitleFilenamePolicy {
    public static func shouldApplyOCRRules(to sourceURL: URL) -> Bool {
        let stem = sourceURL.deletingPathExtension().lastPathComponent.lowercased()
        var tokens = stem.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        while let last = tokens.last, roleSuffixes.contains(last) {
            tokens.removeLast()
        }
        guard let last = tokens.last else { return true }
        if englishSuffixes.contains(last) { return true }
        if nonEnglishSuffixes.contains(last) { return false }
        if tokens.count >= 2,
            nonEnglishCodes.contains(tokens[tokens.count - 2]),
            isRegionOrNumericSuffix(last)
        {
            return false
        }
        return true
    }

    private static func isRegionOrNumericSuffix(_ value: String) -> Bool {
        (value.count == 2 && value.allSatisfy(\.isLetter))
            || (value.count == 3 && value.allSatisfy(\.isNumber))
            || (value.count == 4 && value.allSatisfy(\.isLetter))
    }

    private static let englishSuffixes: Set<String> = ["en", "eng", "english"]
    private static let roleSuffixes: Set<String> = [
        "cc", "commentary", "default", "forced", "sdh", "signs", "songs",
    ]
    private static let nonEnglishCodes: Set<String> = [
        "ar", "ara", "cs", "ces", "da", "dan", "de", "deu", "el", "ell", "es", "spa",
        "fi", "fin", "fr", "fra", "he", "heb", "hi", "hin", "hu", "hun", "id", "ind",
        "it", "ita", "ja", "jpn", "ko", "kor", "nl", "nld", "no", "nor", "pl", "pol",
        "pt", "por", "ro", "ron", "ru", "rus", "sv", "swe", "th", "tha", "tr", "tur",
        "uk", "ukr", "vi", "vie", "zh", "zho",
    ]
    private static let nonEnglishSuffixes = nonEnglishCodes.union([
        "arabic", "chinese", "czech", "danish", "dutch", "finnish", "french", "german",
        "greek", "hebrew", "hindi", "hungarian", "indonesian", "italian", "japanese",
        "korean", "norwegian", "polish", "portuguese", "romanian", "russian", "spanish",
        "swedish", "thai", "turkish", "ukrainian", "vietnamese",
    ])
}
