import Foundation

public struct ChapterDisplay: Codable, Equatable, Hashable, Sendable {
    public var title: String
    public var language: String
    public var country: String?

    public init(title: String, language: String = "en", country: String? = nil) {
        self.title = title
        self.language = language
        self.country = country
    }
}

public struct MatroskaChapterAtom: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var uid: UInt64
    public var start: MediaTime
    public var end: MediaTime?
    public var isHidden: Bool
    public var isEnabled: Bool
    public var displays: [ChapterDisplay]
    public var children: [MatroskaChapterAtom]

    public init(
        id: UUID = UUID(),
        uid: UInt64? = nil,
        start: MediaTime,
        end: MediaTime? = nil,
        isHidden: Bool = false,
        isEnabled: Bool = true,
        displays: [ChapterDisplay],
        children: [MatroskaChapterAtom] = []
    ) {
        self.id = id
        self.uid = uid ?? ChapterUID.make(from: id)
        self.start = start
        self.end = end
        self.isHidden = isHidden
        self.isEnabled = isEnabled
        self.displays = displays
        self.children = children
    }

    public var primaryTitle: String {
        displays.first?.title ?? "Chapter"
    }

    public func regeneratingUIDs() -> MatroskaChapterAtom {
        let id = UUID()
        return MatroskaChapterAtom(
            id: id,
            uid: ChapterUID.make(from: id),
            start: start,
            end: end,
            isHidden: isHidden,
            isEnabled: isEnabled,
            displays: displays,
            children: children.map { $0.regeneratingUIDs() }
        )
    }
}

public struct MatroskaChapterEdition: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var uid: UInt64
    public var isHidden: Bool
    public var isDefault: Bool
    public var isOrdered: Bool
    public var chapters: [MatroskaChapterAtom]

    public init(
        id: UUID = UUID(),
        uid: UInt64? = nil,
        isHidden: Bool = false,
        isDefault: Bool = true,
        isOrdered: Bool = false,
        chapters: [MatroskaChapterAtom]
    ) {
        self.id = id
        self.uid = uid ?? ChapterUID.make(from: id)
        self.isHidden = isHidden
        self.isDefault = isDefault
        self.isOrdered = isOrdered
        self.chapters = chapters
    }
}

public struct MatroskaChapterDocument: Codable, Equatable, Hashable, Sendable {
    public var editions: [MatroskaChapterEdition]

    public init(editions: [MatroskaChapterEdition] = []) {
        self.editions = editions
    }

    public var chapterCount: Int {
        editions.reduce(0) { $0 + $1.chapters.recursiveCount }
    }

    public func validated(mediaDuration: MediaTime? = nil) throws -> Self {
        try ChapterDocumentValidator().validate(self, mediaDuration: mediaDuration)
        return self
    }

    public func flattenedForJellyfin() -> Self {
        let leaves = editions.flatMap { $0.chapters.leafAtoms }
            .sorted {
                if $0.start == $1.start { return $0.uid < $1.uid }
                return $0.start < $1.start
            }
        var seenStarts = Set<MediaTime>()
        let unique = leaves.compactMap { atom -> MatroskaChapterAtom? in
            guard seenStarts.insert(atom.start).inserted else { return nil }
            let regenerated = atom.regeneratingUIDs()
            return MatroskaChapterAtom(
                id: regenerated.id,
                uid: regenerated.uid,
                start: regenerated.start,
                end: regenerated.end,
                isHidden: regenerated.isHidden,
                isEnabled: regenerated.isEnabled,
                displays: regenerated.displays,
                children: []
            )
        }
        guard !unique.isEmpty else { return Self() }
        return Self(
            editions: [
                MatroskaChapterEdition(
                    isDefault: true,
                    chapters: unique
                )
            ]
        )
    }

    public static func fixedInterval(
        duration: MediaTime,
        interval: MediaTime,
        language: String = "en"
    ) throws -> Self {
        guard duration > .zero, interval > .zero else {
            throw ChapterDocumentValidationError.invalidSuggestionInterval
        }
        var chapters = [MatroskaChapterAtom]()
        var start = MediaTime.zero
        var ordinal = 1
        while start < duration {
            let proposedEnd = start.adding(interval)
            let end = min(proposedEnd ?? duration, duration)
            chapters.append(
                MatroskaChapterAtom(
                    start: start,
                    end: end,
                    displays: [
                        ChapterDisplay(
                            title: String(format: "Chapter %02d", ordinal),
                            language: language
                        )
                    ]
                )
            )
            guard end > start else {
                throw ChapterDocumentValidationError.invalidSuggestionInterval
            }
            start = end
            ordinal += 1
            guard chapters.count <= ChapterDocumentValidator.maximumChapters else {
                throw ChapterDocumentValidationError.tooManyChapters
            }
        }
        return try Self(
            editions: [MatroskaChapterEdition(isDefault: true, chapters: chapters)]
        ).validated(mediaDuration: duration)
    }
}

