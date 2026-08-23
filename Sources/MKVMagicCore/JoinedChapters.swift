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

    public init(document: MatroskaChapterDocument, duration: MediaTime) {
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

/// Builds one nested default edition for a hard-join timeline. Callers choose the
/// source edition explicitly so multiple-edition inputs are never silently collapsed.
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
        parents.reserveCapacity(sources.count)

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
        }

        let duration = MediaTime(nanoseconds: outputStart)
        let document = try MatroskaChapterDocument(
            editions: [MatroskaChapterEdition(isDefault: true, chapters: parents)]
        ).validated(mediaDuration: duration)
        return JoinedChapterComposition(document: document, duration: duration)
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
