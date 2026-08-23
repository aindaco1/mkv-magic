import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

private actor ThumbnailWritingRunner: CommandRunning {
    let resultCode: Int32
    let outputData: Data
    private(set) var requests = [CommandRequest]()

    init(resultCode: Int32 = 0, outputData: Data = ThumbnailWritingRunner.validJPEG) {
        self.resultCode = resultCode
        self.outputData = outputData
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        if resultCode == 0, let outputPath = request.arguments.last {
            try outputData.write(to: URL(fileURLWithPath: outputPath))
        }
        return CommandResult(
            exitCode: resultCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(
                data: resultCode == 0 ? Data() : Data("thumbnail failed".utf8),
                wasTruncated: false
            )
        )
    }

    func recordedRequests() -> [CommandRequest] { requests }

    static let validJPEG = Data([0xFF, 0xD8]) + Data("jpeg".utf8) + Data([0xFF, 0xD9])
}

private struct CancellingThumbnailRunner: CommandRunning {
    func run(_ request: CommandRequest) async throws -> CommandResult {
        throw CommandRunnerError.cancelled
    }
}

final class ChapterThumbnailGeneratorTests: XCTestCase {
    func testGeneratesSortedBoundedJPEGsWithExactArgumentArrays() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let runner = ThumbnailWritingRunner()
        let source = videoSource(url: fixture)
        let thumbnails = try await FFmpegChapterThumbnailGenerator(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner
        ).generate(
            source: source,
            times: [MediaTime(nanoseconds: 5_123_456_789), .zero]
        )

        XCTAssertEqual(thumbnails.map(\.time.nanoseconds), [0, 5_123_456_789])
        XCTAssertTrue(thumbnails.allSatisfy { $0.imageData == ThumbnailWritingRunner.validJPEG })
        let requests = await runner.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests[0].arguments[requests[0].arguments.firstIndex(of: "-ss")! + 1], "0.000000000")
        XCTAssertEqual(
            requests[1].arguments[requests[1].arguments.firstIndex(of: "-ss")! + 1],
            "5.123456789"
        )
        XCTAssertTrue(
            requests.allSatisfy {
                $0.arguments.contains("scale=w=min(480\\,iw):h=-2:flags=fast_bilinear")
                    && !$0.arguments.contains("sh") && $0.outputLimit == 1_048_576
            }
        )
    }

    func testRejectsUnsafeRequestsMissingVideoAndMalformedOutput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let runner = ThumbnailWritingRunner()
        let generator = FFmpegChapterThumbnailGenerator(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner)

        await XCTAssertThrowsThumbnailError(
            try await generator.generate(
                source: videoSource(url: fixture),
                times: [.zero, .zero]
            ),
            expected: .invalidRequest
        )
        await XCTAssertThrowsThumbnailError(
            try await generator.generate(
                source: MediaAsset(
                    sourceURL: fixture,
                    container: "matroska,webm",
                    duration: MediaTime(nanoseconds: 10_000_000_000),
                    tracks: [MediaTrack(id: 0, kind: .audio, codec: "aac")]
                ),
                times: [.zero]
            ),
            expected: .noVideoTrack
        )
        await XCTAssertThrowsThumbnailError(
            try await FFmpegChapterThumbnailGenerator(
                ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"),
                runner: ThumbnailWritingRunner(outputData: Data("not jpeg".utf8))
            ).generate(source: videoSource(url: fixture), times: [.zero]),
            expected: .unsafeOutput
        )
        await XCTAssertThrowsThumbnailError(
            try await FFmpegChapterThumbnailGenerator(
                ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"),
                runner: ThumbnailWritingRunner(
                    outputData: Data(
                        repeating: 0,
                        count:
                            FFmpegChapterThumbnailGenerator<ThumbnailWritingRunner>
                            .maximumThumbnailBytes + 1
                    )
                )
            ).generate(source: videoSource(url: fixture), times: [.zero]),
            expected: .unsafeOutput
        )
    }

    func testReportsBoundedToolFailure() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        await XCTAssertThrowsThumbnailError(
            try await FFmpegChapterThumbnailGenerator(
                ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"),
                runner: ThumbnailWritingRunner(resultCode: 7)
            ).generate(source: videoSource(url: fixture), times: [.zero]),
            expected: .ffmpegFailed(exitCode: 7, message: "thumbnail failed")
        )
    }

    func testRejectsARevisionStaleSinceChapterPreviewAndMapsRunnerCancellation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = videoSource(url: fixture)
        await XCTAssertThrowsThumbnailError(
            try await FFmpegChapterThumbnailGenerator(
                ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"),
                runner: ThumbnailWritingRunner()
            ).generate(
                source: source,
                times: [.zero],
                expectedSourceRevision: ChapterSourceRevision(
                    fileSize: 9_999,
                    modificationDate: .distantPast
                )
            ),
            expected: .staleSource
        )

        do {
            _ = try await FFmpegChapterThumbnailGenerator(
                ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"),
                runner: CancellingThumbnailRunner()
            ).generate(source: source, times: [.zero])
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: closing Chapter Studio must not surface a tool failure.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
    }

    private func makeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-thumbnail-\(UUID().uuidString).mkv")
        try Data("fixture".utf8).write(to: url, options: .atomic)
        return url
    }

    private func videoSource(url: URL) -> MediaAsset {
        MediaAsset(
            sourceURL: url,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
    }
}

private func XCTAssertThrowsThumbnailError<T>(
    _ expression: @autoclosure () async throws -> T,
    expected: ChapterThumbnailGeneratorError
) async {
    do {
        _ = try await expression()
        XCTFail("Expected \(expected)")
    } catch {
        XCTAssertEqual(error as? ChapterThumbnailGeneratorError, expected)
    }
}
