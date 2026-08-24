import Foundation
import XCTest

@testable import MKVMagicCore

final class MediaFilenameNormalizationTests: XCTestCase {
    func testNormalizesCommonMovieReleaseNamesForJellyfinAndPlex() {
        let cases = [
            (
                "Eddington.2025.1080p.10bit.BluRay.8CH.X265.HEVC-PSA.clean.mkv",
                "Eddington (2025).mkv"
            ),
            (
                "Plainclothes.2025.1080p.AMZN.WEB-DL.DDP5.1h265.mkv",
                "Plainclothes (2025).mkv"
            ),
            (
                "The_Phoenician_Scheme (2025) (1080p BluRay).mkv",
                "The Phoenician Scheme (2025).mkv"
            ),
            (
                "2001.A.Space.Odyssey.1968.1080p.BluRay.mkv",
                "2001 A Space Odyssey (1968).mkv"
            ),
            ("A.Movie_With.Dots.mkv", "A Movie With Dots.mkv"),
        ]

        for (sourceName, expected) in cases {
            XCTAssertEqual(
                MediaFilenameNormalizationPolicy.suggestedFilename(
                    for: URL(fileURLWithPath: "/media/\(sourceName)")
                ),
                expected,
                sourceName
            )
        }
    }

    func testAlreadyCleanAndUnhelpfulNamesDoNotCreateSuggestions() {
        for sourceName in [
            "Movie (2025).mkv",
            "Movie.mkv",
            ".mkv",
        ] {
            XCTAssertNil(
                MediaFilenameNormalizationPolicy.suggestedFilename(
                    for: URL(fileURLWithPath: "/media/\(sourceName)")
                ),
                sourceName
            )
        }
    }

    func testPreservesExtensionSpellingAndRejectsOutOfRangeYears() {
        XCTAssertEqual(
            MediaFilenameNormalizationPolicy.suggestedFilename(
                for: URL(fileURLWithPath: "/media/Movie_Name.MKV")
            ),
            "Movie Name.MKV"
        )
        XCTAssertEqual(
            MediaFilenameNormalizationPolicy.suggestedFilename(
                for: URL(fileURLWithPath: "/media/Movie.1800.Release.mkv")
            ),
            "Movie 1800 Release.mkv"
        )
    }
}
