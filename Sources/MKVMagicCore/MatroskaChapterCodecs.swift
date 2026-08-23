import Foundation

public enum MatroskaChapterCodecError: Error, Equatable, Sendable {
    case oversizedInput
    case unsafeXML
    case malformedXML
    case unexpectedRoot
    case unsupportedElement(String)
    case duplicateElement(String)
    case missingElement(String)
    case invalidInteger(String)
    case invalidFlag(String)
    case invalidTimestamp(String)
    case invalidSimpleChapterLine(Int)
    case incompleteSimpleChapter(Int)
    case nestedSimpleExportUnsupported
}

extension MatroskaChapterCodecError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .oversizedInput: "The chapter document is larger than 16 MiB."
        case .unsafeXML: "The chapter XML contains a forbidden declaration or entity."
        case .malformedXML: "The chapter XML is malformed."
        case .unexpectedRoot: "The chapter XML must use a Chapters root element."
        case .unsupportedElement(let name): "The chapter XML contains unsupported element \(name)."
        case .duplicateElement(let name): "The chapter XML repeats singleton element \(name)."
        case .missingElement(let name): "The chapter XML is missing required element \(name)."
        case .invalidInteger(let name): "The chapter XML contains an invalid integer in \(name)."
        case .invalidFlag(let name): "The chapter XML contains an invalid flag in \(name)."
        case .invalidTimestamp(let value): "The chapter timestamp \(value) is invalid."
        case .invalidSimpleChapterLine(let line):
            "The simple chapter file has an invalid line at \(line)."
        case .incompleteSimpleChapter(let number):
            "The simple chapter file is missing chapter \(number)'s time or name."
        case .nestedSimpleExportUnsupported:
            "Simple chapter text supports one flat edition. Flatten or export Matroska XML."
        }
    }
}

public struct MatroskaChapterXMLCodec: Sendable {
    public static let maximumInputBytes = 16_777_216

    public init() {}

    public func parse(_ data: Data) throws -> MatroskaChapterDocument {
        guard data.count <= Self.maximumInputBytes else {
            throw MatroskaChapterCodecError.oversizedInput
        }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw MatroskaChapterCodecError.malformedXML
        }
        var sanitizedText = text
        for allowedDeclaration in [
            "<!DOCTYPE Chapters SYSTEM \"matroskachapters.dtd\">",
            "<!DOCTYPE Chapters SYSTEM 'matroskachapters.dtd'>",
        ] {
            sanitizedText = sanitizedText.replacingOccurrences(of: allowedDeclaration, with: "")
        }
        let lowercase = sanitizedText.lowercased()
        guard !lowercase.contains("<!doctype"), !lowercase.contains("<!entity") else {
            throw MatroskaChapterCodecError.unsafeXML
        }