public enum ChapterDocumentValidationError: Error, Equatable, Sendable {
    case tooManyEditions
    case tooManyChapters
    case emptyEdition
    case nestingTooDeep
    case duplicateUID
    case invalidUID
    case multipleDefaultEditions
    case emptyDisplay
    case invalidTitle
    case invalidLanguage
    case invalidCountry
    case negativeStart
    case endBeforeStart
    case outsideMediaDuration
    case childOutsideParent
    case chaptersOutOfOrder
    case invalidSuggestionInterval
    case timeOverflow
}

extension ChapterDocumentValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .tooManyEditions: "The chapter document has too many editions."
        case .tooManyChapters: "The chapter document has too many chapter entries."
        case .emptyEdition: "Every chapter edition must contain at least one chapter."
        case .nestingTooDeep: "The chapter hierarchy is nested too deeply."
        case .duplicateUID: "Chapter and edition UIDs must be unique."
        case .invalidUID: "Chapter and edition UIDs must be nonzero."
        case .multipleDefaultEditions: "Only one chapter edition can be the default."
        case .emptyDisplay: "Every chapter needs at least one display name."
        case .invalidTitle: "Chapter names must be nonempty and no longer than 4,096 bytes."
        case .invalidLanguage: "Chapter language tags must be valid BCP 47 or ISO codes."
        case .invalidCountry: "Chapter countries must use a two-letter code."
        case .negativeStart: "Chapter start times cannot be negative."
        case .endBeforeStart: "A chapter end cannot be earlier than its start."
        case .outsideMediaDuration: "A chapter falls outside the media duration."
        case .childOutsideParent: "A nested chapter falls outside its parent."
        case .chaptersOutOfOrder: "Sibling chapters must be ordered by start time."
        case .invalidSuggestionInterval: "The chapter interval and duration must be positive."
        case .timeOverflow: "The chapter time is too large to represent safely."
        }
    }
}

public struct ChapterDocumentValidator: Sendable {
    public static let maximumEditions = 128
    public static let maximumChapters = 20_000
    public static let maximumDepth = 64
    public static let maximumTitleBytes = 4_096

    public init() {}

    public func validate(
        _ document: MatroskaChapterDocument,
        mediaDuration: MediaTime? = nil
    ) throws {
        guard document.editions.count <= Self.maximumEditions else {
            throw ChapterDocumentValidationError.tooManyEditions
        }
        guard document.chapterCount <= Self.maximumChapters else {
            throw ChapterDocumentValidationError.tooManyChapters
        }
        guard document.editions.filter(\.isDefault).count <= 1 else {
            throw ChapterDocumentValidationError.multipleDefaultEditions
        }
        var editionUIDs = Set<UInt64>()
        var chapterUIDs = Set<UInt64>()
        for edition in document.editions {
            guard !edition.chapters.isEmpty else {
                throw ChapterDocumentValidationError.emptyEdition
            }
            guard edition.uid != 0 else { throw ChapterDocumentValidationError.invalidUID }
            guard editionUIDs.insert(edition.uid).inserted else {
                throw ChapterDocumentValidationError.duplicateUID
            }
            try validate(
                edition.chapters,
                depth: 1,
                parentBounds: nil,
                mediaDuration: mediaDuration,
                chapterUIDs: &chapterUIDs
            )
        }
    }

