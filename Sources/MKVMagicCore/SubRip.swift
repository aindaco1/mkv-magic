import Foundation

public struct SubRipTimestamp: Codable, Comparable, Hashable, Sendable {
    public let milliseconds: Int64

    public init(milliseconds: Int64) {
        self.milliseconds = milliseconds
    }

    public static func < (lhs: SubRipTimestamp, rhs: SubRipTimestamp) -> Bool {
        lhs.milliseconds < rhs.milliseconds
    }
}

public struct SubRipCue: Codable, Hashable, Identifiable, Sendable {
    /// Stable within one parse so review decisions survive normalization and renumbering.
    public let id: Int
    public let originalSequenceNumber: Int?
    public let start: SubRipTimestamp
    public let end: SubRipTimestamp
    public let settings: String?
    public let lines: [String]

    public init(
        id: Int,
        originalSequenceNumber: Int? = nil,
        start: SubRipTimestamp,
        end: SubRipTimestamp,
        settings: String? = nil,
        lines: [String]
    ) {
        self.id = id
        self.originalSequenceNumber = originalSequenceNumber
        self.start = start
        self.end = end
        self.settings = settings
        self.lines = lines
    }
}

public struct SubRipDocument: Codable, Equatable, Sendable {
    public let cues: [SubRipCue]

    public init(cues: [SubRipCue]) {
        self.cues = cues
    }
}

public enum SubtitleTextEncoding: String, Codable, Equatable, Sendable {
    case utf8
    case utf8WithBOM
    case utf16LittleEndian
    case utf16BigEndian
    case windows1252
    case isoLatin1
}

public struct DecodedSubtitleText: Equatable, Sendable {
    public let text: String
    public let encoding: SubtitleTextEncoding

    public init(text: String, encoding: SubtitleTextEncoding) {
        self.text = text
        self.encoding = encoding
    }
}

public enum SubtitleTextDecodingError: Error, Equatable, Sendable {
    case emptyInput
    case unsupportedEncoding
    case containsNull
}

extension SubtitleTextDecodingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyInput: "The subtitle file is empty."
        case .unsupportedEncoding: "The subtitle text encoding is not supported."
        case .containsNull: "The decoded subtitle contains an unexpected null character."
        }
    }
}

public struct SubtitleTextDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> DecodedSubtitleText {
        guard !data.isEmpty else { throw SubtitleTextDecodingError.emptyInput }

        let decoded: DecodedSubtitleText?
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            decoded = String(data: data.dropFirst(3), encoding: .utf8).map {
                DecodedSubtitleText(text: $0, encoding: .utf8WithBOM)
            }
        } else if data.starts(with: [0xFF, 0xFE]) {
            decoded = String(data: data.dropFirst(2), encoding: .utf16LittleEndian).map {
                DecodedSubtitleText(text: $0, encoding: .utf16LittleEndian)
            }
        } else if data.starts(with: [0xFE, 0xFF]) {
            decoded = String(data: data.dropFirst(2), encoding: .utf16BigEndian).map {
                DecodedSubtitleText(text: $0, encoding: .utf16BigEndian)
            }
        } else if let text = String(data: data, encoding: .utf8) {
            decoded = DecodedSubtitleText(text: text, encoding: .utf8)
        } else if let text = String(data: data, encoding: .windowsCP1252) {
            decoded = DecodedSubtitleText(text: text, encoding: .windows1252)
        } else if let text = String(data: data, encoding: .isoLatin1) {
            decoded = DecodedSubtitleText(text: text, encoding: .isoLatin1)
        } else {
            decoded = nil
        }
        guard let decoded else { throw SubtitleTextDecodingError.unsupportedEncoding }
        guard !decoded.text.contains("\0") else { throw SubtitleTextDecodingError.containsNull }
        return decoded
    }
}

