import Foundation
import MKVMagicCore
import MKVMagicPlanning
import XCTest

final class ExactTrimPlannerTests: XCTestCase {
    func testResolvesOneVideoGenerationWithExplicitCopiedOrAACAudio() throws {
        let source = makeSource()
        let choice = ExactTrimChoice(
            videoPreset: .hevcCompatibility,
            videoRateControl: .averageBitrate(2_000_000),
            audioPolicy: .packetCopy
        )
        let copy = try ExactTrimPlanner().resolve(
            source: source,
            range: range(2, 8),
            choice: choice,
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )

        XCTAssertEqual(copy.videoTrackID, 0)
        XCTAssertEqual(copy.videoDynamicRange, .sdr)
        XCTAssertNil(copy.hdr10Signal)
        XCTAssertEqual(copy.audioTrackIDs, [1])
        XCTAssertEqual(copy.trackIDsInOutputOrder, [0, 1])
        XCTAssertEqual(copy.videoEncodeCount, 1)
        XCTAssertEqual(copy.audioEncodeCount, 0)

        let aac = try ExactTrimPlanner().resolve(
            source: source,
            range: range(2, 8),
            choice: ExactTrimChoice(
                videoPreset: .hevcCompatibility,
                videoRateControl: .averageBitrate(2_000_000),
                audioPolicy: .aacPreserveLayout
            ),
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )
        XCTAssertEqual(aac.audioEncodeCount, 1)
    }

    func testRecommendationPrefersFirstVerifiedPresetAndPacketCopiesAudio() throws {
        let planner = ExactTrimPlanner()
        let av1 = try XCTUnwrap(
            planner.recommendedChoice(
                for: makeSource(),
                availableVideoPresets: [.av1Quality, .hevcCompatibility]
            )
        )
        XCTAssertEqual(av1.videoPreset, .av1Quality)
        XCTAssertEqual(av1.videoRateControl, .constantQuality(30))
        XCTAssertEqual(av1.audioPolicy, .packetCopy)

        let hevc = try XCTUnwrap(
            planner.recommendedChoice(
                for: makeSource(),
                availableVideoPresets: [.hevcCompatibility]
            )
        )
        XCTAssertEqual(hevc.videoRateControl, .averageBitrate(500_000))

        let hdr = try XCTUnwrap(
            planner.recommendedChoice(
                for: makeSource(hdr10: true),
                availableVideoPresets: [.h264Compatibility, .hevcCompatibility]
            )
        )
        XCTAssertEqual(hdr.videoPreset, .hevcCompatibility)
    }

    func testResolvesStaticHDR10ForAV1OrHEVCOnly() throws {
        let source = makeSource(hdr10: true)
        let plan = try ExactTrimPlanner().resolve(
            source: source,
            range: range(2, 8),
            choice: ExactTrimChoice(
                videoPreset: .hevcCompatibility,
                videoRateControl: .averageBitrate(2_000_000)
            ),
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )
        XCTAssertEqual(plan.videoDynamicRange, .hdr10)
        XCTAssertEqual(plan.hdr10Signal, MediaHDR10Signal(track: source.tracks[0]))

        XCTAssertThrowsError(
            try ExactTrimPlanner().resolve(
                source: source,
                range: range(2, 8),
                choice: ExactTrimChoice(
                    videoPreset: .h264Compatibility,
                    videoRateControl: .averageBitrate(2_000_000)
                ),
                availableVideoPresets: [.h264Compatibility],
                aacAvailable: true
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .unsupportedDynamicRange) }
    }

    func testFailsClosedForUnsupportedTracksTagsHDRCapabilitiesAndAACFacts() throws {
        let choice = ExactTrimChoice(
            videoPreset: .hevcCompatibility,
            videoRateControl: .averageBitrate(2_000_000)
        )
        let cases: [(MediaAsset, ExactTrimChoice, Set<VideoPreset>, Bool, ExactTrimPlanningError)] =
            [
                (
                    makeSource(extraTrack: MediaTrack(id: 2, kind: .subtitle, codec: "subrip")),
                    choice,
                    [.hevcCompatibility],
                    true,
                    .unsupportedTracks
                ),
                (
                    makeSource(globalTagCount: 1),
                    choice,
                    [.hevcCompatibility],
                    true,
                    .unsupportedTags
                ),
                (
                    makeSource(hdrFormats: ["HDR10 metadata"]),
                    choice,
                    [.hevcCompatibility],
                    true,
                    .unsupportedDynamicRange
                ),
                (
                    makeSource(),
                    choice,
                    [.h264Compatibility],
                    true,
                    .unavailableVideoPreset(.hevcCompatibility)
                ),
                (
                    makeSource(audioLayout: nil),
                    ExactTrimChoice(
                        videoPreset: .hevcCompatibility,
                        videoRateControl: .averageBitrate(2_000_000),
                        audioPolicy: .aacPreserveLayout
                    ),
                    [.hevcCompatibility],
                    true,
                    .incompleteAudioFacts(trackID: 1)
                ),
            ]
        for (source, selected, presets, aac, expected) in cases {
            XCTAssertThrowsError(
                try ExactTrimPlanner().resolve(
                    source: source,
                    range: range(2, 8),
                    choice: selected,
                    availableVideoPresets: presets,
                    aacAvailable: aac
                )
            ) { XCTAssertEqual($0 as? ExactTrimPlanningError, expected) }
        }
    }

