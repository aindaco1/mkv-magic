import MKVMagicCore
import XCTest

final class MatroskaChapterTests: XCTestCase {
    func testMatroskaXMLRoundTripsNestedEditionsFlagsDisplaysAndNanoseconds() throws {
        let xml = Data(
            ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                + "<Chapters><EditionEntry><EditionUID>10</EditionUID>"
                + "<EditionFlagHidden>0</EditionFlagHidden>"
                + "<EditionFlagDefault>1</EditionFlagDefault>"
                + "<EditionFlagOrdered>0</EditionFlagOrdered>"
                + "<ChapterAtom><ChapterUID>100</ChapterUID>"
                + "<ChapterTimeStart>00:00:00.000000000</ChapterTimeStart>"
                + "<ChapterTimeEnd>00:05:00.123456789</ChapterTimeEnd>"
                + "<ChapterFlagHidden>0</ChapterFlagHidden>"
                + "<ChapterFlagEnabled>1</ChapterFlagEnabled>"
                + "<ChapterDisplay><ChapterString>Part &amp; One</ChapterString>"
                + "<ChapterLanguage>eng</ChapterLanguage>"
                + "<ChapLanguageIETF>en-US</ChapLanguageIETF>"
                + "<ChapterCountry>US</ChapterCountry></ChapterDisplay>"
                + "<ChapterAtom><ChapterUID>101</ChapterUID>"
                + "<ChapterTimeStart>00:00:10.000000001</ChapterTimeStart>"
                + "<ChapterDisplay><ChapterString>Opening</ChapterString>"
                + "<ChapterLanguage>eng</ChapterLanguage></ChapterDisplay>"
                + "</ChapterAtom></ChapterAtom></EditionEntry></Chapters>\n").utf8
        )
        let codec = MatroskaChapterXMLCodec()

        let document = try codec.parse(xml)
        let parent = try XCTUnwrap(document.editions.first?.chapters.first)
        XCTAssertEqual(document.chapterCount, 2)
        XCTAssertEqual(parent.primaryTitle, "Part & One")
        XCTAssertEqual(parent.displays.first?.language, "en-us")
        XCTAssertEqual(parent.displays.first?.country, "US")
        XCTAssertEqual(parent.end?.nanoseconds, 300_123_456_789)
        XCTAssertEqual(parent.children.first?.start.nanoseconds, 10_000_000_001)

