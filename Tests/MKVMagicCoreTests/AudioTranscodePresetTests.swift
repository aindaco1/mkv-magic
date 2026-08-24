import MKVMagicCore
import XCTest

final class AudioTranscodePresetTests: XCTestCase {
    func testStableNamesAndCodecIdentitiesAreExplicit() {
        XCTAssertEqual(
            AudioTranscodePreset.allCases.map(\.displayName),
            ["AAC", "Opus", "AC-3", "E-AC-3", "FLAC (Lossless)"]
        )
        XCTAssertEqual(
            AudioTranscodePreset.allCases.map(\.codecName),
            ["aac", "opus", "ac3", "eac3", "flac"]
        )
        XCTAssertTrue(AudioTranscodePreset.flacLossless.isLossless)
        XCTAssertFalse(AudioTranscodePreset.opusQuality.isLossless)
    }

    func testRecommendedRatesPreserveSupportedChannelCountsWithoutDownmixing() {
        XCTAssertEqual(
            AudioTranscodePreset.aacCompatibility.recommendedBitrate(channels: 8), 512_000)
        XCTAssertEqual(AudioTranscodePreset.opusQuality.recommendedBitrate(channels: 1), 96_000)
        XCTAssertEqual(
            AudioTranscodePreset.ac3Compatibility.recommendedBitrate(channels: 6), 640_000)
        XCTAssertEqual(
            AudioTranscodePreset.eac3Compatibility.recommendedBitrate(channels: 6), 768_000)
        XCTAssertNil(AudioTranscodePreset.ac3Compatibility.recommendedBitrate(channels: 8))
        XCTAssertNil(AudioTranscodePreset.flacLossless.recommendedBitrate(channels: 8))
        XCTAssertNil(AudioTranscodePreset.opusQuality.recommendedBitrate(channels: 0))
    }

    func testLayoutBoundaryRejectsObservedImplicitRematrixing() {
        XCTAssertTrue(AudioTranscodePreset.opusQuality.preserves(channelLayout: "7.1", channels: 8))
        XCTAssertFalse(
            AudioTranscodePreset.opusQuality.preserves(channelLayout: "5.1(side)", channels: 6))
        XCTAssertTrue(
            AudioTranscodePreset.ac3Compatibility.preserves(channelLayout: "5.1(side)", channels: 6)
        )
        XCTAssertFalse(
            AudioTranscodePreset.ac3Compatibility.preserves(channelLayout: "7.1", channels: 8))
        XCTAssertFalse(
            AudioTranscodePreset.aacCompatibility.preserves(channelLayout: "7.1", channels: 8))
        XCTAssertTrue(
            AudioTranscodePreset.flacLossless.preserves(channelLayout: "7.1", channels: 8))
        XCTAssertFalse(
            AudioTranscodePreset.flacLossless.preserves(channelLayout: "stereo", channels: 6))
    }

    func testSampleRateTargetIsExplicitAndNeverAnImplicitFallback() {
        XCTAssertEqual(
            AudioTranscodePreset.aacCompatibility.outputSampleRate(forInput: 44_100), 44_100)
        XCTAssertNil(AudioTranscodePreset.aacCompatibility.outputSampleRate(forInput: 96_000))
        XCTAssertEqual(AudioTranscodePreset.opusQuality.outputSampleRate(forInput: 44_100), 48_000)
        XCTAssertEqual(
            AudioTranscodePreset.ac3Compatibility.outputSampleRate(forInput: 32_000), 32_000)
        XCTAssertNil(AudioTranscodePreset.eac3Compatibility.outputSampleRate(forInput: 24_000))
        XCTAssertEqual(
            AudioTranscodePreset.flacLossless.outputSampleRate(forInput: 192_000), 192_000)
    }

    func testJoinLayoutTargetMakesOnlyReviewedSixChannelRematrixes() {
        XCTAssertEqual(
            AudioTranscodePreset.aacCompatibility.joinOutputChannelLayout(
                forSourceLayout: "5.1(side)",
                channels: 6
            ),
            "5.1"
        )
        XCTAssertEqual(
            AudioTranscodePreset.ac3Compatibility.joinOutputChannelLayout(
                forSourceLayout: "5.1",
                channels: 6
            ),
            "5.1(side)"
        )
        XCTAssertEqual(
            AudioTranscodePreset.opusQuality.joinOutputChannelLayout(
                forSourceLayout: "7.1",
                channels: 8
            ),
            "7.1"
        )
        XCTAssertNil(
            AudioTranscodePreset.aacCompatibility.joinOutputChannelLayout(
                forSourceLayout: "7.1",
                channels: 8
            )
        )
        XCTAssertNil(
            AudioTranscodePreset.flacLossless.joinOutputChannelLayout(
                forSourceLayout: "stereo",
                channels: 6
            )
        )
    }
}