public enum SubRipDiagnostic: String, Codable, CaseIterable, Hashable, Sendable {
    case removedByteOrderMark
    case normalizedLineEndings
    case normalizedSequenceNumbers
    case normalizedTimestampSeparator
}

public struct SubRipParseResult: Equatable, Sendable {
    public let document: SubRipDocument
    public let diagnostics: Set<SubRipDiagnostic>

    public init(document: SubRipDocument, diagnostics: Set<SubRipDiagnostic>) {
        self.document = document
        self.diagnostics = diagnostics
    }
}

public enum SubRipParseError: Error, Equatable, Sendable {
    case noCues
    case malformedBlock(block: Int)
    case invalidTimestamp(block: Int)
    case nonIncreasingTime(block: Int)
}

extension SubRipParseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noCues: "No SubRip subtitle cues were found."
        case .malformedBlock(let block): "Subtitle block \(block) is malformed."
        case .invalidTimestamp(let block): "Subtitle block \(block) has an invalid timestamp."
        case .nonIncreasingTime(let block):
            "Subtitle block \(block) ends before it starts."
        }
    }
}

public struct SubRipCodec: Sendable {
    public init() {}

    public func parse(_ decoded: DecodedSubtitleText) throws -> SubRipParseResult {
        var diagnostics = Set<SubRipDiagnostic>()
        if decoded.encoding == .utf8WithBOM
            || decoded.encoding == .utf16LittleEndian
            || decoded.encoding == .utf16BigEndian
        {
            diagnostics.insert(.removedByteOrderMark)
        }
        if decoded.text.utf8.contains(0x0D) { diagnostics.insert(.normalizedLineEndings) }
        var normalized = decoded.text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")
        if normalized.first == "\u{FEFF}" {
            normalized.removeFirst()
            diagnostics.insert(.removedByteOrderMark)
        }

        let blocks = Self.blocks(in: normalized)
        guard !blocks.isEmpty else { throw SubRipParseError.noCues }
        var cues = [SubRipCue]()
        cues.reserveCapacity(blocks.count)
        for (offset, lines) in blocks.enumerated() {
            let blockNumber = offset + 1
            guard !lines.isEmpty else { continue }
            let originalSequenceNumber = Int(lines[0].trimmingCharacters(in: .whitespaces))
            let timingIndex = originalSequenceNumber == nil ? 0 : 1
            guard lines.indices.contains(timingIndex) else {
                throw SubRipParseError.malformedBlock(block: blockNumber)
            }
            if originalSequenceNumber != blockNumber {
                diagnostics.insert(.normalizedSequenceNumbers)
            }
            let timing = try Self.parseTiming(lines[timingIndex], block: blockNumber)
            if timing.usedPeriod { diagnostics.insert(.normalizedTimestampSeparator) }
            let textStart = timingIndex + 1
            guard textStart < lines.count else {
                throw SubRipParseError.malformedBlock(block: blockNumber)
            }
            cues.append(
                SubRipCue(
                    id: offset,
                    originalSequenceNumber: originalSequenceNumber,
                    start: timing.start,
                    end: timing.end,
                    settings: timing.settings,
                    lines: Array(lines[textStart...])
                )
            )
        }
        guard !cues.isEmpty else { throw SubRipParseError.noCues }
        return SubRipParseResult(
            document: SubRipDocument(cues: cues),
            diagnostics: diagnostics
        )
    }

    public func serialize(_ document: SubRipDocument) -> String {
        document.cues.enumerated().map { offset, cue in
            let timing =
                "\(Self.format(cue.start)) --> \(Self.format(cue.end))"
                + cue.settings.map { " \($0)" }.orEmpty
            return ([String(offset + 1), timing] + cue.lines).joined(separator: "\n")
        }.joined(separator: "\n\n") + (document.cues.isEmpty ? "" : "\n")
    }

