import Foundation
import MKVMagicCore
import XCTest

final class BulkMediaEditTests: XCTestCase {
    func testSharedChangesKeepEachTracksOwnOtherFields() throws {
        let first = MediaTrack(
            id: 0, kind: .audio, codec: "aac", uid: 11, language: "en", title: "Main",
            isDefault: true)
        let second = MediaTrack(
            id: 1, kind: .audio, codec: "aac", uid: 42, language: "es", title: "Commentary",
            isCommentary: true)
        let subtitle = MediaTrack(id: 2, kind: .subtitle, codec: "subrip", uid: 91, language: "fr")
        let edits = try BulkTrackMetadataChange(kind: .audio, language: "de").edits(in: [
            first, second, subtitle,
        ])
        XCTAssertEqual(edits.map(\.trackUID), [11, 42])
        XCTAssertEqual(edits.map(\.name), ["Main", "Commentary"])
        XCTAssertEqual(edits.map(\.language), ["de", "de"])
        XCTAssertEqual(edits.map(\.isDefault), [first.isDefault, second.isDefault])
        XCTAssertEqual(edits.map(\.isCommentary), [false, true])
        XCTAssertTrue(
            try BulkTrackMetadataChange(kind: .video, language: "de").edits(in: [first]).isEmpty)
        XCTAssertTrue(
            try BulkTrackMetadataChange(kind: .audio, language: "en").edits(in: [first]).isEmpty)
    }

    func testClearNameAndExplicitFalseFlagsAreNotUnchanged() throws {
        let track = MediaTrack(
            id: 0, kind: .subtitle, codec: "subrip", uid: 1, title: "SDH", isForced: true,
            isHearingImpaired: true)
        let edit = try XCTUnwrap(
            BulkTrackMetadataChange(kind: .subtitle, name: "", flags: [.forced: false]).edits(in: [
                track
            ]).first)
        XCTAssertNil(edit.name)
        XCTAssertFalse(edit.isForced)
        XCTAssertTrue(edit.isHearingImpaired)
        XCTAssertThrowsError(
            try BulkTrackMetadataChange(kind: .audio, language: "es").edits(in: [
                MediaTrack(id: 0, kind: .audio, codec: "aac")
            ]))
    }

    func testAmountsAreRelativeToEachDurationAndRejectEmptyShortNegativeRanges() throws {
        let amount = BatchTrimAmounts(
            beginning: MediaTime(nanoseconds: 3), end: MediaTime(nanoseconds: 2))
        XCTAssertEqual(
            try amount.retainedRange(duration: MediaTime(nanoseconds: 10)),
            MediaTrimRange(start: MediaTime(nanoseconds: 3), end: MediaTime(nanoseconds: 8)))
        XCTAssertEqual(
            try amount.retainedRange(duration: MediaTime(nanoseconds: 20)).end.nanoseconds, 18)
        for duration in [nil, .zero, MediaTime(nanoseconds: 5), MediaTime(nanoseconds: 2)] {
            XCTAssertThrowsError(try amount.retainedRange(duration: duration))
        }
        for invalid in [
            BatchTrimAmounts(beginning: .zero, end: .zero),
            BatchTrimAmounts(beginning: MediaTime(nanoseconds: -1), end: .zero),
            BatchTrimAmounts(
                beginning: MediaTime(nanoseconds: Int64.max), end: MediaTime(nanoseconds: Int64.max)
            ),
        ] {
            XCTAssertThrowsError(
                try invalid.retainedRange(duration: MediaTime(nanoseconds: Int64.max)))
        }
    }

    func testAmountParsingIsExactAndRejectsOverflowAndInvalidInput() throws {
        XCTAssertEqual(
            try BatchTrimAmounts.parseAmount(" 90.000000001 ").nanoseconds, 90_000_000_001)
        XCTAssertEqual(
            try BatchTrimAmounts.parseAmount("00:01:30.000000001").nanoseconds, 90_000_000_001)
        XCTAssertEqual(
            try BatchTrimAmounts.parseAmount("9223372036.854775807").nanoseconds, Int64.max)
        for value in [
            "", "NaN", "-1", "inf", "1e9", "1.0000000001", "9223372036.854775808",
            "99999999999999999999999", "1.",
        ] {
            XCTAssertThrowsError(try BatchTrimAmounts.parseAmount(value), value)
        }
    }
}