    func testRejectsInvalidNoOpAndReversedRanges() throws {
        let source = makeSource()
        let choice = ExactTrimChoice(
            videoPreset: .h264Compatibility,
            videoRateControl: .averageBitrate(2_000_000)
        )
        XCTAssertThrowsError(
            try ExactTrimPlanner().resolve(
                source: source,
                range: range(0, 10),
                choice: choice,
                availableVideoPresets: [.h264Compatibility],
                aacAvailable: true
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .noChange) }
        XCTAssertThrowsError(
            try ExactTrimPlanner().resolve(
                source: source,
                range: range(8, 2),
                choice: choice,
                availableVideoPresets: [.h264Compatibility],
                aacAvailable: true
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .invalidRange) }
    }

    private func makeSource(
        extraTrack: MediaTrack? = nil,
        globalTagCount: Int = 0,
        hdrFormats: [String] = [],
        hdr10: Bool = false,
        audioLayout: String? = "stereo"
    ) -> MediaAsset {
        var tracks = [
            MediaTrack(
                id: 0,
                kind: .video,
                codec: hdr10 ? "hevc" : "h264",
                codecID: hdr10 ? "V_MPEGH/ISO/HEVC" : "V_MPEG4/ISO/AVC",
                profile: hdr10 ? "Main 10" : "High",
                uid: 100,
                isDefault: true,
                dimensions: MediaDimensions(width: 160, height: 90),
                pixelFormat: hdr10 ? "yuv420p10le" : "yuv420p",
                bitDepth: hdr10 ? 10 : 8,
                frameRate: "24/1",
                colorInfo: MediaColorInfo(
                    range: "tv",
                    primaries: hdr10 ? "bt2020" : "bt709",
                    transfer: hdr10 ? "smpte2084" : "bt709",
                    matrix: hdr10 ? "bt2020nc" : "bt709"
                ),
                masteringDisplayMetadata: hdr10 ? masteringDisplay : nil,
                contentLightLevelMetadata: hdr10 ? contentLight : nil,
                hdrFormats: hdr10 ? ["HDR10 metadata"] : hdrFormats
            ),
            MediaTrack(
                id: 1,
                kind: .audio,
                codec: "aac",
                codecID: "A_AAC",
                profile: "LC",
                uid: 101,
                language: "en",
                title: "Main Audio",
                isDefault: true,
                channels: 2,
                channelLayout: audioLayout,
                sampleRate: 48_000
            ),
        ]
        if let extraTrack { tracks.append(extraTrack) }
        return MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Feature.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            fileSize: 1_000,
            tracks: tracks,
            metadata: ["title": "Feature"],
            chapterEntryCount: 0,
            globalTagCount: globalTagCount,
            trackTagCount: 0,
            segmentUID: "SOURCE"
        )
    }

    private func range(_ start: Int64, _ end: Int64) -> MediaTrimRange {
        MediaTrimRange(
            start: MediaTime(nanoseconds: start * 1_000_000_000),
            end: MediaTime(nanoseconds: end * 1_000_000_000)
        )
    }
}

private let masteringDisplay = MediaMasteringDisplayMetadata(
    redX: 34_000,
    redY: 16_000,
    greenX: 13_250,
    greenY: 34_500,
    blueX: 7_500,
    blueY: 3_000,
    whitePointX: 15_635,
    whitePointY: 16_450,
    maxLuminance: 10_000_000,
    minLuminance: 50
)

private let contentLight = MediaContentLightLevelMetadata(
    maxContentLightLevel: 1_000,
    maxFrameAverageLightLevel: 400
)
