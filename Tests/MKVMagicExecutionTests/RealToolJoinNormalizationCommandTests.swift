import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

final class RealToolJoinNormalizationCommandTests: XCTestCase {
    func testBundledFFmpegAndVerifiedExecutorNormalizeTwoDifferentCanvases() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let ffmpegURL = try catalog.url(for: .ffmpeg)
        let capabilities = try await FFmpegCapabilityProbe(
            ffmpegURL: ffmpegURL,
            runner: runner
        ).probe()
        guard capabilities.hevc10VideoToolbox == .verified else {
            throw XCTSkip("Bundled HEVC VideoToolbox did not verify on this Mac")
        }

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-normalization"
        ) { root in
            let first = try await makeVideoFixture(
                root: root,
                name: "first",
                width: 64,
                height: 48,
                fill: 16,
                ffmpegURL: ffmpegURL,
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner
            )
            let second = try await makeVideoFixture(
                root: root,
                name: "second",
                width: 80,
                height: 64,
                fill: 32,
                ffmpegURL: ffmpegURL,
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner
            )
            let sourceURLs = [first, second]
            let sourceDigests = try sourceURLs.map {
                SHA256.hash(data: try Data(contentsOf: $0))
            }
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            var sources = [MediaAsset]()
            for sourceURL in sourceURLs {
                try await sources.append(inspector.inspect(sourceURL))
            }
            let mapping = try JoinTrackMappingProposer().propose(sources: sources).mapping
            let proposal = try JoinNormalizationPlanner().propose(
                sources: sources,
                mapping: mapping,
                preferredVideoPreset: .hevcCompatibility
            )
            XCTAssertTrue(
                proposal.blockers.isEmpty,
                "\(proposal.blockers); colors=\(sources.map { $0.tracks.map(\.colorInfo) })"
            )
            XCTAssertEqual(
                proposal.videoLanes[0].recommendedCanvas,
                MediaDimensions(width: 80, height: 64)
            )
            let choice = JoinVideoTargetChoice(
                preset: .hevcCompatibility,
                canvas: try XCTUnwrap(proposal.videoLanes[0].recommendedCanvas),
                frameRatePolicy: .preserveSourceTiming,
                dynamicRange: .sdr,
                rateControl: .averageBitrate(500_000)
            )
            let resolved = try JoinNormalizationChoiceResolver().resolve(
                sources: sources,
                proposal: proposal,
                choices: JoinNormalizationChoices(videoTargetsByLane: [0: choice]),
                availableVideoPresets: Set(capabilities.availableVideoPresets),
                aacAvailable: capabilities.aac == .verified
            )
            let outputURL = root.appendingPathComponent("normalized.mkv")
            let command = try JoinNormalizationCommandBuilder().build(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities,
                outputURL: outputURL
            )

            let result = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: command.arguments,
                    timeout: 120
                )
            )
            XCTAssertEqual(result.exitCode, 0, result.standardError.text)
            let output = try await inspector.inspect(outputURL)
            XCTAssertEqual(output.tracks.count, 1)
            XCTAssertEqual(output.tracks[0].kind, .video)
            XCTAssertEqual(output.tracks[0].codec, "hevc")
            XCTAssertEqual(output.tracks[0].dimensions, MediaDimensions(width: 80, height: 64))
            XCTAssertEqual(output.tracks[0].bitDepth, 10)
            let duration = try XCTUnwrap(output.duration?.nanoseconds)
            XCTAssertGreaterThan(duration, 800_000_000)
            XCTAssertLessThan(duration, 1_200_000_000)
            XCTAssertEqual(
                try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
                sourceDigests
            )

            let decode = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: [
                        "-hide_banner", "-loglevel", "error", "-i", outputURL.path,
                        "-map", "0:v:0", "-f", "null", "-",
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(decode.exitCode, 0, decode.standardError.text)

            let executor = JoinNormalizationExecutor(
                ffmpegURL: ffmpegURL,
                runner: runner,
                inspector: inspector
            )
            let preview = try executor.preview(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities
            )
            let committedURL = root.appendingPathComponent("verified-normalized-video.mkv")
            let committed = try await executor.execute(
                preview: preview,
                destinationURL: committedURL
            )
            XCTAssertEqual(committed.sourceURL, committedURL)
            XCTAssertEqual(committed.tracks.count, 1)
            XCTAssertEqual(committed.tracks[0].codec, "hevc")
            XCTAssertEqual(
                committed.tracks[0].dimensions,
                MediaDimensions(width: 80, height: 64)
            )
            XCTAssertEqual(committed.tracks[0].bitDepth, 10)
            XCTAssertEqual(
                try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
                sourceDigests
            )

            let chapterSources = try sources.enumerated().map { index, source in
                let sourceDuration = try XCTUnwrap(source.duration)
                return JoinedChapterSource(
                    title: "Part \(index + 1)",
                    duration: sourceDuration,
                    retainedStart: .zero,
                    retainedEnd: sourceDuration,
                    selectedEditionChapters: []
                )
            }
            let chapters = try JoinedChapterComposer().compose(chapterSources)
            let chaptersURL = root.appendingPathComponent("joined-chapters.xml")
            try MatroskaChapterXMLCodec().serialize(chapters.document).write(to: chaptersURL)
            let finalURL = root.appendingPathComponent("assembled.mkv")
            let assembly = try JoinFinalAssemblyCommandBuilder().build(
                sources: sources,
                resolvedPlan: resolved,
                normalizedBundle: committed,
                chapters: chapters,
                chaptersURL: chaptersURL,
                outputURL: finalURL
            )
            let assemblyResult = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .mkvmerge),
                    arguments: assembly.arguments,
                    timeout: 60
                )
            )
            XCTAssertEqual(assemblyResult.exitCode, 0, assemblyResult.standardError.text)
            let assembled = try await inspector.inspect(finalURL)
            XCTAssertEqual(assembled.tracks.count, 1)
            XCTAssertEqual(assembled.tracks[0].codec, "hevc")
            XCTAssertEqual(assembled.chapterEntryCount, 2)
            XCTAssertEqual(
                assembled.tracks[0].dimensions,
                MediaDimensions(width: 80, height: 64)
            )
            XCTAssertEqual(
                try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
                sourceDigests
            )
        }
    }

    func testBundledToolsAssembleNormalizedVideoWithDirectPacketCopyAudio() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let ffmpegURL = try catalog.url(for: .ffmpeg)
        let capabilities = try await FFmpegCapabilityProbe(
            ffmpegURL: ffmpegURL,
            runner: runner
        ).probe()
        guard capabilities.hevc10VideoToolbox == .verified,
            capabilities.aac == .verified
        else {
            throw XCTSkip("Bundled HEVC and AAC capabilities did not verify on this Mac")
        }

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-fused-assembly"
        ) { root in
            let first = try await makeAVFixture(
                root: root,
                name: "first-av",
                width: 64,
                height: 48,
                fill: 16,
                ffmpegURL: ffmpegURL,
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner
            )
            let second = try await makeAVFixture(
                root: root,
                name: "second-av",
                width: 80,
                height: 64,
                fill: 32,
                ffmpegURL: ffmpegURL,
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner
            )
            let sourceURLs = [first, second]
            let sourceDigests = try sourceURLs.map {
                SHA256.hash(data: try Data(contentsOf: $0))
            }
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            var sources = [MediaAsset]()
            for sourceURL in sourceURLs {
                try await sources.append(inspector.inspect(sourceURL))
            }
            let mapping = try JoinTrackMappingProposer().propose(sources: sources).mapping
            let proposal = try JoinNormalizationPlanner().propose(
                sources: sources,
                mapping: mapping,
                preferredVideoPreset: .hevcCompatibility
            )
            XCTAssertTrue(proposal.blockers.isEmpty, "\(proposal.blockers)")
            XCTAssertTrue(try XCTUnwrap(proposal.videoLanes.first).encodesVideo)
            XCTAssertFalse(try XCTUnwrap(proposal.audioLanes.first).encodesAudio)
            let videoLane = try XCTUnwrap(proposal.videoLanes.first)
            let resolved = try JoinNormalizationChoiceResolver().resolve(
                sources: sources,
                proposal: proposal,
                choices: JoinNormalizationChoices(
                    videoTargetsByLane: [
                        videoLane.laneIndex: JoinVideoTargetChoice(
                            preset: .hevcCompatibility,
                            canvas: try XCTUnwrap(videoLane.recommendedCanvas),
                            frameRatePolicy: .preserveSourceTiming,
                            dynamicRange: .sdr,
                            rateControl: .averageBitrate(500_000)
                        )
                    ]
                ),
                availableVideoPresets: Set(capabilities.availableVideoPresets),
                aacAvailable: true
            )
            let normalizationExecutor = JoinNormalizationExecutor(
                ffmpegURL: ffmpegURL,
                runner: runner,
                inspector: inspector
            )
            let normalizationPreview = try normalizationExecutor.preview(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities
            )
            let normalized = try await normalizationExecutor.execute(
                preview: normalizationPreview,
                destinationURL: root.appendingPathComponent("normalized-video.mkv")
            )
            XCTAssertEqual(normalized.tracks.count, 1)
            XCTAssertEqual(normalized.tracks[0].kind, .video)

            let chapterSources = try sources.enumerated().map { index, source in
                let duration = try XCTUnwrap(source.duration)
                return JoinedChapterSource(
                    title: "Part \(index + 1)",
                    duration: duration,
                    retainedStart: .zero,
                    retainedEnd: duration,
                    selectedEditionChapters: []
                )
            }
            let chapters = try JoinedChapterComposer().compose(chapterSources)
            let finalURL = root.appendingPathComponent("assembled-video-and-audio.mkv")
            let finalExecutor = JoinFinalAssemblyExecutor(
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                mkvextractURL: try catalog.url(for: .mkvextract),
                runner: runner,
                inspector: inspector
            )
            let finalPreview = try await finalExecutor.preview(
                sources: sources,
                resolvedPlan: resolved,
                normalizedBundle: normalized,
                chapters: chapters
            )
            XCTAssertEqual(
                finalPreview.commandLanes.map(\.mechanism),
                [.normalized, .packetCopy]
            )
            let assembled = try await finalExecutor.execute(
                preview: finalPreview,
                destinationURL: finalURL
            )
            XCTAssertEqual(assembled.tracks.map(\.kind), [.video, .audio])
            XCTAssertEqual(assembled.tracks[0].codec, "hevc")
            XCTAssertEqual(assembled.tracks[1].codec, "aac")
            XCTAssertEqual(assembled.tracks[1].uid, sources[0].tracks[1].uid)
            XCTAssertEqual(assembled.chapterEntryCount, 2)
            XCTAssertEqual(
                try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
                sourceDigests
            )
        }
    }

    func testBundledFFmpegNormalizesStereoAndSurroundOnceIntoAACSurround() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let ffmpegURL = try catalog.url(for: .ffmpeg)
        let capabilities = try await FFmpegCapabilityProbe(
            ffmpegURL: ffmpegURL,
            runner: runner
        ).probe()
        guard capabilities.aac == .verified else {
            throw XCTSkip("Bundled AAC did not verify on this Mac")
        }

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-audio-normalization"
        ) { root in
            let stereo = try await makeAudioFixture(
                root: root,
                name: "stereo",
                channels: 2,
                layout: "stereo",
                sampleRate: 44_100,
                fill: 1,
                ffmpegURL: ffmpegURL,
                runner: runner
            )
            let surround = try await makeAudioFixture(
                root: root,
                name: "surround",
                channels: 6,
                layout: "5.1(side)",
                sampleRate: 48_000,
                fill: 2,
                ffmpegURL: ffmpegURL,
                runner: runner
            )
            let sourceURLs = [stereo, surround]
            let sourceDigests = try sourceURLs.map {
                SHA256.hash(data: try Data(contentsOf: $0))
            }
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            var sources = [MediaAsset]()
            for sourceURL in sourceURLs {
                try await sources.append(inspector.inspect(sourceURL))
            }
            let mapping = try JoinTrackMappingProposer().propose(sources: sources).mapping
            let proposal = try JoinNormalizationPlanner().propose(
                sources: sources,
                mapping: mapping
            )
            XCTAssertTrue(proposal.blockers.isEmpty, "\(proposal.blockers)")
            let lane = try XCTUnwrap(proposal.audioLanes.first)
            let choice = JoinAudioTargetChoice(
                codec: try XCTUnwrap(lane.outputCodec),
                channels: try XCTUnwrap(lane.outputChannels),
                channelLayout: try XCTUnwrap(lane.outputChannelLayout),
                sampleRate: try XCTUnwrap(lane.outputSampleRate),
                bitrate: try XCTUnwrap(lane.outputBitrate),
                allowsSyntheticSilence: false
            )
            XCTAssertEqual(choice.channels, 6)
            XCTAssertEqual(choice.channelLayout, "5.1")
            let resolved = try JoinNormalizationChoiceResolver().resolve(
                sources: sources,
                proposal: proposal,
                choices: JoinNormalizationChoices(audioTargetsByLane: [0: choice]),
                availableVideoPresets: Set(capabilities.availableVideoPresets),
                aacAvailable: true
            )
            let outputURL = root.appendingPathComponent("normalized-audio.mkv")
            let command = try JoinNormalizationCommandBuilder().build(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities,
                outputURL: outputURL
            )
            let result = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: command.arguments,
                    timeout: 120
                )
            )
            XCTAssertEqual(result.exitCode, 0, result.standardError.text)

            let output = try await inspector.inspect(outputURL)
            XCTAssertEqual(output.tracks.count, 1)
            XCTAssertEqual(output.tracks[0].kind, .audio)
            XCTAssertEqual(output.tracks[0].codec, "aac")
            XCTAssertEqual(output.tracks[0].channels, 6)
            XCTAssertEqual(output.tracks[0].sampleRate, 48_000)
            let duration = try XCTUnwrap(output.duration?.nanoseconds)
            XCTAssertGreaterThan(duration, 1_800_000_000)
            XCTAssertLessThan(duration, 2_200_000_000)
            XCTAssertEqual(
                try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
                sourceDigests
            )

            let decode = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: [
                        "-hide_banner", "-loglevel", "error", "-i", outputURL.path,
                        "-map", "0:a:0", "-f", "null", "-",
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(decode.exitCode, 0, decode.standardError.text)

            let executor = JoinNormalizationExecutor(
                ffmpegURL: ffmpegURL,
                runner: runner,
                inspector: inspector
            )
            let preview = try executor.preview(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities
            )
            let committedURL = root.appendingPathComponent("verified-normalized-audio.mkv")
            let committed = try await executor.execute(
                preview: preview,
                destinationURL: committedURL
            )
            XCTAssertEqual(committed.sourceURL, committedURL)
            XCTAssertEqual(committed.tracks.count, 1)
            XCTAssertEqual(committed.tracks[0].codec, "aac")
            XCTAssertEqual(committed.tracks[0].channels, 6)
            XCTAssertEqual(committed.tracks[0].channelLayout, "5.1")
            XCTAssertEqual(committed.tracks[0].sampleRate, 48_000)
            XCTAssertEqual(
                try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
                sourceDigests
            )
        }
    }

    private func makeVideoFixture(
        root: URL,
        name: String,
        width: Int,
        height: Int,
        fill: UInt8,
        ffmpegURL: URL,
        mkvpropeditURL: URL,
        runner: FoundationCommandRunner
    ) async throws -> URL {
        let rawURL = root.appendingPathComponent("\(name).yuv")
        let outputURL = root.appendingPathComponent("\(name).mkv")
        let bytesPerFrame = width * height * 3 / 2
        try Data(repeating: fill, count: bytesPerFrame * 12).write(to: rawURL)
        let result = try await runner.run(
            CommandRequest(
                executableURL: ffmpegURL,
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "rawvideo", "-pixel_format", "yuv420p",
                    "-video_size", "\(width)x\(height)", "-framerate", "24",
                    "-i", rawURL.path, "-frames:v", "12",
                    "-c:v", "h264_videotoolbox", "-profile:v", "high",
                    "-color_primaries:v", "bt709", "-color_trc:v", "bt709",
                    "-colorspace:v", "bt709", "-color_range:v", "tv",
                    "-bsf:v",
                    "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1",
                    outputURL.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        let colorEdit = try await runner.run(
            CommandRequest(
                executableURL: mkvpropeditURL,
                arguments: [
                    outputURL.path, "--edit", "track:v1",
                    "--set", "color-matrix-coefficients=1",
                    "--set", "color-range=1",
                    "--set", "color-transfer-characteristics=1",
                    "--set", "color-primaries=1",
                    "--tags", "all:",
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(colorEdit.exitCode, 0, colorEdit.standardError.text)
        return outputURL
    }

    private func makeAudioFixture(
        root: URL,
        name: String,
        channels: Int,
        layout: String,
        sampleRate: Int,
        fill: UInt8,
        ffmpegURL: URL,
        runner: FoundationCommandRunner
    ) async throws -> URL {
        let rawURL = root.appendingPathComponent("\(name).pcm")
        let outputURL = root.appendingPathComponent("\(name).mkv")
        try Data(repeating: fill, count: sampleRate * channels * 2).write(to: rawURL)
        let result = try await runner.run(
            CommandRequest(
                executableURL: ffmpegURL,
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", String(sampleRate), "-ac", String(channels),
                    "-channel_layout", layout, "-i", rawURL.path,
                    "-c:a", "aac_at", "-b:a", "192k", outputURL.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        return outputURL
    }

    private func makeAVFixture(
        root: URL,
        name: String,
        width: Int,
        height: Int,
        fill: UInt8,
        ffmpegURL: URL,
        mkvpropeditURL: URL,
        runner: FoundationCommandRunner
    ) async throws -> URL {
        let rawVideoURL = root.appendingPathComponent("\(name).yuv")
        let rawAudioURL = root.appendingPathComponent("\(name).pcm")
        let outputURL = root.appendingPathComponent("\(name).mkv")
        let bytesPerFrame = width * height * 3 / 2
        try Data(repeating: fill, count: bytesPerFrame * 12).write(to: rawVideoURL)
        try Data(repeating: fill, count: 48_000 * 2).write(to: rawAudioURL)
        let result = try await runner.run(
            CommandRequest(
                executableURL: ffmpegURL,
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "rawvideo", "-pixel_format", "yuv420p",
                    "-video_size", "\(width)x\(height)", "-framerate", "24",
                    "-i", rawVideoURL.path,
                    "-f", "s16le", "-ar", "48000", "-ac", "2",
                    "-channel_layout", "stereo", "-i", rawAudioURL.path,
                    "-map", "0:v:0", "-map", "1:a:0", "-frames:v", "12",
                    "-c:v", "h264_videotoolbox", "-profile:v", "high",
                    "-color_primaries:v", "bt709", "-color_trc:v", "bt709",
                    "-colorspace:v", "bt709", "-color_range:v", "tv",
                    "-bsf:v",
                    "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1",
                    "-c:a", "aac_at", "-b:a", "128k",
                    "-metadata", "title=Fused Assembly Fixture",
                    "-metadata:s:a:0", "language=eng",
                    "-metadata:s:a:0", "title=Main Audio",
                    outputURL.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        let edit = try await runner.run(
            CommandRequest(
                executableURL: mkvpropeditURL,
                arguments: [
                    outputURL.path, "--edit", "track:v1",
                    "--set", "color-matrix-coefficients=1",
                    "--set", "color-range=1",
                    "--set", "color-transfer-characteristics=1",
                    "--set", "color-primaries=1",
                    "--tags", "all:",
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(edit.exitCode, 0, edit.standardError.text)
        return outputURL
    }
}
