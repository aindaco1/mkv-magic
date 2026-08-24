import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

final class RealToolMKVRemuxTests: XCTestCase {
    func testBundledToolsPacketCopyChapteredMP4IntoVerifiedMKV() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let capabilities = try await FFmpegCapabilityProbe(
            ffmpegURL: try catalog.url(for: .ffmpeg),
            runner: runner
        ).probe()
        guard capabilities.h264VideoToolbox == .verified else {
            throw XCTSkip("The bundled H.264 fixture encoder is unavailable")
        }

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-remux"
        ) { root in
            let sourceURL = try await makeMP4Fixture(
                root: root,
                ffmpegURL: try catalog.url(for: .ffmpeg),
                runner: runner
            )
            let destinationURL = root.appendingPathComponent("Remuxed.mkv")
            let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            XCTAssertEqual(source.container, "mov")
            XCTAssertEqual(source.tracks.map(\.kind), [.video, .audio, .data])
            XCTAssertEqual(source.chapters.map(\.title), ["Opening", "Second"])

            let executor = MKVRemuxExecutor(
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                ffmpegURL: try catalog.url(for: .ffmpeg),
                ffprobeURL: try catalog.url(for: .ffprobe),
                runner: runner,
                inspector: inspector
            )
            let preview = try executor.preview(source: source)
            XCTAssertEqual(preview.plan.videoEncodeCount, 0)
            XCTAssertEqual(preview.plan.audioEncodeCount, 0)
            XCTAssertEqual(preview.plan.chapterCarrierTrackIDs.count, 1)
            let output = try await executor.execute(
                preview: preview,
                destinationURL: destinationURL
            )

            XCTAssertTrue(output.container.localizedCaseInsensitiveContains("matroska"))
            XCTAssertEqual(output.tracks.map(\.kind), [.video, .audio])
            XCTAssertEqual(
                output.tracks.map(\.codec),
                source.tracks.filter { $0.kind == .video || $0.kind == .audio }.map(\.codec)
            )
            XCTAssertEqual(
                try TrackLanguageTag.canonical(output.tracks[1].language ?? "und"),
                "en"
            )
            XCTAssertEqual(output.tracks[1].title, "Main Audio")
            XCTAssertEqual(output.chapters.map(\.title), source.chapters.map(\.title))
            XCTAssertEqual(output.metadata["title"], "Remux Fixture")
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: sourceURL)),
                sourceDigest
            )
            let decode = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .ffmpeg),
                    arguments: [
                        "-hide_banner", "-nostdin", "-loglevel", "error",
                        "-i", destinationURL.path,
                        "-map", "0:v:0", "-map", "0:a:0", "-f", "null", "-",
                    ],
                    timeout: 120
                )
            )
            XCTAssertEqual(decode.exitCode, 0, decode.standardError.text)
        }
    }

    private func makeMP4Fixture(
        root: URL,
        ffmpegURL: URL,
        runner: FoundationCommandRunner
    ) async throws -> URL {
        let width = 96
        let height = 64
        let frameCount = 20
        let rawVideoURL = root.appendingPathComponent("frames.yuv")
        let rawAudioURL = root.appendingPathComponent("audio.pcm")
        let chapterURL = root.appendingPathComponent("chapters.ffmetadata")
        let sourceURL = root.appendingPathComponent("Source.mp4")
        try Data(repeating: 64, count: width * height * 3 / 2 * frameCount).write(
            to: rawVideoURL
        )
        try Data(repeating: 0, count: 48_000 * 2 * 2 * 2).write(to: rawAudioURL)
        try Data(
            ";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=1000\ntitle=Opening\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=1000\nEND=2000\ntitle=Second\n"
                .utf8
        ).write(to: chapterURL)
        let result = try await runner.run(
            CommandRequest(
                executableURL: ffmpegURL,
                arguments: [
                    "-hide_banner", "-nostdin", "-loglevel", "error",
                    "-f", "rawvideo", "-pixel_format", "yuv420p",
                    "-video_size", "\(width)x\(height)", "-framerate", "10",
                    "-i", rawVideoURL.path,
                    "-f", "s16le", "-ar", "48000", "-ac", "2",
                    "-i", rawAudioURL.path,
                    "-f", "ffmetadata", "-i", chapterURL.path,
                    "-map", "0:v:0", "-map", "1:a:0", "-map_chapters", "2",
                    "-frames:v", "\(frameCount)",
                    "-c:v", "h264_videotoolbox", "-profile:v", "high",
                    "-g", "10", "-bf", "0", "-b:v", "300000",
                    "-pix_fmt", "yuv420p",
                    "-color_primaries", "bt709", "-color_trc", "bt709",
                    "-colorspace", "bt709", "-color_range", "tv",
                    "-bsf:v",
                    "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1",
                    "-c:a", "aac", "-b:a", "128000",
                    "-metadata", "title=Remux Fixture",
                    "-metadata:s:a:0", "language=eng",
                    "-metadata:s:a:0", "title=Main Audio",
                    "-disposition:a:0", "default",
                    sourceURL.path,
                ],
                timeout: 120
            )
        )
        XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        return sourceURL
    }
}
