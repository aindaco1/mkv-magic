import Foundation
import MKVMagicCore
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor TimedTextConversionRunner: CommandRunning {
    private let outputs: [Data]
    private let mutateSourceURL: URL?
    private let mutationCall: Int?
    private var requests = [CommandRequest]()

    init(
        outputs: [Data],
        mutateSourceURL: URL? = nil,
        mutationCall: Int? = nil
    ) {
        self.outputs = outputs
        self.mutateSourceURL = mutateSourceURL
        self.mutationCall = mutationCall
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        let call = requests.count
        requests.append(request)
        guard let outputPath = request.arguments.last else {
            return Self.result(exitCode: 2, message: "missing output")
        }
        let output = outputs[min(call, outputs.count - 1)]
        try output.write(to: URL(fileURLWithPath: outputPath))
        if mutationCall == call, let mutateSourceURL {
            try Data("changed source".utf8).write(to: mutateSourceURL)
        }
        return Self.result(exitCode: 0)
    }

    func capturedRequests() -> [CommandRequest] { requests }

    private static func result(exitCode: Int32, message: String = "") -> CommandResult {
        CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(message.utf8), wasTruncated: false)
        )
    }
}

private actor TimedTextStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()

    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func snapshot() -> [VerifiedOutputExecutionStage] { stages }
}

final class TimedTextSubtitleConversionExecutorTests: XCTestCase {
    func testPreviewsAndCommitsOneVerifiedUTF8ASSSidecar() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceData = try Data(contentsOf: fixture.sourceURL)
        let runner = TimedTextConversionRunner(outputs: [
            assData("First cue"), assData("First cue"),
        ])
        let executor = TimedTextSubtitleConversionExecutor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            runner: runner
        )

        let preview = try await executor.preview(source: fixture.asset, trackID: 2)
        XCTAssertEqual(preview.track.language, "eng")
        XCTAssertEqual(preview.eventCount, 1)
        let stageRecorder = TimedTextStageRecorder()
        let result = try await executor.execute(
            preview: preview,
            destinationURL: fixture.destinationURL,
            onStage: { stage in await stageRecorder.append(stage) }
        )

        let stages = await stageRecorder.snapshot()
        XCTAssertEqual(stages, [.verifying, .committing])
        XCTAssertEqual(result.outputURL, fixture.destinationURL)
        XCTAssertEqual(result.document.events.first?.text, "First cue")
        XCTAssertEqual(try Data(contentsOf: fixture.sourceURL), sourceData)
        let saved = try AdvancedSubStationAlphaCodec().parse(
            SubtitleTextDecoder().decode(Data(contentsOf: fixture.destinationURL))
        ).document
        XCTAssertEqual(saved, preview.document)
        let requests = await runner.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.executableURL.path == "/tools/ffmpeg" })
        XCTAssertTrue(
            requests.allSatisfy { request in
                request.arguments.contains("0:2")
                    && request.arguments.contains("-map_metadata")
                    && request.arguments.contains("-map_chapters")
                    && !request.arguments.contains("sh")
            })
    }

    func testChangedSourceAfterPreviewNeverCreatesDestination() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = TimedTextConversionRunner(outputs: [assData("First cue")])
        let executor = TimedTextSubtitleConversionExecutor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            runner: runner
        )
        let preview = try await executor.preview(source: fixture.asset, trackID: 2)
        try Data("user changed the video".utf8).write(to: fixture.sourceURL)

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(preview: preview, destinationURL: fixture.destinationURL)
        ) {
            XCTAssertEqual($0 as? TimedTextSubtitleConversionError, .staleSource)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    func testSourceChangedDuringRepeatedConversionNeverCommits() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = TimedTextConversionRunner(
            outputs: [assData("First cue"), assData("First cue")],
            mutateSourceURL: fixture.sourceURL,
            mutationCall: 1
        )
        let executor = TimedTextSubtitleConversionExecutor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            runner: runner
        )
        let preview = try await executor.preview(source: fixture.asset, trackID: 2)

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(preview: preview, destinationURL: fixture.destinationURL)
        ) {
            XCTAssertEqual($0 as? TimedTextSubtitleConversionError, .staleSource)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    func testSourceChangedDuringOutputVerificationNeverCommits() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = TimedTextConversionRunner(outputs: [
            assData("First cue"), assData("First cue"),
        ])
        let executor = TimedTextSubtitleConversionExecutor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            runner: runner
        )
        let preview = try await executor.preview(source: fixture.asset, trackID: 2)

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(
                preview: preview,
                destinationURL: fixture.destinationURL,
                onStage: { stage in
                    if stage == .verifying {
                        try Data("changed during verification".utf8).write(to: fixture.sourceURL)
                    }
                }
            )
        ) {
            XCTAssertEqual($0 as? TimedTextSubtitleConversionError, .staleSource)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    func testChangedConversionAndWrongDestinationFailClosed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = TimedTextConversionRunner(
            outputs: [assData("First cue"), assData("Different cue")]
        )
        let executor = TimedTextSubtitleConversionExecutor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            runner: runner
        )
        let preview = try await executor.preview(source: fixture.asset, trackID: 2)

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(preview: preview, destinationURL: fixture.destinationURL)
        ) {
            XCTAssertEqual($0 as? TimedTextSubtitleConversionError, .conversionChanged)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
        await XCTAssertThrowsErrorAsync(
            try await executor.execute(
                preview: preview,
                destinationURL: fixture.root.appendingPathComponent("Subtitle.srt")
            )
        ) {
            XCTAssertEqual($0 as? TimedTextSubtitleConversionError, .unsupportedDestination)
        }
    }

    private func makeFixture() throws -> (
        root: URL, sourceURL: URL, destinationURL: URL, asset: MediaAsset
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-timed-text-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sourceURL = root.appendingPathComponent("Movie.mp4")
        try Data("bounded fake MP4 bytes".utf8).write(to: sourceURL)
        let asset = MediaAsset(
            sourceURL: sourceURL,
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            duration: MediaTime(seconds: 3),
            fileSize: 22,
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "h264"),
                MediaTrack(id: 2, kind: .subtitle, codec: "mov_text", language: "eng"),
            ]
        )
        return (root, sourceURL, root.appendingPathComponent("Movie.ass"), asset)
    }

    private func assData(_ text: String) -> Data {
        Data(
            """
            [Script Info]
            ScriptType: v4.00+

            [V4+ Styles]
            Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
            Style: Default,Arial,16,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,2,10,10,10,1

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,\(text)

            """.utf8
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        handler(error)
    }
}
