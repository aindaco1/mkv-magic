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

    func testTrackRemovalVerifierAcceptsOnlySelectedUIDRemovalAndRenumbering() throws {
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10, language: "und")
        let audio = MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 20, language: "en")
        let subtitle = MediaTrack(
            id: 2, kind: .subtitle, codec: "subrip", uid: 30, language: "en")
        let renumberedSubtitle = MediaTrack(
            id: 1, kind: .subtitle, codec: "subrip", uid: 30, language: "en")
        let original = asset(title: "Movie", tracks: [video, audio, subtitle])
        let output = asset(
            title: "Movie",
            tracks: [video, renumberedSubtitle],
            segmentUID: "2233",
            encoder: "mkvmerge"
        )

        XCTAssertNoThrow(
            try TrackRemovalOutputVerifier().verify(
                original: original,
                output: output,
                removal: TrackRemoval(trackUIDs: [20])
            ))
    }

    func testTrackRemovalVerifierRejectsRetainedTrackMutation() throws {
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)
        let audio = MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 20)
        let mutated = MediaTrack(id: 0, kind: .video, codec: "hevc", uid: 10)

        XCTAssertThrowsError(
            try TrackRemovalOutputVerifier().verify(
                original: asset(title: "Movie", tracks: [video, audio]),
                output: asset(
                    title: "Movie", tracks: [mutated], segmentUID: "2233", encoder: "mkvmerge"),
                removal: TrackRemoval(trackUIDs: [20])
            )
        ) { error in
            XCTAssertEqual(error as? OutputVerificationError, .tracksChanged)
        }
    }

    func testTrackRemovalVerifierRejectsMaterialDurationChange() throws {
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)
        let audio = MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 20)
        let original = asset(title: "Movie", tracks: [video, audio])
        let output = asset(
            title: "Movie",
            tracks: [video],
            duration: MediaTime(seconds: 9.9)!,
            segmentUID: "2233",
            encoder: "mkvmerge"
        )

        XCTAssertThrowsError(
            try TrackRemovalOutputVerifier().verify(
                original: original,
                output: output,
                removal: TrackRemoval(trackUIDs: [20])
            )
        ) { error in
            XCTAssertEqual(error as? OutputVerificationError, .durationChanged)
        }
    }

    private func asset(
        title: String,
        tracks: [MediaTrack] = [
            MediaTrack(id: 0, kind: .audio, codec: "aac", language: "eng")
        ],
        duration: MediaTime = MediaTime(seconds: 10)!,
        segmentUID: String = "0011",
        encoder: String = "fixture"
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Movie.mkv"),
            container: "matroska",
            duration: duration,
            fileSize: 1_024,
            tracks: tracks,
            chapters: [ChapterNode(title: "Chapter 1", start: .zero)],
            attachments: [
                MediaAttachment(id: 1, filename: "Font.otf", mimeType: "font/otf", size: 20)
            ],
            metadata: ["title": title, "encoder": encoder],
            chapterEntryCount: 1,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: segmentUID
        )
    }
}
