import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

private actor FastTrimToolRunner: CommandRunning {
    private let sourceURL: URL
    private let sourceChapters: Data
    private let failingTool: String?
    private let wrongOutputChapters: Bool
    private let sourceToMutate: URL?
    private var outputChapters: Data?
    private var requests = [CommandRequest]()

    init(
        sourceURL: URL,
        sourceChapters: Data,
        failingTool: String? = nil,
        wrongOutputChapters: Bool = false,
        sourceToMutate: URL? = nil
    ) {
        self.sourceURL = sourceURL
        self.sourceChapters = sourceChapters
        self.failingTool = failingTool
        self.wrongOutputChapters = wrongOutputChapters
        self.sourceToMutate = sourceToMutate
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        let tool = request.executableURL.lastPathComponent
        if failingTool == tool { return result(exitCode: 73) }
        switch tool {
        case "ffprobe":
            return result(
                output: """
                    {"frames":[
                      {"best_effort_timestamp_time":"0.000000"},
                      {"best_effort_timestamp_time":"4.000000"},
                      {"best_effort_timestamp_time":"8.000000"}
                    ]}
                    """
            )
        case "mkvextract":
            guard request.arguments.count == 3 else { return result(exitCode: 2) }
            let inputURL = URL(fileURLWithPath: request.arguments[0])
            let outputURL = URL(fileURLWithPath: request.arguments[2])
            let data: Data
            if inputURL == sourceURL {
                data = sourceChapters
            } else if wrongOutputChapters {
                data = try MatroskaChapterXMLCodec().serialize(MatroskaChapterDocument())
            } else if let outputChapters {
                data = outputChapters
            } else {
                return result(exitCode: 2)
            }
            try data.write(to: outputURL)
            return result()
        case "mkvmerge":
            guard let output = value(after: "--output", in: request.arguments) else {
                return result(exitCode: 2)
            }
            try Data("lossless trimmed output".utf8).write(
                to: URL(fileURLWithPath: output)
            )
            if let sourceToMutate {
                try Data("changed during split".utf8).write(to: sourceToMutate, options: .atomic)
            }
            return result()
        case "mkvpropedit":
            guard let chapters = value(after: "--chapters", in: request.arguments),
                !chapters.isEmpty
            else {
                outputChapters = try MatroskaChapterXMLCodec().serialize(
                    MatroskaChapterDocument()
                )
                return result()
            }
            outputChapters = try Data(contentsOf: URL(fileURLWithPath: chapters))
            return result()
        default:
            return result(exitCode: 2)
        }
    }

    func capturedRequests() -> [CommandRequest] { requests }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    private func result(exitCode: Int32 = 0, output: String = "") -> CommandResult {
        CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(output.utf8), wasTruncated: false),
            standardError: CommandOutput(
                data: exitCode == 0 ? Data() : Data("fixture tool failure".utf8),
                wasTruncated: false
            )
        )
    }
}

private actor FastTrimInspector: MediaInspecting {
    enum Behavior: Equatable, Sendable { case valid, wrongDuration, wrongCommittedDuration }

    private let original: MediaAsset
    private let behavior: Behavior
    private var inspections = 0

    init(original: MediaAsset, behavior: Behavior = .valid) {
        self.original = original
        self.behavior = behavior
    }

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        inspections += 1
        let isWrong =
            behavior == .wrongDuration
            || (behavior == .wrongCommittedDuration && inspections == 2)
        return MediaAsset(
            sourceURL: inputURL,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: isWrong ? 5_000_000_000 : 6_000_000_000),
            fileSize: Int64(
                (try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            ),
            tracks: original.tracks,
            attachments: original.attachments,
            metadata: original.metadata,
            chapterEntryCount: 1,
            globalTagCount: original.globalTagCount,
            trackTagCount: original.trackTagCount,
            segmentUID: "TRIMMED-SEGMENT"
        )
    }
}

private actor FastTrimStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()
    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func values() -> [VerifiedOutputExecutionStage] { stages }
}

