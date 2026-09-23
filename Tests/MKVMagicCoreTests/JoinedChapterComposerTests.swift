import MKVMagicCore
import XCTest

final class JoinedChapterComposerTests: XCTestCase {
    func testComposesTrimmedNestedSourcesIntoOneFlatGlobalTimeline() throws {
        let originalUIDs: Set<UInt64> = [10, 11, 12, 13, 20]
        let firstSourceChapters = [
            atom(uid: 10, title: "Opening", start: 0, end: 30),
            atom(
                uid: 11,
                title: "Main",
                start: 30,
                end: 80,
                children: [
                    atom(uid: 12, title: "Scene A", start: 35, end: 45),
                    atom(uid: 13, title: "Scene B", start: 65, end: 80),
                ]
            ),
            atom(uid: 20, title: "Credits", start: 80, end: 100),
        ]
        let result = try JoinedChapterComposer().compose([
            JoinedChapterSource(
                title: "Episode One",
                duration: seconds(100),
                retainedStart: seconds(20),
                retainedEnd: seconds(80),
                selectedEditionChapters: firstSourceChapters
            ),
            JoinedChapterSource(
                title: "Episode Two",
                duration: seconds(50),
                retainedStart: .zero,
                retainedEnd: seconds(50),
                selectedEditionChapters: []
            ),
        ])

        XCTAssertEqual(result.duration, seconds(110))
        let chapters = try XCTUnwrap(result.document.editions.only).chapters
        XCTAssertEqual(
            chapters.map(\.primaryTitle),
            ["Opening", "Scene A", "Scene B", "Chapter 04"]
        )
        XCTAssertEqual(chapters.map { $0.start.seconds }, [0, 15, 45, 60])
        XCTAssertEqual(chapters.map { $0.end?.seconds }, [10, 25, 60, 110])
        XCTAssertTrue(chapters.allSatisfy(\.children.isEmpty))
        XCTAssertTrue(originalUIDs.isDisjoint(with: recursiveUIDs(in: chapters)))
        XCTAssertNoThrow(try result.document.validated(mediaDuration: result.duration))
    }

    func testComposesFlatPlayerCompatibleListFromEveryJoinedLeafChapter() throws {
        let result = try JoinedChapterComposer().compose(
            [
                JoinedChapterSource(
                    title: "Episode One",
                    duration: seconds(20),
                    retainedStart: .zero,
                    retainedEnd: seconds(20),
                    selectedEditionChapters: [
                        atom(uid: 1, title: "Opening", start: 0, end: 10),
                        atom(uid: 2, title: "Middle", start: 10, end: 20),
                    ]
                ),
                JoinedChapterSource(
                    title: "Episode Two",
                    duration: seconds(10),
                    retainedStart: .zero,
                    retainedEnd: seconds(10),
                    selectedEditionChapters: [
                        atom(uid: 3, title: "Finale", start: 0, end: 10)
                    ]
                ),
            ]
        )

        XCTAssertEqual(result.document.chapterCount, 3)
        XCTAssertEqual(result.document.topLevelChapterCount, 3)
        let chapters = try XCTUnwrap(result.document.editions.only).chapters
        XCTAssertEqual(chapters.map(\.primaryTitle), ["Opening", "Middle", "Finale"])
        XCTAssertEqual(chapters.map { $0.start.seconds }, [0, 10, 20])
        XCTAssertTrue(chapters.allSatisfy(\.children.isEmpty))
        XCTAssertNoThrow(try result.document.validated(mediaDuration: result.duration))
    }

    func testRenumbersRepeatedConsecutiveChapterSequencesAcrossRealPartCounts() throws {
        let counts = [42, 43, 46]
        var sources: [JoinedChapterSource] = []
        for (partIndex, count) in counts.enumerated() {
            var chapters: [MatroskaChapterAtom] = []
            for ordinal in 1...count {
                chapters.append(
                    atom(
                        uid: UInt64(partIndex * 100 + ordinal),
                        title: "Chapter \(ordinal)",
                        start: Int64(ordinal - 1),
                        end: Int64(ordinal)
                    ))
            }
            sources.append(
                JoinedChapterSource(
                    title: "Part \(partIndex + 1)",
                    duration: seconds(Int64(count)),
                    retainedStart: .zero,
                    retainedEnd: seconds(Int64(count)),
                    selectedEditionChapters: chapters
                ))
        }

        let result = try JoinedChapterComposer().compose(sources)
        let chapters = try XCTUnwrap(result.document.editions.only).chapters

        XCTAssertEqual(chapters.count, 131)
        XCTAssertEqual(
            chapters.map(\.primaryTitle),
            (1...131).map { "Chapter \($0)" }
        )
        XCTAssertEqual(chapters.map { Int($0.start.seconds) }, Array(0..<131))
    }

