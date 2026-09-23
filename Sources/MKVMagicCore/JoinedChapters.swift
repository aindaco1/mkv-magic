import Foundation

public struct JoinedChapterSource: Equatable, Sendable {
    public let title: String?
    public let displayLanguage: String
    public let displayCountry: String?
    public let duration: MediaTime
    public let retainedStart: MediaTime
    public let retainedEnd: MediaTime
    public let selectedEditionChapters: [MatroskaChapterAtom]

    public init(
        title: String? = nil,
        displayLanguage: String = "en",
        displayCountry: String? = nil,
        duration: MediaTime,
        retainedStart: MediaTime,
        retainedEnd: MediaTime,
        selectedEditionChapters: [MatroskaChapterAtom]
    ) {
        self.title = title
        self.displayLanguage = displayLanguage
        self.displayCountry = displayCountry
        self.duration = duration
        self.retainedStart = retainedStart
        self.retainedEnd = retainedEnd
        self.selectedEditionChapters = selectedEditionChapters
    }
}

public struct JoinedChapterComposition: Equatable, Sendable {
    public let document: MatroskaChapterDocument
    public let duration: MediaTime

    public init(
        document: MatroskaChapterDocument,
        duration: MediaTime
    ) {
        self.document = document
        self.duration = duration
    }
}

public enum JoinedChapterCompositionError: Error, Equatable, Sendable {
    case emptySources
    case invalidSourceDuration
    case invalidRetainedRange
    case timeOverflow
}

extension JoinedChapterCompositionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptySources: "Add at least one source to the joined chapter timeline."
        case .invalidSourceDuration: "Every joined source needs a known positive duration."
        case .invalidRetainedRange:
            "Each retained range must be positive and contained by its source duration."
        case .timeOverflow: "The joined chapter timeline is too long to represent safely."
        }
    }
}

/// Builds one reviewed player-compatible edition for a hard-join timeline. Callers
/// choose the source edition explicitly so multiple-edition inputs are never silently
/// collapsed. Every retained source leaf becomes a top-level output chapter.
public struct JoinedChapterComposer: Sendable {
    public init() {}

    public func compose(_ sources: [JoinedChapterSource]) throws -> JoinedChapterComposition {
        guard !sources.isEmpty else { throw JoinedChapterCompositionError.emptySources }
        guard sources.count <= ChapterDocumentValidator.maximumChapters else {
            throw ChapterDocumentValidationError.tooManyChapters
        }

        var outputStart: Int64 = 0
        var outputChapterCount = 0
        var nextGenericChapterNumber = 1
        var parents = [MatroskaChapterAtom]()
        var sourceEndTimes = [MediaTime]()
        parents.reserveCapacity(sources.count)
        sourceEndTimes.reserveCapacity(sources.count)

        for (index, source) in sources.enumerated() {
            try validate(source)
            let retainedDuration = try subtract(
                source.retainedEnd.nanoseconds,
                source.retainedStart.nanoseconds
            )
            let outputEnd = try add(outputStart, retainedDuration)
            var children = try transform(
                source.selectedEditionChapters,
                parentEnd: source.duration.nanoseconds,
                retainedStart: source.retainedStart.nanoseconds,
                retainedEnd: source.retainedEnd.nanoseconds,
                outputStart: outputStart
            )
            if children.isEmpty {
                children = [
                    MatroskaChapterAtom(
                        start: MediaTime(nanoseconds: outputStart),
                        end: MediaTime(nanoseconds: outputEnd),
                        displays: [
                            ChapterDisplay(
                                title: String(
                                    format: "Chapter %02d", nextGenericChapterNumber),
                                language: try ChapterLanguage.canonical(source.displayLanguage),
                                country: source.displayCountry
                            )
                        ]
                    )
                ]
                nextGenericChapterNumber += 1
            } else {
                nextGenericChapterNumber += leafCount(in: children)
            }
            outputChapterCount += 1 + atomCount(in: children)
            guard outputChapterCount <= ChapterDocumentValidator.maximumChapters else {
                throw ChapterDocumentValidationError.tooManyChapters
            }

            parents.append(
                MatroskaChapterAtom(
                    start: MediaTime(nanoseconds: outputStart),
                    end: MediaTime(nanoseconds: outputEnd),
                    displays: [
                        ChapterDisplay(
                            title: partTitle(index: index, sourceTitle: source.title),
                            language: try ChapterLanguage.canonical(source.displayLanguage),
                            country: source.displayCountry
                        )
                    ],
                    children: children
                )
            )
            outputStart = outputEnd
            sourceEndTimes.append(MediaTime(nanoseconds: outputEnd))
        }

        let duration = MediaTime(nanoseconds: outputStart)
        let nestedDocument = MatroskaChapterDocument(
            editions: [MatroskaChapterEdition(isDefault: true, chapters: parents)]
        )
        let document = JoinedChapterNumberingPolicy.renumberRepeatedSequences(
            in: nestedDocument.flattenedForPlayerCompatibility(),
            sourceEndTimes: sourceEndTimes
        )
        return JoinedChapterComposition(
            document: try document.validated(mediaDuration: duration),
            duration: duration
        )
    }

