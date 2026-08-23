import Foundation

public struct AdvancedSubStationAlphaEvent: Equatable, Identifiable, Sendable {
    public let id: Int
    public let start: SubRipTimestamp
    public let end: SubRipTimestamp
    public let style: String?
    public let text: String

    fileprivate let prefix: String
    fileprivate let fields: [String]
    fileprivate let startFieldIndex: Int
    fileprivate let endFieldIndex: Int
    fileprivate let textFieldIndex: Int

    fileprivate init(
        id: Int,
        start: SubRipTimestamp,
        end: SubRipTimestamp,
        style: String?,
        text: String,
        prefix: String,
        fields: [String],
        startFieldIndex: Int,
        endFieldIndex: Int,
        textFieldIndex: Int
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.style = style
        self.text = text
        self.prefix = prefix
        self.fields = fields
        self.startFieldIndex = startFieldIndex
        self.endFieldIndex = endFieldIndex
        self.textFieldIndex = textFieldIndex
    }

    /// Fields such as layer, style, speaker, margins, and effect that muxing must preserve.
    public var structuralFields: [String] {
        fields.enumerated().compactMap { index, field in
            guard index != startFieldIndex, index != endFieldIndex, index != textFieldIndex else {
                return nil
            }
            return field
        }
    }

    fileprivate func replacingText(_ text: String) -> Self {
        var fields = fields
        fields[textFieldIndex] = text
        return Self(
            id: id,
            start: start,
            end: end,
            style: style,
            text: text,
            prefix: prefix,
            fields: fields,
            startFieldIndex: startFieldIndex,
            endFieldIndex: endFieldIndex,
            textFieldIndex: textFieldIndex
        )
    }

    fileprivate var serialized: String {
        prefix + fields.joined(separator: ",")
    }
}

public enum AdvancedSubStationAlphaLine: Equatable, Sendable {
    case raw(String)
    case dialogue(AdvancedSubStationAlphaEvent)
}

public struct AdvancedSubStationAlphaDocument: Equatable, Sendable {
    public let lines: [AdvancedSubStationAlphaLine]

    public init(lines: [AdvancedSubStationAlphaLine]) {
        self.lines = lines
    }

    public var events: [AdvancedSubStationAlphaEvent] {
        lines.compactMap { line in
            guard case .dialogue(let event) = line else { return nil }
            return event
        }
    }
}

public enum AdvancedSubStationAlphaDiagnostic: String, Codable, CaseIterable, Hashable, Sendable {
    case removedByteOrderMark
    case normalizedLineEndings
}

public struct AdvancedSubStationAlphaParseResult: Equatable, Sendable {
    public let document: AdvancedSubStationAlphaDocument
    public let diagnostics: Set<AdvancedSubStationAlphaDiagnostic>

    public init(
        document: AdvancedSubStationAlphaDocument,
        diagnostics: Set<AdvancedSubStationAlphaDiagnostic>
    ) {
        self.document = document
        self.diagnostics = diagnostics
    }
}

public enum AdvancedSubStationAlphaParseError: Error, Equatable, Sendable {
    case missingEventsSection
    case missingEventFormat
    case invalidEventFormat(line: Int)
    case malformedDialogue(line: Int)
    case invalidTimestamp(line: Int)
    case nonIncreasingTime(line: Int)
    case noDialogueEvents
}

extension AdvancedSubStationAlphaParseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingEventsSection: "The subtitle has no [Events] section."
        case .missingEventFormat: "The [Events] section has no Format line before Dialogue."
        case .invalidEventFormat(let line): "Subtitle line \(line) has an invalid event format."
        case .malformedDialogue(let line): "Subtitle line \(line) has a malformed Dialogue event."
        case .invalidTimestamp(let line): "Subtitle line \(line) has an invalid timestamp."
        case .nonIncreasingTime(let line): "Subtitle line \(line) ends before it starts."
        case .noDialogueEvents: "No ASS/SSA dialogue events were found."
        }
    }
}

