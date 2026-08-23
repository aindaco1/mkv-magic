import Foundation
import XCTest

@testable import MKVMagicCore

final class ExternalSubtitleMatcherTests: XCTestCase {
    func testInfersTrailingLanguageAndRolesWithHighTitleYearMatch() {
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/The Movie (2024).mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 100)
        )
        let subtitle = SubRipDocument(cues: [cue(end: 98_000)])

        let match = ExternalSubtitleMatcher().match(
            media: media,
            subtitleURL: URL(fileURLWithPath: "/Media/The.Movie.2024.en.forced.sdh.srt"),
            subtitle: subtitle
        )

        XCTAssertEqual(match.confidence, .high)
        XCTAssertTrue(match.reasons.contains(.normalizedTitleAndYear))
        XCTAssertTrue(match.reasons.contains(.durationCompatible))
        XCTAssertEqual(
            match.suggestedMetadata,
            ExternalSubtitleTrackMetadata(
                language: "en",
                name: "Forced SDH",
                isForced: true,
                isHearingImpaired: true
            )
        )
    }

    func testDoesNotTreatLanguageWordInsideTitleAsMetadata() {
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/The English Patient.mkv"),
            container: "matroska"
        )

        let match = ExternalSubtitleMatcher().match(
            media: media,
            subtitleURL: URL(fileURLWithPath: "/Media/The English Patient.srt"),
            subtitle: SubRipDocument(cues: [cue(end: 1_000)])
        )

        XCTAssertEqual(match.confidence, .high)
        XCTAssertTrue(match.reasons.contains(.exactBasename))
        XCTAssertEqual(match.suggestedMetadata.language, "und")

        let trailingLanguageWord = ExternalSubtitleMatcher().match(
            media: MediaAsset(
                sourceURL: URL(fileURLWithPath: "/Media/The English.mkv"),
                container: "matroska"
            ),
            subtitleURL: URL(fileURLWithPath: "/Media/The English.srt"),
            subtitle: SubRipDocument(cues: [cue(end: 1_000)])
        )
        XCTAssertEqual(trailingLanguageWord.confidence, .high)
        XCTAssertEqual(trailingLanguageWord.suggestedMetadata.language, "und")
    }

    func testEpisodeMatchRanksButDoesNotInventLanguageOrDurationCompatibility() {
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Series.S01E02.1080p.mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 3_600)
        )

        let match = ExternalSubtitleMatcher().match(
            media: media,
            subtitleURL: URL(fileURLWithPath: "/Other/Series.S01E02.Special.srt"),
            subtitle: SubRipDocument(cues: [cue(end: 30_000)])
        )

        XCTAssertEqual(match.confidence, .low)
        XCTAssertTrue(match.reasons.contains(.episodeIdentifier))
        XCTAssertFalse(match.reasons.contains(.durationCompatible))
        XCTAssertEqual(match.suggestedMetadata.language, "und")
        XCTAssertEqual(match.isDurationCompatible, false)
    }

    func testUnrepresentableDurationDifferenceFailsClosedWithoutOverflow() {
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            duration: MediaTime(nanoseconds: Int64.min)
        )
        let document = SubRipDocument(
            cues: [
                SubRipCue(
                    id: 0,
                    start: SubRipTimestamp(milliseconds: 0),
                    end: SubRipTimestamp(milliseconds: Int64.max),
                    lines: ["Text"]
                )
            ])

        let match = ExternalSubtitleMatcher().match(
            media: media,
            subtitleURL: URL(fileURLWithPath: "/Media/Movie.en.srt"),
            subtitle: document
        )

        XCTAssertEqual(match.isDurationCompatible, false)
        XCTAssertEqual(match.durationDifferenceMilliseconds, Int64.max)
    }

    private func cue(end: Int64) -> SubRipCue {
        SubRipCue(
            id: 0,
            start: SubRipTimestamp(milliseconds: 0),
            end: SubRipTimestamp(milliseconds: end),
            lines: ["Text"]
        )
    }
}
