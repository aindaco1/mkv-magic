import MKVMagicCore
import XCTest

final class TrimTests: XCTestCase {
    func testFastTrimUsesFirstKeyframeAtOrAfterEachRequestedBoundary() throws {
        let plan = try FastTrimPlanner().plan(
            requested: range(3, 7),
            sourceDuration: time(10),
            videoKeyframes: [time(8), time(0), time(4), time(2), time(6), time(4)]
        )

        XCTAssertEqual(plan.adjusted, range(4, 8))
        XCTAssertTrue(plan.startWasAdjusted)
        XCTAssertTrue(plan.endWasAdjusted)
    }

    func testFastTrimKeepsPhysicalEdgesAndRejectsIneffectiveOrInvalidRanges() throws {
        let startOnly = try FastTrimPlanner().plan(
            requested: range(0, 7),
            sourceDuration: time(10),
            videoKeyframes: [time(0), time(4), time(8)]
        )
        XCTAssertEqual(startOnly.adjusted, range(0, 8))

        let endOnly = try FastTrimPlanner().plan(
            requested: range(3, 10),
            sourceDuration: time(10),
            videoKeyframes: [time(0), time(4), time(8)]
        )
        XCTAssertEqual(endOnly.adjusted, range(4, 10))

        XCTAssertThrowsError(
            try FastTrimPlanner().plan(
                requested: range(0, 10),
                sourceDuration: time(10),
                videoKeyframes: [time(0)]
            )
        ) { XCTAssertEqual($0 as? TrimPlanningError, .noChange) }
        XCTAssertThrowsError(
            try FastTrimPlanner().plan(
                requested: range(0, 9.9),
                sourceDuration: time(10),
                videoKeyframes: [time(0)]
            )
        ) { XCTAssertEqual($0 as? TrimPlanningError, .noEffectiveFastTrim) }
        XCTAssertThrowsError(
            try FastTrimPlanner().plan(
                requested: range(5, 5),
                sourceDuration: time(10),
                videoKeyframes: [time(0), time(6)]
            )
        ) { XCTAssertEqual($0 as? TrimPlanningError, .invalidRange) }
    }

    func testChapterTrimClipsRebasesNestingDropsOutsideAndRegeneratesUIDs() throws {
        let outside = atom(uid: 11, start: 0, end: 2, title: "Outside")
        let crossing = atom(uid: 12, start: 1, end: 5, title: "Crossing")
        let childOutside = atom(uid: 21, start: 2, end: 3, title: "Child outside")
        let childInside = atom(uid: 22, start: 4, end: 7, title: "Child inside")
        let parent = atom(
            uid: 13,
            start: 2,
            end: 9,
            title: "Parent",
            children: [childOutside, childInside]
        )
        let after = atom(uid: 14, start: 9, end: 10, title: "After")
        let original = MatroskaChapterDocument(editions: [
            MatroskaChapterEdition(
                uid: 5,
                isDefault: true,
                chapters: [outside, crossing, parent, after]
            )
        ])

        let trimmed = try MatroskaChapterTrimmer().trim(
            original,
            sourceDuration: time(10),
            retainedRange: range(3, 8)
        )

        XCTAssertEqual(trimmed.editions.count, 1)
        let chapters = try XCTUnwrap(trimmed.editions.first?.chapters)
        XCTAssertEqual(chapters.map(\.primaryTitle), ["Crossing", "Parent"])
        XCTAssertEqual(chapters.map(\.start), [time(0), time(0)])
        XCTAssertEqual(chapters.map(\.end), [time(2), time(5)])
        XCTAssertEqual(chapters[1].children.map(\.primaryTitle), ["Child inside"])
        XCTAssertEqual(chapters[1].children[0].start, time(1))
        XCTAssertEqual(chapters[1].children[0].end, time(4))
        XCTAssertNotEqual(trimmed.editions[0].uid, 5)
        XCTAssertTrue(Set(chapters.map(\.uid)).isDisjoint(with: [11, 12, 13, 14]))
    }

    func testChapterTrimDropsEmptyEditionsAndRefusesOrderedEditions() throws {
        let document = MatroskaChapterDocument(editions: [
            MatroskaChapterEdition(
                isDefault: true,
                chapters: [atom(uid: 1, start: 0, end: 2, title: "Before")]
            )
        ])
        XCTAssertEqual(
            try MatroskaChapterTrimmer().trim(
                document,
                sourceDuration: time(10),
                retainedRange: range(4, 8)
            ),
            MatroskaChapterDocument()
        )

        let ordered = MatroskaChapterDocument(editions: [
            MatroskaChapterEdition(
                isDefault: true,
                isOrdered: true,
                chapters: [atom(uid: 2, start: 0, end: 10, title: "Ordered")]
            )
        ])
        XCTAssertThrowsError(
            try MatroskaChapterTrimmer().trim(
                ordered,
                sourceDuration: time(10),
                retainedRange: range(1, 9)
            )
        ) { XCTAssertEqual($0 as? TrimPlanningError, .orderedChaptersUnsupported) }
    }

    private func atom(
        uid: UInt64,
        start: Double,
        end: Double,
        title: String,
        children: [MatroskaChapterAtom] = []
    ) -> MatroskaChapterAtom {
        MatroskaChapterAtom(
            uid: uid,
            start: time(start),
            end: time(end),
            displays: [ChapterDisplay(title: title)],
            children: children
        )
    }

    private func range(_ start: Double, _ end: Double) -> MediaTrimRange {
        MediaTrimRange(start: time(start), end: time(end))
    }

    private func time(_ seconds: Double) -> MediaTime {
        MediaTime(nanoseconds: Int64((seconds * 1_000_000_000).rounded()))
    }
}
