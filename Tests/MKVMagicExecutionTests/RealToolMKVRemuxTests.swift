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
    func testMultipleSidecarsShareOneVerifiedRemuxAndAuditEachTrack() async throws {
        let (catalog, runner, _) = try await requiredTools()
        try await PrivateTemporaryDirectory.withDirectory(prefix: "mkv-magic-multiple-sidecars") {
            root in
            let sourceURL = try await makeMP4Fixture(
                root: root, ffmpegURL: try catalog.url(for: .ffmpeg), runner: runner)
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge), runner: runner)
            let source = try await inspector.inspect(sourceURL)
            let executor = MKVRemuxExecutor(
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                ffmpegURL: try catalog.url(for: .ffmpeg),
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvextractURL: try catalog.url(for: .mkvextract),
                runner: runner, inspector: inspector)
            var previews = [MKVRemuxWithExternalSubtitlePreview]()
            var originals = [URL: Data]()
            originals[sourceURL] = try Data(contentsOf: sourceURL)
            for (index, language) in ["en", "es", "fr"].enumerated() {
                let isASS = index == 2
                let url = root.appendingPathComponent("Source.\(language).\(isASS ? "ass" : "srt")")
                let text =
                    isASS
                    ? "[Script Info]\nScriptType: v4.00+\n[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:00.00,0:00:01.50,Default,,0,0,0,,{\\an8}Distinct styled subtitle\n"
                    : "1\n00:00:00,000 --> 00:00:01,500\nDistinct subtitle \(index)\n"
                let data = Data(text.utf8)
                try data.write(to: url)
                originals[url] = data
                let payload: ExternalSubtitleMuxPayload
                if isASS {
                    payload = .original(
                        .advanced(
                            try await AdvancedSubtitleCleanupExecutor().preview(sourceURL: url)))
                } else {
                    payload = .original(
                        .subRip(try await SubtitleCleanupExecutor().preview(sourceURL: url)))
                }
                previews.append(
                    try executor.preview(
                        source: source, subtitlePayload: payload,
                        subtitleMetadata: ExternalSubtitleTrackMetadata(
                            language: language, isForced: index == 1, isHearingImpaired: index == 2),
                        trackLanguageOverrides: [1: "de"]))
            }
            let output = try await executor.execute(
                previews: previews, destinationURL: root.appendingPathComponent("All.mkv"))
            XCTAssertEqual(
                output.tracks.map(\.kind), [.video, .audio, .subtitle, .subtitle, .subtitle])
            XCTAssertEqual(
                try output.tracks.dropFirst().map {
                    try TrackLanguageTag.canonical($0.language ?? "und")
                }, ["de", "en", "es", "fr"])
            XCTAssertTrue(output.tracks[3].isForced)
            XCTAssertTrue(output.tracks[4].isHearingImpaired)
            XCTAssertEqual(output.chapters.map(\.title), source.chapters.map(\.title))
            for (url, data) in originals { XCTAssertEqual(try Data(contentsOf: url), data) }
            // A repeated source must not be appended twice or create any output.
            let duplicate = root.appendingPathComponent("Duplicate.mkv")
            do {
                _ = try await executor.execute(
                    previews: [previews[0], previews[0]], destinationURL: duplicate)
                XCTFail("Duplicate sidecar accepted")
            } catch { XCTAssertFalse(FileManager.default.fileExists(atPath: duplicate.path)) }
            // Every sidecar, not only the first, is bound to its reviewed bytes.
            let changedURL = previews[1].subtitlePayload.sourceURL
            try Data("1\n00:00:00,000 --> 00:00:01,500\nChanged after review\n".utf8).write(
                to: changedURL)
            let staleOutput = root.appendingPathComponent("Stale.mkv")
            do {
                _ = try await executor.execute(previews: previews, destinationURL: staleOutput)
                XCTFail("Changed second sidecar accepted")
            } catch {
                XCTAssertFalse(FileManager.default.fileExists(atPath: staleOutput.path))
                XCTAssertEqual(try Data(contentsOf: sourceURL), originals[sourceURL])
            }
        }
    }

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

    func testBundledToolsRemuxMP4AndSRTInOneVerifiedZeroEncodePass() async throws {
        let (catalog, runner, _) = try await requiredTools()

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-remux-subtitle"
        ) { root in
            let sourceURL = try await makeMP4Fixture(
                root: root,
                ffmpegURL: try catalog.url(for: .ffmpeg),
                runner: runner,
                chapterTitles: ["", ""]
            )
            let subtitleURL = root.appendingPathComponent("Source.fr.srt")
            let subtitleData = Data(
                "1\n00:00:00,000 --> 00:00:01,500\nBonjour\n".utf8
            )
            try subtitleData.write(to: subtitleURL)
            let destinationURL = root.appendingPathComponent("Source — Subtitled.mkv")
            let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
            let subtitleDigest = SHA256.hash(data: try Data(contentsOf: subtitleURL))
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            XCTAssertEqual(source.chapters.map(\.title), ["Chapter 1", "Chapter 2"])
            let subtitlePreview = try await SubtitleCleanupExecutor().preview(
                sourceURL: subtitleURL
            )
            let executor = MKVRemuxExecutor(
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                ffmpegURL: try catalog.url(for: .ffmpeg),
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvextractURL: try catalog.url(for: .mkvextract),
                runner: runner,
                inspector: inspector
            )
            let preview = try executor.preview(
                source: source,
                subtitlePayload: .original(.subRip(subtitlePreview)),
                subtitleMetadata: ExternalSubtitleTrackMetadata(
                    language: "fr",
                    name: "French"
                ),
                trackLanguageOverrides: [1: "es"]
            )
            let output = try await executor.execute(
                preview: preview,
                destinationURL: destinationURL
            )

            XCTAssertEqual(output.tracks.map(\.kind), [.video, .audio, .subtitle])
            XCTAssertEqual(
                try TrackLanguageTag.canonical(output.tracks[1].language ?? "und"),
                "es"
            )
            XCTAssertEqual(
                try TrackLanguageTag.canonical(output.tracks[2].language ?? "und"),
                "fr"
            )
            XCTAssertEqual(output.tracks[2].title, "French")
            XCTAssertEqual(output.chapters.map(\.title), source.chapters.map(\.title))
            XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: sourceURL)), sourceDigest)
            XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: subtitleURL)), subtitleDigest)
        }
    }

    func testSelectedRealMP4AndSRTIfProvided() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sourcePath = environment["MKV_MAGIC_REMUX_SOURCE"],
            let subtitlePath = environment["MKV_MAGIC_REMUX_SUBTITLE"]
        else {
            throw XCTSkip(
                "Set MKV_MAGIC_REMUX_SOURCE and MKV_MAGIC_REMUX_SUBTITLE for real-media acceptance"
            )
        }
        let (catalog, runner, _) = try await requiredTools()
        let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
        let subtitleURL = URL(fileURLWithPath: subtitlePath).standardizedFileURL
        let sourceRevision = try MediaFileRevisionReader().read(sourceURL)
        let subtitleDigest = SHA256.hash(data: try Data(contentsOf: subtitleURL))

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-selected-real-remux"
        ) { root in
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            let subtitlePreview = try await SubtitleCleanupExecutor().preview(
                sourceURL: subtitleURL
            )
            let subtitleMatch = ExternalSubtitleMatcher().match(
                media: source,
                subtitleURL: subtitleURL,
                subtitle: subtitlePreview.cleanup.original
            )
            let filenameLanguage = FilenameLanguageInference.language(in: sourceURL)
            let audioLanguages = Dictionary(
                uniqueKeysWithValues: source.tracks.filter { $0.kind == .audio }.map { track in
                    let existing = track.language?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let language =
                        existing.flatMap { value in
                            value.isEmpty || value.caseInsensitiveCompare("und") == .orderedSame
                                ? nil : value
                        } ?? filenameLanguage ?? "und"
                    return (track.id, language)
                }
            )
            let executor = MKVRemuxExecutor(
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                ffmpegURL: try catalog.url(for: .ffmpeg),
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvextractURL: try catalog.url(for: .mkvextract),
                runner: runner,
                inspector: inspector
            )
            let preview = try executor.preview(
                source: source,
                subtitlePayload: .original(.subRip(subtitlePreview)),
                subtitleMetadata: subtitleMatch.suggestedMetadata,
                trackLanguageOverrides: audioLanguages
            )
            let output = try await executor.execute(
                preview: preview,
                destinationURL: root.appendingPathComponent("Selected — Subtitled.mkv")
            )

            XCTAssertEqual(output.chapters.map(\.title), source.chapters.map(\.title))
            XCTAssertEqual(output.tracks.last?.kind, .subtitle)
            XCTAssertEqual(try MediaFileRevisionReader().read(sourceURL), sourceRevision)
            XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: subtitleURL)), subtitleDigest)
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
        runner: FoundationCommandRunner,
        chapterTitles: [String] = ["Opening", "Second"]
    ) async throws -> URL {
        XCTAssertEqual(chapterTitles.count, 2)
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
            ";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=1000\ntitle=\(chapterTitles[0])\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=1000\nEND=2000\ntitle=\(chapterTitles[1])\n"
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
