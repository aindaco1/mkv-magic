import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import XCTest

final class MKVRemuxOutputVerifierTests: XCTestCase {
    func testAcceptsNewMKVWithPreservedTracksMetadataTitleAndChapters() throws {
        let source = asset(url: URL(fileURLWithPath: "/Media/Movie.mp4"), container: "mov")
        let plan = try MKVRemuxPlanner().resolve(source: source)
        let output = asset(
            url: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska,webm",
            segmentUID: "0123456789abcdef0123456789abcdef"
        )

        XCTAssertNoThrow(try MKVRemuxOutputVerifier().verify(plan: plan, output: output))
    }

    func testRejectsCodecMetadataChapterAndTitleDrift() throws {
        let source = asset(url: URL(fileURLWithPath: "/Media/Movie.mp4"), container: "mov")
        let plan = try MKVRemuxPlanner().resolve(source: source)
        let verifier = MKVRemuxOutputVerifier()
        XCTAssertThrowsError(
            try verifier.verify(
                plan: plan,
                output: asset(
                    tracks: [video(codec: "hevc"), audio()],
                    segmentUID: "new"
                )
            )
        ) { XCTAssertEqual($0 as? MKVRemuxVerificationError, .tracksChanged) }
        XCTAssertThrowsError(
            try verifier.verify(
                plan: plan,
                output: asset(
                    tracks: [video(), audio(language: "fra")],
                    segmentUID: "new"
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? MKVRemuxVerificationError,
                .trackMetadataChanged(trackID: 1)
            )
        }
        XCTAssertThrowsError(
            try verifier.verify(
                plan: plan,
                output: asset(chapterTitle: "Changed", segmentUID: "new")
            )
        ) { XCTAssertEqual($0 as? MKVRemuxVerificationError, .chaptersChanged) }
        XCTAssertThrowsError(
            try verifier.verify(
                plan: plan,
                output: asset(title: "Changed", segmentUID: "new")
            )
        ) { XCTAssertEqual($0 as? MKVRemuxVerificationError, .titleChanged) }
    }

    func testDurationToleranceAccepts100MillisecondsAndRejectsAnythingLarger() throws {
        let source = asset(url: URL(fileURLWithPath: "/Media/Movie.mp4"), container: "mov")
        let plan = try MKVRemuxPlanner().resolve(source: source)
        let verifier = MKVRemuxOutputVerifier()

        XCTAssertNoThrow(
            try verifier.verify(
                plan: plan,
                output: asset(
                    duration: MediaTime(nanoseconds: 1_124_000_000),
                    segmentUID: "new"
                )
            )
        )
        XCTAssertThrowsError(
            try verifier.verify(
                plan: plan,
                output: asset(
                    duration: MediaTime(nanoseconds: 1_124_000_001),
                    segmentUID: "new"
                )
            )
        ) { XCTAssertEqual($0 as? MKVRemuxVerificationError, .wrongDuration) }
    }

    func testChapterTimeBaseRoundingUsesTheSameBoundedToleranceAsDuration() throws {
        let source = asset(
            url: URL(fileURLWithPath: "/Media/Movie.mp4"),
            container: "mov"
        )
        let plan = try MKVRemuxPlanner().resolve(source: source)
        let verifier = MKVRemuxOutputVerifier()

        XCTAssertNoThrow(
            try verifier.verify(
                plan: plan,
                output: asset(
                    chapterStart: MediaTime(nanoseconds: 100_000_000),
                    chapterEnd: MediaTime(nanoseconds: 600_000_000),
                    segmentUID: "new"
                )
            )
        )
        XCTAssertThrowsError(
            try verifier.verify(
                plan: plan,
                output: asset(
                    chapterStart: MediaTime(nanoseconds: 100_000_001),
                    segmentUID: "new"
                )
            )
        ) { XCTAssertEqual($0 as? MKVRemuxVerificationError, .chaptersChanged) }
    }

    func testAcceptsReviewedAudioLanguageOverrideAndAppendedSubtitle() throws {
        let source = asset(
            url: URL(fileURLWithPath: "/Media/Movie.en.mp4"),
            container: "mov",
            tracks: [video(), audio(language: "und")]
        )
        let plan = try MKVRemuxPlanner().resolve(source: source)
        let subtitle = MediaTrack(
            id: 2,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            language: "fr",
            title: "French"
        )
        let output = asset(
            tracks: [video(), audio(language: "en"), subtitle],
            segmentUID: "new"
        )

        XCTAssertNoThrow(
            try MKVRemuxOutputVerifier().verify(
                plan: plan,
                output: output,
                trackLanguageOverrides: [1: "eng"],
                appendedSubtitle: MKVRemuxAppendedSubtitleExpectation(
                    metadata: ExternalSubtitleTrackMetadata(
                        language: "fr",
                        name: "French"
                    ),
                    format: .subRip,
                    end: SubRipTimestamp(milliseconds: 1_000)
                )
            )
        )
    }

    func testAppendedSubtitleUsesTheSharedPacketCopyDurationTolerance() throws {
        let source = asset(
            url: URL(fileURLWithPath: "/Media/Movie.en.mp4"),
            container: "mov"
        )
        let plan = try MKVRemuxPlanner().resolve(source: source)
        let subtitle = MediaTrack(
            id: 2,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            language: "en"
        )
        let expectation = MKVRemuxAppendedSubtitleExpectation(
            metadata: ExternalSubtitleTrackMetadata(language: "en"),
            format: .subRip,
            end: SubRipTimestamp(milliseconds: 1_000)
        )
        let verifier = MKVRemuxOutputVerifier()

        XCTAssertNoThrow(
            try verifier.verify(
                plan: plan,
                output: asset(
                    tracks: [video(), audio(), subtitle],
                    duration: MediaTime(nanoseconds: 1_124_000_000),
                    segmentUID: "new"
                ),
                appendedSubtitle: expectation
            )
        )
        XCTAssertThrowsError(
            try verifier.verify(
                plan: plan,
                output: asset(
                    tracks: [video(), audio(), subtitle],
                    duration: MediaTime(nanoseconds: 1_124_000_001),
                    segmentUID: "new"
                ),
                appendedSubtitle: expectation
            )
        ) { XCTAssertEqual($0 as? MKVRemuxVerificationError, .wrongDuration) }
    }

    private func asset(
        url: URL = URL(fileURLWithPath: "/Media/Movie.mkv"),
        container: String = "matroska,webm",
        tracks: [MediaTrack]? = nil,
        title: String = "Fixture",
        chapterTitle: String = "Opening",
        chapterStart: MediaTime = .zero,
        chapterEnd: MediaTime = MediaTime(nanoseconds: 500_000_000),
        duration: MediaTime = MediaTime(nanoseconds: 1_024_000_000),
        segmentUID: String? = nil
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: url,
            container: container,
            duration: duration,
            fileSize: 100,
            tracks: tracks ?? [video(), audio()],
            chapters: [
                ChapterNode(
                    title: chapterTitle,
                    start: chapterStart,
                    end: chapterEnd,
                    language: "eng"
                )
            ],
            metadata: ["title": title],
            chapterEntryCount: 1,
            segmentUID: segmentUID
        )
    }

    private func video(codec: String = "h264") -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: codec,
            profile: "High",
            level: 31,
            isDefault: true,
            dimensions: MediaDimensions(width: 320, height: 180),
            pixelFormat: "yuv420p",
            bitDepth: 8,
            frameRate: "24/1"
        )
    }

    private func audio(language: String = "eng") -> MediaTrack {
        MediaTrack(
            id: 1,
            kind: .audio,
            codec: "aac",
            language: language,
            title: "Main Audio",
            isDefault: true,
            channels: 2,
            channelLayout: "stereo",
            sampleRate: 48_000
        )
    }
}
