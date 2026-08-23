import Foundation
import XCTest

@testable import MKVMagicCore

final class SubRipTests: XCTestCase {
    func testDecodesUTF8BOMAndNormalizesStructureWithoutChangingTimingOrSettings() throws {
        let text =
            "\u{FEFF}7\r\n00:00:01.2 --> 00:00:03,450 X1:10 X2:20\r\n Hello  \r\n\r\n"
            + "9\r\n00:00:04,000 --> 00:00:05,000\r\nWorld\r\n"
        let data = Data(text.utf8)

        let decoded = try SubtitleTextDecoder().decode(data)
        let result = try SubRipCodec().parse(decoded)

        XCTAssertEqual(decoded.encoding, .utf8WithBOM)
        XCTAssertEqual(
            result.diagnostics,
            [
                .removedByteOrderMark,
                .normalizedLineEndings,
                .normalizedSequenceNumbers,
                .normalizedTimestampSeparator,
            ]
        )
        XCTAssertEqual(result.document.cues[0].start.milliseconds, 1_200)
        XCTAssertEqual(result.document.cues[0].end.milliseconds, 3_450)
        XCTAssertEqual(result.document.cues[0].settings, "X1:10 X2:20")
        XCTAssertEqual(
            SubRipCodec().serialize(result.document),
            "1\n00:00:01,200 --> 00:00:03,450 X1:10 X2:20\n Hello  \n\n"
                + "2\n00:00:04,000 --> 00:00:05,000\nWorld\n"
        )
    }

    func testDecodesWindows1252Fallback() throws {
        let bytes = Data([
            0x31, 0x0A,
            0x30, 0x30, 0x3A, 0x30, 0x30, 0x3A, 0x30, 0x30, 0x2C, 0x30, 0x30, 0x30,
            0x20, 0x2D, 0x2D, 0x3E, 0x20,
            0x30, 0x30, 0x3A, 0x30, 0x30, 0x3A, 0x30, 0x31, 0x2C, 0x30, 0x30, 0x30,
            0x0A, 0x93, 0x48, 0x69, 0x94, 0x0A,
        ])

        let decoded = try SubtitleTextDecoder().decode(bytes)

        XCTAssertEqual(decoded.encoding, .windows1252)
        XCTAssertEqual(try SubRipCodec().parse(decoded).document.cues[0].lines, ["“Hi”"])
    }

    func testRejectsMalformedAndBackwardsTimings() throws {
        let malformed = DecodedSubtitleText(
            text: "1\nnot timing\nText\n",
            encoding: .utf8
        )
        XCTAssertThrowsError(try SubRipCodec().parse(malformed)) {
            XCTAssertEqual($0 as? SubRipParseError, .invalidTimestamp(block: 1))
        }

        let backwards = DecodedSubtitleText(
            text: "1\n00:00:02,000 --> 00:00:01,000\nText\n",
            encoding: .utf8
        )
        XCTAssertThrowsError(try SubRipCodec().parse(backwards)) {
            XCTAssertEqual($0 as? SubRipParseError, .nonIncreasingTime(block: 1))
        }

        let overflowing = DecodedSubtitleText(
            text:
                "1\n2562047788015216:00:00,000 --> 2562047788015216:00:00,001\nText\n",
            encoding: .utf8
        )
        XCTAssertThrowsError(try SubRipCodec().parse(overflowing)) {
            XCTAssertEqual($0 as? SubRipParseError, .invalidTimestamp(block: 1))
        }
    }

    func testCleanupRemovesOnlyKnownWholeAdBlocksAndTrimsWhitespace() throws {
        let source = DecodedSubtitleText(
            text:
                "1\n00:00:00,000 --> 00:00:01,000\nOfficial YIFY movies site:\nYTS.MX\n\n"
                + "2\n00:00:01,000 --> 00:00:02,000\n  Dialogue here  \n\n"
                + "3\n00:00:02,000 --> 00:00:03,000\nA character downloaded from school\n",
            encoding: .utf8
        )
        let document = try SubRipCodec().parse(source).document

        let preview = SubtitleCleanupPolicy().preview(document)

        XCTAssertEqual(preview.cleaned.cues.map(\.id), [1, 2])
        XCTAssertEqual(preview.cleaned.cues[0].lines, ["Dialogue here"])
        XCTAssertEqual(
            preview.changes.map(\.reasons),
            [[.ytsAdvertisement], [.accidentalWhitespace]]
        )
        XCTAssertEqual(
            preview.document(restoringCueIDs: [0]).cues.map(\.id),
            [0, 1, 2]
        )
        XCTAssertEqual(
            preview.document(restoringCueIDs: [1]).cues[0].lines,
            ["  Dialogue here  "]
        )
    }

    func testMultilineDownloadedFromPatternMatchesAcrossLines() throws {
        let source = DecodedSubtitleText(
            text: "1\n00:00:00,000 --> 00:00:01,000\nDownloaded from\nYTS.BZ\n",
            encoding: .utf8
        )
        let document = try SubRipCodec().parse(source).document

        XCTAssertTrue(SubtitleCleanupPolicy().preview(document).cleaned.cues.isEmpty)
    }

    func testCleanupSeparatesAutomaticOCRFixesFromReviewOnlySpellingSuggestions() throws {
        let source = DecodedSubtitleText(
            text:
                "1\n00:00:00,000 --> 00:00:01,000\ny0u said HE11O\n\n"
                + "2\n00:00:01,000 --> 00:00:02,000\nTbe modem world\n",
            encoding: .utf8
        )
        let document = try SubRipCodec().parse(source).document

        let preview = SubtitleCleanupPolicy().preview(document)

        XCTAssertEqual(
            preview.changes.map(\.reasons), [[.ocrHighConfidence], [.spellingSuggestion]])
        XCTAssertEqual(preview.cleaned.cues[0].lines, ["you said HELLO"])
        XCTAssertEqual(preview.cleaned.cues[1].lines, ["The modern world"])
        XCTAssertEqual(
            preview.document(restoringCueIDs: [1]).cues.map(\.lines),
            [["you said HELLO"], ["Tbe modem world"]]
        )
    }

    func testCleanupCanDisableEnglishOCRWithoutDisablingOtherRules() throws {
        let document = try SubRipCodec().parse(
            DecodedSubtitleText(
                text: "1\n00:00:00,000 --> 00:00:01,000\n y0u \n",
                encoding: .utf8
            )
        ).document

        let preview = SubtitleCleanupPolicy(appliesEnglishOCRRules: false).preview(document)

        XCTAssertEqual(preview.changes.map(\.reasons), [[.accidentalWhitespace]])
        XCTAssertEqual(preview.cleaned.cues[0].lines, ["y0u"])
    }
}