    func testRenumbersAlternateNumberedDisplaysButPreservesCustomDisplays() throws {
        func chapter(_ ordinal: Int, start: Int64) -> MatroskaChapterAtom {
            MatroskaChapterAtom(
                start: seconds(start),
                end: seconds(start + 1),
                displays: [
                    ChapterDisplay(title: "Chapter 0\(ordinal)", language: "en"),
                    ChapterDisplay(title: "Chapitre 0\(ordinal)", language: "fr"),
                    ChapterDisplay(title: ordinal == 1 ? "Opening" : "Closing", language: "und"),
                ]
            )
        }
        let result = try JoinedChapterComposer().compose([
            JoinedChapterSource(
                duration: seconds(2),
                retainedStart: .zero,
                retainedEnd: seconds(2),
                selectedEditionChapters: [chapter(1, start: 0), chapter(2, start: 1)]
            ),
            JoinedChapterSource(
                duration: seconds(2),
                retainedStart: .zero,
                retainedEnd: seconds(2),
                selectedEditionChapters: [chapter(1, start: 0), chapter(2, start: 1)]
            ),
        ])

        let chapters = try XCTUnwrap(result.document.editions.only).chapters
        XCTAssertEqual(
            chapters.map { $0.displays[0].title },
            [
                "Chapter 01", "Chapter 02", "Chapter 03", "Chapter 04",
            ])
        XCTAssertEqual(
            chapters.map { $0.displays[1].title },
            [
                "Chapitre 01", "Chapitre 02", "Chapitre 03", "Chapitre 04",
            ])
        XCTAssertEqual(
            chapters.map { $0.displays[2].title },
            [
                "Opening", "Closing", "Opening", "Closing",
            ])
    }

    func testLeavesMixedAndNonconsecutiveChapterTitlesUnchanged() throws {
        let result = try JoinedChapterComposer().compose([
            JoinedChapterSource(
                duration: seconds(2),
                retainedStart: .zero,
                retainedEnd: seconds(2),
                selectedEditionChapters: [
                    atom(uid: 1, title: "Chapter 1", start: 0, end: 1),
                    atom(uid: 2, title: "Opening", start: 1, end: 2),
                ]
            ),
            JoinedChapterSource(
                duration: seconds(2),
                retainedStart: .zero,
                retainedEnd: seconds(2),
                selectedEditionChapters: [
                    atom(uid: 3, title: "Chapter 1", start: 0, end: 1),
                    atom(uid: 4, title: "Chapter 3", start: 1, end: 2),
                ]
            ),
        ])

        XCTAssertEqual(
            try XCTUnwrap(result.document.editions.only).chapters.map(\.primaryTitle),
            ["Chapter 1", "Opening", "Chapter 1", "Chapter 3"]
        )
    }

    func testClampsCrossingChaptersAndTreatsRetainedEndAsExclusive() throws {
        let result = try JoinedChapterComposer().compose([
            JoinedChapterSource(
                duration: seconds(100),
                retainedStart: seconds(20),
                retainedEnd: seconds(80),
                selectedEditionChapters: [
                    atom(uid: 1, title: "Ends at start", start: 0, end: 20),
                    atom(uid: 2, title: "Crosses start", start: 10, end: 25),
                    atom(uid: 3, title: "Crosses end", start: 75, end: 90),
                    atom(uid: 4, title: "Starts at end", start: 80, end: 90),
                ]
            )
        ])

        let chapters = try XCTUnwrap(result.document.editions.only).chapters
        XCTAssertEqual(chapters.map(\.primaryTitle), ["Crosses start", "Crosses end"])
        XCTAssertEqual(chapters.map { $0.start.seconds }, [0, 55])
        XCTAssertEqual(chapters.map { $0.end?.seconds }, [5, 60])
    }

    func testMaterializesImplicitEndsFromNextSiblingAndSourceBoundary() throws {
        let result = try JoinedChapterComposer().compose([
            JoinedChapterSource(
                duration: seconds(100),
                retainedStart: seconds(20),
                retainedEnd: seconds(80),
                selectedEditionChapters: [
                    MatroskaChapterAtom(
                        uid: 30,
                        start: seconds(10),
                        displays: [ChapterDisplay(title: "First")]
                    ),
                    MatroskaChapterAtom(
                        uid: 40,
                        start: seconds(40),
                        displays: [ChapterDisplay(title: "Second")]
                    ),
                ]
            )
        ])

        let chapters = try XCTUnwrap(result.document.editions.only).chapters
        XCTAssertEqual(chapters.map(\.primaryTitle), ["First", "Second"])
        XCTAssertEqual(chapters.map { $0.start.seconds }, [0, 20])
        XCTAssertEqual(chapters.map { $0.end?.seconds }, [20, 60])
    }