public struct AdvancedSubStationAlphaCodec: Sendable {
    public init() {}

    public func parse(_ decoded: DecodedSubtitleText) throws -> AdvancedSubStationAlphaParseResult {
        var diagnostics = Set<AdvancedSubStationAlphaDiagnostic>()
        if decoded.encoding == .utf8WithBOM
            || decoded.encoding == .utf16LittleEndian
            || decoded.encoding == .utf16BigEndian
        {
            diagnostics.insert(.removedByteOrderMark)
        }
        if decoded.text.utf8.contains(0x0D) {
            diagnostics.insert(.normalizedLineEndings)
        }
        var normalized = decoded.text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")
        if normalized.first == "\u{FEFF}" {
            normalized.removeFirst()
            diagnostics.insert(.removedByteOrderMark)
        }
        var sourceLines = normalized.split(
            separator: "\n", omittingEmptySubsequences: false
        ).map(String.init)
        if normalized.hasSuffix("\n"), sourceLines.last == "" {
            sourceLines.removeLast()
        }

        var section: String?
        var sawEvents = false
        var eventColumns: [String]?
        var lines = [AdvancedSubStationAlphaLine]()
        var eventID = 0
        for (offset, line) in sourceLines.enumerated() {
            let lineNumber = offset + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                section = String(trimmed.dropFirst().dropLast()).lowercased()
                if section == "events" { sawEvents = true }
                lines.append(.raw(line))
                continue
            }
            guard section == "events", let colon = line.firstIndex(of: ":") else {
                lines.append(.raw(line))
                continue
            }
            let label = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let valueStart = line.index(after: colon)
            let value = String(line[valueStart...])
            if label == "format" {
                let columns = value.split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                guard Self.valid(columns: columns) else {
                    throw AdvancedSubStationAlphaParseError.invalidEventFormat(line: lineNumber)
                }
                eventColumns = columns
                lines.append(.raw(line))
                continue
            }
            guard label == "dialogue" else {
                lines.append(.raw(line))
                continue
            }
            guard let eventColumns else {
                throw AdvancedSubStationAlphaParseError.missingEventFormat
            }
            let fields = Self.split(value, fieldCount: eventColumns.count)
            guard fields.count == eventColumns.count,
                let startIndex = eventColumns.firstIndex(of: "start"),
                let endIndex = eventColumns.firstIndex(of: "end"),
                let textIndex = eventColumns.firstIndex(of: "text")
            else {
                throw AdvancedSubStationAlphaParseError.malformedDialogue(line: lineNumber)
            }
            let start = try Self.timestamp(fields[startIndex], line: lineNumber)
            let end = try Self.timestamp(fields[endIndex], line: lineNumber)
            guard end >= start else {
                throw AdvancedSubStationAlphaParseError.nonIncreasingTime(line: lineNumber)
            }
            let style = eventColumns.firstIndex(of: "style").map {
                fields[$0].trimmingCharacters(in: .whitespaces)
            }
            let prefix = String(line[...colon])
            lines.append(
                .dialogue(
                    AdvancedSubStationAlphaEvent(
                        id: eventID,
                        start: start,
                        end: end,
                        style: style?.isEmpty == false ? style : nil,
                        text: fields[textIndex],
                        prefix: prefix,
                        fields: fields,
                        startFieldIndex: startIndex,
                        endFieldIndex: endIndex,
                        textFieldIndex: textIndex
                    )
                )
            )
            eventID += 1
        }
        guard sawEvents else { throw AdvancedSubStationAlphaParseError.missingEventsSection }
        guard eventID > 0 else { throw AdvancedSubStationAlphaParseError.noDialogueEvents }
        return AdvancedSubStationAlphaParseResult(
            document: AdvancedSubStationAlphaDocument(lines: lines),
            diagnostics: diagnostics
        )
    }

    public func serialize(_ document: AdvancedSubStationAlphaDocument) -> String {
        document.lines.map { line in
            switch line {
            case .raw(let value): value
            case .dialogue(let event): event.serialized
            }
        }.joined(separator: "\n") + (document.lines.isEmpty ? "" : "\n")
    }

    private static func valid(columns: [String]) -> Bool {
        guard !columns.isEmpty, Set(columns).count == columns.count else { return false }
        return ["start", "end", "text"].allSatisfy { column in
            columns.filter { $0 == column }.count == 1
        }
    }

    private static func split(_ value: String, fieldCount: Int) -> [String] {
        guard fieldCount > 1 else { return [value] }
        var fields = [String]()
        var start = value.startIndex
        while fields.count < fieldCount - 1,
            let comma = value[start...].firstIndex(of: ",")
        {
            fields.append(String(value[start..<comma]))
            start = value.index(after: comma)
        }
        fields.append(String(value[start...]))
        return fields
    }

    private static func timestamp(_ raw: String, line: Int) throws -> SubRipTimestamp {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = timestampExpression.firstMatch(in: value, range: range),
            let hours = capture(1, match: match, in: value).flatMap(Int64.init),
            let minutes = capture(2, match: match, in: value).flatMap(Int64.init),
            let seconds = capture(3, match: match, in: value).flatMap(Int64.init),
            let fraction = capture(4, match: match, in: value),
            minutes < 60, seconds < 60
        else {
            throw AdvancedSubStationAlphaParseError.invalidTimestamp(line: line)
        }
        let hourMinutes = hours.multipliedReportingOverflow(by: 60)
        let totalMinutes = hourMinutes.partialValue.addingReportingOverflow(minutes)
        let totalSeconds = totalMinutes.partialValue.multipliedReportingOverflow(by: 60)
        let secondsWithRemainder = totalSeconds.partialValue.addingReportingOverflow(seconds)
        let wholeMilliseconds = secondsWithRemainder.partialValue.multipliedReportingOverflow(
            by: 1_000)
        let fractionMilliseconds =
            Int64(
                fraction.padding(toLength: 3, withPad: "0", startingAt: 0)
            ) ?? 0
        let totalMilliseconds = wholeMilliseconds.partialValue.addingReportingOverflow(
            fractionMilliseconds)
        guard !hourMinutes.overflow,
            !totalMinutes.overflow,
            !totalSeconds.overflow,
            !secondsWithRemainder.overflow,
            !wholeMilliseconds.overflow,
            !totalMilliseconds.overflow,
            totalMilliseconds.partialValue <= Int64.max / 1_000_000
        else {
            throw AdvancedSubStationAlphaParseError.invalidTimestamp(line: line)
        }
        return SubRipTimestamp(milliseconds: totalMilliseconds.partialValue)
    }

    private static func capture(
        _ index: Int,
        match: NSTextCheckingResult,
        in value: String
    ) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else {
            return nil
        }
        return String(value[swiftRange])
    }

    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"^(\d+):(\d{2}):(\d{2})[.](\d{1,3})$"#
    )
}

