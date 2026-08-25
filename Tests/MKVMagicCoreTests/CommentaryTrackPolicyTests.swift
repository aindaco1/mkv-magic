import Foundation
import XCTest

@testable import MKVMagicCore

final class CommentaryTrackPolicyTests: XCTestCase {
    func testMarksOnlyClearlyNamedUnmarkedAudioAndSubtitleTracks() throws {
        let audio = MediaTrack(
            id: 1,
            kind: .audio,
            codec: "aac",
            uid: 11,
            language: "eng",
            title: "Director's Commentary",
            isDefault: true,
            isForced: true,
            isEnabled: false,
            isHearingImpaired: true,
            isOriginal: true
        )
        let subtitle = MediaTrack(
            id: 2,
            kind: .subtitle,
            codec: "subrip",
            uid: 12,
            language: "en-US",
            title: "COMMENTARY #2",
            isVisualImpaired: true,
            isTextDescription: true
        )
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Movie.mkv"),
            container: "matroska",
            tracks: [
                audio,
                subtitle,
                MediaTrack(
                    id: 3,
                    kind: .video,
                    codec: "av1",
                    uid: 13,
                    title: "Commentary"
                ),
                MediaTrack(
                    id: 4,
                    kind: .audio,
                    codec: "aac",
                    uid: 14,
                    title: "commentaryless"
                ),
                MediaTrack(
                    id: 5,
                    kind: .audio,
                    codec: "aac",
                    uid: 15,
                    title: "Producer Commentary",
                    isCommentary: true
                ),
            ]
        )

        let edits = try CommentaryTrackPolicy.metadataEdits(in: asset)

        XCTAssertEqual(edits.map(\.trackUID), [11, 12])
        XCTAssertEqual(edits.map(\.name), [audio.title, subtitle.title])
        XCTAssertEqual(edits.map(\.language), ["eng", "en-US"])
        XCTAssertTrue(edits.allSatisfy(\.isCommentary))
        XCTAssertEqual(edits[0].isDefault, audio.isDefault)
        XCTAssertEqual(edits[0].isForced, audio.isForced)
        XCTAssertEqual(edits[0].isEnabled, audio.isEnabled)
        XCTAssertEqual(edits[0].isHearingImpaired, audio.isHearingImpaired)
        XCTAssertEqual(edits[0].isOriginal, audio.isOriginal)
        XCTAssertEqual(edits[1].isVisualImpaired, subtitle.isVisualImpaired)
        XCTAssertEqual(edits[1].isTextDescription, subtitle.isTextDescription)
    }

    func testRefusesMissingOrDuplicateCommentaryTrackUIDs() {
        let missing = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Missing.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    title: "Commentary"
                )
            ]
        )
        XCTAssertThrowsError(try CommentaryTrackPolicy.metadataEdits(in: missing)) {
            XCTAssertEqual($0 as? CommentaryTrackPolicyError, .unstableTrackIdentity)
        }

        let duplicate = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Duplicate.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    uid: 42,
                    title: "Audio Commentary"
                ),
                MediaTrack(
                    id: 2,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 42,
                    title: "Commentary Subs"
                ),
            ]
        )
        XCTAssertThrowsError(try CommentaryTrackPolicy.metadataEdits(in: duplicate)) {
            XCTAssertEqual($0 as? CommentaryTrackPolicyError, .unstableTrackIdentity)
        }
    }
}
