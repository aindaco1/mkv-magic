import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

private actor JoinFinalToolRunner: CommandRunning {
    private let exitCode: Int32
    private let wrongChapters: Bool
    private let sourceToMutate: URL?
    private var chapterData: Data?
    private var requests = [CommandRequest]()

    init(
        exitCode: Int32 = 0,
        wrongChapters: Bool = false,
        sourceToMutate: URL? = nil
    ) {
        self.exitCode = exitCode
        self.wrongChapters = wrongChapters
        self.sourceToMutate = sourceToMutate
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        switch request.executableURL.lastPathComponent {
        case "mkvmerge":
            guard exitCode == 0,
                let outputIndex = request.arguments.firstIndex(of: "--output"),
                request.arguments.indices.contains(outputIndex + 1),
                let chaptersIndex = request.arguments.firstIndex(of: "--chapters"),
                request.arguments.indices.contains(chaptersIndex + 1)
            else {
                return result(exitCode: exitCode == 0 ? 2 : exitCode)
            }
            chapterData = try Data(
                contentsOf: URL(fileURLWithPath: request.arguments[chaptersIndex + 1])
            )
            try Data("assembled output".utf8).write(
                to: URL(fileURLWithPath: request.arguments[outputIndex + 1])
            )
            if let sourceToMutate {
                try Data("changed during final mux".utf8).write(
                    to: sourceToMutate,
                    options: .atomic
                )
            }
            return result(exitCode: 0)
        case "mkvextract":
            guard request.arguments.count == 3, let chapterData else {
                return result(exitCode: 2)
            }
            let data =
                wrongChapters
                ? try MatroskaChapterXMLCodec().serialize(MatroskaChapterDocument())
                : chapterData
            try data.write(to: URL(fileURLWithPath: request.arguments[2]))
            return result(exitCode: 0)
        default:
            return result(exitCode: 2)
        }
    }

    func capturedRequests() -> [CommandRequest] { requests }

    private func result(exitCode: Int32) -> CommandResult {
        CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(
                data: exitCode == 0 ? Data() : Data("fixture tool failure".utf8),
                wasTruncated: false
            )
        )
    }
}

private actor JoinFinalInspector: MediaInspecting {
    enum Behavior: Equatable, Sendable {
        case valid
        case wrongTrack
        case wrongMetadata
        case wrongAttachments
        case wrongTags
        case wrongCommittedTrack
    }

    private let behavior: Behavior
    private var inspections = 0

    init(behavior: Behavior = .valid) {
        self.behavior = behavior
    }

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        inspections += 1
        let wrong =
            behavior == .wrongTrack
            || (behavior == .wrongCommittedTrack && inspections == 2)
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
                    uid: 500,
                    isDefault: true,
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
                ),
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    codecID: "A_AAC",
                    profile: "LC",
                    uid: 101,
                    language: "en",
                    title: behavior == .wrongMetadata ? "Wrong Audio" : "Main Audio",
                    isDefault: true,
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: 48_000
                ),
            ],
            attachments: behavior == .wrongAttachments
                ? [MediaAttachment(id: 9, filename: "unexpected.jpg")]
                : [],
            metadata: ["title": "Joined Feature"],
            chapterEntryCount: 2,
            globalTagCount: 0,
            trackTagCount: behavior == .wrongTags ? 1 : 0,
            segmentUID: "FINAL-SEGMENT-UID"
        )
    }
}

private actor JoinFinalStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()

    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func values() -> [VerifiedOutputExecutionStage] { stages }
}

final class JoinFinalAssemblyExecutorTests: XCTestCase {
    func testExecutesOneFinalMuxAndCommitsOnlyAfterTwoCompleteAudits() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let inputURLs = fixture.sources.map(\.sourceURL) + [fixture.normalized.sourceURL]
        let originalBytes = try inputURLs.map { try Data(contentsOf: $0) }
        let runner = JoinFinalToolRunner()
        let executor = makeExecutor(runner: runner, inspector: JoinFinalInspector())
        let preview = try await executor.preview(
            sources: fixture.sources,
            resolvedPlan: fixture.resolved,
            normalizedBundle: fixture.normalized,
            chapters: fixture.chapters
        )
        let destination = fixture.root.appendingPathComponent("Final.mkv")
        let recorder = JoinFinalStageRecorder()

        let output = try await executor.execute(
            preview: preview,
            destinationURL: destination,
            onStage: { stage in await recorder.append(stage) }
        )