final class FastTrimExecutorTests: XCTestCase {
    func testExecutesLosslessSplitDisclosesAdjustmentAndAuditsNestedChaptersTwice() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let originalBytes = try Data(contentsOf: fixture.source.sourceURL)
        let runner = FastTrimToolRunner(
            sourceURL: fixture.source.sourceURL,
            sourceChapters: fixture.chapterData
        )
        let executor = makeExecutor(
            runner: runner,
            inspector: FastTrimInspector(original: fixture.source)
        )
        let preview = try await executor.preview(
            source: fixture.source,
            requestedRange: range(3, 9)
        )
        XCTAssertEqual(preview.plan.adjusted, range(4, 10))
        XCTAssertTrue(preview.plan.startWasAdjusted)
        XCTAssertTrue(preview.plan.endWasAdjusted)
        XCTAssertEqual(preview.trimmedChapters.editions[0].chapters[0].start, .zero)
        XCTAssertEqual(
            preview.trimmedChapters.editions[0].chapters[0].end,
            MediaTime(nanoseconds: 6_000_000_000)
        )
        let destination = fixture.root.appendingPathComponent("Trimmed.mkv")
        let recorder = FastTrimStageRecorder()

        let output = try await executor.execute(
            preview: preview,
            destinationURL: destination,
            onStage: { stage in await recorder.append(stage) }
        )

