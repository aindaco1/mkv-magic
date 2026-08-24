import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

private actor WorkflowConversionRecordingRunner: CommandRunning, CommandLineDigesting {
    private let underlying = FoundationCommandRunner()
    private var executableNames = [String]()

    func run(_ request: CommandRequest) async throws -> CommandResult {
        executableNames.append(request.executableURL.lastPathComponent)
        return try await underlying.run(request)
    }

    func digestLines(
        _ requests: [CommandRequest],
        policy: CommandLineDigestPolicy
    ) async throws -> CommandLineDigest {
        try await underlying.digestLines(requests, policy: policy)
    }

    func digestTrailingHexLines(
        _ requests: [CommandRequest],
        policy: CommandTrailingHexDigestPolicy
    ) async throws -> CommandLineDigest {
        try await underlying.digestTrailingHexLines(requests, policy: policy)
    }

    func digestIntegerKeyedLines(
        _ requests: [CommandIntegerKeyedDigestRequest],
        policy: CommandIntegerKeyedLineDigestPolicy
    ) async throws -> [Int: CommandLineDigest] {
        try await underlying.digestIntegerKeyedLines(requests, policy: policy)
    }

    func capturedExecutableNames() -> [String] { executableNames }
}

final class RealToolExactTrimTests: XCTestCase {
    func testBundledToolsExactTrimOnceAtRequestedTimesWithPreservedAudioAttachmentAndChapters()
        async throws
    {
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
        guard !capabilities.availableVideoPresets.isEmpty,
            capabilities.h264VideoToolbox == .verified
        else {
            throw XCTSkip("No bundled Exact Trim and H.264 fixture encoder verified on this Mac")
        }

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-exact-trim"
        ) { root in
            let sourceURL = try await makeFixture(
                root: root,
                ffmpegURL: ffmpegURL,
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner
            )
            let destinationURL = root.appendingPathComponent("Exact Trimmed.mkv")
            let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            XCTAssertEqual(source.tracks.map(\.kind), [.video, .audio])
            XCTAssertEqual(source.attachments.count, 1)
            XCTAssertEqual(source.chapterEntryCount, 1)
            XCTAssertEqual(source.globalTagCount, 0)
            XCTAssertEqual(source.trackTagCount, 0)

            let planner = ExactTrimPlanner()
            let choice = try XCTUnwrap(
                planner.recommendedChoice(
                    for: source,
                    availableVideoPresets: capabilities.availableVideoPresets
                )
            )
            let requested = MediaTrimRange(
                start: MediaTime(nanoseconds: 3_250_000_000),
                end: MediaTime(nanoseconds: 7_750_000_000)
            )
            let executor = ExactTrimExecutor(
                ffmpegURL: ffmpegURL,
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            let preview = try await executor.preview(
                source: source,
                range: requested,
                choice: choice,
                capabilities: capabilities
            )

            XCTAssertEqual(preview.resolvedPlan.range, requested)
            XCTAssertEqual(preview.resolvedPlan.videoEncodeCount, 1)
            XCTAssertEqual(preview.resolvedPlan.audioEncodeCount, 0)
            XCTAssertEqual(preview.encodedAudioTrackIDs, [])
            XCTAssertEqual(preview.copiedAudioTrackIDs, [source.tracks[1].id])
            XCTAssertEqual(preview.trimmedChapters.editions[0].chapters[0].start, .zero)
            XCTAssertEqual(
                preview.trimmedChapters.editions[0].chapters[0].end,
                MediaTime(nanoseconds: 4_500_000_000)
            )
            XCTAssertEqual(
                preview.trimmedChapters.editions[0].chapters[0].children[1].start,
                MediaTime(nanoseconds: 1_750_000_000)
            )

            let output = try await executor.execute(
                preview: preview,
                destinationURL: destinationURL
            )

            XCTAssertEqual(output.sourceURL, destinationURL)
            XCTAssertEqual(output.tracks.map(\.kind), [.video, .audio])
            XCTAssertEqual(output.tracks[0].codec, expectedCodec(choice.videoPreset))
            XCTAssertEqual(output.tracks[1].codec, source.tracks[1].codec)
            XCTAssertEqual(output.attachments.count, 1)
            XCTAssertEqual(output.attachments[0].filename, "fixture.bin")
            XCTAssertEqual(output.attachments[0].description, "Exact Trim fixture")
            XCTAssertEqual(output.chapterEntryCount, 1)
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: sourceURL)),
                sourceDigest
            )
            let duration = try XCTUnwrap(output.duration?.nanoseconds)
            XCTAssertGreaterThanOrEqual(duration, 4_400_000_000)
            XCTAssertLessThanOrEqual(duration, 4_600_000_000)

            let outputChapters = try await ChapterEditExecutor(
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            ).preview(source: output)
            let codec = MatroskaChapterXMLCodec()
            XCTAssertEqual(
                try codec.serialize(outputChapters.original),
                try codec.serialize(preview.trimmedChapters)
            )

            let decode = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: [
                        "-hide_banner", "-nostdin", "-loglevel", "error",
                        "-i", destinationURL.path,
                        "-map", "0:v:0", "-map", "0:a:0", "-f", "null", "-",
                    ],
                    timeout: 120
                )
            )
            XCTAssertEqual(decode.exitCode, 0, decode.standardError.text)

            let convertedURL = root.appendingPathComponent("Converted Complete.mkv")
            let sourceDuration = try XCTUnwrap(source.duration)
            let conversionPreview = try await executor.preview(
                source: source,
                range: MediaTrimRange(start: .zero, end: sourceDuration),
                choice: choice,
                operation: .transcode,
                capabilities: capabilities
            )
            XCTAssertEqual(conversionPreview.resolvedPlan.operation, .transcode)
            XCTAssertEqual(
                try codec.serialize(conversionPreview.trimmedChapters),
                try codec.serialize(conversionPreview.originalChapters)
            )
            let converted = try await executor.execute(
                preview: conversionPreview,
                destinationURL: convertedURL
            )
            XCTAssertEqual(converted.tracks[0].codec, expectedCodec(choice.videoPreset))
            XCTAssertEqual(converted.tracks[1].codec, source.tracks[1].codec)
            XCTAssertEqual(converted.attachments.count, source.attachments.count)
            XCTAssertEqual(converted.attachments[0].filename, source.attachments[0].filename)
            XCTAssertEqual(converted.attachments[0].mimeType, source.attachments[0].mimeType)
            XCTAssertEqual(converted.attachments[0].size, source.attachments[0].size)
            XCTAssertEqual(converted.attachments[0].description, source.attachments[0].description)
            XCTAssertEqual(converted.chapterEntryCount, source.chapterEntryCount)
            let convertedChapters = try await ChapterEditExecutor(
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            ).preview(source: converted)
            XCTAssertEqual(
                try codec.serialize(convertedChapters.original),
                try codec.serialize(conversionPreview.originalChapters)
            )
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: sourceURL)),
                sourceDigest
            )
        }
    }

    func testBundledToolsExactTrimEveryVerifiedAudioFormatWithoutLayoutDrift() async throws {
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
        guard capabilities.h264VideoToolbox == .verified,
            Set(capabilities.availableAudioPresets) == Set(AudioTranscodePreset.allCases)
        else {
            throw XCTSkip("The complete bundled Exact Trim audio matrix is unavailable")
        }

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-exact-audio"
        ) { root in
            let sourceURL = try await makeFixture(
                root: root,
                ffmpegURL: ffmpegURL,
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner
            )
            let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            let sourceAudio = try XCTUnwrap(source.tracks.first { $0.kind == .audio })
            let executor = ExactTrimExecutor(
                ffmpegURL: ffmpegURL,
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            for preset in AudioTranscodePreset.allCases {
                let preview = try await executor.preview(
                    source: source,
                    range: MediaTrimRange(
                        start: MediaTime(nanoseconds: 250_000_000),
                        end: MediaTime(nanoseconds: 1_250_000_000)
                    ),
                    choice: ExactTrimChoice(
                        videoPreset: .h264Compatibility,
                        videoRateControl: .averageBitrate(500_000),
                        audioPolicy: ExactTrimAudioPolicy(preset: preset)
                    ),
                    capabilities: capabilities
                )
                XCTAssertEqual(preview.resolvedPlan.audioEncodeCount, 1)
                let output = try await executor.execute(
                    preview: preview,
                    destinationURL: root.appendingPathComponent("\(preset.rawValue).mkv")
                )
                let outputAudio = try XCTUnwrap(output.tracks.first { $0.kind == .audio })
                XCTAssertEqual(outputAudio.codec, preset.codecName)
                XCTAssertEqual(outputAudio.channels, sourceAudio.channels)
                XCTAssertEqual(outputAudio.channelLayout, sourceAudio.channelLayout)
                XCTAssertEqual(
                    outputAudio.sampleRate,
                    sourceAudio.sampleRate.flatMap(preset.outputSampleRate(forInput:))
                )
            }
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: sourceURL)),
                sourceDigest
            )
        }
    }

    func testBundledToolsExactTrimPreservesStaticHDR10Signal() async throws {
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
        guard
            capabilities.softwareAV1 == .verified
                || capabilities.hevc10VideoToolbox == .verified
        else {
            throw XCTSkip("No bundled 10-bit AV1 or HEVC encoder verified on this Mac")
        }

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-hdr10-exact-trim"
        ) { root in
            let sourceURL = try await makeHDR10Fixture(
                root: root,
                ffmpegURL: ffmpegURL,
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner
            )
            let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            let expectedSignal = try XCTUnwrap(
                source.tracks.first.flatMap(MediaHDR10Signal.init(track:))
            )
            let preset: VideoPreset =
                capabilities.softwareAV1 == .verified ? .av1Quality : .hevcCompatibility
            let rateControl: JoinVideoRateControl =
                preset == .av1Quality ? .constantQuality(30) : .averageBitrate(500_000)
            let choice = ExactTrimChoice(
                videoPreset: preset,
                videoRateControl: rateControl,
                encoderTuning: preset == .av1Quality ? .svtAV1Preset(10) : .codecDefault,
                audioPolicy: .packetCopy
            )
            let executor = ExactTrimExecutor(
                ffmpegURL: ffmpegURL,
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            let preview = try await executor.preview(
                source: source,
                range: MediaTrimRange(
                    start: MediaTime(nanoseconds: 200_000_000),
                    end: MediaTime(nanoseconds: 1_400_000_000)
                ),
                choice: choice,
                capabilities: capabilities
            )
            let destination = root.appendingPathComponent("HDR10 Exact Trim.mkv")
            let output = try await executor.execute(
                preview: preview,
                destinationURL: destination
            )

            XCTAssertEqual(output.tracks.count, 1)
            XCTAssertEqual(output.tracks[0].codec, expectedCodec(preset))
            XCTAssertEqual(MediaHDR10Signal(track: output.tracks[0]), expectedSignal)
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: sourceURL)),
                sourceDigest
            )
        }
    }

    func testBundledToolsCompleteConversionPacketCopiesEmbeddedTextSubtitle() async throws {
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
        guard capabilities.h264VideoToolbox == .verified else {
            throw XCTSkip("The bundled H.264 fixture encoder is unavailable")
        }

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-convert-subtitle"
        ) { root in
            let sourceURL = try await makeFixture(
                root: root,
                ffmpegURL: ffmpegURL,
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                includeSubtitle: true
            )
            let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            XCTAssertEqual(source.tracks.map(\.kind), [.video, .audio, .subtitle])
            let sourceSubtitle = try XCTUnwrap(
                source.tracks.first { $0.kind == .subtitle }
            )
            let executor = ExactTrimExecutor(
                ffmpegURL: ffmpegURL,
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            let preview = try await executor.preview(
                source: source,
                range: MediaTrimRange(
                    start: .zero,
                    end: try XCTUnwrap(source.duration)
                ),
                choice: ExactTrimChoice(
                    videoPreset: .h264Compatibility,
                    videoRateControl: .averageBitrate(500_000),
                    audioPolicy: .packetCopy
                ),
                operation: .transcode,
                capabilities: capabilities
            )
            XCTAssertEqual(preview.copiedSubtitleTrackIDs, [sourceSubtitle.id])
            let destination = root.appendingPathComponent("Converted with Subtitles.mkv")
            let output = try await executor.execute(
                preview: preview,
                destinationURL: destination
            )

            let outputSubtitle = try XCTUnwrap(
                output.tracks.first { $0.kind == .subtitle }
            )
            XCTAssertEqual(output.tracks.map(\.kind), [.video, .audio, .subtitle])
            XCTAssertEqual(outputSubtitle.codec, sourceSubtitle.codec)
            XCTAssertEqual(outputSubtitle.language, sourceSubtitle.language)
            XCTAssertEqual(outputSubtitle.title, sourceSubtitle.title)
            XCTAssertEqual(outputSubtitle.isForced, sourceSubtitle.isForced)
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: sourceURL)),
                sourceDigest
            )
        }
    }

    func testBundledToolsSavedWorkflowPreparesEditsThenEncodesVideoExactlyOnce() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let fixtureRunner = FoundationCommandRunner()
        let ffmpegURL = try catalog.url(for: .ffmpeg)
        let capabilities = try await FFmpegCapabilityProbe(
            ffmpegURL: ffmpegURL,
            runner: fixtureRunner
        ).probe()
        guard capabilities.h264VideoToolbox == .verified else {
            throw XCTSkip("The bundled H.264 fixture and conversion encoder is unavailable")
        }

        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-workflow-convert"
        ) { root in
            let sourceURL = try await makeFixture(
                root: root,
                ffmpegURL: ffmpegURL,
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: fixtureRunner,
                includeSubtitle: true
            )
            let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
            let runner = WorkflowConversionRecordingRunner()
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            XCTAssertEqual(segmentTitle(source), "Exact Trim Fixture")
            XCTAssertEqual(source.tracks.map(\.kind), [.video, .audio, .subtitle])
            let workflow = SavedWorkflow(
                name: "Clean title and convert",
                steps: [
                    SavedWorkflowStep(action: .removeSegmentTitle),
                    SavedWorkflowStep(action: .convertVideoH264),
                ]
            )
            let compiled = try SavedWorkflowCompiler().compile(
                workflow,
                for: source,
                inputs: SavedWorkflowResolvedInputs(
                    availableVideoPresets: capabilities.availableVideoPresets
                )
            )
            let destination = root.appendingPathComponent("Workflow Converted.mkv")
            let executor = SavedWorkflowVideoConversionExecutor(
                ffmpegURL: ffmpegURL,
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            let output = try await executor.execute(
                source: source,
                workflow: compiled,
                capabilities: capabilities,
                expectedSourceRevision: try MediaFileRevisionReader().read(sourceURL),
                destinationURL: destination
            )

            let executableNames = await runner.capturedExecutableNames()
            XCTAssertEqual(executableNames.filter { $0 == "ffmpeg" }.count, 1)
            XCTAssertLessThan(
                try XCTUnwrap(executableNames.firstIndex(of: "mkvpropedit")),
                try XCTUnwrap(executableNames.firstIndex(of: "ffmpeg"))
            )
            XCTAssertNil(segmentTitle(output))
            XCTAssertEqual(output.tracks.map(\.kind), [.video, .audio, .subtitle])
            XCTAssertEqual(output.tracks[0].codec, "h264")
            XCTAssertEqual(output.attachments.count, 1)
            XCTAssertEqual(output.chapterEntryCount, 1)
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: sourceURL)),
                sourceDigest
            )
            let reopenedSource = try await inspector.inspect(sourceURL)
            XCTAssertEqual(segmentTitle(reopenedSource), "Exact Trim Fixture")
        }
    }

    private func makeFixture(
        root: URL,
        ffmpegURL: URL,
        mkvpropeditURL: URL,
        runner: FoundationCommandRunner,
        includeSubtitle: Bool = false
    ) async throws -> URL {
        let rawVideoURL = root.appendingPathComponent("frames.yuv")
        let rawAudioURL = root.appendingPathComponent("audio.pcm")
        let sourceURL = root.appendingPathComponent("Source.mkv")
        let width = 128
        let height = 96
        let frameCount = 100
        let bytesPerFrame = width * height * 3 / 2
        var video = Data()
        video.reserveCapacity(bytesPerFrame * frameCount)
        for frame in 0..<frameCount {
            video.append(Data(repeating: UInt8(16 + (frame % 32)), count: bytesPerFrame))
        }
        try video.write(to: rawVideoURL)
        try Data(repeating: 0, count: 48_000 * 2 * 2 * 10).write(to: rawAudioURL)
        let subtitleURL = root.appendingPathComponent("english.srt")
        if includeSubtitle {
            try Data(
                "1\n00:00:01,000 --> 00:00:02,000\nFirst cue\n\n"
                    .appending("2\n00:00:06,000 --> 00:00:07,000\nSecond cue\n")
                    .utf8
            ).write(to: subtitleURL)
        }

        var arguments = [
            "-hide_banner", "-nostdin", "-loglevel", "error",
            "-f", "rawvideo", "-pixel_format", "yuv420p",
            "-video_size", "\(width)x\(height)", "-framerate", "10",
            "-i", rawVideoURL.path,
            "-f", "s16le", "-ar", "48000", "-ac", "2",
            "-i", rawAudioURL.path,
        ]
        if includeSubtitle {
            arguments.append(contentsOf: ["-f", "srt", "-i", subtitleURL.path])
        }
        arguments.append(contentsOf: ["-map", "0:v:0", "-map", "1:a:0"])
        if includeSubtitle {
            arguments.append(contentsOf: ["-map", "2:s:0"])
        }
        arguments.append(contentsOf: [
            "-frames:v", "\(frameCount)",
            "-c:v", "h264_videotoolbox", "-profile:v", "high",
            "-g", "20", "-bf", "0", "-b:v", "500000",
            "-color_primaries", "bt709", "-color_trc", "bt709",
            "-colorspace", "bt709", "-color_range", "tv",
            "-bsf:v",
            "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1",
            "-c:a", "aac", "-b:a", "192000",
            "-c:s", "srt",
            "-metadata", "title=Exact Trim Fixture",
            "-metadata:s:a:0", "language=eng",
            "-metadata:s:a:0", "title=Original Mix",
            "-disposition:a:0", "default",
        ])
        if includeSubtitle {
            arguments.append(contentsOf: [
                "-metadata:s:s:0", "language=eng",
                "-metadata:s:s:0", "title=English Full",
                "-disposition:s:0", "forced",
            ])
        }
        arguments.append(sourceURL.path)
        let encode = try await runner.run(
            CommandRequest(
                executableURL: ffmpegURL,
                arguments: arguments,
                timeout: 120
            )
        )
        XCTAssertEqual(encode.exitCode, 0, encode.standardError.text)

        let chapterURL = root.appendingPathComponent("source-chapters.xml")
        try MatroskaChapterXMLCodec().serialize(nestedChapters()).write(to: chapterURL)
        let attachmentURL = root.appendingPathComponent("fixture.bin")
        try Data("attachment payload".utf8).write(to: attachmentURL)
        let edit = try await runner.run(
            CommandRequest(
                executableURL: mkvpropeditURL,
                arguments: [
                    "--abort-on-warnings", sourceURL.path,
                    "--edit", "track:v1",
                    "--set", "color-matrix-coefficients=1",
                    "--set", "color-range=1",
                    "--set", "color-transfer-characteristics=1",
                    "--set", "color-primaries=1",
                    "--chapters", chapterURL.path,
                    "--attachment-name", "fixture.bin",
                    "--attachment-mime-type", "application/octet-stream",
                    "--attachment-description", "Exact Trim fixture",
                    "--add-attachment", attachmentURL.path,
                    "--tags", "all:",
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(edit.exitCode, 0, edit.standardError.text)
        return sourceURL
    }

    private func makeHDR10Fixture(
        root: URL,
        ffmpegURL: URL,
        mkvpropeditURL: URL,
        runner: FoundationCommandRunner
    ) async throws -> URL {
        let width = 96
        let height = 64
        let frameCount = 20
        let rawVideoURL = root.appendingPathComponent("hdr10-frames.yuv")
        let sourceURL = root.appendingPathComponent("HDR10 Source.mkv")
        try Data(repeating: 0, count: width * height * 3 * frameCount).write(
            to: rawVideoURL
        )
        let encode = try await runner.run(
            CommandRequest(
                executableURL: ffmpegURL,
                arguments: [
                    "-hide_banner", "-nostdin", "-loglevel", "error",
                    "-mastering_display:v:0",
                    "G(13250,34500)B(7500,3000)R(34000,16000)"
                        + "WP(15635,16450)L(10000000,50)",
                    "-content_light:v:0", "1000,400",
                    "-f", "rawvideo", "-pixel_format", "yuv420p10le",
                    "-video_size", "\(width)x\(height)", "-framerate", "10",
                    "-i", rawVideoURL.path,
                    "-frames:v", "\(frameCount)",
                    "-vf",
                    "setparams=range=limited:color_primaries=bt2020:"
                        + "color_trc=smpte2084:colorspace=bt2020nc",
                    "-c:v", "hevc_videotoolbox", "-profile:v", "main10",
                    "-pix_fmt", "p010le", "-b:v", "500000",
                    "-color_primaries", "9", "-color_trc", "16",
                    "-colorspace", "9", "-color_range", "1",
                    "-metadata", "title=HDR10 Exact Trim Fixture",
                    sourceURL.path,
                ],
                timeout: 120
            )
        )
        XCTAssertEqual(encode.exitCode, 0, encode.standardError.text)
        let clearTags = try await runner.run(
            CommandRequest(
                executableURL: mkvpropeditURL,
                arguments: ["--abort-on-warnings", sourceURL.path, "--tags", "all:"],
                timeout: 60
            )
        )
        XCTAssertEqual(clearTags.exitCode, 0, clearTags.standardError.text)
        return sourceURL
    }

    private func nestedChapters() -> MatroskaChapterDocument {
        let duration = MediaTime(nanoseconds: 10_000_000_000)
        return MatroskaChapterDocument(editions: [
            MatroskaChapterEdition(
                isDefault: true,
                chapters: [
                    MatroskaChapterAtom(
                        start: .zero,
                        end: duration,
                        displays: [ChapterDisplay(title: "Feature")],
                        children: [
                            MatroskaChapterAtom(
                                start: .zero,
                                end: MediaTime(nanoseconds: 5_000_000_000),
                                displays: [ChapterDisplay(title: "First Half")]
                            ),
                            MatroskaChapterAtom(
                                start: MediaTime(nanoseconds: 5_000_000_000),
                                end: duration,
                                displays: [ChapterDisplay(title: "Second Half")]
                            ),
                        ]
                    )
                ]
            )
        ])
    }

    private func expectedCodec(_ preset: VideoPreset) -> String {
        switch preset {
        case .av1Quality: "av1"
        case .hevcCompatibility: "hevc"
        case .h264Compatibility: "h264"
        case .proRes: "prores"
        }
    }

    private func segmentTitle(_ asset: MediaAsset) -> String? {
        asset.metadata.first(where: {
            $0.key.caseInsensitiveCompare("title") == .orderedSame
        })?.value
    }
}
