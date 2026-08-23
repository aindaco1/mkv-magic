import Foundation

public enum ChapterSuggestionSignal: String, Codable, CaseIterable, Hashable, Sendable {
    case sceneChange
    case blackFrame
    case silence

    public var displayName: String {
        switch self {
        case .sceneChange: "Scene change"
        case .blackFrame: "Black frame"
        case .silence: "Silence"
        }
    }
}

public struct ChapterSuggestionDetection: Equatable, Hashable, Sendable {
    public let time: MediaTime
    public let signal: ChapterSuggestionSignal

    public init(time: MediaTime, signal: ChapterSuggestionSignal) {
        self.time = time
        self.signal = signal
    }
}

public struct ChapterSuggestion: Equatable, Hashable, Identifiable, Sendable {
    public let time: MediaTime
    public let signals: [ChapterSuggestionSignal]

    public init(time: MediaTime, signals: [ChapterSuggestionSignal]) {
        self.time = time
        self.signals = signals
    }

    public var id: String {
        "\(time.nanoseconds):\(signals.map(\.rawValue).joined(separator: ","))"
    }

    public var signalDescription: String {
        signals.map(\.displayName).joined(separator: " + ")
    }
}

public struct ChapterSuggestionOptions: Equatable, Sendable {
    public var detectsSceneChanges: Bool
    public var detectsBlackFrames: Bool
    public var detectsSilence: Bool
    public var sceneThreshold: Double
    public var blackMinimumDuration: MediaTime
    public var blackPictureThreshold: Double
    public var silenceNoiseDecibels: Double
    public var silenceMinimumDuration: MediaTime
    public var minimumSpacing: MediaTime
    public var mergeTolerance: MediaTime
    public var existingChapterTolerance: MediaTime
    public var edgeGuard: MediaTime
    public var maximumSuggestions: Int

    public init(
        detectsSceneChanges: Bool = true,
        detectsBlackFrames: Bool = true,
        detectsSilence: Bool = true,
        sceneThreshold: Double = 0.4,
        blackMinimumDuration: MediaTime = MediaTime(nanoseconds: 500_000_000),
        blackPictureThreshold: Double = 0.98,
        silenceNoiseDecibels: Double = -35,
        silenceMinimumDuration: MediaTime = MediaTime(nanoseconds: 500_000_000),
        minimumSpacing: MediaTime = MediaTime(nanoseconds: 60_000_000_000),
        mergeTolerance: MediaTime = MediaTime(nanoseconds: 1_000_000_000),
        existingChapterTolerance: MediaTime = MediaTime(nanoseconds: 1_000_000_000),
        edgeGuard: MediaTime = MediaTime(nanoseconds: 2_000_000_000),
        maximumSuggestions: Int = 500
    ) {
        self.detectsSceneChanges = detectsSceneChanges
        self.detectsBlackFrames = detectsBlackFrames
        self.detectsSilence = detectsSilence
        self.sceneThreshold = sceneThreshold
        self.blackMinimumDuration = blackMinimumDuration
        self.blackPictureThreshold = blackPictureThreshold
        self.silenceNoiseDecibels = silenceNoiseDecibels
        self.silenceMinimumDuration = silenceMinimumDuration
        self.minimumSpacing = minimumSpacing
        self.mergeTolerance = mergeTolerance
        self.existingChapterTolerance = existingChapterTolerance
        self.edgeGuard = edgeGuard
        self.maximumSuggestions = maximumSuggestions
    }

    public var hasEnabledDetector: Bool {
        detectsSceneChanges || detectsBlackFrames || detectsSilence
    }

    public func validated() throws -> Self {
        guard hasEnabledDetector,
            sceneThreshold.isFinite, (0.05...1).contains(sceneThreshold),
            blackPictureThreshold.isFinite, (0.5...1).contains(blackPictureThreshold),
            silenceNoiseDecibels.isFinite, (-100 ... -1).contains(silenceNoiseDecibels),
            blackMinimumDuration.nanoseconds >= 0,
            silenceMinimumDuration.nanoseconds >= 0,
            minimumSpacing.nanoseconds >= 0,
            mergeTolerance.nanoseconds >= 0,
            existingChapterTolerance.nanoseconds >= 0,
            edgeGuard.nanoseconds >= 0,
            (1...5_000).contains(maximumSuggestions)
        else {
            throw ChapterSuggestionError.invalidOptions
        }
        return self
    }
}

