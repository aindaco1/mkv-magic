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
}
