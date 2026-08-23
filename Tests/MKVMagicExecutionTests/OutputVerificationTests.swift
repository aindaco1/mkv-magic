import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicExecution

final class OutputVerificationTests: XCTestCase {
    func testSegmentTitleVerificationAcceptsOnlyIntendedMetadataChange() throws {
        let original = asset(title: "Old")
        let output = asset(title: "New")

        XCTAssertNoThrow(
            try SegmentTitleOutputVerifier().verify(
                original: original,
                output: output,
                expectedTitle: "New"
            ))
    }

    func testSegmentTitleVerificationRejectsTrackChange() throws {
        let original = asset(title: "Old")
        let changedTrack = MediaTrack(id: 0, kind: .audio, codec: "opus", language: "eng")
        let output = asset(title: "New", tracks: [changedTrack])

        do {
            try SegmentTitleOutputVerifier().verify(
                original: original,
                output: output,
                expectedTitle: "New"
            )
            XCTFail("Expected track change refusal")
        } catch {
            XCTAssertEqual(error as? OutputVerificationError, .tracksChanged)
        }
    }

    func testTrackMetadataVerifierAcceptsOnlyTheSelectedSemanticChanges() throws {
        let originalTrack = MediaTrack(
            id: 0,
            kind: .audio,
            codec: "aac",
            uid: 42,
            language: "en",
            title: "Main",
            isDefault: true
        )
        let outputTrack = MediaTrack(
            id: 0,
            kind: .audio,
            codec: "aac",
            uid: 42,
            language: "es",
            title: "Spanish",
            isForced: true,
            isCommentary: true
        )
        let edit = TrackMetadataEdit(
            trackUID: 42,
            name: "Spanish",
            language: "spa",
            isDefault: false,
            isForced: true,
            isEnabled: true,
            isCommentary: true,
            isHearingImpaired: false,
            isVisualImpaired: false,
            isOriginal: false,
            isTextDescription: false
        )

        XCTAssertNoThrow(
            try TrackMetadataOutputVerifier().verify(
                original: asset(title: "Movie", tracks: [originalTrack]),
                output: asset(title: "Movie", tracks: [outputTrack]),
                expectedEdit: edit
            ))
    }

    func testTrackMetadataVerifierRejectsUnrelatedCodecChange() throws {
        let originalTrack = MediaTrack(
            id: 0, kind: .audio, codec: "aac", uid: 42, language: "en", title: "Main")
        let outputTrack = MediaTrack(
            id: 0, kind: .audio, codec: "opus", uid: 42, language: "es", title: "Spanish")
        let edit = TrackMetadataEdit(
            trackUID: 42,
            name: "Spanish",
            language: "es",
            isDefault: false,
            isForced: false,
            isEnabled: true,
            isCommentary: false,
            isHearingImpaired: false,
            isVisualImpaired: false,
            isOriginal: false,
            isTextDescription: false
        )

        XCTAssertThrowsError(
            try TrackMetadataOutputVerifier().verify(
                original: asset(title: "Movie", tracks: [originalTrack]),
                output: asset(title: "Movie", tracks: [outputTrack]),
                expectedEdit: edit
            )
        ) { error in
            XCTAssertEqual(error as? OutputVerificationError, .tracksChanged)
        }
    }

    private func asset(
        title: String,
        tracks: [MediaTrack] = [
            MediaTrack(id: 0, kind: .audio, codec: "aac", language: "eng")
        ]
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Movie.mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: 1_024,
            tracks: tracks,
            chapters: [ChapterNode(title: "Chapter 1", start: .zero)],
            attachments: [
                MediaAttachment(id: 1, filename: "Font.otf", mimeType: "font/otf", size: 20)
            ],
            metadata: ["title": title, "encoder": "fixture"],
            chapterEntryCount: 1,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "0011"
        )
    }
}
