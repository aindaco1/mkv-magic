import Foundation
import XCTest

@testable import MKVMagicCore

final class TimedTextSubtitleTests: XCTestCase {
    func testFindsStableTimedTextTracksOnlyInMP4FamilyContainers() {
        let asset = makeAsset(
            tracks: [
                MediaTrack(id: 5, kind: .subtitle, codec: "timed_text"),
                MediaTrack(id: 1, kind: .video, codec: "h264"),
                MediaTrack(id: 3, kind: .subtitle, codec: "mov_text"),
                MediaTrack(id: 4, kind: .subtitle, codec: "subrip"),
            ]
        )

        XCTAssertEqual(
            TimedTextSubtitleConversionPolicy.convertibleTracks(in: asset).map(\.id),
            [3, 5]
        )
        XCTAssertTrue(TimedTextSubtitleConversionPolicy.canOffer(for: asset))
    }

    func testRejectsMismatchedContainersAndUnstableTrackIndexes() {
        let timedText = MediaTrack(id: 2, kind: .subtitle, codec: "tx3g")
        XCTAssertFalse(
            TimedTextSubtitleConversionPolicy.canOffer(
                for: makeAsset(path: "/media/Movie.mkv", container: "matroska", tracks: [timedText])
            )
        )
        XCTAssertFalse(
            TimedTextSubtitleConversionPolicy.canOffer(
                for: makeAsset(path: "/media/Movie.mp4", container: "avi", tracks: [timedText])
            )
        )
        XCTAssertFalse(
            TimedTextSubtitleConversionPolicy.canOffer(
                for: makeAsset(
                    path: "/media/Movie.mp4",
                    container: "movie-data",
                    tracks: [timedText]
                )
            )
        )
        XCTAssertFalse(
            TimedTextSubtitleConversionPolicy.canOffer(
                for: makeAsset(
                    tracks: [
                        timedText,
                        MediaTrack(id: 2, kind: .subtitle, codec: "mov_text"),
                    ]
                )
            )
        )
        XCTAssertFalse(
            TimedTextSubtitleConversionPolicy.canOffer(
                for: makeAsset(
                    tracks: [
                        MediaTrack(id: 2, kind: .video, codec: "h264"),
                        timedText,
                    ]
                )
            )
        )
        XCTAssertFalse(
            TimedTextSubtitleConversionPolicy.canOffer(
                for: makeAsset(
                    tracks: [MediaTrack(id: -1, kind: .subtitle, codec: "mov_text")]
                )
            )
        )
    }

    private func makeAsset(
        path: String = "/media/Movie.mp4",
        container: String = "mov,mp4,m4a,3gp,3g2,mj2",
        tracks: [MediaTrack]
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: path),
            container: container,
            tracks: tracks
        )
    }
}
