import Foundation

public struct MediaTrimRange: Codable, Equatable, Hashable, Sendable {
    public let start: MediaTime
    public let end: MediaTime

    public init(start: MediaTime, end: MediaTime) {
        self.start = start
        self.end = end
    }

    public var duration: MediaTime {
        MediaTime(nanoseconds: end.nanoseconds - start.nanoseconds)
    }
}

public struct FastTrimPlan: Equatable, Sendable {
    public let requested: MediaTrimRange
    public let adjusted: MediaTrimRange

    public init(requested: MediaTrimRange, adjusted: MediaTrimRange) {
        self.requested = requested
        self.adjusted = adjusted
    }

    public var startWasAdjusted: Bool { requested.start != adjusted.start }
    public var endWasAdjusted: Bool { requested.end != adjusted.end }
}

public enum TrimPlanningError: Error, Equatable, Sendable {
    case invalidDuration
    case invalidRange
    case noChange
    case missingKeyframes
    case noEffectiveFastTrim
    case orderedChaptersUnsupported
    case timeOverflow
}

extension TrimPlanningError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidDuration: "Trimming needs a known positive media duration."
        case .invalidRange: "The trim in/out range must be positive and inside the media."
        case .noChange: "The requested range keeps the complete media file."
        case .missingKeyframes:
            "No suitable video keyframe exists after the requested trim boundary."
        case .noEffectiveFastTrim:
            "Keyframe alignment would keep the complete file; use Exact Trim instead."
        case .orderedChaptersUnsupported:
            "Ordered Matroska editions cannot be trimmed safely in this version."
        case .timeOverflow: "The trim range is too large to represent safely."
        }
    }
}

/// Resolves the boundaries that `mkvmerge --split parts:` will actually use.
/// MKVToolNix starts or ends a retained part at the first keyframe at or after
/// the requested timestamp. The physical end of the source is also a valid end.
public struct FastTrimPlanner: Sendable {
    public init() {}

    public func plan(
        requested: MediaTrimRange,
        sourceDuration: MediaTime,
        videoKeyframes: [MediaTime]
    ) throws -> FastTrimPlan {
        guard sourceDuration > .zero else { throw TrimPlanningError.invalidDuration }
        try validate(requested, sourceDuration: sourceDuration)
        guard requested.start != .zero || requested.end != sourceDuration else {
            throw TrimPlanningError.noChange
        }

        let keyframes = Array(
            Set(videoKeyframes.filter { $0 >= .zero && $0 <= sourceDuration })
        ).sorted()
        let adjustedStart: MediaTime
        if requested.start == .zero {
            adjustedStart = .zero
        } else {
            guard let keyframe = keyframes.first(where: { $0 >= requested.start }) else {
                throw TrimPlanningError.missingKeyframes
            }
            adjustedStart = keyframe
        }
        let adjustedEnd: MediaTime
        if requested.end == sourceDuration {
            adjustedEnd = sourceDuration
        } else {
            adjustedEnd = keyframes.first(where: { $0 >= requested.end }) ?? sourceDuration
        }
        guard adjustedEnd > adjustedStart else {
            throw TrimPlanningError.missingKeyframes
        }
        let adjusted = MediaTrimRange(start: adjustedStart, end: adjustedEnd)
        guard adjusted.start != .zero || adjusted.end != sourceDuration else {
            throw TrimPlanningError.noEffectiveFastTrim
        }
        return FastTrimPlan(requested: requested, adjusted: adjusted)
    }

    private func validate(_ range: MediaTrimRange, sourceDuration: MediaTime) throws {
        guard range.start >= .zero,
            range.end > range.start,
            range.end <= sourceDuration
        else {
            throw TrimPlanningError.invalidRange
        }
    }
}

/// Intersects every nested chapter with one retained source range and rebases
/// it to output time zero. Empty editions are removed and all retained UIDs are
/// regenerated for the new Matroska segment.
public struct MatroskaChapterTrimmer: Sendable {
    public init() {}

    public func trim(
        _ document: MatroskaChapterDocument,
        sourceDuration: MediaTime,
        retainedRange: MediaTrimRange
    ) throws -> MatroskaChapterDocument {
        guard sourceDuration > .zero else { throw TrimPlanningError.invalidDuration }
        guard retainedRange.start >= .zero,
            retainedRange.end > retainedRange.start,
            retainedRange.end <= sourceDuration
        else {
            throw TrimPlanningError.invalidRange
        }
        _ = try document.validated(mediaDuration: sourceDuration)
        guard !document.editions.contains(where: \.isOrdered) else {
            throw TrimPlanningError.orderedChaptersUnsupported
        }
        let outputDuration = try subtract(
            retainedRange.end.nanoseconds,
            retainedRange.start.nanoseconds
        )
        var editions = [MatroskaChapterEdition]()
        editions.reserveCapacity(document.editions.count)
        for edition in document.editions {
            let chapters = try transform(
                edition.chapters,
                parentEnd: sourceDuration.nanoseconds,
                retainedStart: retainedRange.start.nanoseconds,
                retainedEnd: retainedRange.end.nanoseconds
            )
            guard !chapters.isEmpty else { continue }
            editions.append(
                MatroskaChapterEdition(
                    isHidden: edition.isHidden,
                    isDefault: edition.isDefault,
                    isOrdered: false,
                    chapters: chapters
                )
            )
        }
        return try MatroskaChapterDocument(editions: editions).validated(
            mediaDuration: MediaTime(nanoseconds: outputDuration)
        )
    }

    private func transform(
        _ chapters: [MatroskaChapterAtom],
        parentEnd: Int64,
        retainedStart: Int64,
        retainedEnd: Int64
    ) throws -> [MatroskaChapterAtom] {
        var transformed = [MatroskaChapterAtom]()
        transformed.reserveCapacity(chapters.count)
        for (index, chapter) in chapters.enumerated() {
            let inferredEnd =
                chapter.end?.nanoseconds
                ?? (chapters.indices.contains(index + 1)
                    ? chapters[index + 1].start.nanoseconds
                    : parentEnd)
            let clippedStart = max(chapter.start.nanoseconds, retainedStart)
            let clippedEnd = min(inferredEnd, retainedEnd)
            guard clippedEnd > clippedStart else { continue }
            let rebasedStart = try subtract(clippedStart, retainedStart)
            let rebasedEnd = try subtract(clippedEnd, retainedStart)
            let children = try transform(
                chapter.children,
                parentEnd: inferredEnd,
                retainedStart: retainedStart,
                retainedEnd: retainedEnd
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

    private func subtract(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.subtractingReportingOverflow(rhs)
        guard !result.overflow else { throw TrimPlanningError.timeOverflow }
        return result.partialValue
    }
}
