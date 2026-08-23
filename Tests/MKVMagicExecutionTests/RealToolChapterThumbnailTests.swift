import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

final class RealToolChapterThumbnailTests: XCTestCase {
    func testBundledFFmpegExtractsBoundedJPEGsWithoutChangingSource() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        let runner = FoundationCommandRunner()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-thumbnails-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let videoURL = root.appendingPathComponent("video.rgb")
        let sourceURL = root.appendingPathComponent("source.mkv")
        let frameBytes = 64 * 36 * 3
        var video = Data(repeating: 0, count: frameBytes * 10)
        video.append(Data(repeating: 255, count: frameBytes * 10))
        try video.write(to: videoURL)
        let created = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "64x36",
                    "-framerate", "10", "-i", videoURL.path,
                    "-c:v", "ffv1", sourceURL.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(created.exitCode, 0, created.standardError.text)
        let sourceData = try Data(contentsOf: sourceURL)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 2_000_000_000),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "ffv1")]
        )

        let thumbnails = try await FFmpegChapterThumbnailGenerator(
            ffmpegURL: try catalog.url(for: .ffmpeg), runner: runner
        ).generate(
            source: source,
            times: [.zero, MediaTime(nanoseconds: 1_000_000_000)]
        )

        XCTAssertEqual(thumbnails.map(\.time.nanoseconds), [0, 1_000_000_000])
        XCTAssertTrue(
            thumbnails.allSatisfy {
                $0.imageData.starts(with: Data([0xFF, 0xD8]))
                    && $0.imageData.suffix(2) == Data([0xFF, 0xD9])
            }
        )
        XCTAssertTrue(
            thumbnails.allSatisfy {
                $0.imageData.count
                    <= FFmpegChapterThumbnailGenerator<FoundationCommandRunner>
                    .maximumThumbnailBytes
            }
        )
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }
}
