import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

@testable import MKVMagic

final class TrimThumbnailUXTests: XCTestCase {
    func testTrimSamplingIsUniqueBoundedAndDoesNotOverflow() {
        for duration: Int64 in [1, 4, 100, .max] {
            let samples = TrimPresentationPolicy.thumbnailTimes(
                duration: MediaTime(nanoseconds: duration))
            XCTAssertFalse(samples.isEmpty)
            XCTAssertEqual(samples, Array(Set(samples)).sorted())
            XCTAssertTrue(samples.allSatisfy { $0.nanoseconds >= 0 && $0.nanoseconds < duration })
        }
        XCTAssertEqual(TrimPresentationPolicy.thumbnailTimes(duration: .zero), [])
    }

    func testTrimSamplesStayInsideTheVideoInsteadOfSeekingPastItsLastFrame() async throws {
        guard let root = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT for bundled-tool thumbnails")
        }
        let catalog = try ToolCatalog(rootURL: URL(fileURLWithPath: root, isDirectory: true))
        let ffmpeg = try catalog.url(for: .ffmpeg)
        let runner = FoundationCommandRunner()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-trim-samples-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("frames.yuv")
        let output = directory.appendingPathComponent("short.mkv")
        try Data(repeating: 128, count: 96 * 64 * 3 / 2 * 24).write(to: raw)
        let result = try await runner.run(
            CommandRequest(
                executableURL: ffmpeg,
                arguments: [
                    "-hide_banner", "-nostdin", "-loglevel", "error", "-f", "rawvideo",
                    "-pixel_format", "yuv420p", "-video_size", "96x64", "-framerate", "24",
                    "-i", raw.path, "-c:v", "ffv1", "-an", output.path,
                ]))
        XCTAssertEqual(result.exitCode, 0)
        let source = MediaAsset(
            sourceURL: output, container: "matroska",
            duration: MediaTime(nanoseconds: 1_000_000_000),
            tracks: [.init(id: 0, kind: .video, codec: "ffv1")])
        let times = TrimPresentationPolicy.thumbnailTimes(duration: try XCTUnwrap(source.duration))
        let thumbnails = try await FFmpegChapterThumbnailGenerator(
            ffmpegURL: ffmpeg, runner: runner
        )
        .generate(source: source, times: times)
        XCTAssertEqual(thumbnails.count, 5)
        XCTAssertEqual(thumbnails.map(\.time), times)
    }
}
