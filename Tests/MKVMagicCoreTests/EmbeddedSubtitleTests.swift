import XCTest

@testable import MKVMagicCore

final class EmbeddedSubtitleTests: XCTestCase {
    func testRecognizesOnlyEditableMatroskaTextSubtitleCodecsWithStableUIDs() {
        let srt = MediaTrack(
            id: 2, kind: .subtitle, codec: "SubRip/SRT", codecID: "S_TEXT/UTF8", uid: 12)
        let ass = MediaTrack(
            id: 3, kind: .subtitle, codec: "ASS", codecID: "s_text/ass", uid: 13)
        let ssa = MediaTrack(
            id: 4, kind: .subtitle, codec: "SSA", codecID: "S_TEXT/SSA", uid: 14)
        let pgs = MediaTrack(
            id: 5, kind: .subtitle, codec: "PGS", codecID: "S_HDMV/PGS", uid: 15)
        let unstable = MediaTrack(
            id: 6, kind: .subtitle, codec: "SubRip/SRT", codecID: "S_TEXT/UTF8")
        let video = MediaTrack(id: 0, kind: .video, codec: "AV1", codecID: "V_AV1", uid: 10)
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            tracks: [video, srt, ass, ssa, pgs, unstable]
        )

        XCTAssertEqual(EmbeddedTextSubtitlePolicy.format(for: srt), .subRip)
        XCTAssertEqual(EmbeddedTextSubtitlePolicy.format(for: ass), .ass)
        XCTAssertEqual(EmbeddedTextSubtitlePolicy.format(for: ssa), .ssa)
        XCTAssertNil(EmbeddedTextSubtitlePolicy.format(for: pgs))
        XCTAssertNil(EmbeddedTextSubtitlePolicy.format(for: video))
        XCTAssertEqual(
            EmbeddedTextSubtitlePolicy.editableTracks(in: asset).compactMap(\.uid),
            [12, 13, 14]
        )
    }

    func testEnglishOCRUsesTrackLanguageAndTreatsUnknownAsUnspecified() {
        XCTAssertTrue(
            EmbeddedTextSubtitlePolicy.appliesEnglishOCRRules(
                to: MediaTrack(
                    id: 0, kind: .subtitle, codec: "SRT", language: "en-US")
            ))
        XCTAssertTrue(
            EmbeddedTextSubtitlePolicy.appliesEnglishOCRRules(
                to: MediaTrack(id: 0, kind: .subtitle, codec: "SRT")
            ))
        XCTAssertFalse(
            EmbeddedTextSubtitlePolicy.appliesEnglishOCRRules(
                to: MediaTrack(id: 0, kind: .subtitle, codec: "SRT", language: "fr")
            ))
        XCTAssertFalse(
            EmbeddedTextSubtitlePolicy.appliesEnglishOCRRules(
                to: MediaTrack(id: 0, kind: .subtitle, codec: "SRT", language: "not a tag")
            ))
    }
}