        let xml: XMLDocument
        do {
            xml = try XMLDocument(
                data: Data(sanitizedText.utf8),
                options: [.nodeLoadExternalEntitiesNever]
            )
        } catch {
            throw MatroskaChapterCodecError.malformedXML
        }
        guard let root = xml.rootElement(), root.name == "Chapters" else {
            throw MatroskaChapterCodecError.unexpectedRoot
        }
        let editions = try root.elementChildren.map { element in
            guard element.name == "EditionEntry" else {
                throw MatroskaChapterCodecError.unsupportedElement(element.name ?? "unknown")
            }
            return try edition(element)
        }
        return try MatroskaChapterDocument(editions: editions).validated()
    }

    public func serialize(_ document: MatroskaChapterDocument) throws -> Data {
        _ = try document.validated()
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<Chapters>"]
        for edition in document.editions {
            lines.append("  <EditionEntry>")
            lines.append("    <EditionUID>\(edition.uid)</EditionUID>")
            lines.append("    <EditionFlagHidden>\(edition.isHidden.xmlFlag)</EditionFlagHidden>")
            lines.append(
                "    <EditionFlagDefault>\(edition.isDefault.xmlFlag)</EditionFlagDefault>")
            lines.append(
                "    <EditionFlagOrdered>\(edition.isOrdered.xmlFlag)</EditionFlagOrdered>")
            for chapter in edition.chapters {
                append(chapter, depth: 2, to: &lines)
            }
            lines.append("  </EditionEntry>")
        }
        lines.append("</Chapters>")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private func edition(_ element: XMLElement) throws -> MatroskaChapterEdition {
        try rejectUnsupportedChildren(
            element,
            allowed: [
                "EditionUID", "EditionFlagHidden", "EditionFlagDefault", "EditionFlagOrdered",
                "ChapterAtom",
            ]
        )
        let id = UUID()
        let uid = try optionalUInt64(element, named: "EditionUID")
        let chapters = try element.elementChildren.filter { $0.name == "ChapterAtom" }.map(atom)
        return MatroskaChapterEdition(
            id: id,
            uid: uid,
            isHidden: try flag(element, named: "EditionFlagHidden", default: false),
            isDefault: try flag(element, named: "EditionFlagDefault", default: false),
            isOrdered: try flag(element, named: "EditionFlagOrdered", default: false),
            chapters: chapters
        )
    }

    private func atom(_ element: XMLElement) throws -> MatroskaChapterAtom {
        try rejectUnsupportedChildren(
            element,
            allowed: [
                "ChapterUID", "ChapterTimeStart", "ChapterTimeEnd", "ChapterFlagHidden",
                "ChapterFlagEnabled", "ChapterDisplay", "ChapterAtom",
            ]
        )
        guard let rawStart = try optionalScalar(element, named: "ChapterTimeStart") else {
            throw MatroskaChapterCodecError.missingElement("ChapterTimeStart")
        }
        let id = UUID()
        return MatroskaChapterAtom(
            id: id,
            uid: try optionalUInt64(element, named: "ChapterUID"),
            start: try ChapterTimestamp.parse(rawStart),
            end: try optionalScalar(element, named: "ChapterTimeEnd").map(ChapterTimestamp.parse),
            isHidden: try flag(element, named: "ChapterFlagHidden", default: false),
            isEnabled: try flag(element, named: "ChapterFlagEnabled", default: true),
            displays: try element.elementChildren.filter { $0.name == "ChapterDisplay" }.map(
                display),
            children: try element.elementChildren.filter { $0.name == "ChapterAtom" }.map(atom)
        )
    }

    private func display(_ element: XMLElement) throws -> ChapterDisplay {
        try rejectUnsupportedChildren(
            element,
            allowed: ["ChapterString", "ChapterLanguage", "ChapLanguageIETF", "ChapterCountry"]
        )
        guard let title = try optionalScalar(element, named: "ChapterString") else {
            throw MatroskaChapterCodecError.missingElement("ChapterString")
        }
        let language =
            try optionalScalar(element, named: "ChapLanguageIETF")
            ?? optionalScalar(element, named: "ChapterLanguage")
            ?? "und"
        return ChapterDisplay(
            title: title,
            language: try ChapterLanguage.canonical(language),
            country: try optionalScalar(element, named: "ChapterCountry")?.uppercased()
        )
    }

    private func rejectUnsupportedChildren(_ element: XMLElement, allowed: Set<String>) throws {
        for child in element.elementChildren {
            guard let name = child.name, allowed.contains(name) else {
                throw MatroskaChapterCodecError.unsupportedElement(child.name ?? "unknown")
            }
        }
    }

    private func optionalScalar(_ element: XMLElement, named name: String) throws -> String? {
        let matches = element.elementChildren.filter { $0.name == name }
        guard matches.count <= 1 else {
            throw MatroskaChapterCodecError.duplicateElement(name)
        }
        guard let match = matches.first else { return nil }
        guard match.elementChildren.isEmpty, let value = match.stringValue else {
            throw MatroskaChapterCodecError.malformedXML
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optionalUInt64(_ element: XMLElement, named name: String) throws -> UInt64? {
        guard let value = try optionalScalar(element, named: name) else { return nil }
        guard let parsed = UInt64(value), parsed != 0 else {
            throw MatroskaChapterCodecError.invalidInteger(name)
        }
        return parsed
    }

    private func flag(_ element: XMLElement, named name: String, default defaultValue: Bool) throws
        -> Bool
    {
        guard let value = try optionalScalar(element, named: name) else { return defaultValue }
        switch value {
        case "0": return false
        case "1": return true
        default: throw MatroskaChapterCodecError.invalidFlag(name)
        }
    }

    private func append(_ chapter: MatroskaChapterAtom, depth: Int, to lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        let childIndent = indent + "  "
        lines.append("\(indent)<ChapterAtom>")
        lines.append("\(childIndent)<ChapterUID>\(chapter.uid)</ChapterUID>")
        lines.append(
            "\(childIndent)<ChapterTimeStart>\(ChapterTimestamp.format(chapter.start))</ChapterTimeStart>"
        )
        if let end = chapter.end {
            lines.append(
                "\(childIndent)<ChapterTimeEnd>\(ChapterTimestamp.format(end))</ChapterTimeEnd>"
            )
        }
        lines.append(
            "\(childIndent)<ChapterFlagHidden>\(chapter.isHidden.xmlFlag)</ChapterFlagHidden>"
        )
        lines.append(
            "\(childIndent)<ChapterFlagEnabled>\(chapter.isEnabled.xmlFlag)</ChapterFlagEnabled>"
        )
        for display in chapter.displays {
            lines.append("\(childIndent)<ChapterDisplay>")
            lines.append(
                "\(childIndent)  <ChapterString>\(display.title.xmlEscaped)</ChapterString>"
            )
            lines.append(
                "\(childIndent)  <ChapterLanguage>\(ChapterLanguage.legacyCode(for: display.language))</ChapterLanguage>"
            )
            let ietf = (try? ChapterLanguage.canonical(display.language)) ?? "und"
            lines.append(
                "\(childIndent)  <ChapLanguageIETF>\(ietf.xmlEscaped)</ChapLanguageIETF>"
            )
            if let country = display.country {
                lines.append(
                    "\(childIndent)  <ChapterCountry>\(country.uppercased().xmlEscaped)</ChapterCountry>"
                )
            }
            lines.append("\(childIndent)</ChapterDisplay>")
        }
        for child in chapter.children {
            append(child, depth: depth + 1, to: &lines)
        }
        lines.append("\(indent)</ChapterAtom>")
    }
}

public struct SimpleChapterTextCodec: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> MatroskaChapterDocument {
        guard data.count <= MatroskaChapterXMLCodec.maximumInputBytes else {
            throw MatroskaChapterCodecError.oversizedInput
        }
        let decoded = try SubtitleTextDecoder().decode(data)
        var entries = [Int: (time: String?, name: String?)]()
        for (offset, rawLine) in decoded.text.split(
            separator: "\n", omittingEmptySubsequences: true
        ).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("CHAPTER"), let equals = line.firstIndex(of: "=") else {
                throw MatroskaChapterCodecError.invalidSimpleChapterLine(lineNumber)
            }
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
            let isName = key.hasSuffix("NAME")
            let numberText = key.dropFirst("CHAPTER".count).dropLast(isName ? 4 : 0)
            guard let number = Int(numberText), number > 0 else {
                throw MatroskaChapterCodecError.invalidSimpleChapterLine(lineNumber)
            }
            var entry = entries[number] ?? (nil, nil)
            if isName {
                guard entry.name == nil else {
                    throw MatroskaChapterCodecError.invalidSimpleChapterLine(lineNumber)
                }
                entry.name = value
            } else {
                guard entry.time == nil else {
                    throw MatroskaChapterCodecError.invalidSimpleChapterLine(lineNumber)
                }
                entry.time = value
            }
            entries[number] = entry
        }
        guard !entries.isEmpty else { throw MatroskaChapterCodecError.malformedXML }
        let orderedNumbers = entries.keys.sorted()
        guard orderedNumbers == Array(1...entries.count) else {
            throw MatroskaChapterCodecError.invalidSimpleChapterLine(1)
        }
        var chapters = [MatroskaChapterAtom]()
        for number in orderedNumbers {
            guard let entry = entries[number], let time = entry.time, let name = entry.name else {
                throw MatroskaChapterCodecError.incompleteSimpleChapter(number)
            }
            chapters.append(
                MatroskaChapterAtom(
                    start: try ChapterTimestamp.parse(time),
                    displays: [ChapterDisplay(title: name, language: "en")]
                )
            )
        }
        for index in chapters.indices.dropLast() {
            chapters[index].end = chapters[index + 1].start
        }
        return try MatroskaChapterDocument(
            editions: [MatroskaChapterEdition(isDefault: true, chapters: chapters)]
        ).validated()
    }

    public func serialize(_ document: MatroskaChapterDocument) throws -> Data {
        _ = try document.validated()
        guard document.editions.count == 1,
            let edition = document.editions.first,
            edition.chapters.allSatisfy(\.children.isEmpty)
        else {
            throw MatroskaChapterCodecError.nestedSimpleExportUnsupported
        }
        var lines = [String]()
        for (offset, chapter) in edition.chapters.enumerated() {
            let number = String(format: "%02d", offset + 1)
            lines.append("CHAPTER\(number)=\(ChapterTimestamp.format(chapter.start, digits: 3))")
            lines.append("CHAPTER\(number)NAME=\(chapter.primaryTitle)")
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}

public enum ChapterTimestamp {
    public static func parse(_ rawValue: String) throws -> MediaTime {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
            let hours = Int64(parts[0]),
            hours >= 0,
            let minutes = Int64(parts[1]),
            minutes >= 0, minutes < 60
        else {
            throw MatroskaChapterCodecError.invalidTimestamp(rawValue)
        }
        let secondParts = parts[2].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(secondParts.count),
            let seconds = Int64(secondParts[0]),
            seconds >= 0, seconds < 60
        else {
            throw MatroskaChapterCodecError.invalidTimestamp(rawValue)
        }
        let fraction: Int64
        if secondParts.count == 2 {
            let digits = secondParts[1]
            guard !digits.isEmpty, digits.count <= 9,
                digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                let parsed = Int64(digits)
            else {
                throw MatroskaChapterCodecError.invalidTimestamp(rawValue)
            }
            let scale = Self.powerOfTen(9 - digits.count)
            let result = parsed.multipliedReportingOverflow(by: scale)
            guard !result.overflow else {
                throw MatroskaChapterCodecError.invalidTimestamp(rawValue)
            }
            fraction = result.partialValue
        } else {
            fraction = 0
        }
        let hourSeconds = hours.multipliedReportingOverflow(by: 3_600)
        let minuteSeconds = minutes.multipliedReportingOverflow(by: 60)
        let combinedMinutes = hourSeconds.partialValue.addingReportingOverflow(
            minuteSeconds.partialValue)
        let combinedSeconds = combinedMinutes.partialValue.addingReportingOverflow(seconds)
        let wholeNanoseconds = combinedSeconds.partialValue.multipliedReportingOverflow(
            by: 1_000_000_000)
        let result = wholeNanoseconds.partialValue.addingReportingOverflow(fraction)
        guard !hourSeconds.overflow, !minuteSeconds.overflow, !combinedMinutes.overflow,
            !combinedSeconds.overflow, !wholeNanoseconds.overflow, !result.overflow
        else {
            throw ChapterDocumentValidationError.timeOverflow
        }
        return MediaTime(nanoseconds: result.partialValue)
    }

    public static func format(_ time: MediaTime, digits: Int = 9) -> String {
        let safeDigits = min(max(digits, 0), 9)
        let nanoseconds = max(time.nanoseconds, 0)
        let totalSeconds = nanoseconds / 1_000_000_000
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        let fraction = nanoseconds % 1_000_000_000
        let fractionText = String(format: "%09lld", fraction).prefix(safeDigits)
        let base = String(format: "%02lld:%02lld:%02lld", hours, minutes, seconds)
        return safeDigits == 0 ? base : "\(base).\(fractionText)"
    }

    private static func powerOfTen(_ exponent: Int) -> Int64 {
        (0..<exponent).reduce(Int64(1)) { value, _ in value * 10 }
    }
}

extension Bool {
    fileprivate var xmlFlag: Int { self ? 1 : 0 }
}

extension String {
    fileprivate var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

extension XMLElement {
    fileprivate var elementChildren: [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }
    }
}