        XCTAssertEqual(output.sourceURL, destination)
        XCTAssertEqual(try Data(contentsOf: fixture.source.sourceURL), originalBytes)
        let stages = await recorder.values()
        XCTAssertEqual(stages, [.verifying, .committing])
        let requests = await runner.capturedRequests()
        XCTAssertEqual(requests.filter { $0.executableURL.lastPathComponent == "ffprobe" }.count, 1)
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvmerge" }.count, 1)
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvpropedit" }.count,
            1
        )
        let merge = try XCTUnwrap(
            requests.first { $0.executableURL.lastPathComponent == "mkvmerge" }
        )
        XCTAssertEqual(
            value(after: "--split", in: merge.arguments),
            "parts:00:00:04.000000000-00:00:10.000000000"
        )
        XCTAssertNotEqual(value(after: "--output", in: merge.arguments), destination.path)
        let outputExtracts = requests.filter {
            $0.executableURL.lastPathComponent == "mkvextract"
                && $0.arguments.first != fixture.source.sourceURL.path
        }
        XCTAssertEqual(outputExtracts.count, 2)
    }

    func testChangedSourceBeforeOrDuringSplitNeverCommits() async throws {
        let before = try makeFixture()
        defer { try? FileManager.default.removeItem(at: before.root) }
        let beforeRunner = FastTrimToolRunner(
            sourceURL: before.source.sourceURL,
            sourceChapters: before.chapterData
        )
        let beforeExecutor = makeExecutor(
            runner: beforeRunner,
            inspector: FastTrimInspector(original: before.source)
        )
        let beforePreview = try await beforeExecutor.preview(
            source: before.source,
            requestedRange: range(3, 9)
        )
        try Data("changed before execution".utf8).write(
            to: before.source.sourceURL,
            options: .atomic
        )
        let beforeDestination = before.root.appendingPathComponent("before.mkv")
        await assertThrows(
            try await beforeExecutor.execute(
                preview: beforePreview,
                destinationURL: beforeDestination
            )
        ) { XCTAssertEqual($0 as? FastTrimExecutionError, .staleSource) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: beforeDestination.path))
        let beforeRequests = await beforeRunner.capturedRequests()
        XCTAssertFalse(
            beforeRequests.contains { $0.executableURL.lastPathComponent == "mkvmerge" }
        )

        let during = try makeFixture()
        defer { try? FileManager.default.removeItem(at: during.root) }
        let duringRunner = FastTrimToolRunner(
            sourceURL: during.source.sourceURL,
            sourceChapters: during.chapterData,
            sourceToMutate: during.source.sourceURL
        )
        let duringExecutor = makeExecutor(
            runner: duringRunner,
            inspector: FastTrimInspector(original: during.source)
        )
        let duringPreview = try await duringExecutor.preview(
            source: during.source,
            requestedRange: range(3, 9)
        )
        let duringDestination = during.root.appendingPathComponent("during.mkv")
        await assertThrows(
            try await duringExecutor.execute(
                preview: duringPreview,
                destinationURL: duringDestination
            )
        ) { XCTAssertEqual($0 as? FastTrimExecutionError, .staleSource) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: duringDestination.path))
    }

    func testToolDurationAndChapterFailuresLeaveNoDestination() async throws {
        for mode in 0..<3 {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let runner = FastTrimToolRunner(
                sourceURL: fixture.source.sourceURL,
                sourceChapters: fixture.chapterData,
                failingTool: mode == 0 ? "mkvmerge" : nil,
                wrongOutputChapters: mode == 2
            )
            let inspector = FastTrimInspector(
                original: fixture.source,
                behavior: mode == 1 ? .wrongDuration : .valid
            )
            let executor = makeExecutor(runner: runner, inspector: inspector)
            let preview = try await executor.preview(
                source: fixture.source,
                requestedRange: range(3, 9)
            )
            let destination = fixture.root.appendingPathComponent("failed.mkv")
            await assertThrows(
                try await executor.execute(
                    preview: preview,
                    destinationURL: destination
                )
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testCommittedReopenFailureReportsTheSavedOutput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = FastTrimToolRunner(
            sourceURL: fixture.source.sourceURL,
            sourceChapters: fixture.chapterData
        )
        let executor = makeExecutor(
            runner: runner,
            inspector: FastTrimInspector(
                original: fixture.source,
                behavior: .wrongCommittedDuration
            )
        )
        let preview = try await executor.preview(
            source: fixture.source,
            requestedRange: range(3, 9)
        )
        let destination = fixture.root.appendingPathComponent("audit-failed.mkv")

        await assertThrows(
            try await executor.execute(preview: preview, destinationURL: destination)
        ) { error in
            guard
                case .committedOutputAuditFailed(let outputURL, _) =
                    error as? FastTrimExecutionError
            else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(outputURL, destination)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    private struct Fixture {
        let root: URL
        let source: MediaAsset
        let chapterData: Data
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-fast-trim-executor-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sourceURL = root.appendingPathComponent("Source.mkv")
        try Data("original source bytes".utf8).write(to: sourceURL)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            fileSize: Int64("original source bytes".utf8.count),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: "mpeg4",
                    codecID: "V_MPEG4/ISO/ASP",
                    profile: "Advanced Simple Profile",
                    uid: 100,
                    isDefault: true,
                    dimensions: MediaDimensions(width: 160, height: 90),
                    pixelFormat: "yuv420p",
                    bitDepth: 8,
                    frameRate: "10/1"
                )
            ],
            metadata: ["title": "Feature"],
            chapterEntryCount: 1,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "SOURCE-SEGMENT"
        )
        let chapters = MatroskaChapterDocument(editions: [
            MatroskaChapterEdition(
                isDefault: true,
                chapters: [
                    MatroskaChapterAtom(
                        start: .zero,
                        end: MediaTime(nanoseconds: 10_000_000_000),
                        displays: [ChapterDisplay(title: "Complete Feature")]
                    )
                ]
            )
        ])
        return Fixture(
            root: root,
            source: source,
            chapterData: try MatroskaChapterXMLCodec().serialize(chapters)
        )
    }

    private func makeExecutor(
        runner: FastTrimToolRunner,
        inspector: FastTrimInspector
    ) -> FastTrimExecutor<FastTrimToolRunner, FastTrimInspector> {
        FastTrimExecutor(
            ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: inspector
        )
    }

    private func range(_ start: Int64, _ end: Int64) -> MediaTrimRange {
        MediaTrimRange(
            start: MediaTime(nanoseconds: start * 1_000_000_000),
            end: MediaTime(nanoseconds: end * 1_000_000_000)
        )
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}

private func assertThrows<T>(
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
