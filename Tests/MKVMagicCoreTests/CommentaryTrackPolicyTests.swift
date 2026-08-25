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
            XCTAssertEqual($0 as? TrackRolePolicyError, .unstableTrackIdentity)
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
                    kind: .video,
                    codec: "av1",
                    uid: 42,
                    title: "Main Feature"
                ),
            ]
        )
        XCTAssertThrowsError(try CommentaryTrackPolicy.metadataEdits(in: duplicate)) {
            XCTAssertEqual($0 as? TrackRolePolicyError, .unstableTrackIdentity)
        }
    }

    func testNormalizesAudioAndSubtitleNamesIndependentlyAndPreservesOtherFields() throws {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Normalize.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .audio,
                    codec: "aac",
                    uid: 10,
                    language: "eng",
                    title: "Director Commentary",
                    isDefault: true
                ),
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    uid: 11,
                    language: "en-US",
                    title: "Cast Track",
                    isCommentary: true,
                    isOriginal: true
                ),
                MediaTrack(
                    id: 2,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 12,
                    title: "Commentary subtitles",
                    isHearingImpaired: true
                ),
                MediaTrack(
                    id: 3,
                    kind: .audio,
                    codec: "aac",
                    uid: 13,
                    title: "commentaryless"
                ),
            ]
        )

        let edits = try CommentaryNamePolicy.metadataEdits(in: asset)

        XCTAssertEqual(edits.map(\.trackUID), [10, 11, 12])
        XCTAssertEqual(edits.map(\.name), ["Commentary", "Commentary #2", "Commentary"])
        XCTAssertEqual(edits.map(\.language), ["eng", "en-US", "und"])
        XCTAssertTrue(edits[0].isDefault)
        XCTAssertFalse(edits[0].isCommentary)
        XCTAssertTrue(edits[1].isCommentary)
        XCTAssertTrue(edits[1].isOriginal)
        XCTAssertTrue(edits[2].isHearingImpaired)

        let normalized = MediaAsset(
            sourceURL: asset.sourceURL,
            container: asset.container,
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .audio,
                    codec: "aac",
                    uid: 10,
                    title: "Commentary",
                    isCommentary: true
                ),
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    uid: 11,
                    title: "Commentary #2",
                    isCommentary: true
                ),
            ]
        )
        XCTAssertEqual(try CommentaryNamePolicy.metadataEdits(in: normalized), [])
    }

    func testNameNormalizationRequiresStableIdentityOnlyWhenANameChanges() throws {
        let alreadyNormalizedWithoutUID = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Stable.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .audio,
                    codec: "aac",
                    title: "Commentary",
                    isCommentary: true
                )
            ]
        )
        XCTAssertEqual(
            try CommentaryNamePolicy.metadataEdits(in: alreadyNormalizedWithoutUID),
            []
        )

        let needsChangeWithoutUID = MediaAsset(
            sourceURL: alreadyNormalizedWithoutUID.sourceURL,
            container: alreadyNormalizedWithoutUID.container,
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .audio,
                    codec: "aac",
                    title: "Director Commentary"
                )
            ]
        )
        XCTAssertThrowsError(try CommentaryNamePolicy.metadataEdits(in: needsChangeWithoutUID)) {
            XCTAssertEqual($0 as? TrackRolePolicyError, .unstableTrackIdentity)
        }

        let duplicateUID = MediaAsset(
            sourceURL: alreadyNormalizedWithoutUID.sourceURL,
            container: alreadyNormalizedWithoutUID.container,
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .audio,
                    codec: "aac",
                    uid: 7,
                    title: "Director Commentary"
                ),
                MediaTrack(
                    id: 1,
                    kind: .video,
                    codec: "av1",
                    uid: 7
                ),
            ]
        )
        XCTAssertThrowsError(try CommentaryNamePolicy.metadataEdits(in: duplicateUID)) {
            XCTAssertEqual($0 as? TrackRolePolicyError, .unstableTrackIdentity)
        }
    }

    func testMarksOnlyClearlyNamedUnforcedSubtitleTracks() throws {
        let source = MediaTrack(
            id: 0,
            kind: .subtitle,
            codec: "subrip",
            uid: 10,
            language: "en-US",
            title: "English FORCED",
            isDefault: true,
            isEnabled: false,
            isHearingImpaired: true
        )
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Forced.mkv"),
            container: "matroska",
            tracks: [
                source,
                MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 11,
                    title: "unforced"
                ),
                MediaTrack(
                    id: 2,
                    kind: .audio,
                    codec: "aac",
                    uid: 12,
                    title: "Forced"
                ),
                MediaTrack(
                    id: 3,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 13,
                    title: "Forced",
                    isForced: true
                ),
            ]
        )

        let edits = try ForcedSubtitlePolicy.metadataEdits(in: asset)

        XCTAssertEqual(edits.map(\.trackUID), [10])
        XCTAssertEqual(edits.first?.name, source.title)
        XCTAssertEqual(edits.first?.language, "en-US")
        XCTAssertTrue(edits.first?.isForced == true)
        XCTAssertTrue(edits.first?.isDefault == true)
        XCTAssertTrue(edits.first?.isEnabled == false)
        XCTAssertTrue(edits.first?.isHearingImpaired == true)
    }

    func testForcedSubtitleMarkingRequiresAUIDUniqueAcrossEveryTrack() {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Unstable Forced.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 9,
                    title: "Forced"
                ),
                MediaTrack(id: 1, kind: .video, codec: "av1", uid: 9),
            ]
        )

        XCTAssertThrowsError(try ForcedSubtitlePolicy.metadataEdits(in: asset)) {
            XCTAssertEqual($0 as? TrackRolePolicyError, .unstableTrackIdentity)
        }
    }

    func testMarksOnlyClearlyNamedUnmarkedHearingImpairedSubtitles() throws {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/SDH.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 10,
                    language: "en",
                    title: "English SDH",
                    isDefault: true
                ),
                MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 11,
                    title: "English CC",
                    isForced: true
                ),
                MediaTrack(
                    id: 2,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 12,
                    title: "Hearing-Impaired"
                ),
                MediaTrack(
                    id: 3,
                    kind: .audio,
                    codec: "aac",
                    uid: 13,
                    title: "SDH"
                ),
                MediaTrack(
                    id: 4,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 14,
                    title: "SDHless"
                ),
                MediaTrack(
                    id: 5,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 15,
                    title: "English SDH",
                    isHearingImpaired: true
                ),
                MediaTrack(
                    id: 6,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 16,
                    title: "English HearingImpaired"
                ),
            ]
        )

        let edits = try HearingImpairedSubtitlePolicy.metadataEdits(in: asset)

        XCTAssertEqual(edits.map(\.trackUID), [10, 11, 12, 16])
        XCTAssertTrue(edits.allSatisfy(\.isHearingImpaired))
        XCTAssertTrue(edits[0].isDefault)
        XCTAssertTrue(edits[1].isForced)
        XCTAssertEqual(edits[2].name, "Hearing-Impaired")
    }

    func testHearingImpairedSubtitleMarkingRequiresUniqueStableIdentity() {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Unstable SDH.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 8,
                    title: "English SDH"
                ),
                MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 8),
            ]
        )

        XCTAssertThrowsError(try HearingImpairedSubtitlePolicy.metadataEdits(in: asset)) {
            XCTAssertEqual($0 as? TrackRolePolicyError, .unstableTrackIdentity)
        }
    }
}
