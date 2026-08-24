import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

final class FFmpegEncodingBenchmarkTests: XCTestCase {
    func testMeasuresBothEncodersLocallyAndRecommendsPracticalAV1() async throws {
        let runner = BenchmarkRunner(av1Duration: 0.2, hevcDuration: 0.05)
        let report = try await FFmpegEncodingBenchmark(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            runner: runner
        ).run(capabilities: capabilities(), environment: environment())

        XCTAssertEqual(report.recommendedPreset, .av1Quality)
        XCTAssertEqual(report.attempts.map(\.preset), [.av1Quality, .hevcCompatibility])
        XCTAssertEqual(report.attempts[0].metrics?.averagePSNR, 41.5)
        XCTAssertEqual(report.attempts[1].metrics?.averagePSNR, 39.25)
        XCTAssertGreaterThan(
            try XCTUnwrap(report.attempts[0].metrics?.estimated1080pRealtimeFactor),
            EncodingBenchmarkRecommendation.minimumAV1Estimated1080pRealtimeFactor
        )

        let requests = await runner.requests()
        XCTAssertEqual(requests.count, 4)
        let av1 = try XCTUnwrap(requests.first(where: { $0.arguments.contains("libsvtav1") }))
        XCTAssertTrue(av1.arguments.contains("-preset:v:0"))
        XCTAssertTrue(av1.arguments.contains("8"))
        XCTAssertTrue(av1.arguments.contains("-crf:v:0"))
        let hevc = try XCTUnwrap(
            requests.first(where: { $0.arguments.contains("hevc_videotoolbox") })
        )
        XCTAssertTrue(hevc.arguments.contains("-profile:v:0"))
        XCTAssertTrue(hevc.arguments.contains("main10"))
        XCTAssertTrue(
            requests.filter { $0.arguments.contains("-filter_complex") }
                .allSatisfy {
                    $0.arguments.contains("psnr")
                        || $0.arguments.contains(where: {
                            $0.contains("psnr")
                        })
                }
        )
        let fixturePaths = await runner.fixturePaths()
        XCTAssertEqual(Set(fixturePaths).count, 1)
        XCTAssertTrue(fixturePaths.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    }

    func testAV1TimeoutBecomesHEVCRecommendationInsteadOfLosingTheResult() async throws {
        let runner = BenchmarkRunner(
            av1Duration: 0.2,
            hevcDuration: 0.05,
            timedOutEncoders: ["libsvtav1"]
        )
        let report = try await FFmpegEncodingBenchmark(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            runner: runner
        ).run(capabilities: capabilities(), environment: environment())

        XCTAssertEqual(report.recommendedPreset, .hevcCompatibility)
        XCTAssertEqual(report.attempts[0].outcome, .timedOut)
        XCTAssertNil(report.attempts[0].metrics)
        XCTAssertEqual(report.attempts[1].outcome, .completed)
    }

    func testNoVerifiedBenchmarkEncoderFailsBeforeCreatingPrivateMedia() async throws {
        let runner = BenchmarkRunner(av1Duration: 1, hevcDuration: 1)
        do {
            _ = try await FFmpegEncodingBenchmark(
                ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
                runner: runner
            ).run(capabilities: .unavailable, environment: environment())
            XCTFail("Expected no encoder")
        } catch {
            XCTAssertEqual(
                error as? FFmpegEncodingBenchmarkError,
                .noBenchmarkableEncoder
            )
        }
        let requests = await runner.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testCurrentBundledRuntimeCompletesTimedAV1AndHEVC() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let ffmpegURL = try catalog.url(for: .ffmpeg)
        let capabilities = try await FFmpegCapabilityProbe(
            ffmpegURL: ffmpegURL,
            runner: FoundationCommandRunner()
        ).probe()
        let ffmpegEntry = try XCTUnwrap(
            catalog.manifest.tools.first(where: { $0.name == .ffmpeg })
        )

        let report = try await FFmpegEncodingBenchmark(
            ffmpegURL: ffmpegURL,
            runner: FoundationCommandRunner()
        ).run(
            capabilities: capabilities,
            environment: EncodingBenchmarkEnvironment(
                ffmpegSHA256: ffmpegEntry.sha256,
                architecture: catalog.architecture.rawValue,
                activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
            )
        )

        XCTAssertEqual(report.attempts.count, 2)
        XCTAssertTrue(report.attempts.allSatisfy { $0.outcome == .completed })
        XCTAssertTrue(report.attempts.allSatisfy { $0.metrics?.averagePSNR != nil })
        XCTAssertTrue(
            report.attempts.contains(where: { $0.preset == report.recommendedPreset })
        )
    }

    private func capabilities() -> FFmpegEncodingCapabilities {
        FFmpegEncodingCapabilities(
            softwareAV1: .verified,
            softwareAV1Encoder: "libsvtav1",
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .unavailable,
            proRes: .unavailable,
            proResEncoder: nil,
            aac: .unavailable,
            aacEncoder: nil,
            availableFilters: ["psnr"]
        )
    }

    private func environment() -> EncodingBenchmarkEnvironment {
        EncodingBenchmarkEnvironment(
            ffmpegSHA256: String(repeating: "a", count: 64),
            architecture: "arm64",
            activeProcessorCount: 8
        )
    }
}

private actor BenchmarkRunner: CommandRunning {
    private let av1Duration: TimeInterval
    private let hevcDuration: TimeInterval
    private let timedOutEncoders: Set<String>
    private var captured = [CommandRequest]()
    private var capturedFixturePaths = [String]()

    init(
        av1Duration: TimeInterval,
        hevcDuration: TimeInterval,
        timedOutEncoders: Set<String> = []
    ) {
        self.av1Duration = av1Duration
        self.hevcDuration = hevcDuration
        self.timedOutEncoders = timedOutEncoders
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        captured.append(request)
        if request.arguments.contains("-filter_complex") {
            let psnr = request.arguments.contains("libdav1d") ? "41.50" : "39.25"
            return result(error: "[Parsed_psnr_0] PSNR y:42 average:\(psnr) min:38 max:45\n")
        }
        let encoder = value(after: "-c:v:0", in: request.arguments) ?? ""
        if let input = value(after: "-i", in: request.arguments) {
            capturedFixturePaths.append(input)
            let values = try URL(fileURLWithPath: input).resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                values.fileSize
                    == FFmpegEncodingBenchmark<BenchmarkRunner>.sourceWidth
                    * FFmpegEncodingBenchmark<BenchmarkRunner>.sourceHeight * 3
                    * FFmpegEncodingBenchmark<BenchmarkRunner>.sourceFrameCount
            else {
                return result(exitCode: 1, duration: 0.1)
            }
        }
        if timedOutEncoders.contains(encoder) { throw CommandRunnerError.timedOut }
        guard let outputPath = request.arguments.last, outputPath.hasPrefix("/") else {
            return result(exitCode: 1, duration: 0.1)
        }
        let byteCount = encoder == "libsvtav1" ? 250_000 : 375_000
        try Data(repeating: 0x5A, count: byteCount).write(
            to: URL(fileURLWithPath: outputPath),
            options: .atomic
        )
        return result(
            duration: encoder == "libsvtav1" ? av1Duration : hevcDuration
        )
    }

    func requests() -> [CommandRequest] { captured }
    func fixturePaths() -> [String] { capturedFixturePaths }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }

    private func result(
        exitCode: Int32 = 0,
        error: String = "",
        duration: TimeInterval = 0
    ) -> CommandResult {
        CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(error.utf8), wasTruncated: false),
            duration: duration
        )
    }
}