    private func validate(_ source: JoinedChapterSource) throws {
        guard source.duration > .zero else {
            throw JoinedChapterCompositionError.invalidSourceDuration
        }
        guard source.retainedStart >= .zero,
            source.retainedEnd > source.retainedStart,
            source.retainedEnd <= source.duration
        else {
            throw JoinedChapterCompositionError.invalidRetainedRange
        }
        _ = try ChapterLanguage.canonical(source.displayLanguage)
        if !source.selectedEditionChapters.isEmpty {
            _ = try MatroskaChapterDocument(
                editions: [
                    MatroskaChapterEdition(
                        isDefault: true,
                        chapters: source.selectedEditionChapters
                    )
                ]
            ).validated(mediaDuration: source.duration)
        }
    }

    private func transform(
        _ chapters: [MatroskaChapterAtom],
        parentEnd: Int64,
        retainedStart: Int64,
        retainedEnd: Int64,
        outputStart: Int64
    ) throws -> [MatroskaChapterAtom] {
        var transformed = [MatroskaChapterAtom]()
        transformed.reserveCapacity(chapters.count)
        for index in chapters.indices {
            let chapter = chapters[index]
            let inferredEnd =
                chapter.end?.nanoseconds
                ?? (chapters.indices.contains(index + 1)
                    ? chapters[index + 1].start.nanoseconds : parentEnd)
            guard inferredEnd > retainedStart, chapter.start.nanoseconds < retainedEnd else {
                continue
            }
            let clippedStart = max(chapter.start.nanoseconds, retainedStart)
            let clippedEnd = min(inferredEnd, retainedEnd)
            guard clippedEnd >= clippedStart else { continue }
            let rebasedStart = try add(
                outputStart,
                try subtract(clippedStart, retainedStart)
            )
            let rebasedEnd = try add(
                outputStart,
                try subtract(clippedEnd, retainedStart)
            )
            let children = try transform(
                chapter.children,
                parentEnd: inferredEnd,
                retainedStart: retainedStart,
                retainedEnd: retainedEnd,
                outputStart: outputStart
            )
            transformed.append(
                MatroskaChapterAtom(
                    start: MediaTime(nanoseconds: rebasedStart),
                    end: MediaTime(nanoseconds: rebasedEnd),
                    isHidden: chapter.isHidden,
                    isEnabled: chapter.isEnabled,
                    displays: chapter.displays,
                    children: children
                )
            )
        }
        return transformed
    }

    private func partTitle(index: Int, sourceTitle: String?) -> String {
        let part = "Part \(index + 1)"
        guard let sourceTitle else { return part }
        let title = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? part : "\(part) — \(title)"
    }

    private func leafCount(in chapters: [MatroskaChapterAtom]) -> Int {
        chapters.reduce(0) { count, chapter in
            count + (chapter.children.isEmpty ? 1 : leafCount(in: chapter.children))
        }
    }

    private func atomCount(in chapters: [MatroskaChapterAtom]) -> Int {
        chapters.reduce(0) { $0 + 1 + atomCount(in: $1.children) }
    }

    private func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw JoinedChapterCompositionError.timeOverflow }
        return result.partialValue
    }

    private func subtract(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.subtractingReportingOverflow(rhs)
        guard !result.overflow else { throw JoinedChapterCompositionError.timeOverflow }
        return result.partialValue
    }
}