        let serialized = try codec.serialize(document)
        XCTAssertTrue(String(decoding: serialized, as: UTF8.self).contains("Part &amp; One"))
        XCTAssertEqual(try codec.serialize(codec.parse(serialized)), serialized)
    }

    func testMatroskaXMLRejectsEntitiesUnsupportedMetadataAndDuplicateSingletons() throws {
        let codec = MatroskaChapterXMLCodec()
        XCTAssertNoThrow(
            try codec.parse(
                Data(
                    ("<?xml version=\"1.0\"?>\n"
                        + "<!DOCTYPE Chapters SYSTEM \"matroskachapters.dtd\">\n"
                        + "<Chapters/>").utf8
                )
            )
        )
        XCTAssertThrowsError(
            try codec.parse(
                Data(
                    "<!DOCTYPE Chapters [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><Chapters/>"
                        .utf8)
            )
        ) { error in
            XCTAssertEqual(error as? MatroskaChapterCodecError, .unsafeXML)
        }
        XCTAssertThrowsError(
            try codec.parse(
                Data(
                    ("<Chapters><EditionEntry><ChapterAtom>"
                        + "<ChapterTimeStart>00:00:00</ChapterTimeStart>"
                        + "<ChapterTrack/></ChapterAtom></EditionEntry></Chapters>").utf8)
            )
        ) { error in
            XCTAssertEqual(
                error as? MatroskaChapterCodecError,
                .unsupportedElement("ChapterTrack")
            )
        }
        XCTAssertThrowsError(
            try codec.parse(
                Data(
                    ("<Chapters><EditionEntry><EditionUID>1</EditionUID><EditionUID>2</EditionUID>"
                        + "</EditionEntry></Chapters>").utf8)
            )
        ) { error in
            XCTAssertEqual(
                error as? MatroskaChapterCodecError,
                .duplicateElement("EditionUID")
            )
        }
    }

    func testSimpleChapterTextImportsAndExportsOneFlatEdition() throws {
        let simple = Data(
            ("CHAPTER01=00:00:00.000\nCHAPTER01NAME=Opening\n"
                + "CHAPTER02=00:01:02.345\nCHAPTER02NAME=Second Act\n").utf8
        )
        let codec = SimpleChapterTextCodec()

        let document = try codec.parse(simple)
        let chapters = try XCTUnwrap(document.editions.first).chapters
        XCTAssertEqual(chapters.map(\.primaryTitle), ["Opening", "Second Act"])
        XCTAssertEqual(chapters.first?.end?.nanoseconds, 62_345_000_000)
        XCTAssertEqual(chapters.last?.end, nil)
        XCTAssertEqual(try codec.serialize(document), simple)

        let nested = MatroskaChapterDocument(
            editions: [
                MatroskaChapterEdition(
                    chapters: [
                        MatroskaChapterAtom(
                            start: .zero,
                            displays: [ChapterDisplay(title: "Parent")],
                            children: [
                                MatroskaChapterAtom(
                                    start: .zero,
                                    displays: [ChapterDisplay(title: "Child")]
                                )
                            ]
                        )
                    ]
                )
            ]
        )
        XCTAssertThrowsError(try codec.serialize(nested)) { error in
            XCTAssertEqual(
                error as? MatroskaChapterCodecError,
                .nestedSimpleExportUnsupported
            )
        }
    }

    func testChapterTimestampParsingIsExactAndRejectsOverflow() throws {
        XCTAssertEqual(
            try ChapterTimestamp.parse("12:34:56.123456789").nanoseconds,
            45_296_123_456_789
        )
        XCTAssertEqual(
            ChapterTimestamp.format(MediaTime(nanoseconds: 45_296_123_456_789)),
            "12:34:56.123456789"
        )
        XCTAssertThrowsError(try ChapterTimestamp.parse("00:60:00.000"))
        XCTAssertThrowsError(try ChapterTimestamp.parse("-1:00:00.000"))
        XCTAssertThrowsError(try ChapterTimestamp.parse("999999999999:00:00.000"))
    }

    func testValidatesNestedDefaultEditionAndPreservesMultipleDisplays() throws {
        let child = MatroskaChapterAtom(
            uid: 101,
            start: MediaTime(nanoseconds: 1_000_000_000),
            end: MediaTime(nanoseconds: 2_000_000_000),
            displays: [
                ChapterDisplay(title: "Opening", language: "en", country: "US"),
                ChapterDisplay(title: "Ouverture", language: "fr"),
            ]
        )
        let parent = MatroskaChapterAtom(
            uid: 100,
            start: .zero,
            end: MediaTime(nanoseconds: 5_000_000_000),
            displays: [ChapterDisplay(title: "Part 1", language: "eng")],
            children: [child]
        )
        let document = MatroskaChapterDocument(
            editions: [
                MatroskaChapterEdition(uid: 10, isDefault: true, chapters: [parent])
            ]
        )

        XCTAssertNoThrow(
            try document.validated(mediaDuration: MediaTime(nanoseconds: 5_000_000_000))
        )
        XCTAssertEqual(document.chapterCount, 2)
        XCTAssertEqual(try ChapterLanguage.canonical("ENG"), "en")
        XCTAssertEqual(ChapterLanguage.legacyCode(for: "fr-CA"), "fre")
    }

    func testRejectsDuplicateUIDInvalidMetadataOrderingAndEscapingParentRange() throws {
        XCTAssertThrowsError(
            try MatroskaChapterDocument(
                editions: [MatroskaChapterEdition(uid: 1, chapters: [])]
            ).validated()
        ) { error in
            XCTAssertEqual(error as? ChapterDocumentValidationError, .emptyEdition)
        }

        let invalidTitle = MatroskaChapterAtom(
            uid: 42,
            start: .zero,
            displays: [ChapterDisplay(title: "  ")]
        )
        XCTAssertThrowsError(
            try MatroskaChapterDocument(
                editions: [MatroskaChapterEdition(uid: 1, chapters: [invalidTitle])]
            ).validated()
        ) { error in
            XCTAssertEqual(error as? ChapterDocumentValidationError, .invalidTitle)
        }

        let duplicate = MatroskaChapterAtom(
            uid: 42,
            start: .zero,
            displays: [ChapterDisplay(title: "Chapter")]
        )
        XCTAssertThrowsError(
            try MatroskaChapterDocument(
                editions: [
                    MatroskaChapterEdition(uid: 1, chapters: [duplicate, duplicate])
                ]
            ).validated()
        ) { error in
            XCTAssertEqual(error as? ChapterDocumentValidationError, .duplicateUID)
        }

        let child = MatroskaChapterAtom(
            uid: 3,
            start: MediaTime(nanoseconds: 11),
            displays: [ChapterDisplay(title: "Outside")]
        )
        let parent = MatroskaChapterAtom(
            uid: 2,
            start: .zero,
            end: MediaTime(nanoseconds: 10),
            displays: [ChapterDisplay(title: "Parent")],
            children: [child]
        )
        XCTAssertThrowsError(
            try MatroskaChapterDocument(
                editions: [MatroskaChapterEdition(uid: 1, chapters: [parent])]
            ).validated()
        ) { error in
            XCTAssertEqual(error as? ChapterDocumentValidationError, .childOutsideParent)
        }

        let unboundedParent = MatroskaChapterAtom(
            uid: 4,
            start: MediaTime(nanoseconds: 10),
            displays: [ChapterDisplay(title: "Parent")],
            children: [
                MatroskaChapterAtom(
                    uid: 5,
                    start: MediaTime(nanoseconds: 9),
                    displays: [ChapterDisplay(title: "Before parent")]
                )
            ]
        )
        XCTAssertThrowsError(
            try MatroskaChapterDocument(
                editions: [MatroskaChapterEdition(uid: 2, chapters: [unboundedParent])]
            ).validated()
        ) { error in
            XCTAssertEqual(error as? ChapterDocumentValidationError, .childOutsideParent)
        }
        XCTAssertThrowsError(try ChapterLanguage.canonical("1"))
    }

    func testCreatesBoundedFixedIntervalChaptersWithEnglishDefaults() throws {
        let document = try MatroskaChapterDocument.fixedInterval(
            duration: MediaTime(nanoseconds: 155_000_000_000),
            interval: MediaTime(nanoseconds: 60_000_000_000)
        )
        let chapters = try XCTUnwrap(document.editions.first).chapters

        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters.map(\.primaryTitle), ["Chapter 01", "Chapter 02", "Chapter 03"])
        XCTAssertEqual(chapters.map(\.start.nanoseconds), [0, 60_000_000_000, 120_000_000_000])
        XCTAssertEqual(chapters.last?.end?.nanoseconds, 155_000_000_000)
        XCTAssertEqual(chapters.first?.displays.first?.language, "en")
    }

    func testImportsContainerNeutralHierarchyIntoOneStableMatroskaEdition() throws {
        let sourceID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let parentID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let childID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let inspected = [
            ChapterNode(
                id: parentID,
                title: "Part One",
                start: .zero,
                end: MediaTime(nanoseconds: 10_000_000_000),
                language: nil,
                children: [
                    ChapterNode(
                        id: childID,
                        title: "Opening",
                        start: MediaTime(nanoseconds: 1_000_000_000),
                        end: MediaTime(nanoseconds: 3_000_000_000),
                        language: "ENG"
                    )
                ]
            )
        ]

        let first = try MatroskaChapterDocument.importingInspectedChapters(
            inspected,
            sourceID: sourceID,
            mediaDuration: MediaTime(nanoseconds: 10_000_000_000)
        )
        let second = try MatroskaChapterDocument.importingInspectedChapters(
            inspected,
            sourceID: sourceID,
            mediaDuration: MediaTime(nanoseconds: 10_000_000_000)
        )
        let edition = try XCTUnwrap(first.editions.first)
        let parent = try XCTUnwrap(edition.chapters.first)
        let child = try XCTUnwrap(parent.children.first)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.chapterCount, 2)
        XCTAssertEqual(edition.id, sourceID)
        XCTAssertEqual(parent.id, parentID)
        XCTAssertEqual(child.id, childID)
        XCTAssertEqual(parent.displays.first?.language, "und")
        XCTAssertEqual(child.displays.first?.language, "en")
        XCTAssertEqual(
            try MatroskaChapterDocument.importingInspectedChapters(
                [],
                sourceID: sourceID,
                mediaDuration: MediaTime(nanoseconds: 10_000_000_000)
            ),
            MatroskaChapterDocument()
        )
    }

    func testJellyfinFlattenKeepsOnlyLeavesSortsAndRegeneratesUIDs() throws {
        let first = MatroskaChapterAtom(
            uid: 11,
            start: .zero,
            end: MediaTime(nanoseconds: 10),
            displays: [ChapterDisplay(title: "Chapter 01")]
        )
        let second = MatroskaChapterAtom(
            uid: 12,
            start: MediaTime(nanoseconds: 10),
            end: MediaTime(nanoseconds: 20),
            displays: [ChapterDisplay(title: "Chapter 02")]
        )
        let parent = MatroskaChapterAtom(
            uid: 10,
            start: .zero,
            end: MediaTime(nanoseconds: 20),
            displays: [ChapterDisplay(title: "Part 1")],
            children: [first, second]
        )
        let document = MatroskaChapterDocument(
            editions: [MatroskaChapterEdition(uid: 1, chapters: [parent])]
        )

        let flat = document.flattenedForJellyfin()
        let chapters = try XCTUnwrap(flat.editions.first).chapters
        XCTAssertEqual(chapters.map(\.primaryTitle), ["Chapter 01", "Chapter 02"])
        XCTAssertTrue(chapters.allSatisfy(\.children.isEmpty))
        XCTAssertFalse(Set(chapters.map(\.uid)).isSubset(of: [10, 11, 12]))
        XCTAssertNoThrow(try flat.validated())
    }
}
