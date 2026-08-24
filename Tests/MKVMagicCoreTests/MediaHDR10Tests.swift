import MKVMagicCore
import XCTest

final class MediaHDR10Tests: XCTestCase {
    func testAcceptsCompleteStaticHDR10AndBT709SDR() {
        let hdr = makeHDR10Track()
        let signal = MediaHDR10Signal(track: hdr)
        XCTAssertEqual(signal?.masteringDisplayMetadata, hdr.masteringDisplayMetadata)
        XCTAssertEqual(signal?.contentLightLevelMetadata, hdr.contentLightLevelMetadata)
        XCTAssertFalse(MediaHDR10Signal.isBT709SDR(hdr))

        XCTAssertTrue(MediaHDR10Signal.isBT709SDR(makeSDRTrack()))
        XCTAssertNil(MediaHDR10Signal(track: makeSDRTrack()))
    }

    func testRejectsDynamicIncompleteAndIncorrectlySignaledHDR() {
        XCTAssertNil(MediaHDR10Signal(track: makeHDR10Track(hdrFormats: ["HDR10+"])))
        XCTAssertNil(MediaHDR10Signal(track: makeHDR10Track(hdrFormats: ["Dolby Vision"])))
        XCTAssertNil(
            MediaHDR10Signal(
                track: makeHDR10Track(
                    masteringDisplay: nil,
                    contentLight: nil,
                    hdrFormats: ["HDR10 metadata"]
                )
            )
        )
        XCTAssertNil(
            MediaHDR10Signal(
                track: makeHDR10Track(
                    color: MediaColorInfo(
                        range: "tv",
                        primaries: "bt709",
                        transfer: "smpte2084",
                        matrix: "bt709"
                    )
                )
            )
        )
    }

    private func makeHDR10Track(
        color: MediaColorInfo = MediaColorInfo(
            range: "tv",
            primaries: "bt2020",
            transfer: "smpte2084",
            matrix: "bt2020nc"
        ),
        masteringDisplay: MediaMasteringDisplayMetadata? = mastering,
        contentLight: MediaContentLightLevelMetadata? = content,
        hdrFormats: [String] = ["HDR10 metadata"]
    ) -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: "hevc",
            pixelFormat: "yuv420p10le",
            bitDepth: 10,
            colorInfo: color,
            masteringDisplayMetadata: masteringDisplay,
            contentLightLevelMetadata: contentLight,
            hdrFormats: hdrFormats
        )
    }

    private func makeSDRTrack() -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: "h264",
            pixelFormat: "yuv420p",
            bitDepth: 8,
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt709",
                transfer: "bt709",
                matrix: "bt709"
            )
        )
    }
}

private let mastering = MediaMasteringDisplayMetadata(
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

private let content = MediaContentLightLevelMetadata(
    maxContentLightLevel: 1_000,
    maxFrameAverageLightLevel: 400
)
