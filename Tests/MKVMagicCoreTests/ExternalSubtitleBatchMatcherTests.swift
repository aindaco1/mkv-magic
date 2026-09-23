import Foundation
import XCTest

@testable import MKVMagicCore

final class ExternalSubtitleBatchMatcherTests: XCTestCase {
    func testIncludesEveryConfidentLanguageAndRoleMatch() throws {
        let videos = [
            asset("Feature.2025.1080p.BluRay.H264.AAC5.1.English.mp4"), asset("Other.2025.mp4"),
        ]
        let subtitles = ["Feature.2025.en.srt", "Feature.2025.es.srt", "Feature.2025.en.sdh.srt"]
            .map(asset)
        let matches = ExternalSubtitleBatchMatcher.associate(media: videos, subtitles: subtitles)
        XCTAssertEqual(matches.map(\.subtitleID), subtitles.map(\.id))
        XCTAssertEqual(matches.map(\.suggestedMediaID), Array(repeating: videos[0].id, count: 3))
        XCTAssertTrue(matches.allSatisfy { $0.confidence == .high })
        XCTAssertEqual(FilenameLanguageInference.language(in: videos[0].sourceURL), "en")
    }

    func testDuplicateTitlesAreNotResolvedByFolderOrInputOrdering() {
        let videos = [asset("Feature.2025.mp4"), asset("/Elsewhere/Feature.2025.mp4")]
        let subtitle = asset("Feature.2025.es.srt")
        for order in [videos, videos.reversed().map { $0 }] {
            let match = ExternalSubtitleBatchMatcher.associate(media: order, subtitles: [subtitle])[
                0]
            XCTAssertNil(match.suggestedMediaID)
            XCTAssertEqual(Set(match.candidateMediaIDs), Set(videos.map(\.id)))
            XCTAssertEqual(match.confidence, .medium)
        }
    }

    func testSimilarNamesAreCandidatesNotAutomaticAssignments() {
        let video = asset("A.Quiet.Summer.Night.2025.mp4")
        let subtitle = asset("A.Quiet.Summer.Night.Special.2025.en.srt")
        let match = ExternalSubtitleBatchMatcher.associate(media: [video], subtitles: [subtitle])[0]
        XCTAssertNil(match.suggestedMediaID)
        XCTAssertEqual(match.candidateMediaIDs, [video.id])
        XCTAssertEqual(match.confidence, .medium)
    }

    func testNeverAutoPairsDifferentEpisodesYearsPartsOrCutsWithSharedPrefixes() {
        for (videoName, subtitleName) in [
            ("Long.Series.Title.S01E01.mp4", "Long.Series.Title.S01E02.en.srt"),
            ("Long.Movie.Title.2024.mp4", "Long.Movie.Title.2025.en.srt"),
            ("Long.Movie.Title.Part1.mp4", "Long.Movie.Title.Part2.en.srt"),
            ("Long.Movie.Title.2025.Extended.mp4", "Long.Movie.Title.2025.Theatrical.en.srt"),
            ("Series.2025.08.01.mp4", "Series.2025.08.02.en.srt"),
            ("Feature.2025.mp4", "Feature.2025.Special.Edition.en.srt"),
            ("Feature.2025.mp4", "Feature.2025.Custom.Cut.en.srt"),
        ] {
            let match = ExternalSubtitleBatchMatcher.associate(
                media: [asset(videoName)], subtitles: [asset(subtitleName)])[0]
            XCTAssertNil(
                match.suggestedMediaID, "Unsafe automatic match: \(videoName) / \(subtitleName)")
        }
    }

    func testUnmatchedAndNumericTitlesRemainReviewable() {
        let video = asset("1917.2019.mp4")
        let subtitles = [asset("1917.2019.en.srt"), asset("Unrelated.fr.srt")]
        let matches = ExternalSubtitleBatchMatcher.associate(media: [video], subtitles: subtitles)
        XCTAssertEqual(matches[0].suggestedMediaID, video.id)
        XCTAssertNil(matches[1].suggestedMediaID)
        XCTAssertTrue(matches[1].candidateMediaIDs.isEmpty)
    }

    private func asset(_ filename: String) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(
                fileURLWithPath: filename.hasPrefix("/") ? filename : "/Media/\(filename)"),
            container: "")
    }
}
