import Foundation
import MKVMagicCore
import MKVMagicPlanning
import XCTest

final class CompleteAudioConversionPlannerTests: XCTestCase {
    func testResolvesEveryAudioTrackAndPreservesMediaOrder() throws {
        let source = makeSource()

        let plan = try CompleteAudioConversionPlanner().resolve(
            source: source,
            preset: .flacLossless,
            availableAudioPresets: [.flacLossless]
        )

        XCTAssertEqual(plan.audioTrackIDs, [1, 3])
        XCTAssertEqual(plan.copiedTrackIDs, [0, 2])
        XCTAssertEqual(plan.trackIDsInOutputOrder, [0, 1, 2, 3])
        XCTAssertEqual(plan.videoEncodeCount, 0)
        XCTAssertEqual(plan.audioEncodeCount, 2)
    }

    func testRejectsMissingProbeTagsAndImplicitLayoutChanges() {
        XCTAssertThrowsError(
            try CompleteAudioConversionPlanner().resolve(
                source: makeSource(),
                preset: .opusQuality,
                availableAudioPresets: []
            )
        ) {
            XCTAssertEqual(
                $0 as? CompleteAudioConversionPlanningError,
                .unavailableAudioPreset(.opusQuality)
            )
        }

        XCTAssertThrowsError(
            try CompleteAudioConversionPlanner().resolve(
                source: makeSource(globalTags: 1),
                preset: .flacLossless,
                availableAudioPresets: [.flacLossless]
            )
        ) {
            XCTAssertEqual(
                $0 as? CompleteAudioConversionPlanningError,
                .unsupportedTags
            )
        }

        XCTAssertThrowsError(
            try CompleteAudioConversionPlanner().resolve(
                source: makeSource(secondAudioChannels: 8, secondAudioLayout: "7.1"),
                preset: .ac3Compatibility,
                availableAudioPresets: [.ac3Compatibility]
            )
        ) {
            XCTAssertEqual(
                $0 as? CompleteAudioConversionPlanningError,
                .incompleteAudioFacts(trackID: 3)
            )
        }
    }

    func testRejectsFilesWithoutAudioAndUnsupportedTrackKinds() {
        let silent = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Silent.mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 10),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")],
            globalTagCount: 0,
            trackTagCount: 0
        )
        XCTAssertThrowsError(
            try CompleteAudioConversionPlanner().resolve(
                source: silent,
                preset: .aacCompatibility,
                availableAudioPresets: [.aacCompatibility]
            )
        ) {
            XCTAssertEqual(
                $0 as? CompleteAudioConversionPlanningError,
                .noAudioTracks
            )
        }

        let unsupported = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Data.mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 10),
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1"),
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: 48_000
                ),
                MediaTrack(id: 2, kind: .data, codec: "bin_data"),
            ],
            globalTagCount: 0,
            trackTagCount: 0
        )
        XCTAssertThrowsError(
            try CompleteAudioConversionPlanner().resolve(
                source: unsupported,
                preset: .aacCompatibility,
                availableAudioPresets: [.aacCompatibility]
            )
        ) {
            XCTAssertEqual(
                $0 as? CompleteAudioConversionPlanningError,
                .unsupportedTracks
            )
        }
    }

    private func makeSource(
        globalTags: Int = 0,
        secondAudioChannels: Int = 6,
        secondAudioLayout: String = "5.1"
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Feature.mkv"),
            container: "matroska,webm",
            duration: MediaTime(seconds: 10),
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1"),
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: 48_000
                ),
                MediaTrack(id: 2, kind: .subtitle, codec: "subrip"),
                MediaTrack(
                    id: 3,
                    kind: .audio,
                    codec: "eac3",
                    channels: secondAudioChannels,
                    channelLayout: secondAudioLayout,
                    sampleRate: 48_000
                ),
            ],
            globalTagCount: globalTags,
            trackTagCount: 0
        )
    }
}
