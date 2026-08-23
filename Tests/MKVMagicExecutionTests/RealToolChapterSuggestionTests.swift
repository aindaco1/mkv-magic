import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

final class RealToolChapterSuggestionTests: XCTestCase {
    func testBundledFFmpegFindsSceneAndBlackBoundaryInOneLocalPass() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        let runner = FoundationCommandRunner()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-suggestions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let videoURL = root.appendingPathComponent("video.rgb")
        let audioURL = root.appendingPathComponent("audio.pcm")
        let sourceURL = root.appendingPathComponent("source.mkv")
        let frameBytes = 16 * 16 * 3
        var video = Data(repeating: 0, count: frameBytes * 10)
        video.append(Data(repeating: 255, count: frameBytes * 10))
        try video.write(to: videoURL)
        try Data(repeating: 0, count: 48_000 * 2 * 2).write(to: audioURL)

        let created = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "16x16",
                    "-framerate", "10", "-i", videoURL.path,
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", audioURL.path,
                    "-c:v", "ffv1", "-c:a", "pcm_s16le", "-shortest", sourceURL.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(created.exitCode, 0, created.standardError.text)

        var options = ChapterSuggestionOptions()
        options.sceneThreshold = 0.3
        options.blackMinimumDuration = MediaTime(nanoseconds: 200_000_000)
        options.silenceMinimumDuration = MediaTime(nanoseconds: 200_000_000)
        options.minimumSpacing = .zero
        options.edgeGuard = .zero
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 2_000_000_000),
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "ffv1"),
                MediaTrack(id: 1, kind: .audio, codec: "pcm_s16le"),
            ]
        )

        let suggestions = try await FFmpegChapterSuggestionAnalyzer(
            ffmpegURL: try catalog.url(for: .ffmpeg), runner: runner
        ).analyze(source: source, options: options)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].time.nanoseconds, 1_000_000_000)
        XCTAssertEqual(suggestions[0].signals, [.sceneChange, .blackFrame])
    }
}
