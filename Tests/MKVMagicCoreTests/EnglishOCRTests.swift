import XCTest

@testable import MKVMagicCore

final class EnglishOCRTests: XCTestCase {
    func testAutomaticallyCorrectsUniqueGlyphWordsAndPronounContractions() {
        let review = EnglishOCRCorrectionPolicy().review(
            "l'm sure y0u said HE11O, and 1’ll go."
        )

        XCTAssertEqual(review.corrections.map(\.confidence), [.high, .high, .high, .high])
        XCTAssertEqual(
            review.automaticallyCorrectedText,
            "I'm sure you said HELLO, and I’ll go."
        )
        XCTAssertEqual(review.fullySuggestedText, review.automaticallyCorrectedText)
    }

    func testLetterOnlyConfusionsRequireReviewAndPreserveCase() {
        let review = EnglishOCRCorrectionPolicy().review(
            "Tbe modem world is otber than this."
        )

        XCTAssertTrue(review.corrections.allSatisfy { $0.confidence == .reviewRequired })
        XCTAssertEqual(review.automaticallyCorrectedText, review.originalText)
        XCTAssertEqual(review.fullySuggestedText, "The modern world is other than this.")
    }

    func testProtectsMarkupOverridesURLsAndEmailAddresses() {
        let input = #"<i>y0u</i> {\fnHE11O} y0u https://example.test/y0u person+y0u@example.test"#
        let review = EnglishOCRCorrectionPolicy().review(input)

        XCTAssertEqual(
            review.automaticallyCorrectedText,
            #"<i>you</i> {\fnHE11O} you https://example.test/y0u person+y0u@example.test"#
        )
        XCTAssertEqual(review.corrections.map(\.before), ["y0u", "y0u"])
    }

    func testScansManyProtectedRegionsWithoutLosingUnprotectedCorrections() {
        let input = Array(repeating: "<i>HE11O</i> y0u", count: 5_000)
            .joined(separator: " ")

        let review = EnglishOCRCorrectionPolicy().review(input)

        XCTAssertEqual(review.corrections.count, 10_000)
        XCTAssertEqual(Set(review.corrections.map(\.before)), ["HE11O", "y0u"])
        XCTAssertEqual(Set(review.corrections.map(\.after)), ["HELLO", "you"])
        XCTAssertTrue(review.automaticallyCorrectedText.hasPrefix("<i>HELLO</i> you"))
        XCTAssertTrue(review.automaticallyCorrectedText.hasSuffix("<i>HELLO</i> you"))
    }

    func testLeavesOrdinaryWordsNamesNumbersAndAmbiguousGlyphsUnchanged() {
        let input = "Model 3, room 101, modem, Alonso, R2-D2, and | are unchanged."
        let review = EnglishOCRCorrectionPolicy().review(input)

        XCTAssertEqual(review.automaticallyCorrectedText, input)
        XCTAssertEqual(
            review.fullySuggestedText,
            input.replacingOccurrences(of: "modem", with: "modern")
        )
    }

    func testFilenamePolicySkipsExplicitNonEnglishSuffixesWithoutMistakingTitles() {
        XCTAssertFalse(
            EnglishSubtitleFilenamePolicy.shouldApplyOCRRules(
                to: URL(fileURLWithPath: "/Media/Movie.fr.srt")
            )
        )
        XCTAssertFalse(
            EnglishSubtitleFilenamePolicy.shouldApplyOCRRules(
                to: URL(fileURLWithPath: "/Media/Movie.pt-BR.ass")
            )
        )
        XCTAssertFalse(
            EnglishSubtitleFilenamePolicy.shouldApplyOCRRules(
                to: URL(fileURLWithPath: "/Media/Movie.fr-FR.forced.srt")
            )
        )
        XCTAssertFalse(
            EnglishSubtitleFilenamePolicy.shouldApplyOCRRules(
                to: URL(fileURLWithPath: "/Media/Movie.zh-Hans.sdh.ass")
            )
        )
        XCTAssertTrue(
            EnglishSubtitleFilenamePolicy.shouldApplyOCRRules(
                to: URL(fileURLWithPath: "/Media/The French Dispatch.srt")
            )
        )
        XCTAssertTrue(
            EnglishSubtitleFilenamePolicy.shouldApplyOCRRules(
                to: URL(fileURLWithPath: "/Media/Movie.en.forced.ssa")
            )
        )
    }
}