        XCTAssertEqual(output.sourceURL, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try inputURLs.map { try Data(contentsOf: $0) }, originalBytes)
        let stages = await recorder.values()
        XCTAssertEqual(stages, [.verifying, .committing])
        let requests = await runner.capturedRequests()
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvmerge" }.count,
            1
        )
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvextract" }.count,
            2
        )
        let merge = try XCTUnwrap(
            requests.first { $0.executableURL.lastPathComponent == "mkvmerge" }
        )
        XCTAssertTrue(merge.arguments.contains("--append-to"))
        XCTAssertNotEqual(value(after: "--output", in: merge.arguments), destination.path)
    }

    func testChangedInputsBeforeAndDuringMuxNeverCommit() async throws {
        let before = try makeFixture()
        defer { try? FileManager.default.removeItem(at: before.root) }
        let beforeRunner = JoinFinalToolRunner()
        let beforeExecutor = makeExecutor(
            runner: beforeRunner,
            inspector: JoinFinalInspector()
        )
        let beforePreview = try await beforeExecutor.preview(
            sources: before.sources,
            resolvedPlan: before.resolved,
            normalizedBundle: before.normalized,
            chapters: before.chapters
        )
        try Data("changed bundle".utf8).write(
            to: before.normalized.sourceURL,
            options: .atomic
        )
        let beforeDestination = before.root.appendingPathComponent("stale.mkv")
        await XCTAssertThrowsErrorAsync(
            try await beforeExecutor.execute(
                preview: beforePreview,
                destinationURL: beforeDestination
            )
        ) { error in
            XCTAssertEqual(error as? JoinFinalAssemblyExecutionError, .staleInput)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: beforeDestination.path))
        let beforeRequests = await beforeRunner.capturedRequests()
        XCTAssertTrue(beforeRequests.isEmpty)

        let during = try makeFixture()
        defer { try? FileManager.default.removeItem(at: during.root) }
        let duringRunner = JoinFinalToolRunner(
            sourceToMutate: during.sources[1].sourceURL
        )
        let duringExecutor = makeExecutor(
            runner: duringRunner,
            inspector: JoinFinalInspector()
        )
        let duringPreview = try await duringExecutor.preview(
            sources: during.sources,
            resolvedPlan: during.resolved,
            normalizedBundle: during.normalized,
            chapters: during.chapters
        )
        let duringDestination = during.root.appendingPathComponent("during.mkv")
        await XCTAssertThrowsErrorAsync(
            try await duringExecutor.execute(
                preview: duringPreview,
                destinationURL: duringDestination
            )
        ) { error in
            XCTAssertEqual(error as? JoinFinalAssemblyExecutionError, .staleInput)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: duringDestination.path))
        let duringRequests = await duringRunner.capturedRequests()
        XCTAssertEqual(duringRequests.count, 1)
    }

    func testToolTrackAndChapterFailuresLeaveNoDestination() async throws {
        let cases: [(JoinFinalToolRunner, JoinFinalInspector)] = [
            (JoinFinalToolRunner(exitCode: 71), JoinFinalInspector()),
            (JoinFinalToolRunner(), JoinFinalInspector(behavior: .wrongTrack)),
            (JoinFinalToolRunner(), JoinFinalInspector(behavior: .wrongMetadata)),
            (JoinFinalToolRunner(), JoinFinalInspector(behavior: .wrongAttachments)),
            (JoinFinalToolRunner(), JoinFinalInspector(behavior: .wrongTags)),
            (JoinFinalToolRunner(wrongChapters: true), JoinFinalInspector()),
        ]
        for (runner, inspector) in cases {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let executor = makeExecutor(runner: runner, inspector: inspector)
            let preview = try await executor.preview(
                sources: fixture.sources,
                resolvedPlan: fixture.resolved,
                normalizedBundle: fixture.normalized,
                chapters: fixture.chapters
            )
            let destination = fixture.root.appendingPathComponent("failed.mkv")
            await XCTAssertThrowsErrorAsync(
                try await executor.execute(
                    preview: preview,
                    destinationURL: destination
                )
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testCommittedReopenFailureReportsSavedOutputTruthfully() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let executor = makeExecutor(
            runner: JoinFinalToolRunner(),
            inspector: JoinFinalInspector(behavior: .wrongCommittedTrack)
        )
        let preview = try await executor.preview(
            sources: fixture.sources,
            resolvedPlan: fixture.resolved,
            normalizedBundle: fixture.normalized,
            chapters: fixture.chapters
        )
        let destination = fixture.root.appendingPathComponent("audit-failed.mkv")

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(
                preview: preview,
                destinationURL: destination
            )
        ) { error in
            guard
                case .committedOutputAuditFailed(let outputURL, let reason) =
                    error as? JoinFinalAssemblyExecutionError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(outputURL, destination)
            XCTAssertTrue(reason.contains("track order or stream facts"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCancellationAtCommitBoundaryRemovesVerifiedTemporaryOutput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = JoinFinalToolRunner()
        let executor = makeExecutor(runner: runner, inspector: JoinFinalInspector())
        let preview = try await executor.preview(
            sources: fixture.sources,
            resolvedPlan: fixture.resolved,
            normalizedBundle: fixture.normalized,
            chapters: fixture.chapters
        )
        let destination = fixture.root.appendingPathComponent("cancelled.mkv")

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
            XCTFail("A cancelled final assembly must not commit")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let requests = await runner.capturedRequests()
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvmerge" }.count,
            1
        )
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvextract" }.count,
            1
        )
    }

    private struct Fixture {
        let root: URL
        let sources: [MediaAsset]
        let resolved: ResolvedJoinNormalizationPlan
        let normalized: MediaAsset
        let chapters: JoinedChapterComposition
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-final-executor-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let firstURL = root.appendingPathComponent("Part 1.mkv")
        let secondURL = root.appendingPathComponent("Part 2.mkv")
        let normalizedURL = root.appendingPathComponent("Normalized.mkv")
        try Data([1]).write(to: firstURL)
        try Data([2]).write(to: secondURL)
        try Data([3]).write(to: normalizedURL)
        let sources = [
            source(url: firstURL, width: 64, height: 48, segmentUID: "SOURCE-ONE"),
            source(url: secondURL, width: 80, height: 64, segmentUID: "SOURCE-TWO"),
        ]
        let mapping = JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .video, trackIDsBySource: [0, 0]),
            JoinTrackLane(kind: .audio, trackIDsBySource: [1, 1]),
        ])
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping,
            preferredVideoPreset: .hevcCompatibility
        )
        let lane = try XCTUnwrap(proposal.videoLanes.first)
        let resolved = try JoinNormalizationChoiceResolver().resolve(
            sources: sources,
            proposal: proposal,
            choices: JoinNormalizationChoices(
                videoTargetsByLane: [
                    0: JoinVideoTargetChoice(
                        preset: .hevcCompatibility,
                        canvas: try XCTUnwrap(lane.recommendedCanvas),
                        frameRatePolicy: .preserveSourceTiming,
                        dynamicRange: .sdr,
                        rateControl: .averageBitrate(500_000)
                    )
                ]
            ),
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )
        let chapters = try JoinedChapterComposer().compose([
            chapterSource(title: "Part 1"), chapterSource(title: "Part 2"),
        ])
        return Fixture(
            root: root,
            sources: sources,
            resolved: resolved,
            normalized: MediaAsset(
                sourceURL: normalizedURL,
                container: "matroska,webm",
                duration: MediaTime(nanoseconds: 2_000_000_000),
                fileSize: 1,
                tracks: [
                    MediaTrack(
                        id: 5,
                        kind: .video,
                        codec: "hevc",
                        codecID: "V_MPEGH/ISO/HEVC",
                        profile: "Main 10",
                        uid: 500,
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
                ],
                chapterEntryCount: 0,
                globalTagCount: 0,
                trackTagCount: 0,
                segmentUID: "NORMALIZED-BUNDLE"
            ),
            chapters: chapters
        )
    }

    private func source(
        url: URL,
        width: Int,
        height: Int,
        segmentUID: String
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: url,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 1_000_000_000),
            fileSize: 1,
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: "h264",
                    codecID: "V_MPEG4/ISO/AVC",
                    profile: "High",
                    level: 40,
                    uid: 100,
                    isDefault: true,
                    dimensions: MediaDimensions(width: width, height: height),
                    displayDimensions: MediaDimensions(width: width, height: height),
                    pixelFormat: "yuv420p",
                    bitDepth: 8,
                    frameRate: "24/1",
                    colorInfo: MediaColorInfo(
                        range: "tv",
                        primaries: "bt709",
                        transfer: "bt709",
                        matrix: "bt709"
                    )
                ),
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    codecID: "A_AAC",
                    profile: "LC",
                    uid: 101,
                    language: "en",
                    title: "Main Audio",
                    isDefault: true,
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: 48_000
                ),
            ],
            metadata: ["title": "Joined Feature"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: segmentUID
        )
    }

    private func chapterSource(title: String) -> JoinedChapterSource {
        JoinedChapterSource(
            title: title,
            duration: MediaTime(nanoseconds: 1_000_000_000),
            retainedStart: .zero,
            retainedEnd: MediaTime(nanoseconds: 1_000_000_000),
            selectedEditionChapters: []
        )
    }

    private func makeExecutor(
        runner: JoinFinalToolRunner,
        inspector: JoinFinalInspector
    ) -> JoinFinalAssemblyExecutor<JoinFinalToolRunner, JoinFinalInspector> {
        JoinFinalAssemblyExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: inspector
        )
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (any Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
