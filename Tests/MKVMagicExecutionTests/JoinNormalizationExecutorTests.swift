import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

private actor JoinNormalizationToolRunner: CommandRunning {
    private let exitCode: Int32
    private let sourceToMutate: URL?
    private var requests = [CommandRequest]()

    init(exitCode: Int32 = 0, sourceToMutate: URL? = nil) {
        self.exitCode = exitCode
        self.sourceToMutate = sourceToMutate
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        if exitCode == 0, let path = request.arguments.last {
            try Data("normalized bundle".utf8).write(to: URL(fileURLWithPath: path))
            if let sourceToMutate {
                try Data("source changed during normalization".utf8).write(
                    to: sourceToMutate,
                    options: .atomic
                )
            }
        }
        return CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(
                data: exitCode == 0 ? Data() : Data("fixture FFmpeg failure".utf8),
                wasTruncated: false
            )
        )
    }

    func capturedRequests() -> [CommandRequest] { requests }
}

private actor JoinNormalizationInspector: MediaInspecting {
    enum Behavior: Equatable, Sendable {
        case valid
        case wrongCodec
        case wrongCommittedCodec
    }

    private let behavior: Behavior
    private var inspections = 0

    init(behavior: Behavior = .valid) {
        self.behavior = behavior
    }

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        inspections += 1
        let wrong =
            behavior == .wrongCodec
            || (behavior == .wrongCommittedCodec && inspections == 2)
        return MediaAsset(
            sourceURL: inputURL,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 2_000_000_000),
            fileSize: Int64(
                (try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            ),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: wrong ? "h264" : "hevc",
                    codecID: wrong ? "V_MPEG4/ISO/AVC" : "V_MPEGH/ISO/HEVC",
                    profile: wrong ? "High" : "Main 10",
                    dimensions: MediaDimensions(width: 80, height: 64),
                    displayDimensions: MediaDimensions(width: 80, height: 64),
                    pixelFormat: wrong ? "yuv420p" : "p010le",
                    bitDepth: wrong ? 8 : 10,
                    frameRate: "24/1",
                    colorInfo: MediaColorInfo(
                        range: "tv",
                        primaries: "bt709",
                        transfer: "bt709",
                        matrix: "bt709"
                    )
                )
            ],
            chapterEntryCount: 0,
            segmentUID: "1234567890ABCDEF1234567890ABCDEF"
        )
    }
}

private actor JoinNormalizationStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()

    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func values() -> [VerifiedOutputExecutionStage] { stages }
}

final class JoinNormalizationExecutorTests: XCTestCase {
    func testExecutesFFmpegOnceAndCommitsOnlyAfterTwoSemanticAudits() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let originalBytes = try fixture.sources.map { try Data(contentsOf: $0.sourceURL) }
        let runner = JoinNormalizationToolRunner()
        let inspector = JoinNormalizationInspector()
        let executor = makeExecutor(runner: runner, inspector: inspector)
        let preview = try executor.preview(
            sources: fixture.sources,
            resolvedPlan: fixture.resolvedPlan,
            capabilities: capabilities()
        )
        let destination = fixture.directory.appendingPathComponent("normalized.mkv")
        let recorder = JoinNormalizationStageRecorder()

        let output = try await executor.execute(
            preview: preview,
            destinationURL: destination,
            onStage: { stage in await recorder.append(stage) }
        )

