import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

private actor RealToolProgressRecorder {
    private var updates = [VerifiedOutputToolProgress]()

    func append(_ update: VerifiedOutputToolProgress) { updates.append(update) }
    func snapshot() -> [VerifiedOutputToolProgress] { updates }
}

final class RealToolMKVRemuxTests: XCTestCase {
    func testBundledToolsPacketCopyChapteredMP4IntoVerifiedMKV() async throws {
        let (catalog, runner, _) = try await requiredTools()

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
            let progress = RealToolProgressRecorder()
            let output = try await executor.execute(
                preview: preview,
                destinationURL: destinationURL,
                onProgress: { await progress.append($0) }
            )
            let progressUpdates = await progress.snapshot()
            XCTAssertFalse(progressUpdates.isEmpty)
            XCTAssertEqual(progressUpdates.last?.phase, .multiplexing)
            XCTAssertEqual(progressUpdates.last?.percentage, 100)

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

    func testBundledToolsTranscodeChapteredMP4OnceIntoVerifiedMKV() async throws {
        let (catalog, runner, capabilities) = try await requiredTools()

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-mp4-transcode"
        ) { root in
            let sourceURL = try await makeMP4Fixture(
                root: root,
                ffmpegURL: try catalog.url(for: .ffmpeg),
                runner: runner
            )
            let destinationURL = root.appendingPathComponent("Converted.mkv")
            let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            let executor = ExactTrimExecutor(
                ffmpegURL: try catalog.url(for: .ffmpeg),
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            let preview = try await executor.preview(
                source: source,
                range: MediaTrimRange(start: .zero, end: try XCTUnwrap(source.duration)),
                choice: ExactTrimChoice(
                    videoPreset: .h264Compatibility,
                    videoRateControl: .averageBitrate(300_000),
                    audioPolicy: .packetCopy
                ),
                operation: .transcode,
                capabilities: capabilities
            )

            XCTAssertEqual(preview.resolvedPlan.sourceKind, .quickTime)
            XCTAssertEqual(preview.resolvedPlan.trackIDsInOutputOrder, [0, 1])
            XCTAssertEqual(preview.resolvedPlan.videoEncodeCount, 1)
            XCTAssertEqual(preview.resolvedPlan.audioEncodeCount, 0)
            XCTAssertEqual(preview.copiedAudioTrackIDs, [1])
            XCTAssertEqual(preview.originalChapters.chapterCount, 2)
            XCTAssertEqual(
                preview.originalChapters.editions.first?.chapters.map(\.primaryTitle),
                ["Opening", "Second"]
            )

            let output = try await executor.execute(
                preview: preview,
                destinationURL: destinationURL
            )

            XCTAssertTrue(output.container.localizedCaseInsensitiveContains("matroska"))
            XCTAssertEqual(output.tracks.map(\.kind), [.video, .audio])
            XCTAssertEqual(output.tracks[0].codec, "h264")
            XCTAssertEqual(output.tracks[1].codec, source.tracks[1].codec)
            XCTAssertEqual(output.tracks[1].title, "Main Audio")
            XCTAssertEqual(output.chapters.map(\.title), ["Opening", "Second"])
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

    func testBundledToolsTranscodeChapterFreeWebMOnceIntoVerifiedMKV() async throws {
        let (catalog, runner, capabilities) = try await requiredTools()

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-webm-transcode"
        ) { root in
            let sourceURL = try await makeWebMFixture(
                root: root,
                ffmpegURL: try catalog.url(for: .ffmpeg),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner
            )
            let destinationURL = root.appendingPathComponent("Converted WebM.mkv")
            let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            XCTAssertTrue(source.container.localizedCaseInsensitiveContains("matroska"))
            XCTAssertEqual(source.tracks.map(\.kind), [.video, .audio])
            XCTAssertEqual(source.chapters, [])
            XCTAssertTrue(ExactTrimPlanner().canOfferTranscode(for: source))
            let executor = ExactTrimExecutor(
                ffmpegURL: try catalog.url(for: .ffmpeg),
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            let preview = try await executor.preview(
                source: source,
                range: MediaTrimRange(start: .zero, end: try XCTUnwrap(source.duration)),
                choice: ExactTrimChoice(
                    videoPreset: .h264Compatibility,
                    videoRateControl: .averageBitrate(300_000),
                    audioPolicy: .packetCopy
                ),
                operation: .transcode,
                capabilities: capabilities
            )
            XCTAssertEqual(preview.resolvedPlan.sourceKind, .webM)
            XCTAssertTrue(preview.originalChapters.editions.isEmpty)
            XCTAssertEqual(preview.resolvedPlan.videoEncodeCount, 1)
            XCTAssertEqual(preview.resolvedPlan.audioEncodeCount, 0)

            let output = try await executor.execute(
                preview: preview,
                destinationURL: destinationURL
            )

            XCTAssertEqual(output.tracks.map(\.kind), [.video, .audio])
            XCTAssertEqual(output.tracks[0].codec, "h264")
            XCTAssertEqual(output.tracks[1].codec, "opus")
            XCTAssertEqual(output.tracks[1].title, "Main Audio")
            XCTAssertEqual(output.chapters, [])
            XCTAssertEqual(output.metadata["title"], "WebM Fixture")
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: sourceURL)),
                sourceDigest
            )
        }
    }

    private func requiredTools() async throws -> (
        ToolCatalog, FoundationCommandRunner, FFmpegEncodingCapabilities
    ) {
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
        return (catalog, runner, capabilities)
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

    private func makeWebMFixture(
        root: URL,
        ffmpegURL: URL,
        mkvpropeditURL: URL,
        runner: FoundationCommandRunner
    ) async throws -> URL {
        let width = 96
        let height = 64
        let frameCount = 10
        let rawVideoURL = root.appendingPathComponent("webm-frames.yuv")
        let rawAudioURL = root.appendingPathComponent("webm-audio.pcm")
        let sourceURL = root.appendingPathComponent("Source.webm")
        try Data(repeating: 64, count: width * height * 3 / 2 * frameCount).write(
            to: rawVideoURL
        )
        try Data(repeating: 0, count: 48_000 * 2 * 2).write(to: rawAudioURL)
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
                    "-frames:v", "\(frameCount)",
                    "-c:v", "libsvtav1", "-preset", "10", "-crf", "40",
                    "-pix_fmt", "yuv420p",
                    "-color_primaries", "bt709", "-color_trc", "bt709",
                    "-colorspace", "bt709", "-color_range", "tv",
                    "-bsf:v",
                    "av1_metadata=color_primaries=1:transfer_characteristics=1:matrix_coefficients=1:color_range=tv",
                    "-c:a", "libopus", "-b:a", "64000",
                    "-metadata", "title=WebM Fixture",
                    "-metadata:s:a:0", "language=eng",
                    "-metadata:s:a:0", "title=Main Audio",
                    "-disposition:a:0", "default",
                    sourceURL.path,
                ],
                timeout: 120
            )
        )
        XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        let colorEdit = try await runner.run(
            CommandRequest(
                executableURL: mkvpropeditURL,
                arguments: [
                    "--abort-on-warnings", sourceURL.path,
                    "--edit", "track:v1",
                    "--set", "color-matrix-coefficients=1",
                    "--set", "color-range=1",
                    "--set", "color-transfer-characteristics=1",
                    "--set", "color-primaries=1",
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(colorEdit.exitCode, 0, colorEdit.standardError.text)
        return sourceURL
    }
}