public enum ChapterSuggestionError: Error, Equatable, Sendable {
    case invalidOptions
    case invalidDuration
}

extension ChapterSuggestionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidOptions:
            "Choose at least one detector and use values within the supported ranges."
        case .invalidDuration:
            "A known positive media duration is required for chapter suggestions."
        }
    }
}

public enum ChapterSuggestionConsolidator {
    public static func consolidate(
        _ rawDetections: [ChapterSuggestionDetection],
        duration: MediaTime,
        existingChapterStarts: [MediaTime] = [],
        options rawOptions: ChapterSuggestionOptions = ChapterSuggestionOptions()
    ) throws -> [ChapterSuggestion] {
        let options = try rawOptions.validated()
        guard duration > .zero else { throw ChapterSuggestionError.invalidDuration }

        let upperBound = subtractClamped(duration.nanoseconds, options.edgeGuard.nanoseconds)
        let lowerBound = options.edgeGuard.nanoseconds
        let detections = Set(rawDetections).filter { detection in
            detection.time.nanoseconds >= lowerBound
                && detection.time.nanoseconds <= upperBound
                && detection.time > .zero
                && detection.time < duration
        }.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return priority(lhs.signal) < priority(rhs.signal)
        }

        var clusters = [[ChapterSuggestionDetection]]()
        for detection in detections {
            if let last = clusters.indices.last,
                let previous = clusters[last].last,
                distance(previous.time, detection.time) <= options.mergeTolerance.nanoseconds
            {
                clusters[last].append(detection)
            } else {
                clusters.append([detection])
            }
        }

        let existing = existingChapterStarts.filter { $0 >= .zero && $0 < duration }
        var suggestions = [ChapterSuggestion]()
        for cluster in clusters {
            guard let representative = cluster.min(by: detectionPreference) else { continue }
            let isNearExisting = existing.contains {
                distance($0, representative.time) <= options.existingChapterTolerance.nanoseconds
            }
            guard !isNearExisting else { continue }
            if let previous = suggestions.last,
                distance(previous.time, representative.time) < options.minimumSpacing.nanoseconds
            {
                continue
            }
            let signals = Array(Set(cluster.map(\.signal))).sorted { priority($0) < priority($1) }
            suggestions.append(ChapterSuggestion(time: representative.time, signals: signals))
            if suggestions.count == options.maximumSuggestions { break }
        }
        return suggestions
    }

    private static func detectionPreference(
        _ lhs: ChapterSuggestionDetection,
        _ rhs: ChapterSuggestionDetection
    ) -> Bool {
        let leftPriority = priority(lhs.signal)
        let rightPriority = priority(rhs.signal)
        if leftPriority != rightPriority { return leftPriority < rightPriority }
        return lhs.time < rhs.time
    }

    private static func priority(_ signal: ChapterSuggestionSignal) -> Int {
        switch signal {
        case .sceneChange: 0
        case .blackFrame: 1
        case .silence: 2
        }
    }

    private static func distance(_ lhs: MediaTime, _ rhs: MediaTime) -> Int64 {
        let difference = lhs.nanoseconds.subtractingReportingOverflow(rhs.nanoseconds)
        guard !difference.overflow else { return Int64.max }
        if difference.partialValue == Int64.min { return Int64.max }
        return Swift.abs(difference.partialValue)
    }

    private static func subtractClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let result = lhs.subtractingReportingOverflow(rhs)
        return result.overflow ? Int64.min : result.partialValue
    }
}

public struct ChapterSuggestionApplicationResult: Equatable, Sendable {
    public let document: MatroskaChapterDocument
    public let addedCount: Int
    public let skippedCount: Int
    public let firstAddedChapterID: UUID?

