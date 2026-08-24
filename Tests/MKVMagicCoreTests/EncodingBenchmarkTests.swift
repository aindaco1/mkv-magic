import Foundation
import MKVMagicCore
import XCTest

final class EncodingBenchmarkTests: XCTestCase {
    func testQualityFirstAV1WinsWhenEstimated1080pSpeedIsPractical() {
        let attempts = [
            attempt(.av1Quality, estimated1080pRealtimeFactor: 0.75),
            attempt(.hevcCompatibility, estimated1080pRealtimeFactor: 4),
        ]

        XCTAssertEqual(EncodingBenchmarkRecommendation.choose(from: attempts), .av1Quality)
    }

    func testHEVCWinsWhenSoftwareAV1IsImpracticallySlow() {
        let attempts = [
            attempt(.av1Quality, estimated1080pRealtimeFactor: 0.49),
            attempt(.hevcCompatibility, estimated1080pRealtimeFactor: 4),
        ]

        XCTAssertEqual(
            EncodingBenchmarkRecommendation.choose(from: attempts),
            .hevcCompatibility
        )
    }

    func testCompletedEncoderWinsWhenTheAlternativeTimesOut() {
        let attempts = [
            EncodingBenchmarkAttempt(
                preset: .av1Quality,
                encoder: "libsvtav1",
                outcome: .timedOut,
                metrics: nil
            ),
            attempt(.hevcCompatibility, estimated1080pRealtimeFactor: 3),
        ]

        XCTAssertEqual(
            EncodingBenchmarkRecommendation.choose(from: attempts),
            .hevcCompatibility
        )
        XCTAssertNil(
            EncodingBenchmarkRecommendation.choose(
                from: [
                    EncodingBenchmarkAttempt(
                        preset: .av1Quality,
                        encoder: "libsvtav1",
                        outcome: .failed,
                        metrics: nil
                    )
                ]
            )
        )
    }

    func testDuplicateAttemptsCannotTrapOrOverrideTheFirstCompletedMeasurement() {
        let attempts = [
            attempt(.av1Quality, estimated1080pRealtimeFactor: 0.1),
            attempt(.av1Quality, estimated1080pRealtimeFactor: 2),
            attempt(.hevcCompatibility, estimated1080pRealtimeFactor: 3),
        ]

        XCTAssertEqual(
            EncodingBenchmarkRecommendation.choose(from: attempts),
            .hevcCompatibility
        )
    }

    func testReportMatchesOnlyTheExactLocalRuntimeEnvironment() {
        let environment = EncodingBenchmarkEnvironment(
            ffmpegSHA256: String(repeating: "a", count: 64),
            architecture: "arm64",
            activeProcessorCount: 8
        )
        let report = EncodingBenchmarkReport(
            environment: environment,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceWidth: 640,
            sourceHeight: 360,
            sourceFrameRate: 24,
            sourceFrameCount: 72,
            attempts: [attempt(.av1Quality, estimated1080pRealtimeFactor: 1)],
            recommendedPreset: .av1Quality
        )

        XCTAssertTrue(report.matches(environment))
        XCTAssertFalse(
            report.matches(
                EncodingBenchmarkEnvironment(
                    ffmpegSHA256: String(repeating: "b", count: 64),
                    architecture: "arm64",
                    activeProcessorCount: 8
                )
            )
        )
    }

    private func attempt(
        _ preset: VideoPreset,
        estimated1080pRealtimeFactor: Double
    ) -> EncodingBenchmarkAttempt {
        EncodingBenchmarkAttempt(
            preset: preset,
            encoder: preset == .av1Quality ? "libsvtav1" : "hevc_videotoolbox",
            outcome: .completed,
            metrics: EncodingBenchmarkMetrics(
                elapsedSeconds: 1,
                framesPerSecond: 72,
                sourceRealtimeFactor: 3,
                estimated1080pRealtimeFactor: estimated1080pRealtimeFactor,
                outputBytes: 100_000,
                outputBitrate: 266_667,
                averagePSNR: 42
            )
        )
    }
}