public struct AdvancedSubStationAlphaCleanupChange: Equatable, Identifiable, Sendable {
    public let id: Int
    public let reasons: Set<SubtitleCleanupReason>
    public let before: AdvancedSubStationAlphaEvent
    public let after: AdvancedSubStationAlphaEvent?

    public init(
        id: Int,
        reasons: Set<SubtitleCleanupReason>,
        before: AdvancedSubStationAlphaEvent,
        after: AdvancedSubStationAlphaEvent?
    ) {
        self.id = id
        self.reasons = reasons
        self.before = before
        self.after = after
    }
}

public struct AdvancedSubStationAlphaCleanupPreview: Equatable, Sendable {
    public let original: AdvancedSubStationAlphaDocument
    public let cleaned: AdvancedSubStationAlphaDocument
    public let changes: [AdvancedSubStationAlphaCleanupChange]

    public init(
        original: AdvancedSubStationAlphaDocument,
        cleaned: AdvancedSubStationAlphaDocument,
        changes: [AdvancedSubStationAlphaCleanupChange]
    ) {
        self.original = original
        self.cleaned = cleaned
        self.changes = changes
    }

    public func document(restoringEventIDs restored: Set<Int>) -> AdvancedSubStationAlphaDocument {
        let cleanedByID = Dictionary(uniqueKeysWithValues: cleaned.events.map { ($0.id, $0) })
        return AdvancedSubStationAlphaDocument(
            lines: original.lines.compactMap { line in
                guard case .dialogue(let event) = line else { return line }
                if restored.contains(event.id) { return line }
                return cleanedByID[event.id].map(AdvancedSubStationAlphaLine.dialogue)
            }
        )
    }
}