private enum JoinedChapterNumberingPolicy {
    static func renumberRepeatedSequences(
        in document: MatroskaChapterDocument,
        sourceEndTimes: [MediaTime]
    ) -> MatroskaChapterDocument {
        guard sourceEndTimes.count >= 2,
            document.editions.count == 1,
            !document.editions[0].chapters.isEmpty
        else { return document }

        let chapters = document.editions[0].chapters
        var grouped = Array(repeating: [Int](), count: sourceEndTimes.count)
        var sourceIndex = 0
        for index in chapters.indices {
            while sourceIndex < sourceEndTimes.count,
                chapters[index].start >= sourceEndTimes[sourceIndex]
            {
                sourceIndex += 1
            }
            guard sourceIndex < grouped.count else { return document }
            grouped[sourceIndex].append(index)
        }
        guard grouped.allSatisfy({ !$0.isEmpty }) else { return document }

        let parsed = chapters.map { NumberedChapterTitle.parse($0.primaryTitle) }
        guard parsed.allSatisfy({ $0 != nil }) else { return document }
        let titles = parsed.compactMap { $0 }
        guard let first = titles.first,
            titles.allSatisfy({ $0.normalizedPrefix == first.normalizedPrefix }),
            grouped.allSatisfy({ indicesAreConsecutive($0, titles: titles) })
        else { return document }

        var expected = first.value
        let alreadyGlobal = titles.allSatisfy { title in
            guard title.value == expected else { return false }
            let (next, overflow) = expected.addingReportingOverflow(1)
            guard !overflow else { return false }
            expected = next
            return true
        }
        guard !alreadyGlobal else { return document }

        var renumbered = document
        expected = first.value
        for index in renumbered.editions[0].chapters.indices {
            let originalNumber = titles[index].value
            renumbered.editions[0].chapters[index].displays =
                renumbered.editions[0].chapters[index].displays.map { display in
                    guard let parsedDisplay = NumberedChapterTitle.parse(display.title),
                        parsedDisplay.value == originalNumber
                    else { return display }
                    var changed = display
                    changed.title = parsedDisplay.replacingNumber(with: expected)
                    return changed
                }
            let (next, overflow) = expected.addingReportingOverflow(1)
            guard !overflow else { return document }
            expected = next
        }
        return renumbered
    }

    private static func indicesAreConsecutive(
        _ indices: [Int],
        titles: [NumberedChapterTitle]
    ) -> Bool {
        guard let firstIndex = indices.first else { return false }
        var expected = titles[firstIndex].value
        for index in indices {
            guard titles[index].value == expected else { return false }
            let (next, overflow) = expected.addingReportingOverflow(1)
            guard !overflow else { return false }
            expected = next
        }
        return true
    }
}

private struct NumberedChapterTitle {
    let title: String
    let numberRange: Range<String.Index>
    let value: Int
    let width: Int
    let normalizedPrefix: String

    static func parse(_ title: String) -> Self? {
        var ranges = [Range<String.Index>]()
        var runStart: String.Index?
        var index = title.startIndex
        while index < title.endIndex {
            let isASCIIDigit = title[index].isASCII && title[index].isNumber
            if isASCIIDigit, runStart == nil {
                runStart = index
            } else if !isASCIIDigit, let digitStart = runStart {
                ranges.append(digitStart..<index)
                runStart = nil
            }
            index = title.index(after: index)
        }
        if let digitStart = runStart { ranges.append(digitStart..<title.endIndex) }
        guard ranges.count == 1, let numberRange = ranges.first,
            title[numberRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
            let value = Int(title[numberRange])
        else { return nil }
        let prefix = title[..<numberRange.lowerBound]
        let normalizedPrefix = prefix.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        return Self(
            title: title,
            numberRange: numberRange,
            value: value,
            width: title.distance(from: numberRange.lowerBound, to: numberRange.upperBound),
            normalizedPrefix: normalizedPrefix
        )
    }

    func replacingNumber(with replacement: Int) -> String {
        let digits = String(format: "%0*d", width, replacement)
        return String(title[..<numberRange.lowerBound]) + digits
            + String(title[numberRange.upperBound...])
    }
}