        XCTAssertEqual(output.sourceURL, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(
            try fixture.sources.map { try Data(contentsOf: $0.sourceURL) },
            originalBytes
        )
        let stages = await recorder.values()
        XCTAssertEqual(stages, [.verifying, .committing])
        let requests = await runner.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].executableURL.path, "/tools/ffmpeg")
        XCTAssertFalse(requests[0].arguments.contains("-y"))
        XCTAssertNotEqual(requests[0].arguments.last, destination.path)
    }

    func testToolFailureAndSemanticFailureLeaveNoDestination() async throws {
        for (runner, inspector, expectedToolFailure) in [
            (
                JoinNormalizationToolRunner(exitCode: 71),
                JoinNormalizationInspector(),
                true
            ),
            (
                JoinNormalizationToolRunner(),
                JoinNormalizationInspector(behavior: .wrongCodec),
                false
            ),
        ] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let executor = makeExecutor(runner: runner, inspector: inspector)
            let preview = try executor.preview(
                sources: fixture.sources,
                resolvedPlan: fixture.resolvedPlan,
                capabilities: capabilities()
            )
            let destination = fixture.directory.appendingPathComponent("rejected.mkv")

            do {
                _ = try await executor.execute(
                    preview: preview,
                    destinationURL: destination
                )
                XCTFail("Expected normalization to fail")
            } catch {
                if expectedToolFailure {
                    guard
                        case .toolFailed(let code, let message) =
                            error as? JoinNormalizationExecutionError
                    else {
                        return XCTFail("Unexpected error: \(error)")
                    }
                    XCTAssertEqual(code, 71)
                    XCTAssertEqual(message, "fixture FFmpeg failure")
                } else {
                    XCTAssertEqual(
                        error as? JoinNormalizationVerificationError,
                        .videoMismatch(laneIndex: 0)
                    )
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testStaleSourceBeforeAndDuringExecutionFailsClosed() async throws {
        let before = try makeFixture()
        defer { try? FileManager.default.removeItem(at: before.directory) }
        let beforeRunner = JoinNormalizationToolRunner()
        let beforeExecutor = makeExecutor(
            runner: beforeRunner,
            inspector: JoinNormalizationInspector()
        )
        let beforePreview = try beforeExecutor.preview(
            sources: before.sources,
            resolvedPlan: before.resolvedPlan,
            capabilities: capabilities()
        )
        try Data("changed before normalization".utf8).write(
            to: before.sources[0].sourceURL,
            options: .atomic
        )

        do {
            _ = try await beforeExecutor.execute(
                preview: beforePreview,
                destinationURL: before.directory.appendingPathComponent("before.mkv")
            )
            XCTFail("Expected stale source failure")
        } catch {
            XCTAssertEqual(error as? JoinNormalizationExecutionError, .staleSource)
        }
        let beforeRequests = await beforeRunner.capturedRequests()
        XCTAssertTrue(beforeRequests.isEmpty)

        let during = try makeFixture()
        defer { try? FileManager.default.removeItem(at: during.directory) }
        let duringRunner = JoinNormalizationToolRunner(
            sourceToMutate: during.sources[1].sourceURL
        )
        let duringExecutor = makeExecutor(
            runner: duringRunner,
            inspector: JoinNormalizationInspector()
        )
        let duringPreview = try duringExecutor.preview(
            sources: during.sources,
            resolvedPlan: during.resolvedPlan,
            capabilities: capabilities()
        )
        let duringDestination = during.directory.appendingPathComponent("during.mkv")

        do {
            _ = try await duringExecutor.execute(
                preview: duringPreview,
                destinationURL: duringDestination
            )
            XCTFail("Expected stale source failure")
        } catch {
            XCTAssertEqual(error as? JoinNormalizationExecutionError, .staleSource)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: duringDestination.path))
        let duringRequests = await duringRunner.capturedRequests()
        XCTAssertEqual(duringRequests.count, 1)
    }

    func testCommittedReopenAuditFailureReportsSavedOutput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let executor = makeExecutor(
            runner: JoinNormalizationToolRunner(),
            inspector: JoinNormalizationInspector(behavior: .wrongCommittedCodec)
        )
        let preview = try executor.preview(
            sources: fixture.sources,
            resolvedPlan: fixture.resolvedPlan,
            capabilities: capabilities()
        )
        let destination = fixture.directory.appendingPathComponent("audit-failed.mkv")

        do {
            _ = try await executor.execute(
                preview: preview,
                destinationURL: destination
            )
            XCTFail("Expected committed reopen audit failure")
        } catch {
            guard
                case .committedOutputAuditFailed(let outputURL, let reason) =
                    error as? JoinNormalizationExecutionError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(outputURL, destination)
            XCTAssertTrue(reason.contains("video lane 1"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCancellationAtCommitBoundaryRemovesVerifiedTemporaryOutput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let runner = JoinNormalizationToolRunner()
        let executor = makeExecutor(
            runner: runner,
            inspector: JoinNormalizationInspector()
        )
        let preview = try executor.preview(
            sources: fixture.sources,
            resolvedPlan: fixture.resolvedPlan,
            capabilities: capabilities()
        )
        let destination = fixture.directory.appendingPathComponent("cancelled.mkv")

        let result = await Task {
            try await executor.execute(
                preview: preview,
                destinationURL: destination,
                onStage: { stage in
                    if stage == .committing {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            )
        }.result

        switch result {
        case .success:
            XCTFail("A cancelled normalized bundle must not commit")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let requests = await runner.capturedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testPreviewRequiresKnownDurationAndExecuteRequiresMKV() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let executor = makeExecutor(
            runner: JoinNormalizationToolRunner(),
            inspector: JoinNormalizationInspector()
        )
        let source = fixture.sources[0]
        XCTAssertThrowsError(
            try executor.preview(
                sources: [],
                resolvedPlan: fixture.resolvedPlan,
                capabilities: capabilities()
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationExecutionError,
                .insufficientSources
            )
        }
        let unknownDurationSource = MediaAsset(
            sourceURL: source.sourceURL,
            container: source.container,
            fileSize: source.fileSize,
            tracks: source.tracks
        )
        XCTAssertThrowsError(
            try executor.preview(
                sources: [unknownDurationSource, fixture.sources[1]],
                resolvedPlan: fixture.resolvedPlan,
                capabilities: capabilities()
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationExecutionError,
                .unsupportedSourceDuration(sourceIndex: 0)
            )
        }

        let linkedURL = fixture.directory.appendingPathComponent("linked-source.mkv")
        try FileManager.default.createSymbolicLink(
            at: linkedURL,
            withDestinationURL: source.sourceURL
        )
        let linkedSource = MediaAsset(
            sourceURL: linkedURL,
            container: source.container,
            duration: source.duration,
            fileSize: source.fileSize,
            tracks: source.tracks
        )
        XCTAssertThrowsError(
            try executor.preview(
                sources: [linkedSource, fixture.sources[1]],
                resolvedPlan: fixture.resolvedPlan,
                capabilities: capabilities()
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationExecutionError,
                .invalidSourcePath(sourceIndex: 0)
            )
        }

        let oversizedTimelineSources = fixture.sources.map { source in
            MediaAsset(
                sourceURL: source.sourceURL,
                container: source.container,
                duration: MediaTime(nanoseconds: Int64.max),
                fileSize: source.fileSize,
                tracks: source.tracks
            )
        }
        XCTAssertThrowsError(
            try executor.preview(
                sources: oversizedTimelineSources,
                resolvedPlan: fixture.resolvedPlan,
                capabilities: capabilities()
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationExecutionError,
                .unsupportedSourceTimeline
            )
        }

        let preview = try executor.preview(
            sources: fixture.sources,
            resolvedPlan: fixture.resolvedPlan,
            capabilities: capabilities()
        )
        do {
            _ = try await executor.execute(
                preview: preview,
                destinationURL: fixture.directory.appendingPathComponent("not-mkv.mp4")
            )
            XCTFail("Expected unsupported destination")
        } catch {
            XCTAssertEqual(
                error as? JoinNormalizationExecutionError,
                .unsupportedDestination
            )
        }
    }

    func testVerifierRejectsWrongDurationAndUnexpectedStructure() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let verifier = JoinNormalizationOutputVerifier()
        let baseTrack = outputVideo()
        let wrongDuration = MediaAsset(
            sourceURL: fixture.directory.appendingPathComponent("wrong-duration.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 3_000_000_000),
            fileSize: 1,
            tracks: [baseTrack]
        )
        XCTAssertThrowsError(
            try verifier.verify(
                sources: fixture.sources,
                resolvedPlan: fixture.resolvedPlan,
                output: wrongDuration
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationVerificationError,
                .wrongDuration
            )
        }

        let unexpectedAttachment = MediaAsset(
            sourceURL: fixture.directory.appendingPathComponent("attachment.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 2_000_000_000),
            fileSize: 1,
            tracks: [baseTrack],
            attachments: [MediaAttachment(id: 2, filename: "cover.jpg")]
        )
        XCTAssertThrowsError(
            try verifier.verify(
                sources: fixture.sources,
                resolvedPlan: fixture.resolvedPlan,
                output: unexpectedAttachment
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationVerificationError,
                .unexpectedStructure
            )
        }
    }

    func testVerifierRequiresExactReviewedHDR10Signal() throws {
        let sources = [
            MediaAsset(
                sourceURL: URL(fileURLWithPath: "/media/hdr-part-1.mkv"),
                container: "matroska,webm",
                duration: MediaTime(nanoseconds: 1_000_000_000),
                tracks: [hdr10Video(dimensions: MediaDimensions(width: 64, height: 48))]
            ),
            MediaAsset(
                sourceURL: URL(fileURLWithPath: "/media/hdr-part-2.mkv"),
                container: "matroska,webm",
                duration: MediaTime(nanoseconds: 1_000_000_000),
                tracks: [hdr10Video(dimensions: MediaDimensions(width: 80, height: 64))]
            ),
        ]
        let mapping = JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .video, trackIDsBySource: [0, 0])
        ])
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping,
            preferredVideoPreset: .hevcCompatibility
        )
        let lane = try XCTUnwrap(proposal.videoLanes.first)
        let choice = JoinVideoTargetChoice(
            preset: .hevcCompatibility,
            canvas: try XCTUnwrap(lane.recommendedCanvas),
            frameRatePolicy: .preserveSourceTiming,
            dynamicRange: .hdr10,
            rateControl: .averageBitrate(500_000)
        )
        let resolved = try JoinNormalizationChoiceResolver().resolve(
            sources: sources,
            proposal: proposal,
            choices: JoinNormalizationChoices(videoTargetsByLane: [0: choice]),
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )
        let verifier = JoinNormalizationOutputVerifier()

        try verifier.verify(
            sources: sources,
            resolvedPlan: resolved,
            output: hdr10Output(maxContentLightLevel: 1_000)
        )
        XCTAssertThrowsError(
            try verifier.verify(
                sources: sources,
                resolvedPlan: resolved,
                output: hdr10Output(maxContentLightLevel: 999)
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationVerificationError,
                .videoMismatch(laneIndex: 0)
            )
        }
    }

    private struct Fixture {
        let directory: URL
        let sources: [MediaAsset]
        let resolvedPlan: ResolvedJoinNormalizationPlan
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-normalization-executor-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var sources = [MediaAsset]()
        for (index, dimensions) in [
            MediaDimensions(width: 64, height: 48),
            MediaDimensions(width: 80, height: 64),
        ].enumerated() {
            let url = directory.appendingPathComponent("part-\(index + 1).mkv")
            let data = Data("source \(index + 1)".utf8)
            try data.write(to: url)
            sources.append(
                MediaAsset(
                    sourceURL: url,
                    container: "matroska,webm",
                    duration: MediaTime(nanoseconds: 1_000_000_000),
                    fileSize: Int64(data.count),
                    tracks: [sourceVideo(dimensions: dimensions)]
                )
            )
        }
        let mapping = JoinTrackMapping(
            lanes: [JoinTrackLane(kind: .video, trackIDsBySource: [0, 0])]
        )
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping,
            preferredVideoPreset: .hevcCompatibility
        )
        let lane = try XCTUnwrap(proposal.videoLanes.first)
        let choice = JoinVideoTargetChoice(
            preset: .hevcCompatibility,
            canvas: try XCTUnwrap(lane.recommendedCanvas),
            frameRatePolicy: try XCTUnwrap(lane.recommendedFrameRatePolicy),
            dynamicRange: try XCTUnwrap(lane.recommendedDynamicRange),
            rateControl: .averageBitrate(500_000)
        )
        let resolvedPlan = try JoinNormalizationChoiceResolver().resolve(
            sources: sources,
            proposal: proposal,
            choices: JoinNormalizationChoices(videoTargetsByLane: [0: choice]),
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )
        return Fixture(directory: directory, sources: sources, resolvedPlan: resolvedPlan)
    }

    private func makeExecutor(
        runner: JoinNormalizationToolRunner,
        inspector: JoinNormalizationInspector
    ) -> JoinNormalizationExecutor<JoinNormalizationToolRunner, JoinNormalizationInspector> {
        JoinNormalizationExecutor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            runner: runner,
            inspector: inspector
        )
    }

    private func capabilities() -> FFmpegEncodingCapabilities {
        FFmpegEncodingCapabilities(
            softwareAV1: .unavailable,
            softwareAV1Encoder: nil,
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .unavailable,
            proRes: .unavailable,
            proResEncoder: nil,
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters
        )
    }

    private func sourceVideo(dimensions: MediaDimensions) -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            profile: "High",
            level: 40,
            dimensions: dimensions,
            displayDimensions: dimensions,
            pixelFormat: "yuv420p",
            bitDepth: 8,
            frameRate: "24/1",
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt709",
                transfer: "bt709",
                matrix: "bt709"
            )
        )
    }

    private func outputVideo() -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: "hevc",
            dimensions: MediaDimensions(width: 80, height: 64),
            displayDimensions: MediaDimensions(width: 80, height: 64),
            pixelFormat: "p010le",
            bitDepth: 10,
            frameRate: "24/1",
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt709",
                transfer: "bt709",
                matrix: "bt709"
            )
        )
    }

    private func hdr10Video(
        dimensions: MediaDimensions,
        maxContentLightLevel: Int = 1_000
    ) -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: "hevc",
            codecID: "V_MPEGH/ISO/HEVC",
            profile: "Main 10",
            dimensions: dimensions,
            displayDimensions: dimensions,
            pixelFormat: "p010le",
            bitDepth: 10,
            frameRate: "24/1",
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt2020",
                transfer: "smpte2084",
                matrix: "bt2020nc"
            ),
            masteringDisplayMetadata: MediaMasteringDisplayMetadata(
                redX: 34_000,
                redY: 16_000,
                greenX: 13_250,
                greenY: 34_500,
                blueX: 7_500,
                blueY: 3_000,
                whitePointX: 15_635,
                whitePointY: 16_450,
                maxLuminance: 10_000_000,
                minLuminance: 50
            ),
            contentLightLevelMetadata: MediaContentLightLevelMetadata(
                maxContentLightLevel: maxContentLightLevel,
                maxFrameAverageLightLevel: 400
            ),
            hdrFormats: ["HDR10 metadata"]
        )
    }

    private func hdr10Output(maxContentLightLevel: Int) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: "/output/hdr10.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 2_000_000_000),
            fileSize: 1,
            tracks: [
                hdr10Video(
                    dimensions: MediaDimensions(width: 80, height: 64),
                    maxContentLightLevel: maxContentLightLevel
                )
            ],
            chapterEntryCount: 0
        )
    }
}
