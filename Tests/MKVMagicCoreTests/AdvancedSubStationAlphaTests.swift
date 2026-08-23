import XCTest

@testable import MKVMagicCore

final class AdvancedSubStationAlphaTests: XCTestCase {
    func testRoundTripsASSStructureStylesOverridesUnknownSectionsAndCommas() throws {
        let input =
            "\u{FEFF}[Script Info]\r\n"
            + "ScriptType: v4.00+\r\n"
            + "PlayResX: 1920\r\n"
            + "\r\n[V4+ Styles]\r\n"
            + "Format: Name, Fontname, Fontsize, Bold\r\n"
            + "Style: Default,Helvetica,48,-1\r\n"
            + "\r\n[Events]\r\n"
            + "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\r\n"
            + "Comment: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,Keep this comment\r\n"
            + "Dialogue: 0,0:00:01.20,0:00:03.45,Default,,0,0,0,,{\\an8}Hello, world\r\n"
            + "\r\n[Aegisub Project Garbage]\r\n"
            + "Last Style Storage: Default\r\n"
        let result = try AdvancedSubStationAlphaCodec().parse(
            DecodedSubtitleText(text: input, encoding: .utf8WithBOM)
        )

        XCTAssertEqual(
            result.diagnostics,
            [.removedByteOrderMark, .normalizedLineEndings]
        )
        XCTAssertEqual(result.document.events.count, 1)
        XCTAssertEqual(result.document.events[0].start, SubRipTimestamp(milliseconds: 1_200))
        XCTAssertEqual(result.document.events[0].end, SubRipTimestamp(milliseconds: 3_450))
        XCTAssertEqual(result.document.events[0].style, "Default")
        XCTAssertEqual(result.document.events[0].text, #"{\an8}Hello, world"#)
        XCTAssertEqual(
            AdvancedSubStationAlphaCodec().serialize(result.document),
            input.dropFirst().replacingOccurrences(of: "\r\n", with: "\n")
        )
    }

    func testCleanupChangesOnlyDialogueTextFieldAndCanRestoreEachEvent() throws {
        let document = try parse(
            "[Script Info]\n"
                + "Title: Example\n"
                + "[Events]\n"
                + "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
                + "Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0010,0020,0030,fx,  Hello, world  \n"
                + "Dialogue: 2,0:00:03.00,0:00:04.00,Signs,,0,0,0,,{\\i1}Downloaded from YTS.MX{\\i0}\n"
        )

        let preview = AdvancedSubStationAlphaCleanupPolicy().preview(document)

        XCTAssertEqual(preview.changes.count, 2)
        XCTAssertEqual(preview.changes[0].reasons, [.accidentalWhitespace])
        XCTAssertEqual(preview.changes[0].after?.text, "Hello, world")
        XCTAssertEqual(preview.changes[1].reasons, [.ytsAdvertisement])
        XCTAssertNil(preview.changes[1].after)
        XCTAssertEqual(preview.cleaned.events.count, 1)
        let cleaned = AdvancedSubStationAlphaCodec().serialize(preview.cleaned)
        XCTAssertTrue(
            cleaned.contains(
                "Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0010,0020,0030,fx,Hello, world"
            )
        )
        XCTAssertFalse(cleaned.contains("YTS.MX"))
        XCTAssertTrue(cleaned.contains("Title: Example"))

        XCTAssertEqual(
            preview.document(restoringEventIDs: [0]).events.map(\.text),
            ["  Hello, world  "]
        )
        XCTAssertEqual(
            preview.document(restoringEventIDs: [1]).events.map(\.text),
            ["Hello, world", #"{\i1}Downloaded from YTS.MX{\i0}"#]
        )
        XCTAssertEqual(preview.document(restoringEventIDs: [0, 1]), document)
    }

    func testParsesLegacySSAEventFormatWithoutRewritingIt() throws {
        let input =
            "[Script Info]\nScriptType: v4.00\n"
            + "[V4 Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
            + "[Events]\n"
            + "Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
            + "Dialogue: Marked=0,0:00:01.00,0:00:02.50,Default,,0,0,0,,Legacy text\n"
        let document = try parse(input)

        XCTAssertEqual(document.events.first?.text, "Legacy text")
        XCTAssertEqual(AdvancedSubStationAlphaCodec().serialize(document), input)
    }

    func testCleanupAppliesEnglishOCRToDialogueTextWithoutChangingOverrideTags() throws {
        let document = try parse(
            "[Events]\nFormat: Layer, Start, End, Style, Text\n"
                + #"Dialogue: 0,0:00:01.00,0:00:02.00,Default,{\an8}y0u said HE11O"# + "\n"
                + "Dialogue: 0,0:00:03.00,0:00:04.00,Default,Tbe modem world\n"
        )

        let preview = AdvancedSubStationAlphaCleanupPolicy().preview(document)

        XCTAssertEqual(
            preview.changes.map(\.reasons), [[.ocrHighConfidence], [.spellingSuggestion]])
        XCTAssertEqual(preview.cleaned.events[0].text, #"{\an8}you said HELLO"#)
        XCTAssertEqual(preview.cleaned.events[1].text, "The modern world")
        XCTAssertEqual(
            preview.document(restoringEventIDs: [1]).events.map(\.text),
            [#"{\an8}you said HELLO"#, "Tbe modem world"]
        )
    }

    func testCleanupCanDisableEnglishOCRForAdvancedSubtitles() throws {
        let document = try parse(
            "[Events]\nFormat: Start, End, Text\n"
                + "Dialogue: 0:00:01.00,0:00:02.00, y0u \n"
        )

        let preview = AdvancedSubStationAlphaCleanupPolicy(
            appliesEnglishOCRRules: false
        ).preview(document)

        XCTAssertEqual(preview.changes.map(\.reasons), [[.accidentalWhitespace]])
        XCTAssertEqual(preview.cleaned.events[0].text, "y0u")
    }

    func testRejectsMissingDuplicateAndMalformedEventStructure() {
        XCTAssertThrowsError(
            try parse("[Script Info]\nTitle: Missing events\n")
        ) { error in
            XCTAssertEqual(error as? AdvancedSubStationAlphaParseError, .missingEventsSection)
        }
        XCTAssertThrowsError(
            try parse("[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,Text\n")
        ) { error in
            XCTAssertEqual(error as? AdvancedSubStationAlphaParseError, .missingEventFormat)
        }
        XCTAssertThrowsError(
            try parse(
                "[Events]\nFormat: Start, End, Text, Text\n"
                    + "Dialogue: 0:00:01.00,0:00:02.00,One,Two\n"
            )
        ) { error in
            XCTAssertEqual(
                error as? AdvancedSubStationAlphaParseError,
                .invalidEventFormat(line: 2)
            )
        }
        XCTAssertThrowsError(
            try parse(
                "[Events]\nFormat: Start, End, Style, Text\n"
                    + "Dialogue: 0:00:01.00,0:00:02.00,Only three\n"
            )
        ) { error in
            XCTAssertEqual(
                error as? AdvancedSubStationAlphaParseError,
                .malformedDialogue(line: 3)
            )
        }
    }

    func testRejectsBackwardsAndUnrepresentableTimestamps() {
        XCTAssertThrowsError(
            try parse(
                "[Events]\nFormat: Start, End, Text\n"
                    + "Dialogue: 0:00:03.00,0:00:02.00,Backwards\n"
            )
        ) { error in
            XCTAssertEqual(
                error as? AdvancedSubStationAlphaParseError,
                .nonIncreasingTime(line: 3)
            )
        }
        XCTAssertThrowsError(
            try parse(
                "[Events]\nFormat: Start, End, Text\n"
                    + "Dialogue: 2562047788015216:00:00.00,2562047788015216:00:00.01,Huge\n"
            )
        ) { error in
            XCTAssertEqual(
                error as? AdvancedSubStationAlphaParseError,
                .invalidTimestamp(line: 3)
            )
        }
    }

    private func parse(_ text: String) throws -> AdvancedSubStationAlphaDocument {
        try AdvancedSubStationAlphaCodec().parse(
            DecodedSubtitleText(text: text, encoding: .utf8)
        ).document
    }
}
