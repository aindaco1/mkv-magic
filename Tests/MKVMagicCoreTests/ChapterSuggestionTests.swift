import MKVMagicCore
import XCTest

final class ChapterSuggestionTests: XCTestCase {
    func testConsolidatesNearbySignalsPreferringSceneTimeAndExcludesExistingChapters() throws {
        let seconds: (Double) -> MediaTime = { MediaTime(seconds: $0)! }
        var options = ChapterSuggestionOptions()
        options.minimumSpacing = .zero
        options.edgeGuard = .zero
        let suggestions = try ChapterSuggestionConsolidator.consolidate(
            [
                ChapterSuggestionDetection(time: seconds(10.2), signal: .blackFrame),
                ChapterSuggestionDetection(time: seconds(10), signal: .sceneChange),
                ChapterSuggestionDetection(time: seconds(10.4), signal: .silence),
                ChapterSuggestionDetection(time: seconds(40), signal: .sceneChange),
                ChapterSuggestionDetection(time: seconds(70), signal: .blackFrame),
            ],
            duration: seconds(100),
            existingChapterStarts: [seconds(40.5)],
            options: options
        )

        XCTAssertEqual(suggestions.map(\.time), [seconds(10), seconds(70)])
        XCTAssertEqual(suggestions[0].signals, [.sceneChange, .blackFrame, .silence])
        XCTAssertEqual(suggestions[0].signalDescription, "Scene change + Black frame + Silence")
    }

    func testAppliesEdgeSpacingAndMaximumSuggestionBoundsDeterministically() throws {
        let seconds: (Double) -> MediaTime = { MediaTime(seconds: $0)! }
        var options = ChapterSuggestionOptions()
        options.edgeGuard = seconds(2)
        options.minimumSpacing = seconds(10)
        options.mergeTolerance = .zero
        options.maximumSuggestions = 2
        let suggestions = try ChapterSuggestionConsolidator.consolidate(
            [1, 2, 7, 12, 20, 31, 99].map {
                ChapterSuggestionDetection(time: seconds(Double($0)), signal: .sceneChange)
            },
            duration: seconds(100),
            options: options
        )

        XCTAssertEqual(suggestions.map(\.time), [seconds(2), seconds(12)])
    }

    func testRejectsInvalidOptionsAndDuration() {
        var options = ChapterSuggestionOptions()
        options.detectsSceneChanges = false
        options.detectsBlackFrames = false
        options.detectsSilence = false
        XCTAssertThrowsError(
            try ChapterSuggestionConsolidator.consolidate(
                [], duration: MediaTime(nanoseconds: 1), options: options)
        ) { error in
            XCTAssertEqual(error as? ChapterSuggestionError, .invalidOptions)
        }

        XCTAssertThrowsError(
            try ChapterSuggestionConsolidator.consolidate([], duration: .zero)
        ) { error in
            XCTAssertEqual(error as? ChapterSuggestionError, .invalidDuration)
        }
    }

    func testDuplicateDetectionsCollapseAndResultIDsAreStable() throws {
        var options = ChapterSuggestionOptions()
        options.edgeGuard = .zero
        options.minimumSpacing = .zero
        let detection = ChapterSuggestionDetection(
            time: MediaTime(nanoseconds: 5_000_000_000), signal: .blackFrame)
        let suggestions = try ChapterSuggestionConsolidator.consolidate(
            [detection, detection],
            duration: MediaTime(nanoseconds: 10_000_000_000),
            options: options
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].id, "5000000000:blackFrame")
    }

    func testAppliesReviewedSuggestionsToRequestedEditionAndSkipsInvalidOverlaps() throws {
        let editionID = UUID()
        let original = MatroskaChapterDocument(
            editions: [
                MatroskaChapterEdition(
                    id: editionID,
                    chapters: [
                        MatroskaChapterAtom(
                            uid: 1,
                            start: .zero,
                            end: MediaTime(nanoseconds: 20_000_000_000),
                            displays: [ChapterDisplay(title: "Opening")]
                        )
                    ]
                )
            ]
        )
        let suggestions = [
            ChapterSuggestion(
                time: MediaTime(nanoseconds: 10_000_000_000), signals: [.sceneChange]),
            ChapterSuggestion(
                time: MediaTime(nanoseconds: 30_000_000_000), signals: [.silence]),
            ChapterSuggestion(time: .zero, signals: [.blackFrame]),
        ]

        let result = try ChapterSuggestionApplicator.apply(
            suggestions,
            to: original,
            editionID: editionID,
            mediaDuration: MediaTime(nanoseconds: 60_000_000_000)
        )

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.skippedCount, 2)
        XCTAssertNotNil(result.firstAddedChapterID)
        XCTAssertEqual(
            result.document.editions[0].chapters.map(\.start.nanoseconds),
            [0, 30_000_000_000]
        )
        XCTAssertEqual(result.document.editions[0].chapters[1].displays[0].title, "Chapter 2")
    }

    func testApplyingToEmptyDocumentCreatesOneDefaultEdition() throws {
        let result = try ChapterSuggestionApplicator.apply(
            [
                ChapterSuggestion(
                    time: MediaTime(nanoseconds: 5_000_000_000), signals: [.sceneChange])
            ],
            to: MatroskaChapterDocument(),
            mediaDuration: MediaTime(nanoseconds: 10_000_000_000)
        )

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.document.editions.count, 1)
        XCTAssertTrue(result.document.editions[0].isDefault)
    }

    func testEmptyOrInvalidSuggestionsCannotLeaveAnEmptyEdition() throws {
        let empty = try ChapterSuggestionApplicator.apply(
            [],
            to: MatroskaChapterDocument(),
            mediaDuration: MediaTime(nanoseconds: 10_000_000_000)
        )
        XCTAssertEqual(empty.document, MatroskaChapterDocument())
        XCTAssertEqual(empty.addedCount, 0)

        let invalid = try ChapterSuggestionApplicator.apply(
            [
                ChapterSuggestion(
                    time: MediaTime(nanoseconds: 20_000_000_000), signals: [.sceneChange])
            ],
            to: MatroskaChapterDocument(),
            mediaDuration: MediaTime(nanoseconds: 10_000_000_000)
        )
        XCTAssertEqual(invalid.document, MatroskaChapterDocument())
        XCTAssertEqual(invalid.addedCount, 0)
        XCTAssertEqual(invalid.skippedCount, 1)
    }
}
