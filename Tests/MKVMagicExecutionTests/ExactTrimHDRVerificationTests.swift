import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import XCTest

final class ExactTrimHDRVerificationTests: XCTestCase {
    func testCompleteFileConversionRequiresCopiedSubtitleIdentity() throws {
        let source = subtitleConversionAsset(videoCodec: "h264", subtitleCodec: "subrip")
        let resolved = try ExactTrimPlanner().resolve(
            source: source,
            range: MediaTrimRange(start: .zero, end: try XCTUnwrap(source.duration)),
            choice: ExactTrimChoice(
                videoPreset: .hevcCompatibility,
                videoRateControl: .averageBitrate(2_000_000)
            ),
            operation: .transcode,
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )
        let verifier = ExactTrimOutputVerifier()

        try verifier.verify(
            resolvedPlan: resolved,
            chapters: MatroskaChapterDocument(),
            output: subtitleConversionAsset(
                videoCodec: "hevc",
                subtitleCodec: "subrip",
                output: true
            )
        )
        XCTAssertThrowsError(
            try verifier.verify(
                resolvedPlan: resolved,
                chapters: MatroskaChapterDocument(),
                output: subtitleConversionAsset(
                    videoCodec: "hevc",
                    subtitleCodec: "ass",
                    output: true
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ExactTrimVerificationError,
                .subtitleMismatch(trackID: 2)
            )
        }
    }

    func testRequiresExactReviewedHDR10Signal() throws {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/HDR Feature.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            fileSize: 1_000,
            tracks: [hdr10Track(codec: "hevc", uid: 100)],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "SOURCE"
        )
        let range = MediaTrimRange(
            start: MediaTime(nanoseconds: 2_000_000_000),
            end: MediaTime(nanoseconds: 7_000_000_000)
        )
        let choice = ExactTrimChoice(
            videoPreset: .av1Quality,
            videoRateControl: .constantQuality(30),
            audioPolicy: .packetCopy
        )
        let resolved = try ExactTrimPlanner().resolve(
            source: source,
            range: range,
            choice: choice,
            availableVideoPresets: [.av1Quality],
            aacAvailable: true
        )
        let verifier = ExactTrimOutputVerifier()

        try verifier.verify(
            resolvedPlan: resolved,
            chapters: MatroskaChapterDocument(),
            output: output(maxContentLightLevel: 1_000)
        )
        XCTAssertThrowsError(
            try verifier.verify(
                resolvedPlan: resolved,
                chapters: MatroskaChapterDocument(),
                output: output(maxContentLightLevel: 999)
            )
        ) { error in
            XCTAssertEqual(error as? ExactTrimVerificationError, .videoMismatch)
        }
    }

    private func output(maxContentLightLevel: Int) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: "/output/HDR Feature - Trimmed.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 5_000_000_000),
            fileSize: 500,
            tracks: [
                hdr10Track(
                    codec: "av1",
                    uid: 100,
                    maxContentLightLevel: maxContentLightLevel
                )
            ],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "OUTPUT"
        )
    }

    private func subtitleConversionAsset(
        videoCodec: String,
        subtitleCodec: String,
        output: Bool = false
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(
                fileURLWithPath: output
                    ? "/output/Subtitle Feature.mkv" : "/media/Subtitle Feature.mkv"
            ),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            fileSize: 1_000,
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: videoCodec,
                    codecID: videoCodec == "hevc"
                        ? "V_MPEGH/ISO/HEVC" : "V_MPEG4/ISO/AVC",
                    profile: videoCodec == "hevc" ? "Main 10" : "High",
                    uid: output ? 500 : 100,
                    isDefault: true,
                    dimensions: MediaDimensions(width: 160, height: 90),
                    pixelFormat: videoCodec == "hevc" ? "p010le" : "yuv420p",
                    bitDepth: videoCodec == "hevc" ? 10 : 8,
                    frameRate: "24/1",
                    colorInfo: MediaColorInfo(
                        range: "tv",
                        primaries: "bt709",
                        transfer: "bt709",
                        matrix: "bt709"
                    )
                ),
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    codecID: "A_AAC",
                    profile: "LC",
                    uid: output ? 501 : 101,
                    language: "en",
                    isDefault: true,
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: 48_000
                ),
                MediaTrack(
                    id: 2,
                    kind: .subtitle,
                    codec: subtitleCodec,
                    codecID: subtitleCodec == "subrip" ? "S_TEXT/UTF8" : "S_TEXT/ASS",
                    uid: output ? 502 : 102,
                    language: "en",
                    title: "English",
                    isForced: true
                ),
            ],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: output ? "OUTPUT" : "SOURCE"
        )
    }

    private func hdr10Track(
        codec: String,
        uid: UInt64,
        maxContentLightLevel: Int = 1_000
    ) -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: codec,
            codecID: codec == "av1" ? "V_AV1" : "V_MPEGH/ISO/HEVC",
            profile: codec == "av1" ? "Main" : "Main 10",
            uid: uid,
            isDefault: true,
            dimensions: MediaDimensions(width: 160, height: 90),
            displayDimensions: MediaDimensions(width: 160, height: 90),
            pixelFormat: "yuv420p10le",
            bitDepth: 10,
            frameRate: "24/1",
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
                maxContentLightLevel: maxContentLightLevel,
                maxFrameAverageLightLevel: 400
            ),
            hdrFormats: ["HDR10 metadata"]
        )
    }
}
