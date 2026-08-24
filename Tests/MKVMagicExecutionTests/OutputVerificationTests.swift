import Foundation
import MKVMagicCore
import MKVMagicPlanning
import XCTest

@testable import MKVMagicExecution

final class OutputVerificationTests: XCTestCase {
    func testUnchangedCopyVerifierAcceptsOnlyPreservedInspectionFacts() throws {
        let original = asset(title: "Movie")

        XCTAssertNoThrow(
            try UnchangedCopyOutputVerifier().verify(
                original: original,
                output: asset(title: "Movie")
            )
        )
        XCTAssertThrowsError(
            try UnchangedCopyOutputVerifier().verify(
                original: original,
                output: asset(title: "Changed")
            )
        ) { error in
            XCTAssertEqual(error as? OutputVerificationError, .tagsChanged)
        }
    }

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

    func testTrackRemovalVerifierAllowsOnlyRequestedSegmentTitleRemoval() throws {
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)
        let audio = MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 20)
        let original = asset(title: "Movie", tracks: [video, audio])
        var output = asset(
            title: "",
            tracks: [video],
            segmentUID: "2233",
            encoder: "mkvmerge"
        )
        output = MediaAsset(
            sourceURL: output.sourceURL,
            container: output.container,
            duration: output.duration,
            fileSize: output.fileSize,
            tracks: output.tracks,
            chapters: output.chapters,
            attachments: output.attachments,
            metadata: ["encoder": "mkvmerge"],
            chapterEntryCount: output.chapterEntryCount,
            globalTagCount: output.globalTagCount,
            trackTagCount: output.trackTagCount,
            segmentUID: output.segmentUID
        )

        XCTAssertNoThrow(
            try TrackRemovalOutputVerifier().verify(
                original: original,
                output: output,
                removal: TrackRemoval(trackUIDs: [20]),
                segmentTitle: .set(nil)
            )
        )

        XCTAssertThrowsError(
            try TrackRemovalOutputVerifier().verify(
                original: original,
                output: asset(
                    title: "Wrong",
                    tracks: [video],
                    segmentUID: "2233",
                    encoder: "mkvmerge"
                ),
                removal: TrackRemoval(trackUIDs: [20]),
                segmentTitle: .set(nil)
            )
        ) { error in
            XCTAssertEqual(error as? OutputVerificationError, .titleMismatch)
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

    func testExternalSubtitleVerifierAcceptsOneReviewedSRTAddedLast() throws {
        let audio = MediaTrack(
            id: 0, kind: .audio, codec: "aac", uid: 20, language: "eng")
        let added = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 30,
            language: "en",
            title: "English SDH",
            isDefault: true,
            isHearingImpaired: true
        )
        let original = asset(title: "Movie", tracks: [audio])
        let output = asset(
            title: "Movie",
            tracks: [audio, added],
            segmentUID: "2233",
            encoder: "mkvmerge"
        )

        XCTAssertNoThrow(
            try ExternalSubtitleMuxOutputVerifier().verify(
                original: original,
                output: output,
                expectedMetadata: ExternalSubtitleTrackMetadata(
                    language: "eng",
                    name: "English SDH",
                    isDefault: true,
                    isHearingImpaired: true
                ),
                subtitleEnd: SubRipTimestamp(milliseconds: 9_500)
            ))
    }

    func testExternalSubtitleVerifierAcceptsReviewedRemovalAndTitleDeletionTogether() throws {
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)
        let french = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            uid: 20,
            language: "fr"
        )
        let added = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 30,
            language: "en"
        )
        let verifier = ExternalSubtitleMuxOutputVerifier()
        let original = asset(title: "Movie", tracks: [video, french], trackTagCount: 2)
        let validOutput = asset(
            title: nil,
            tracks: [video, added],
            segmentUID: "2233",
            encoder: "mkvmerge",
            trackTagCount: 1
        )

        XCTAssertNoThrow(
            try verifier.verify(
                original: original,
                output: validOutput,
                expectedMetadata: ExternalSubtitleTrackMetadata(language: "en"),
                subtitleEnd: SubRipTimestamp(milliseconds: 9_500),
                trackRemoval: TrackRemoval(trackUIDs: [20]),
                segmentTitle: .set(nil)
            )
        )
        XCTAssertThrowsError(
            try verifier.verify(
                original: original,
                output: asset(
                    title: nil,
                    tracks: [video, french, added],
                    segmentUID: "2233",
                    encoder: "mkvmerge",
                    trackTagCount: 1
                ),
                expectedMetadata: ExternalSubtitleTrackMetadata(language: "en"),
                subtitleEnd: SubRipTimestamp(milliseconds: 9_500),
                trackRemoval: TrackRemoval(trackUIDs: [20]),
                segmentTitle: .set(nil)
            )
        ) { error in
            XCTAssertEqual(error as? OutputVerificationError, .tracksChanged)
        }
    }

    func testExternalSubtitleVerifierRejectsRetainedTrackMutation() throws {
        let originalTrack = MediaTrack(
            id: 0, kind: .audio, codec: "aac", uid: 20, language: "en")
        let mutatedTrack = MediaTrack(
            id: 0, kind: .audio, codec: "opus", uid: 20, language: "en")
        let added = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 30,
            language: "en"
        )

        XCTAssertThrowsError(
            try ExternalSubtitleMuxOutputVerifier().verify(
                original: asset(title: "Movie", tracks: [originalTrack]),
                output: asset(
                    title: "Movie",
                    tracks: [mutatedTrack, added],
                    segmentUID: "2233",
                    encoder: "mkvmerge"
                ),
                expectedMetadata: ExternalSubtitleTrackMetadata(language: "en"),
                subtitleEnd: SubRipTimestamp(milliseconds: 9_500)
            )
        ) { error in
            XCTAssertEqual(error as? OutputVerificationError, .tracksChanged)
        }
    }

    func testExternalSubtitleVerifierRejectsUnrepresentableDurationWithoutOverflow() throws {
        let audio = MediaTrack(
            id: 0, kind: .audio, codec: "aac", uid: 20, language: "en")
        let added = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 30,
            language: "en"
        )

        XCTAssertThrowsError(
            try ExternalSubtitleMuxOutputVerifier().verify(
                original: asset(title: "Movie", tracks: [audio]),
                output: asset(
                    title: "Movie",
                    tracks: [audio, added],
                    segmentUID: "2233",
                    encoder: "mkvmerge"
                ),
                expectedMetadata: ExternalSubtitleTrackMetadata(language: "en"),
                subtitleEnd: SubRipTimestamp(milliseconds: Int64.max)
            )
        ) { error in
            XCTAssertEqual(error as? OutputVerificationError, .durationChanged)
        }
    }

    func testExternalSubtitleVerifierRejectsLostTrackTags() throws {
        let audio = MediaTrack(
            id: 0, kind: .audio, codec: "aac", uid: 20, language: "en")
        let added = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 30,
            language: "en"
        )

        XCTAssertThrowsError(
            try ExternalSubtitleMuxOutputVerifier().verify(
                original: asset(title: "Movie", tracks: [audio], trackTagCount: 2),
                output: asset(
                    title: "Movie",
                    tracks: [audio, added],
                    segmentUID: "2233",
                    encoder: "mkvmerge",
                    trackTagCount: 0
                ),
                expectedMetadata: ExternalSubtitleTrackMetadata(language: "en"),
                subtitleEnd: SubRipTimestamp(milliseconds: 9_500)
            )
        ) { error in
            XCTAssertEqual(error as? OutputVerificationError, .tagsChanged)
        }
    }

    func testExternalSubtitleVerifierRequiresReviewedAdvancedSubtitleCodec() throws {
        let audio = MediaTrack(
            id: 0, kind: .audio, codec: "aac", uid: 20, language: "en")
        let added = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "SubStationAlpha",
            codecID: "S_TEXT/ASS",
            uid: 30,
            language: "en",
            title: "Styled"
        )
        let original = asset(title: "Movie", tracks: [audio])
        let output = asset(
            title: "Movie",
            tracks: [audio, added],
            segmentUID: "2233",
            encoder: "mkvmerge"
        )
        let verifier = ExternalSubtitleMuxOutputVerifier()

        XCTAssertNoThrow(
            try verifier.verify(
                original: original,
                output: output,
                expectedMetadata: ExternalSubtitleTrackMetadata(
                    language: "en",
                    name: "Styled"
                ),
                expectedFormat: .ass,
                subtitleEnd: SubRipTimestamp(milliseconds: 9_500)
            )
        )
        XCTAssertThrowsError(
            try verifier.verify(
                original: original,
                output: output,
                expectedMetadata: ExternalSubtitleTrackMetadata(
                    language: "en",
                    name: "Styled"
                ),
                expectedFormat: .ssa,
                subtitleEnd: SubRipTimestamp(milliseconds: 9_500)
            )
        ) { error in
            XCTAssertEqual(error as? OutputVerificationError, .tracksChanged)
        }
    }

    func testEmbeddedSubtitleReplacementVerifierAcceptsSameTrackAtSamePositionAndUID() throws {
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", codecID: "V_AV1", uid: 10)
        let subtitle = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 20,
            language: "en",
            title: "English",
            isDefault: true
        )
        let audio = MediaTrack(id: 2, kind: .audio, codec: "aac", uid: 30, language: "en")
        let original = asset(title: "Movie", tracks: [video, subtitle, audio])
        let output = asset(
            title: "Movie",
            tracks: [video, subtitle, audio],
            segmentUID: "2233",
            encoder: "mkvmerge"
        )

        XCTAssertNoThrow(
            try EmbeddedSubtitleReplacementOutputVerifier().verify(
                original: original,
                output: output,
                replacedTrackUID: 20,
                expectedFormat: .subRip
            ))
    }

    func testEmbeddedSubtitleReplacementVerifierRejectsUIDMetadataOrOrderDrift() throws {
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", codecID: "V_AV1", uid: 10)
        let subtitle = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 20,
            language: "en",
            isForced: true
        )
        let audio = MediaTrack(id: 2, kind: .audio, codec: "aac", uid: 30)
        let replacementWithNewUID = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 99,
            language: "en"
        )
        let verifier = EmbeddedSubtitleReplacementOutputVerifier()

        for tracks in [
            [video, replacementWithNewUID, audio],
            [video, audio, subtitle],
        ] {
            XCTAssertThrowsError(
                try verifier.verify(
                    original: asset(title: "Movie", tracks: [video, subtitle, audio]),
                    output: asset(
                        title: "Movie",
                        tracks: tracks,
                        segmentUID: "2233",
                        encoder: "mkvmerge"
                    ),
                    replacedTrackUID: 20,
                    expectedFormat: .subRip
                )
            ) { error in
                XCTAssertEqual(error as? OutputVerificationError, .tracksChanged)
            }
        }
    }

    func testCompleteAudioConversionVerifierAcceptsOnlyReviewedAudioChanges() throws {
        let sourceTracks = [
            MediaTrack(
                id: 0,
                kind: .video,
                codec: "av1",
                codecID: "V_AV1",
                dimensions: MediaDimensions(width: 1920, height: 1080),
                bitDepth: 10
            ),
            MediaTrack(
                id: 1,
                kind: .audio,
                codec: "aac",
                codecID: "A_AAC",
                language: "en",
                title: "Main",
                isDefault: true,
                channels: 6,
                channelLayout: "5.1",
                sampleRate: 48_000
            ),
            MediaTrack(
                id: 2,
                kind: .subtitle,
                codec: "subrip",
                codecID: "S_TEXT/UTF8",
                language: "en"
            ),
        ]
        let original = asset(title: "Movie", tracks: sourceTracks)
        let plan = try CompleteAudioConversionPlanner().resolve(
            source: original,
            preset: .flacLossless,
            availableAudioPresets: [.flacLossless]
        )
        let outputTracks = [
            sourceTracks[0],
            MediaTrack(
                id: 1,
                kind: .audio,
                codec: "flac",
                codecID: "A_FLAC",
                language: "en",
                title: "Main",
                isDefault: true,
                channels: 6,
                channelLayout: "5.1",
                sampleRate: 48_000
            ),
            sourceTracks[2],
        ]
        let output = asset(
            title: "Movie",
            tracks: outputTracks,
            segmentUID: "2233",
            encoder: "ffmpeg"
        )
        let chapters = MatroskaChapterDocument(editions: [
            MatroskaChapterEdition(
                chapters: [
                    MatroskaChapterAtom(
                        start: .zero,
                        displays: [ChapterDisplay(title: "Chapter 1")]
                    )
                ]
            )
        ])
        let verifier = CompleteAudioConversionOutputVerifier()

        XCTAssertNoThrow(
            try verifier.verify(
                resolvedPlan: plan,
                chapters: chapters,
                output: output
            )
        )

        var changedVideo = outputTracks
        changedVideo[0] = MediaTrack(
            id: 0,
            kind: .video,
            codec: "hevc",
            codecID: "V_MPEGH/ISO/HEVC",
            dimensions: MediaDimensions(width: 1920, height: 1080),
            bitDepth: 10
        )
        XCTAssertThrowsError(
            try verifier.verify(
                resolvedPlan: plan,
                chapters: chapters,
                output: asset(
                    title: "Movie",
                    tracks: changedVideo,
                    segmentUID: "2233",
                    encoder: "ffmpeg"
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? CompleteAudioConversionVerificationError,
                .copiedTrackMismatch(trackID: 0)
            )
        }
    }

    private func asset(
        title: String?,
        tracks: [MediaTrack] = [
            MediaTrack(id: 0, kind: .audio, codec: "aac", language: "eng")
        ],
        duration: MediaTime = MediaTime(seconds: 10)!,
        segmentUID: String = "0011",
        encoder: String = "fixture",
        trackTagCount: Int = 0
    ) -> MediaAsset {
        var metadata = ["encoder": encoder]
        if let title { metadata["title"] = title }
        return MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Movie.mkv"),
            container: "matroska",
            duration: duration,
            fileSize: 1_024,
            tracks: tracks,
            chapters: [ChapterNode(title: "Chapter 1", start: .zero)],
            attachments: [
                MediaAttachment(id: 1, filename: "Font.otf", mimeType: "font/otf", size: 20)
            ],
            metadata: metadata,
            chapterEntryCount: 1,
            globalTagCount: 0,
            trackTagCount: trackTagCount,
            segmentUID: segmentUID
        )
    }
}