public struct AdvancedSubStationAlphaCleanupPolicy: Sendable {
    private let appliesEnglishOCRRules: Bool

    public init(appliesEnglishOCRRules: Bool = true) {
        self.appliesEnglishOCRRules = appliesEnglishOCRRules
    }

    public func preview(
        _ document: AdvancedSubStationAlphaDocument
    ) -> AdvancedSubStationAlphaCleanupPreview {
        var cleanedLines = [AdvancedSubStationAlphaLine]()
        var changes = [AdvancedSubStationAlphaCleanupChange]()
        let ocrPolicy = EnglishOCRCorrectionPolicy()
        for line in document.lines {
            guard case .dialogue(let event) = line else {
                cleanedLines.append(line)
                continue
            }
            if Self.isKnownAdvertisement(event.text) {
                changes.append(
                    AdvancedSubStationAlphaCleanupChange(
                        id: event.id,
                        reasons: [.ytsAdvertisement],
                        before: event,
                        after: nil
                    )
                )
                continue
            }
            var reasons = Set<SubtitleCleanupReason>()
            var normalizedText = event.text.trimmingCharacters(in: .whitespaces)
            if normalizedText != event.text {
                reasons.insert(.accidentalWhitespace)
            }
            if appliesEnglishOCRRules {
                let review = ocrPolicy.review(normalizedText)
                let automaticallyCorrected = review.automaticallyCorrectedText
                if automaticallyCorrected != normalizedText {
                    normalizedText = automaticallyCorrected
                    reasons.insert(.ocrHighConfidence)
                } else if reasons.isEmpty, review.fullySuggestedText != normalizedText {
                    normalizedText = review.fullySuggestedText
                    reasons.insert(.spellingSuggestion)
                }
            }
            let normalizedEvent = event.replacingText(normalizedText)
            cleanedLines.append(.dialogue(normalizedEvent))
            if !reasons.isEmpty {
                changes.append(
                    AdvancedSubStationAlphaCleanupChange(
                        id: event.id,
                        reasons: reasons,
                        before: event,
                        after: normalizedEvent
                    )
                )
            }
        }
        return AdvancedSubStationAlphaCleanupPreview(
            original: document,
            cleaned: AdvancedSubStationAlphaDocument(lines: cleanedLines),
            changes: changes
        )
    }

    private static func isKnownAdvertisement(_ rawText: String) -> Bool {
        let range = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        let withoutOverrides = overrideExpression.stringByReplacingMatches(
            in: rawText,
            range: range,
            withTemplate: ""
        )
        let text =
            withoutOverrides
            .replacingOccurrences(of: #"\N"#, with: " ")
            .replacingOccurrences(of: #"\n"#, with: " ")
            .replacingOccurrences(of: #"\h"#, with: " ")
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        let hasKnownDomain = ["yts.mx", "yts.lt", "yts.bz"].contains { text.contains($0) }
        guard hasKnownDomain else { return false }
        return text.contains("official yify movies site")
            || text.contains("downloaded from")
    }

    private static let overrideExpression = try! NSRegularExpression(pattern: #"\{[^}]*\}"#)
}