    func testPreservesChapterDisplayAndFlagsWhileRegeneratingIdentity() throws {
        let source = MatroskaChapterAtom(
            uid: 42,
            start: seconds(5),
            end: seconds(10),
            isHidden: true,
            isEnabled: false,
            displays: [
                ChapterDisplay(title: "Ouverture", language: "fr", country: "FR")
            ]
        )
        let result = try JoinedChapterComposer().compose([
            JoinedChapterSource(
                title: "Film",
                displayLanguage: "en-US",
                displayCountry: "US",
                duration: seconds(20),
                retainedStart: .zero,
                retainedEnd: seconds(20),
                selectedEditionChapters: [source]
            )
        ])

        let chapter = try XCTUnwrap(result.document.editions.only?.chapters.only)
        XCTAssertEqual(chapter.displays, source.displays)
        XCTAssertTrue(chapter.children.isEmpty)
        XCTAssertTrue(chapter.isHidden)
        XCTAssertFalse(chapter.isEnabled)
        XCTAssertNotEqual(chapter.uid, source.uid)
        XCTAssertNotEqual(chapter.id, source.id)
    }

    func testRejectsInvalidInputsInvalidSourceTreeAndTimelineOverflow() throws {
        XCTAssertThrowsError(try JoinedChapterComposer().compose([])) { error in
            XCTAssertEqual(error as? JoinedChapterCompositionError, .emptySources)
        }
        XCTAssertThrowsError(
            try JoinedChapterComposer().compose([
                JoinedChapterSource(
                    duration: .zero,
                    retainedStart: .zero,
                    retainedEnd: seconds(1),
                    selectedEditionChapters: []
                )
            ])
        ) { error in
            XCTAssertEqual(error as? JoinedChapterCompositionError, .invalidSourceDuration)
        }
        XCTAssertThrowsError(
            try JoinedChapterComposer().compose([
                JoinedChapterSource(
                    duration: seconds(-1),
                    retainedStart: .zero,
                    retainedEnd: seconds(1),
                    selectedEditionChapters: []
                )
            ])
        ) { error in
            XCTAssertEqual(error as? JoinedChapterCompositionError, .invalidSourceDuration)
        }
        for (retainedStart, retainedEnd) in [
            (seconds(-1), seconds(5)),
            (seconds(5), seconds(5)),
            (seconds(6), seconds(5)),
            (seconds(5), seconds(11)),
        ] {
            XCTAssertThrowsError(
                try JoinedChapterComposer().compose([
                    JoinedChapterSource(
                        duration: seconds(10),
                        retainedStart: retainedStart,
                        retainedEnd: retainedEnd,
                        selectedEditionChapters: []
                    )
                ])
            ) { error in
                XCTAssertEqual(error as? JoinedChapterCompositionError, .invalidRetainedRange)
            }
        }
        let duplicate = atom(uid: 7, title: "Duplicate", start: 0, end: 1)
        XCTAssertThrowsError(
            try JoinedChapterComposer().compose([
                JoinedChapterSource(
                    duration: seconds(10),
                    retainedStart: .zero,
                    retainedEnd: seconds(10),
                    selectedEditionChapters: [duplicate, duplicate]
                )
            ])
        ) { error in
            XCTAssertEqual(error as? ChapterDocumentValidationError, .duplicateUID)
        }
        XCTAssertThrowsError(
            try JoinedChapterComposer().compose([
                JoinedChapterSource(
                    duration: MediaTime(nanoseconds: Int64.max),
                    retainedStart: .zero,
                    retainedEnd: MediaTime(nanoseconds: Int64.max),
                    selectedEditionChapters: []
                ),
                JoinedChapterSource(
                    duration: seconds(1),
                    retainedStart: .zero,
                    retainedEnd: seconds(1),
                    selectedEditionChapters: []
                ),
            ])
        ) { error in
            XCTAssertEqual(error as? JoinedChapterCompositionError, .timeOverflow)
        }

        let minimalSource = JoinedChapterSource(
            duration: seconds(1),
            retainedStart: .zero,
            retainedEnd: seconds(1),
            selectedEditionChapters: []
        )
        XCTAssertThrowsError(
            try JoinedChapterComposer().compose(
                Array(
                    repeating: minimalSource,
                    count: ChapterDocumentValidator.maximumChapters + 1
                )
            )
        ) { error in
            XCTAssertEqual(error as? ChapterDocumentValidationError, .tooManyChapters)
        }
    }

    private func atom(
        uid: UInt64,
        title: String,
        start: Int64,
        end: Int64,
        children: [MatroskaChapterAtom] = []
    ) -> MatroskaChapterAtom {
        MatroskaChapterAtom(
            uid: uid,
            start: seconds(start),
            end: seconds(end),
            displays: [ChapterDisplay(title: title)],
            children: children
        )
    }

    private func seconds(_ value: Int64) -> MediaTime {
        MediaTime(nanoseconds: value * 1_000_000_000)
    }

    private func recursiveUIDs(in chapters: [MatroskaChapterAtom]) -> Set<UInt64> {
        Set(chapters.flatMap { [$0.uid] + Array(recursiveUIDs(in: $0.children)) })
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? first : nil }
}
