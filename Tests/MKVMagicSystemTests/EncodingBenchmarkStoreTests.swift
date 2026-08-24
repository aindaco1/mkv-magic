import Foundation
import MKVMagicCore
import MKVMagicSystem
import XCTest

final class EncodingBenchmarkStoreTests: XCTestCase {
    private var rootURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-encoding-benchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        fileURL = rootURL.appendingPathComponent("encoding-benchmark.json")
    }

    override func tearDownWithError() throws {
        if rootURL != nil { try FileManager.default.removeItem(at: rootURL) }
    }

    func testRoundTripsPrivateVersionedReport() async throws {
        let store = try JSONEncodingBenchmarkStore(fileURL: fileURL)
        let report = makeReport()

        try await store.save(report)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, report)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("libsvtav1"))
        XCTAssertFalse(text.contains("sourceURL"))
        XCTAssertFalse(text.contains("filename"))
    }

    func testMissingReportLoadsAsNil() async throws {
        let store = try JSONEncodingBenchmarkStore(fileURL: fileURL)
        let loaded = try await store.load()
        XCTAssertNil(loaded)
    }

    func testUnexpectedFieldsAndUnsupportedSchemaFailClosed() async throws {
        let store = try JSONEncodingBenchmarkStore(fileURL: fileURL)
        try await store.save(makeReport())
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL))
                as? [String: Any]
        )
        object["sourcePath"] = "/private/media/Movie.mkv"
        try JSONSerialization.data(withJSONObject: object).write(to: fileURL, options: .atomic)

        do {
            _ = try await store.load()
            XCTFail("Expected unexpected-field refusal")
        } catch {
            XCTAssertEqual(error as? EncodingBenchmarkStoreError, .unexpectedFields)
        }

        object.removeValue(forKey: "sourcePath")
        object["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: object).write(to: fileURL, options: .atomic)
        do {
            _ = try await store.load()
            XCTFail("Expected unsupported-schema refusal")
        } catch {
            XCTAssertEqual(error as? EncodingBenchmarkStoreError, .unsupportedSchema)
        }
    }

    func testSymlinkAndInconsistentRecommendationFailClosed() async throws {
        let target = rootURL.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: target)
        let store = try JSONEncodingBenchmarkStore(fileURL: fileURL)
        do {
            _ = try await store.load()
            XCTFail("Expected unsafe path")
        } catch {
            XCTAssertEqual(error as? EncodingBenchmarkStoreError, .unsafePath)
        }

        try FileManager.default.removeItem(at: fileURL)
        let invalid = EncodingBenchmarkReport(
            environment: makeReport().environment,
            completedAt: Date(),
            sourceWidth: 640,
            sourceHeight: 360,
            sourceFrameRate: 24,
            sourceFrameCount: 72,
            attempts: makeReport().attempts,
            recommendedPreset: .hevcCompatibility
        )
        do {
            try await store.save(invalid)
            XCTFail("Expected inconsistent recommendation refusal")
        } catch {
            XCTAssertEqual(error as? EncodingBenchmarkStoreError, .malformedReport)
        }
    }

    func testInvalidMetricsFailClosed() async throws {
        let store = try JSONEncodingBenchmarkStore(fileURL: fileURL)
        let invalid = EncodingBenchmarkReport(
            environment: makeReport().environment,
            completedAt: Date(),
            sourceWidth: 640,
            sourceHeight: 360,
            sourceFrameRate: 24,
            sourceFrameCount: 72,
            attempts: [
                EncodingBenchmarkAttempt(
                    preset: .av1Quality,
                    encoder: "libsvtav1",
                    outcome: .completed,
                    metrics: EncodingBenchmarkMetrics(
                        elapsedSeconds: -1,
                        framesPerSecond: 72,
                        sourceRealtimeFactor: 3,
                        estimated1080pRealtimeFactor: 0.6,
                        outputBytes: 350_000,
                        outputBitrate: 933_333,
                        averagePSNR: 41.25
                    )
                )
            ],
            recommendedPreset: .av1Quality
        )

        do {
            try await store.save(invalid)
            XCTFail("Expected invalid metrics refusal")
        } catch {
            XCTAssertEqual(error as? EncodingBenchmarkStoreError, .malformedReport)
        }
    }

    private func makeReport() -> EncodingBenchmarkReport {
        let metrics = EncodingBenchmarkMetrics(
            elapsedSeconds: 1.5,
            framesPerSecond: 48,
            sourceRealtimeFactor: 2,
            estimated1080pRealtimeFactor: 0.6,
            outputBytes: 350_000,
            outputBitrate: 933_333,
            averagePSNR: 41.25
        )
        return EncodingBenchmarkReport(
            environment: EncodingBenchmarkEnvironment(
                ffmpegSHA256: String(repeating: "a", count: 64),
                architecture: "arm64",
                activeProcessorCount: 8
            ),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000.125),
            sourceWidth: 640,
            sourceHeight: 360,
            sourceFrameRate: 24,
            sourceFrameCount: 72,
            attempts: [
                EncodingBenchmarkAttempt(
                    preset: .av1Quality,
                    encoder: "libsvtav1",
                    outcome: .completed,
                    metrics: metrics
                )
            ],
            recommendedPreset: .av1Quality
        )
    }
}