    private static func blocks(in text: String) -> [[String]] {
        var result = [[String]]()
        var current = [String]()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    result.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func parseTiming(
        _ line: String,
        block: Int
    ) throws -> (
        start: SubRipTimestamp,
        end: SubRipTimestamp,
        settings: String?,
        usedPeriod: Bool
    ) {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = timingExpression.firstMatch(in: line, range: range),
            match.numberOfRanges == 10
        else {
            throw SubRipParseError.invalidTimestamp(block: block)
        }
        func capture(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else {
                return nil
            }
            return String(line[swiftRange])
        }
        guard let startHours = capture(1).flatMap(Int64.init),
            let startMinutes = capture(2).flatMap(Int64.init),
            let startSeconds = capture(3).flatMap(Int64.init),
            let startFraction = capture(4),
            let endHours = capture(5).flatMap(Int64.init),
            let endMinutes = capture(6).flatMap(Int64.init),
            let endSeconds = capture(7).flatMap(Int64.init),
            let endFraction = capture(8),
            startMinutes < 60, startSeconds < 60, endMinutes < 60, endSeconds < 60
        else {
            throw SubRipParseError.invalidTimestamp(block: block)
        }
        let start = try timestamp(
            hours: startHours,
            minutes: startMinutes,
            seconds: startSeconds,
            fraction: startFraction,
            block: block
        )
        let end = try timestamp(
            hours: endHours,
            minutes: endMinutes,
            seconds: endSeconds,
            fraction: endFraction,
            block: block
        )
        guard end >= start else { throw SubRipParseError.nonIncreasingTime(block: block) }
        let settings = capture(9)?.trimmingCharacters(in: .whitespaces)
        return (
            start,
            end,
            settings?.isEmpty == false ? settings : nil,
            line.contains(".")
        )
    }

    private static func milliseconds(_ fraction: String) -> Int64 {
        Int64(fraction.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
    }

    private static func timestamp(
        hours: Int64,
        minutes: Int64,
        seconds: Int64,
        fraction: String,
        block: Int
    ) throws -> SubRipTimestamp {
        let hourMinutes = hours.multipliedReportingOverflow(by: 60)
        let totalMinutes = hourMinutes.partialValue.addingReportingOverflow(minutes)
        let totalSeconds = totalMinutes.partialValue.multipliedReportingOverflow(by: 60)
        let secondsWithRemainder = totalSeconds.partialValue.addingReportingOverflow(seconds)
        let wholeMilliseconds = secondsWithRemainder.partialValue.multipliedReportingOverflow(
            by: 1_000)
        let totalMilliseconds = wholeMilliseconds.partialValue.addingReportingOverflow(
            milliseconds(fraction))
        guard !hourMinutes.overflow,
            !totalMinutes.overflow,
            !totalSeconds.overflow,
            !secondsWithRemainder.overflow,
            !wholeMilliseconds.overflow,
            !totalMilliseconds.overflow,
            totalMilliseconds.partialValue <= Int64.max / 1_000_000
        else {
            throw SubRipParseError.invalidTimestamp(block: block)
        }
        return SubRipTimestamp(milliseconds: totalMilliseconds.partialValue)
    }

    private static func format(_ timestamp: SubRipTimestamp) -> String {
        let value = max(0, timestamp.milliseconds)
        let hours = value / 3_600_000
        let minutes = (value / 60_000) % 60
        let seconds = (value / 1_000) % 60
        let milliseconds = value % 1_000
        return String(
            format: "%02lld:%02lld:%02lld,%03lld",
            hours,
            minutes,
            seconds,
            milliseconds
        )
    }

    private static let timingExpression = try! NSRegularExpression(
        pattern:
            #"^\s*(\d+):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d+):(\d{2}):(\d{2})[,.](\d{1,3})(?:\s+(.*?))?\s*$"#
    )
}

public enum SubtitleCleanupReason: String, Codable, CaseIterable, Hashable, Sendable {
    case ytsAdvertisement
    case accidentalWhitespace
    case ocrHighConfidence
    case spellingSuggestion
}

public struct SubtitleCleanupChange: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let reasons: Set<SubtitleCleanupReason>
    public let before: SubRipCue
    public let after: SubRipCue?

    public init(
        id: Int,
        reasons: Set<SubtitleCleanupReason>,
        before: SubRipCue,
        after: SubRipCue?
    ) {
        self.id = id
        self.reasons = reasons
        self.before = before
        self.after = after
    }
}

public struct SubtitleCleanupPreview: Equatable, Sendable {
    public let original: SubRipDocument
    public let cleaned: SubRipDocument
    public let changes: [SubtitleCleanupChange]