    private func validate(
        _ chapters: [MatroskaChapterAtom],
        depth: Int,
        parentBounds: ChapterParentBounds?,
        mediaDuration: MediaTime?,
        chapterUIDs: inout Set<UInt64>
    ) throws {
        guard depth <= Self.maximumDepth else {
            throw ChapterDocumentValidationError.nestingTooDeep
        }
        var previousStart: MediaTime?
        for chapter in chapters {
            guard chapter.uid != 0 else { throw ChapterDocumentValidationError.invalidUID }
            guard chapterUIDs.insert(chapter.uid).inserted else {
                throw ChapterDocumentValidationError.duplicateUID
            }
            guard chapter.start >= .zero else {
                throw ChapterDocumentValidationError.negativeStart
            }
            if let previousStart, chapter.start < previousStart {
                throw ChapterDocumentValidationError.chaptersOutOfOrder
            }
            previousStart = chapter.start
            if let end = chapter.end, end < chapter.start {
                throw ChapterDocumentValidationError.endBeforeStart
            }
            if let mediaDuration,
                chapter.start > mediaDuration || (chapter.end.map { $0 > mediaDuration } ?? false)
            {
                throw ChapterDocumentValidationError.outsideMediaDuration
            }
            if let parentBounds {
                guard chapter.start >= parentBounds.start else {
                    throw ChapterDocumentValidationError.childOutsideParent
                }
                if let upperBound = parentBounds.end,
                    chapter.start > upperBound || (chapter.end.map { $0 > upperBound } ?? false)
                {
                    throw ChapterDocumentValidationError.childOutsideParent
                }
            }
            guard !chapter.displays.isEmpty else {
                throw ChapterDocumentValidationError.emptyDisplay
            }
            for display in chapter.displays {
                let title = display.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.utf8.count <= Self.maximumTitleBytes,
                    !title.contains("\0")
                else {
                    throw ChapterDocumentValidationError.invalidTitle
                }
                guard ChapterLanguage.isValid(display.language) else {
                    throw ChapterDocumentValidationError.invalidLanguage
                }
                if let country = display.country,
                    country.count != 2 || !country.allSatisfy({ $0.isASCII && $0.isLetter })
                {
                    throw ChapterDocumentValidationError.invalidCountry
                }
            }
            try validate(
                chapter.children,
                depth: depth + 1,
                parentBounds: ChapterParentBounds(start: chapter.start, end: chapter.end),
                mediaDuration: mediaDuration,
                chapterUIDs: &chapterUIDs
            )
        }
    }
}

public enum ChapterLanguage {
    public static func canonical(_ rawValue: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(value) else { throw ChapterDocumentValidationError.invalidLanguage }
        let lowercased = value.replacingOccurrences(of: "_", with: "-").lowercased()
        return legacyToModern[lowercased] ?? lowercased
    }

    public static func legacyCode(for rawValue: String) -> String {
        let canonical = (try? canonical(rawValue)) ?? "und"
        let primary = canonical.split(separator: "-").first.map(String.init) ?? canonical
        return modernToLegacy[primary] ?? (primary.count == 3 ? primary : "und")
    }

    fileprivate static func isValid(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 64 else { return false }
        let components = value.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", omittingEmptySubsequences: false)
        guard let primary = components.first,
            (2...8).contains(primary.count),
            primary.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return false }
        return components.dropFirst().allSatisfy { component in
            (1...8).contains(component.count)
                && component.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
    }

    private static let legacyToModern = [
        "eng": "en", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de",
        "spa": "es", "ita": "it", "por": "pt", "dut": "nl", "nld": "nl",
        "jpn": "ja", "chi": "zh", "zho": "zh", "kor": "ko", "rus": "ru",
        "und": "und",
    ]

    private static let modernToLegacy = [
        "en": "eng", "fr": "fre", "de": "ger", "es": "spa", "it": "ita",
        "pt": "por", "nl": "dut", "ja": "jpn", "zh": "chi", "ko": "kor",
        "ru": "rus", "und": "und",
    ]
}

private struct ChapterParentBounds {
    let start: MediaTime
    let end: MediaTime?
}

private enum ChapterUID {
    static func make(from id: UUID) -> UInt64 {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let value = bytes.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return value == 0 ? 1 : value
    }
}

extension MediaTime {
    fileprivate func adding(_ other: MediaTime) -> MediaTime? {
        let result = nanoseconds.addingReportingOverflow(other.nanoseconds)
        return result.overflow ? nil : MediaTime(nanoseconds: result.partialValue)
    }
}

extension Array where Element == MatroskaChapterAtom {
    fileprivate var recursiveCount: Int {
        reduce(0) { $0 + 1 + $1.children.recursiveCount }
    }

    fileprivate var leafAtoms: [MatroskaChapterAtom] {
        flatMap { atom in
            atom.children.isEmpty ? [atom] : atom.children.leafAtoms
        }
    }
}
