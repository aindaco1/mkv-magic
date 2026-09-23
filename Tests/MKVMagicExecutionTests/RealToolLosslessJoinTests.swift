import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

final class RealToolLosslessJoinTests: XCTestCase {
    func testBundledToolsHardJoinCompatibleMKVsWithExactNestedChapters() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-lossless-join-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawOne = root.appendingPathComponent("one.pcm")
        let rawTwo = root.appendingPathComponent("two.pcm")
        let rawThree = root.appendingPathComponent("three.pcm")
        let sourceOne = root.appendingPathComponent("one.mkv")
        let sourceTwo = root.appendingPathComponent("two.mkv")
        let sourceThree = root.appendingPathComponent("three.mkv")
        let destination = root.appendingPathComponent("joined.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawOne)
        try Data(repeating: 1, count: 96_000).write(to: rawTwo)
        try Data(repeating: 2, count: 96_000).write(to: rawThree)

        for (raw, output) in [
            (rawOne, sourceOne), (rawTwo, sourceTwo), (rawThree, sourceThree),
        ] {
            let result = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .ffmpeg),
                    arguments: [
                        "-hide_banner", "-loglevel", "error",
                        "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", raw.path,
                        "-c:a", "aac",
                        "-metadata", "title=Lossless Join Fixture",
                        "-metadata:s:a:0", "language=eng",
                        "-metadata:s:a:0", "title=Main Audio",
                        output.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        }

        let sourceURLs = [sourceOne, sourceTwo, sourceThree]
        let digests = try sourceURLs.map {
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
        let proposal = try JoinTrackMappingProposer().propose(sources: sources)
        XCTAssertTrue(proposal.ambiguities.isEmpty)
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: proposal.mapping
        )
        XCTAssertEqual(report.disposition, .losslessCandidate)

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
        let executor = LosslessJoinExecutor(
            ffmpegURL: try catalog.url(for: .ffmpeg),
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            mkvextractURL: try catalog.url(for: .mkvextract),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        )
        let preview = try executor.preview(
            sources: sources,
            mapping: proposal.mapping,
            chapters: chapters
        )

        let output = try await executor.execute(
            preview: preview,
            destinationURL: destination
        )

        XCTAssertEqual(output.tracks.count, 1)
        XCTAssertEqual(output.tracks[0].uid, sources[0].tracks[0].uid)
        XCTAssertEqual(output.tracks[0].codecID, sources[0].tracks[0].codecID)
        XCTAssertEqual(output.chapterEntryCount, 3)
        XCTAssertEqual(output.metadata["title"], "Lossless Join Fixture")
        XCTAssertEqual(
            try sourceURLs.map {
                SHA256.hash(data: try Data(contentsOf: $0))
            },
            digests
        )

        let chapterPreview = try await ChapterEditExecutor(
            mkvextractURL: try catalog.url(for: .mkvextract),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        ).preview(source: output)
        let codec = MatroskaChapterXMLCodec()
        XCTAssertEqual(
            try codec.serialize(chapterPreview.original),
            try codec.serialize(chapters.document)
        )
    }

    func testBundledToolsPreserveCanonicalHEVCPacketPayloadsAcrossJoin() async throws {
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-lossless-hevc-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        var sourceURLs = [URL]()
        let bytesPerFrame = 80 * 64 * 3 / 2
        for (index, fill) in [UInt8(16), UInt8(32)].enumerated() {
            let raw = root.appendingPathComponent("part-\(index + 1).yuv")
            let source = root.appendingPathComponent("part-\(index + 1).mkv")
            try Data(repeating: fill, count: bytesPerFrame * 12).write(to: raw)
            let encode = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: [
                        "-hide_banner", "-loglevel", "error",
                        "-f", "rawvideo", "-pixel_format", "yuv420p",
                        "-video_size", "80x64", "-framerate", "24",
                        "-i", raw.path, "-frames:v", "12",
                        "-c:v", "hevc_videotoolbox", "-profile:v", "main10",
                        "-pix_fmt", "p010le", "-b:v", "500k",
                        source.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(encode.exitCode, 0, encode.standardError.text)
            sourceURLs.append(source)
        }

        let sourceDigests = try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) }
        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        var sources = [MediaAsset]()
        for url in sourceURLs { try await sources.append(inspector.inspect(url)) }
        let mapping = try JoinTrackMappingProposer().propose(sources: sources).mapping
        let report = try JoinCompatibilityAnalyzer().analyze(sources: sources, mapping: mapping)
        XCTAssertEqual(report.disposition, .losslessCandidate)
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
        let executor = LosslessJoinExecutor(
            ffmpegURL: ffmpegURL,
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            mkvextractURL: try catalog.url(for: .mkvextract),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        )
        let preview = try executor.preview(
            sources: sources,
            mapping: mapping,
            chapters: chapters
        )