    public init(
        original: SubRipDocument,
        cleaned: SubRipDocument,
        changes: [SubtitleCleanupChange]
    ) {
        self.original = original
        self.cleaned = cleaned
        self.changes = changes
    }

    public func document(restoringCueIDs restored: Set<Int>) -> SubRipDocument {
        let cleanedByID = Dictionary(uniqueKeysWithValues: cleaned.cues.map { ($0.id, $0) })
        return SubRipDocument(
            cues: original.cues.compactMap { cue in
                if restored.contains(cue.id) { return cue }
                return cleanedByID[cue.id]
            }
        )
    }
}

public struct SubtitleCleanupPolicy: Sendable {
    private let appliesEnglishOCRRules: Bool

    public init(appliesEnglishOCRRules: Bool = true) {
        self.appliesEnglishOCRRules = appliesEnglishOCRRules
    }

    public func preview(_ document: SubRipDocument) -> SubtitleCleanupPreview {
        var cleaned = [SubRipCue]()
        var changes = [SubtitleCleanupChange]()
        let ocrPolicy = EnglishOCRCorrectionPolicy()
        for cue in document.cues {
            if Self.isKnownAdvertisement(cue.lines) {
                changes.append(
                    SubtitleCleanupChange(
                        id: cue.id,
                        reasons: [.ytsAdvertisement],
                        before: cue,
                        after: nil
                    )
                )
                continue
            }
            var reasons = Set<SubtitleCleanupReason>()
            var normalizedLines = cue.lines.map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if normalizedLines != cue.lines {
                reasons.insert(.accidentalWhitespace)
            }
            if appliesEnglishOCRRules {
                let reviews = normalizedLines.map(ocrPolicy.review)
                let automaticallyCorrected = reviews.map(\.automaticallyCorrectedText)
                if automaticallyCorrected != normalizedLines {
                    normalizedLines = automaticallyCorrected
                    reasons.insert(.ocrHighConfidence)
                } else if reasons.isEmpty {
                    let suggested = reviews.map(\.fullySuggestedText)
                    if suggested != normalizedLines {
                        normalizedLines = suggested
                        reasons.insert(.spellingSuggestion)
                    }
                }
            }
            let normalizedCue = SubRipCue(
                id: cue.id,
                originalSequenceNumber: cue.originalSequenceNumber,
                start: cue.start,
                end: cue.end,
                settings: cue.settings,
                lines: normalizedLines
            )
            cleaned.append(normalizedCue)
            if !reasons.isEmpty {
                changes.append(
                    SubtitleCleanupChange(
                        id: cue.id,
                        reasons: reasons,
                        before: cue,
                        after: normalizedCue
                    )
                )
            }
        }
        return SubtitleCleanupPreview(
            original: document,
            cleaned: SubRipDocument(cues: cleaned),
            changes: changes
        )
    }

    private static func isKnownAdvertisement(_ lines: [String]) -> Bool {
        let text = lines.joined(separator: " ")
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        let hasKnownDomain = ["yts.mx", "yts.lt", "yts.bz"].contains { text.contains($0) }
        guard hasKnownDomain else { return false }
        return text.contains("official yify movies site")
            || text.contains("downloaded from")
    }
}

extension Optional where Wrapped == String {
    fileprivate var orEmpty: String { self ?? "" }
}
