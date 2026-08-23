import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

private actor ChapterSuggestionStubRunner: CommandRunning {
    let result: CommandResult
    private(set) var requests = [CommandRequest]()

    init(result: CommandResult) {
        self.result = result
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        return result
    }

    func onlyRequest() -> CommandRequest? {
        requests.count == 1 ? requests[0] : nil
    }
}

private actor ChapterSuggestionMutatingRunner: CommandRunning {
    let sourceURL: URL

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        let handle = try FileHandle(forWritingTo: sourceURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("changed".utf8))
        try handle.close()
        return CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}

final class ChapterSuggestionAnalyzerTests: XCTestCase {
    func testBuildsOneBoundedFilterGraphAndParsesAllDetectors() async throws {
        let stderr = """
            [Parsed_showinfo_2] n: 0 pts: 10000 pts_time:10 duration_time:0.1
            [Parsed_blackdetect_3] black_start:9 black_end:10.2 black_duration:1.2
            [Parsed_silencedetect_4] silence_start: 50
            [Parsed_silencedetect_4] silence_end: 50.5 | silence_duration: 0.5
            [Parsed_showinfo_2] pts_time:N/A
            """
        let runner = ChapterSuggestionStubRunner(result: result(stderr: stderr))
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        var options = ChapterSuggestionOptions()
        options.edgeGuard = .zero
        options.minimumSpacing = .zero
        let source = MediaAsset(
            sourceURL: fixture,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 100_000_000_000),
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1"),
                MediaTrack(id: 1, kind: .audio, codec: "aac"),
            ]
        )

        let suggestions = try await FFmpegChapterSuggestionAnalyzer(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner
        ).analyze(source: source, options: options)

        XCTAssertEqual(suggestions.map(\.time.nanoseconds), [10_000_000_000, 50_500_000_000])
        XCTAssertEqual(suggestions[0].signals, [.sceneChange, .blackFrame])
        XCTAssertEqual(suggestions[1].signals, [.silence])
        let recordedRequest = await runner.onlyRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.executableURL.path, "/usr/bin/true")
        XCTAssertEqual(request.outputLimit, 16_777_216)
        XCTAssertEqual(request.arguments.filter { $0 == "-filter_complex" }.count, 1)
        let filterIndex = try XCTUnwrap(request.arguments.firstIndex(of: "-filter_complex"))
        let graph = request.arguments[filterIndex + 1]
        XCTAssertTrue(
            graph.contains("fps=10,scale=w=min(640\\,iw):h=-2:flags=fast_bilinear")
        )
        XCTAssertTrue(graph.contains("split=2"))
        XCTAssertTrue(graph.contains("select=gt(scene\\,0.400000),showinfo"))
        XCTAssertTrue(graph.contains("blackdetect=d=0.500000:pic_th=0.980000"))
        XCTAssertTrue(graph.contains("silencedetect=n=-35.000000dB:d=0.500000"))
        XCTAssertFalse(request.arguments.contains("sh"))
    }

    func testUsesOnlyAvailableSelectedStreams() async throws {
        let runner = ChapterSuggestionStubRunner(result: result(stderr: ""))
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = MediaAsset(
            sourceURL: fixture,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            tracks: [MediaTrack(id: 0, kind: .audio, codec: "aac")]
        )

        _ = try await FFmpegChapterSuggestionAnalyzer(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner
        ).analyze(source: source)

        let recordedRequest = await runner.onlyRequest()
        let request = try XCTUnwrap(recordedRequest)
        let graph = request.arguments[request.arguments.firstIndex(of: "-filter_complex")! + 1]
        XCTAssertEqual(
            graph,
            "[0:a:0]silencedetect=n=-35.000000dB:d=0.500000[silenceout]"
        )
        XCTAssertFalse(graph.contains("0:v"))
    }

    func testRejectsMissingStreamsTruncationAndToolFailure() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = MediaAsset(
            sourceURL: fixture,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000)
        )
        let noStreamsRunner = ChapterSuggestionStubRunner(result: result(stderr: ""))
        await XCTAssertThrowsErrorAsync(
            try await FFmpegChapterSuggestionAnalyzer(
                ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"), runner: noStreamsRunner
            ).analyze(source: source)
        ) { error in
            XCTAssertEqual(error as? ChapterSuggestionAnalyzerError, .noSupportedStreams)
        }

        let videoSource = MediaAsset(
            sourceURL: fixture,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
        let truncatedRunner = ChapterSuggestionStubRunner(
            result: result(stderr: "partial", wasTruncated: true))
        await XCTAssertThrowsErrorAsync(
            try await FFmpegChapterSuggestionAnalyzer(
                ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"), runner: truncatedRunner
            ).analyze(source: videoSource)
        ) { error in
            XCTAssertEqual(error as? ChapterSuggestionAnalyzerError, .truncatedAnalysis)
        }

        let failedRunner = ChapterSuggestionStubRunner(
            result: result(stderr: "decoder failed", exitCode: 9))
        await XCTAssertThrowsErrorAsync(
            try await FFmpegChapterSuggestionAnalyzer(
                ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"), runner: failedRunner
            ).analyze(source: videoSource)
        ) { error in
            XCTAssertEqual(
                error as? ChapterSuggestionAnalyzerError,
                .ffmpegFailed(exitCode: 9, message: "decoder failed")
            )
        }
    }

    func testRejectsSuggestionsWhenSourceChangesDuringAnalysis() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = MediaAsset(
            sourceURL: fixture,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )

        await XCTAssertThrowsErrorAsync(
            try await FFmpegChapterSuggestionAnalyzer(
                ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"),
                runner: ChapterSuggestionMutatingRunner(sourceURL: fixture)
            ).analyze(source: source)
        ) { error in
            XCTAssertEqual(error as? ChapterSuggestionAnalyzerError, .staleSource)
        }
    }

    private func result(
        stderr: String,
        exitCode: Int32 = 0,
        wasTruncated: Bool = false
    ) -> CommandResult {
        CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(
                data: Data(stderr.utf8), wasTruncated: wasTruncated)
        )
    }

    private func makeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-analysis-\(UUID().uuidString).mkv")
        try Data("fixture".utf8).write(to: url, options: .atomic)
        return url
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error")
    } catch {
        errorHandler(error)
    }
}
