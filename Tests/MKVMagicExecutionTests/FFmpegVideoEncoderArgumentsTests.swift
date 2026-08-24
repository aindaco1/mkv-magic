import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import XCTest

@testable import MKVMagicExecution

final class FFmpegVideoEncoderArgumentsTests: XCTestCase {
    func testHDR10AV1PinsColorSignalAndStaticInputMetadata() throws {
        let signal = try XCTUnwrap(MediaHDR10Signal(track: makeHDR10Track()))
        let builder = FFmpegVideoEncoderArguments()
        let arguments = try builder.make(
            outputIndex: 2,
            encoder: "libsvtav1",
            preset: .av1Quality,
            rateControl: .constantQuality(30),
            dynamicRange: .hdr10,
            hdr10Signal: signal
        )
        XCTAssertTrue(arguments.contains("-svtav1-params:v:2"))
        XCTAssertTrue(arguments.contains("-color_primaries:v:2"))
        XCTAssertTrue(arguments.contains("9"))
        XCTAssertEqual(
            builder.setParamsFilter(for: .hdr10),
            "setparams=range=limited:color_primaries=bt2020:color_trc=smpte2084:"
                + "colorspace=bt2020nc"
        )
        XCTAssertEqual(
            builder.inputMetadataArguments(signal, streamSpecifier: "v:0"),
            [
                "-mastering_display:v:0",
                "G(13250,34500)B(7500,3000)R(34000,16000)"
                    + "WP(15635,16450)L(10000000,50)",
                "-content_light:v:0", "1000,400",
            ]
        )
    }

    func testHDR10RejectsEightBitAndMissingSignalChoices() throws {
        let signal = try XCTUnwrap(MediaHDR10Signal(track: makeHDR10Track()))
        let builder = FFmpegVideoEncoderArguments()
        XCTAssertThrowsError(
            try builder.make(
                outputIndex: 0,
                encoder: "h264_videotoolbox",
                preset: .h264Compatibility,
                rateControl: .averageBitrate(2_000_000),
                dynamicRange: .hdr10,
                hdr10Signal: signal
            )
        )
        XCTAssertThrowsError(
            try builder.make(
                outputIndex: 0,
                encoder: "libsvtav1",
                preset: .av1Quality,
                rateControl: .constantQuality(30),
                dynamicRange: .hdr10
            )
        )
    }

    private func makeHDR10Track() -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: "hevc",
            pixelFormat: "yuv420p10le",
            bitDepth: 10,
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt2020",
                transfer: "smpte2084",
                matrix: "bt2020nc"
            ),
            masteringDisplayMetadata: MediaMasteringDisplayMetadata(
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
            ),
            contentLightLevelMetadata: MediaContentLightLevelMetadata(
                maxContentLightLevel: 1_000,
                maxFrameAverageLightLevel: 400
            ),
            hdrFormats: ["HDR10 metadata"]
        )
    }
}
