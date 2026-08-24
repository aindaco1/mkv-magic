import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

final class FFmpegCapabilityProbeTests: XCTestCase {
    func testActivelyVerifiedEncodersDrivePreferredPreset() async throws {
        let runner = CapabilityRunner(
            encoders: """
                 V..... libsvtav1           SVT-AV1
                 V..... hevc_videotoolbox   HEVC VideoToolbox
                 V..... h264_videotoolbox   H.264 VideoToolbox
                 V..... prores_ks            ProRes
                 A..... aac_at               AAC AudioToolbox
                """,
            filters: Self.requiredFilters
        )
        let capabilities = try await FFmpegCapabilityProbe(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            runner: runner
        ).probe()

        XCTAssertEqual(capabilities.softwareAV1, .verified)
        XCTAssertEqual(capabilities.softwareAV1Encoder, "libsvtav1")
        XCTAssertEqual(capabilities.hevc10VideoToolbox, .verified)
        XCTAssertEqual(capabilities.h264VideoToolbox, .verified)
        XCTAssertEqual(capabilities.proRes, .verified)
        XCTAssertEqual(capabilities.aac, .verified)
        XCTAssertEqual(
            capabilities.availableVideoPresets,
            [.av1Quality, .hevcCompatibility, .h264Compatibility, .proRes]
        )
        XCTAssertEqual(capabilities.recommendedVideoPreset, .av1Quality)
        XCTAssertTrue(capabilities.missingJoinFilters.isEmpty)

        let requests = await runner.requests()
        let inputPaths = requests.compactMap { request -> String? in
            guard let inputIndex = request.arguments.firstIndex(of: "-i"),
                request.arguments.indices.contains(inputIndex + 1)
            else {
                return nil
            }
            return request.arguments[inputIndex + 1]
        }
        XCTAssertEqual(inputPaths.count, 5)
        XCTAssertTrue(inputPaths.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
        XCTAssertTrue(
            requests.filter { $0.arguments.contains("-c:v") || $0.arguments.contains("-c:a") }
                .allSatisfy { $0.arguments.last == "-" }
        )
    }

    func testDeclaredButFailingHEVCFallsBackToVerifiedH264() async throws {
        let runner = CapabilityRunner(
            encoders: """
                 V..... hevc_videotoolbox   HEVC VideoToolbox
                 V..... h264_videotoolbox   H.264 VideoToolbox
                 A..... aac                  AAC
                """,
            filters: Self.requiredFilters,
            failingEncoders: ["hevc_videotoolbox"]
        )
        let capabilities = try await FFmpegCapabilityProbe(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            runner: runner
        ).probe()

        XCTAssertEqual(capabilities.softwareAV1, .unavailable)
        XCTAssertNil(capabilities.softwareAV1Encoder)
        XCTAssertEqual(capabilities.hevc10VideoToolbox, .declared)
        XCTAssertEqual(capabilities.h264VideoToolbox, .verified)
        XCTAssertEqual(capabilities.aac, .verified)
        XCTAssertEqual(capabilities.availableVideoPresets, [.h264Compatibility])
        XCTAssertEqual(capabilities.recommendedVideoPreset, .h264Compatibility)
    }

    func testTruncatedListingFailsClosedBeforeAnySmokeEncode() async throws {
        let runner = CapabilityRunner(
            encoders: " V..... h264_videotoolbox H.264",
            filters: Self.requiredFilters,
            truncatedListings: true
        )

        do {
            _ = try await FFmpegCapabilityProbe(
                ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
                runner: runner
            ).probe()
            XCTFail("Expected a truncated-listing error")
        } catch {
            XCTAssertEqual(error as? FFmpegCapabilityProbeError, .truncatedListing)
        }
        let requests = await runner.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testCurrentBundledRuntimeReportsOnlyActivelyUsableChoices() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let capabilities = try await FFmpegCapabilityProbe(
            ffmpegURL: try catalog.url(for: .ffmpeg),
            runner: FoundationCommandRunner()
        ).probe()

        XCTAssertEqual(capabilities.softwareAV1, .verified)
        XCTAssertEqual(capabilities.softwareAV1Encoder, "libsvtav1")
        XCTAssertEqual(capabilities.hevc10VideoToolbox, .verified)
        XCTAssertEqual(capabilities.h264VideoToolbox, .verified)
        XCTAssertEqual(capabilities.proRes, .verified)
        XCTAssertEqual(capabilities.aac, .verified)
        XCTAssertEqual(capabilities.recommendedVideoPreset, .av1Quality)
        XCTAssertTrue(capabilities.missingJoinFilters.isEmpty)
    }

    private static let requiredFilters = FFmpegEncodingCapabilities.requiredJoinFilters
        .sorted()
        .map { " .. \($0) A->A description" }
        .joined(separator: "\n")
}

private actor CapabilityRunner: CommandRunning {
    private let encoders: String
    private let filters: String
    private let failingEncoders: Set<String>
    private let truncatedListings: Bool
    private var captured = [CommandRequest]()

    init(
        encoders: String,
        filters: String,
        failingEncoders: Set<String> = [],
        truncatedListings: Bool = false
    ) {
        self.encoders = encoders
        self.filters = filters
        self.failingEncoders = failingEncoders
        self.truncatedListings = truncatedListings
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        captured.append(request)
        if request.arguments.contains("-encoders") {
            return result(text: encoders, truncated: truncatedListings)
        }
        if request.arguments.contains("-filters") {
            return result(text: filters, truncated: truncatedListings)
        }
        let encoder =
            value(after: "-c:v", in: request.arguments)
            ?? value(after: "-c:a", in: request.arguments)
        return result(exitCode: encoder.map { failingEncoders.contains($0) } == true ? 1 : 0)
    }

    func requests() -> [CommandRequest] { captured }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }

    private func result(
        exitCode: Int32 = 0,
        text: String = "",
        truncated: Bool = false
    ) -> CommandResult {
        CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(text.utf8), wasTruncated: truncated),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}
