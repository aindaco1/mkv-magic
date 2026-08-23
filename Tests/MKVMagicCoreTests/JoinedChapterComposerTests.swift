import MKVMagicCore
import XCTest

final class JoinedChapterComposerTests: XCTestCase {
    func testComposesTrimmedNestedSourcesWithGlobalTimesAndBoundaryChild() throws {
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
        let parents = try XCTUnwrap(result.document.editions.only).chapters
        XCTAssertEqual(
            parents.map(\.primaryTitle), ["Part 1 — Episode One", "Part 2 — Episode Two"])
        XCTAssertEqual(parents.map { $0.start.seconds }, [0, 60])
        XCTAssertEqual(parents.map { $0.end?.seconds }, [60, 110])
        XCTAssertEqual(parents[0].children.map(\.primaryTitle), ["Opening", "Main"])
        XCTAssertEqual(parents[0].children.map { $0.start.seconds }, [0, 10])
        XCTAssertEqual(parents[0].children.map { $0.end?.seconds }, [10, 60])
        XCTAssertEqual(parents[0].children[1].children.map(\.primaryTitle), ["Scene A", "Scene B"])
        XCTAssertEqual(
            parents[0].children[1].children.map { $0.start.seconds },
            [15, 45]
        )
        XCTAssertEqual(
            parents[0].children[1].children.map { $0.end?.seconds },
            [25, 60]
        )
        XCTAssertEqual(parents[1].children.map(\.primaryTitle), ["Chapter 04"])
        XCTAssertEqual(parents[1].children.first?.start, seconds(60))
        XCTAssertEqual(parents[1].children.first?.end, seconds(110))
        XCTAssertTrue(originalUIDs.isDisjoint(with: recursiveUIDs(in: parents)))
        XCTAssertNoThrow(try result.document.validated(mediaDuration: result.duration))
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

        let children = try XCTUnwrap(result.document.editions.only?.chapters.only).children
        XCTAssertEqual(children.map(\.primaryTitle), ["Crosses start", "Crosses end"])
        XCTAssertEqual(children.map { $0.start.seconds }, [0, 55])
        XCTAssertEqual(children.map { $0.end?.seconds }, [5, 60])
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

        let children = try XCTUnwrap(result.document.editions.only?.chapters.only).children
        XCTAssertEqual(children.map(\.primaryTitle), ["First", "Second"])
        XCTAssertEqual(children.map { $0.start.seconds }, [0, 20])
        XCTAssertEqual(children.map { $0.end?.seconds }, [20, 60])
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

        let parent = try XCTUnwrap(result.document.editions.only?.chapters.only)
        let child = try XCTUnwrap(parent.children.only)
        XCTAssertEqual(
            parent.displays,
            [ChapterDisplay(title: "Part 1 — Film", language: "en-us", country: "US")])
        XCTAssertEqual(child.displays, source.displays)
        XCTAssertTrue(child.isHidden)
        XCTAssertFalse(child.isEnabled)
        XCTAssertNotEqual(child.uid, source.uid)
        XCTAssertNotEqual(child.id, source.id)
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