    public init(
        document: MatroskaChapterDocument,
        addedCount: Int,
        skippedCount: Int,
        firstAddedChapterID: UUID?
    ) {
        self.document = document
        self.addedCount = addedCount
        self.skippedCount = skippedCount
        self.firstAddedChapterID = firstAddedChapterID
    }
}

public enum ChapterSuggestionApplicationError: Error, Equatable, Sendable {
    case missingEdition
    case tooManySuggestions
}

extension ChapterSuggestionApplicationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingEdition: "The selected chapter edition is no longer available."
        case .tooManySuggestions: "Too many chapter suggestions were selected."
        }
    }
}

public enum ChapterSuggestionApplicator {
    public static func apply(
        _ suggestions: [ChapterSuggestion],
        to rawDocument: MatroskaChapterDocument,
        editionID requestedEditionID: UUID? = nil,
        mediaDuration: MediaTime?
    ) throws -> ChapterSuggestionApplicationResult {
        guard suggestions.count <= ChapterDocumentValidator.maximumChapters else {
            throw ChapterSuggestionApplicationError.tooManySuggestions
        }
        let original = try rawDocument.validated(mediaDuration: mediaDuration)
        guard !suggestions.isEmpty else {
            return ChapterSuggestionApplicationResult(
                document: original,
                addedCount: 0,
                skippedCount: 0,
                firstAddedChapterID: nil
            )
        }
        var document = original
        let editionID: UUID
        if document.editions.isEmpty {
            editionID = requestedEditionID ?? UUID()
            document.editions.append(
                MatroskaChapterEdition(id: editionID, isDefault: true, chapters: []))
        } else {
            editionID = requestedEditionID ?? document.editions[0].id
        }
        guard let editionIndex = document.editions.firstIndex(where: { $0.id == editionID }) else {
            throw ChapterSuggestionApplicationError.missingEdition
        }

        var addedCount = 0
        var skippedCount = 0
        var firstAddedChapterID: UUID?
        for suggestion in suggestions.sorted(by: suggestionOrder) {
            let targetChapters = document.editions[editionIndex].chapters
            if chapterStarts(in: document).contains(suggestion.time)
                || isInsideClosedRange(suggestion.time, chapters: targetChapters)
            {
                skippedCount += 1
                continue
            }
            let chapter = MatroskaChapterAtom(
                start: suggestion.time,
                displays: [
                    ChapterDisplay(title: "Chapter \(document.chapterCount + 1)", language: "en")
                ]
            )
            var candidate = document
            candidate.editions[editionIndex].chapters.append(chapter)
            candidate.editions[editionIndex].chapters.sort { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.uid < rhs.uid
            }
            do {
                document = try candidate.validated(mediaDuration: mediaDuration)
                firstAddedChapterID = firstAddedChapterID ?? chapter.id
                addedCount += 1
            } catch {
                skippedCount += 1
            }
        }
        let resultDocument = addedCount == 0 ? original : document
        return ChapterSuggestionApplicationResult(
            document: resultDocument,
            addedCount: addedCount,
            skippedCount: skippedCount,
            firstAddedChapterID: firstAddedChapterID
        )
    }

    private static func suggestionOrder(_ lhs: ChapterSuggestion, _ rhs: ChapterSuggestion) -> Bool
    {
        if lhs.time != rhs.time { return lhs.time < rhs.time }
        return lhs.id < rhs.id
    }

    private static func chapterStarts(in document: MatroskaChapterDocument) -> Set<MediaTime> {
        Set(document.editions.flatMap { chapterStarts(in: $0.chapters) })
    }

    private static func chapterStarts(in chapters: [MatroskaChapterAtom]) -> [MediaTime] {
        chapters.flatMap { [$0.start] + chapterStarts(in: $0.children) }
    }

    private static func isInsideClosedRange(
        _ time: MediaTime,
        chapters: [MatroskaChapterAtom]
    ) -> Bool {
        chapters.contains { chapter in
            if let end = chapter.end, time > chapter.start, time < end { return true }
            return isInsideClosedRange(time, chapters: chapter.children)
        }
    }
}