        let output = try await executor.execute(
            preview: preview,
            destinationURL: root.appendingPathComponent("joined-hevc.mkv")
        )

        XCTAssertEqual(output.tracks.count, 1)
        XCTAssertEqual(output.tracks[0].codec, "hevc")
        XCTAssertEqual(output.chapterEntryCount, 2)
        XCTAssertEqual(
            try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
            sourceDigests
        )
    }

    func testBundledToolsJoinThreeH264AACSubRipMKVs() async throws {
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
            throw XCTSkip("Bundled H.264 VideoToolbox did not verify on this Mac")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-lossless-three-lane-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let bytesPerFrame = 80 * 64 * 3 / 2
        var sourceURLs = [URL]()
        for (index, fill) in [UInt8(16), UInt8(32), UInt8(48)].enumerated() {
            let rawVideo = root.appendingPathComponent("part-\(index + 1).yuv")
            let rawAudio = root.appendingPathComponent("part-\(index + 1).pcm")
            let subtitle = root.appendingPathComponent("part-\(index + 1).srt")
            let source = root.appendingPathComponent("part-\(index + 1).mkv")
            try Data(repeating: fill, count: bytesPerFrame * 24).write(to: rawVideo)
            try Data(repeating: fill, count: 48_000 * 2 * 2).write(to: rawAudio)
            try Data(
                "1\n00:00:00,050 --> 00:00:00,850\nPart \(index + 1)\n".utf8
            ).write(to: subtitle)
            let encode = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: [
                        "-hide_banner", "-loglevel", "error",
                        "-f", "rawvideo", "-pixel_format", "yuv420p",
                        "-video_size", "80x64", "-framerate", "24",
                        "-i", rawVideo.path,
                        "-f", "s16le", "-ar", "48000", "-ac", "2",
                        "-i", rawAudio.path,
                        "-f", "srt", "-i", subtitle.path,
                        "-map", "0:v:0", "-map", "1:a:0", "-map", "2:s:0",
                        "-frames:v", "24", "-t", "1",
                        "-c:v", "h264_videotoolbox", "-profile:v", "high",
                        "-pix_fmt", "yuv420p", "-b:v", "500k",
                        "-c:a", "aac", "-b:a", "128k", "-c:s", "srt",
                        "-metadata", "title=Three Lane Fixture",
                        "-metadata:s:a:0", "language=eng",
                        "-metadata:s:s:0", "language=eng",
                        source.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(encode.exitCode, 0, encode.standardError.text)
            sourceURLs.append(source)
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
        XCTAssertEqual(
            sources.map { $0.tracks.map(\.kind) },
            [
                [.video, .audio, .subtitle],
                [.video, .audio, .subtitle],
                [.video, .audio, .subtitle],
            ])
        let mapping = try JoinTrackMappingProposer().propose(sources: sources).mapping
        XCTAssertEqual(
            try JoinCompatibilityAnalyzer().analyze(sources: sources, mapping: mapping)
                .disposition,
            .losslessCandidate
        )
        let chapters = try JoinedChapterComposer().compose(
            sources.enumerated().map { index, source in
                let duration = try XCTUnwrap(source.duration)
                return JoinedChapterSource(
                    title: "Part \(index + 1)",
                    duration: duration,
                    retainedStart: .zero,
                    retainedEnd: duration,
                    selectedEditionChapters: []
                )
            }
        )
        let executor = LosslessJoinExecutor(
            ffmpegURL: ffmpegURL,
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            mkvextractURL: try catalog.url(for: .mkvextract),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        )
        let preview = try executor.preview(
            sources: sources,
            mapping: mapping,
            chapters: chapters
        )

        let output = try await executor.execute(
            preview: preview,
            destinationURL: root.appendingPathComponent("joined-three-lane.mkv")
        )

        XCTAssertEqual(output.tracks.map(\.kind), [.video, .audio, .subtitle])
        XCTAssertEqual(output.chapterEntryCount, 3)
    }

    func testBundledToolsRouteH264CodecInitializationMismatchToCommonFormat() async throws {
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
            throw XCTSkip("Bundled H.264 VideoToolbox did not verify on this Mac")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-h264-initialization-mismatch-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawVideo = root.appendingPathComponent("black.yuv")
        let width = 1_280
        let height = 720
        let frameCount = 24
        let bytesPerFrame = width * height * 3 / 2
        try Data(repeating: 0, count: bytesPerFrame * frameCount).write(to: rawVideo)
        var sourceURLs = [URL]()
        for coder in ["cavlc", "cabac"] {
            let source = root.appendingPathComponent("\(coder).mkv")
            let encode = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: [
                        "-hide_banner", "-loglevel", "error",
                        "-f", "rawvideo", "-pixel_format", "yuv420p",
                        "-video_size", "\(width)x\(height)", "-framerate", "24",
                        "-i", rawVideo.path, "-frames:v", String(frameCount), "-an",
                        "-c:v", "h264_videotoolbox", "-profile:v", "high",
                        "-level:v", "3.1", "-coder", coder, "-g", "24",
                        "-b:v", "500k", "-pix_fmt", "yuv420p",
                        source.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(encode.exitCode, 0, encode.standardError.text)
            sourceURLs.append(source)
        }
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
        let first = try XCTUnwrap(sources[0].tracks.first)
        let second = try XCTUnwrap(sources[1].tracks.first)
        XCTAssertEqual(first.codec, second.codec)
        XCTAssertEqual(first.profile, second.profile)
        XCTAssertEqual(first.level, second.level)
        XCTAssertEqual(first.dimensions, second.dimensions)
        XCTAssertEqual(first.pixelFormat, second.pixelFormat)
        XCTAssertEqual(first.frameRate, second.frameRate)
        XCTAssertTrue(MediaHDR10Signal.isUntaggedHDAVCSDRCandidate(first))
        XCTAssertTrue(MediaHDR10Signal.isUntaggedHDAVCSDRCandidate(second))
        XCTAssertNotNil(first.codecInitializationDigest)
        XCTAssertNotNil(second.codecInitializationDigest)
        XCTAssertNotEqual(first.codecInitializationDigest, second.codecInitializationDigest)

        let mapping = try JoinTrackMappingProposer().propose(sources: sources).mapping
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: mapping
        )
        XCTAssertEqual(report.disposition, .normalizationRequired)
        XCTAssertTrue(
            report.issues.contains {
                $0.reason == .codecInitialization && $0.severity == .normalizationRequired
            }
        )

        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping,
            preferredVideoPreset: .h264Compatibility
        )
        XCTAssertTrue(proposal.blockers.isEmpty, "\(proposal.blockers)")
        let lane = try XCTUnwrap(proposal.videoLanes.first)
        XCTAssertEqual(lane.recommendedDynamicRange, .sdr)
        XCTAssertTrue(proposal.decisions.contains { $0.kind == .untaggedSDR })
        let resolved = try JoinNormalizationChoiceResolver().resolve(
            sources: sources,
            proposal: proposal,
            choices: JoinNormalizationChoices(videoTargetsByLane: [
                lane.laneIndex: JoinVideoTargetChoice(
                    preset: .h264Compatibility,
                    canvas: try XCTUnwrap(lane.recommendedCanvas),
                    frameRatePolicy: .preserveSourceTiming,
                    dynamicRange: .sdr,
                    rateControl: .averageBitrate(500_000)
                )
            ]),
            availableVideoPresets: Set(capabilities.availableVideoPresets),
            aacAvailable: capabilities.aac == .verified
        )
        let normalizationExecutor = JoinNormalizationExecutor(
            ffmpegURL: ffmpegURL,
            runner: runner,
            inspector: inspector
        )
        let output = try await normalizationExecutor.execute(
            preview: normalizationExecutor.preview(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities
            ),
            destinationURL: root.appendingPathComponent("verified-common-format.mkv")
        )

        XCTAssertEqual(output.tracks.count, 1)
        XCTAssertEqual(output.tracks[0].dimensions, MediaDimensions(width: width, height: height))
        XCTAssertTrue(MediaHDR10Signal.isBT709SDR(output.tracks[0]))
        XCTAssertEqual(
            try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
            sourceDigests
        )
    }

    func testBundledToolsCommitReviewedCodecPrivateAppendOnlyAfterCleanAudit() async throws {
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
            throw XCTSkip("Bundled H.264 VideoToolbox did not verify on this Mac")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-reviewed-codec-private-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawVideo = root.appendingPathComponent("black.yuv")
        let width = 1_280
        let height = 720
        let frameCount = 24
        try Data(repeating: 0, count: width * height * 3 / 2 * frameCount).write(
            to: rawVideo
        )
        var sourceURLs = [URL]()
        for coder in ["cavlc", "cabac"] {
            let elementaryStream = root.appendingPathComponent("\(coder).h264")
            let source = root.appendingPathComponent("\(coder).mkv")
            let encode = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: [
                        "-hide_banner", "-loglevel", "error",
                        "-f", "rawvideo", "-pixel_format", "yuv420p",
                        "-video_size", "\(width)x\(height)", "-framerate", "24",
                        "-i", rawVideo.path, "-frames:v", String(frameCount), "-an",
                        "-c:v", "h264_videotoolbox", "-profile:v", "high",
                        "-level:v", "3.1", "-coder", coder, "-g", "24",
                        "-b:v", "500k", "-pix_fmt", "yuv420p",
                        "-f", "h264", elementaryStream.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(encode.exitCode, 0, encode.standardError.text)
            let mux = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .mkvmerge),
                    arguments: [
                        "--output", source.path,
                        "--default-duration", "0:24fps",
                        elementaryStream.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertLessThanOrEqual(mux.exitCode, 1, mux.standardError.text)
            sourceURLs.append(source)
        }
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
        XCTAssertNotEqual(
            sources[0].tracks.first?.codecInitializationDigest,
            sources[1].tracks.first?.codecInitializationDigest
        )
        let mapping = try JoinTrackMappingProposer().propose(sources: sources).mapping
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: mapping
        )
        XCTAssertTrue(ReviewedMKVToolNixLosslessAppendPolicy.canOffer(for: report))
        let chapters = try JoinedChapterComposer().compose(
            sources.enumerated().map { index, source in
                let duration = try XCTUnwrap(source.duration)
                let midpoint = MediaTime(nanoseconds: duration.nanoseconds / 2)
                return JoinedChapterSource(
                    title: "Part \(index + 1)",
                    duration: duration,
                    retainedStart: .zero,
                    retainedEnd: duration,
                    selectedEditionChapters: [
                        MatroskaChapterAtom(
                            uid: UInt64(index * 10 + 1),
                            start: .zero,
                            end: midpoint,
                            displays: [ChapterDisplay(title: "Chapter 1")]
                        ),
                        MatroskaChapterAtom(
                            uid: UInt64(index * 10 + 2),
                            start: midpoint,
                            end: duration,
                            displays: [ChapterDisplay(title: "Chapter 2")]
                        ),
                    ]
                )
            }
        )
        let executor = LosslessJoinExecutor(
            ffmpegURL: ffmpegURL,
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            mkvextractURL: try catalog.url(for: .mkvextract),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        )
        XCTAssertThrowsError(
            try executor.preview(
                sources: sources,
                mapping: mapping,
                chapters: chapters
            )
        )
        let preview = try executor.preview(
            sources: sources,
            mapping: mapping,
            chapters: chapters,
            usesReviewedMKVToolNixWarningTolerance: true
        )
        XCTAssertTrue(preview.usesHeaderNormalizedVideoAppend)
        XCTAssertEqual(preview.headerNormalizedVideoLaneIndices, [0])

        let output = try await executor.execute(
            preview: preview,
            destinationURL: root.appendingPathComponent("joined-reviewed.mkv")
        )

        XCTAssertTrue(preview.usesReviewedMKVToolNixWarningTolerance)
        XCTAssertEqual(output.tracks.count, 1)
        XCTAssertEqual(output.tracks[0].codec, "h264")
        XCTAssertEqual(chapters.document.topLevelChapterCount, 4)
        XCTAssertEqual(
            chapters.document.editions.first?.chapters.map(\.primaryTitle),
            ["Chapter 1", "Chapter 2", "Chapter 3", "Chapter 4"]
        )
        XCTAssertEqual(output.chapterEntryCount, 4)
        let decode = try await runner.run(
            CommandRequest(
                executableURL: ffmpegURL,
                arguments: [
                    "-hide_banner", "-loglevel", "error", "-xerror",
                    "-i", output.sourceURL.path,
                    "-map", "0:v:0", "-f", "null", "-",
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(decode.exitCode, 0, decode.standardError.text)
        XCTAssertEqual(
            try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
            sourceDigests
        )
    }
}
