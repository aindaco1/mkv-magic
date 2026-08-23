import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

private actor ChapterToolRunner: CommandRunning {
    private let sourceURL: URL
    private let originalXML: Data
    private let returnWrongEditedChapters: Bool
    private var desiredXML: Data?
    private var invocations = [[String]]()

    init(sourceURL: URL, originalXML: Data, returnWrongEditedChapters: Bool = false) {
        self.sourceURL = sourceURL
        self.originalXML = originalXML
        self.returnWrongEditedChapters = returnWrongEditedChapters
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        invocations.append(request.arguments)
        switch request.executableURL.lastPathComponent {
        case "mkvextract":
            let inputURL = URL(fileURLWithPath: request.arguments[0]).standardizedFileURL
            let outputURL = URL(fileURLWithPath: request.arguments[2])
            let isOriginal = inputURL == sourceURL.standardizedFileURL
            let data =
                if isOriginal || returnWrongEditedChapters {
                    originalXML
                } else {
                    desiredXML ?? originalXML
                }
            try data.write(to: outputURL)
            return success()
        case "mkvpropedit":
            guard let chaptersIndex = request.arguments.firstIndex(of: "--chapters") else {
                return failure()
            }
            let chapterPath = request.arguments[request.arguments.index(after: chaptersIndex)]
            desiredXML =
                chapterPath.isEmpty
                ? Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Chapters>\n</Chapters>\n".utf8)
                : try Data(contentsOf: URL(fileURLWithPath: chapterPath))
            return success()
        default:
            return failure()
        }
    }

    func calls() -> [[String]] { invocations }

    private func success() -> CommandResult {
        CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }

    private func failure() -> CommandResult {
        CommandResult(
            exitCode: 2,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data("unexpected tool".utf8), wasTruncated: false)
        )
    }
}

private struct ChapterInspector: MediaInspecting {
    let source: MediaAsset

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: source.container,
            formatLongName: source.formatLongName,
            duration: source.duration,
            fileSize: Int64(
                (try? inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 1),
            bitrate: source.bitrate,
            tracks: source.tracks,
            chapters: [],
            attachments: source.attachments,
            metadata: source.metadata,
            chapterEntryCount: 0,
            globalTagCount: source.globalTagCount,
            trackTagCount: source.trackTagCount,
            segmentUID: source.segmentUID,
            muxingApplication: source.muxingApplication,
            writingApplication: source.writingApplication,
            warnings: source.warnings
        )
    }
}

private actor ChapterStageRecorder {
    private var values = [VerifiedOutputExecutionStage]()

    func append(_ value: VerifiedOutputExecutionStage) { values.append(value) }
    func stages() -> [VerifiedOutputExecutionStage] { values }
}

final class ChapterEditExecutorTests: XCTestCase {
    func testVerifiedChapterReplacementPreservesSourceAndAuditsCommittedOutput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let originalBytes = try Data(contentsOf: fixture.source.sourceURL)
        let runner = ChapterToolRunner(
            sourceURL: fixture.source.sourceURL,
            originalXML: fixture.originalXML
        )
        let executor = makeExecutor(runner: runner, source: fixture.source)
        let preview = try await executor.preview(source: fixture.source)
        let destination = fixture.directory.appendingPathComponent("edited.mkv")
        let stageRecorder = ChapterStageRecorder()

        let output = try await executor.execute(
            preview: preview,
            desired: fixture.desired,
            destinationURL: destination,
            onStage: { stage in await stageRecorder.append(stage) }
        )

        XCTAssertEqual(output.sourceURL, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: fixture.source.sourceURL), originalBytes)
        let stages = await stageRecorder.stages()
        XCTAssertEqual(stages, [.verifying, .committing])
        let calls = await runner.calls()
        XCTAssertEqual(calls.filter { $0.contains("chapters") }.count, 4)
        XCTAssertEqual(calls.filter { $0.contains("--chapters") }.count, 1)
    }

    func testChangedSourceAfterPreviewFailsBeforePropertyEdit() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let runner = ChapterToolRunner(
            sourceURL: fixture.source.sourceURL,
            originalXML: fixture.originalXML
        )
        let executor = makeExecutor(runner: runner, source: fixture.source)
        let preview = try await executor.preview(source: fixture.source)
        try Data("changed".utf8).write(to: fixture.source.sourceURL, options: .atomic)
        let destination = fixture.directory.appendingPathComponent("stale.mkv")

        do {
            _ = try await executor.execute(
                preview: preview,
                desired: fixture.desired,
                destinationURL: destination
            )
            XCTFail("Expected stale source refusal")
        } catch {
            XCTAssertEqual(error as? ChapterEditExecutionError, .staleSource)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let calls = await runner.calls()
        XCTAssertFalse(calls.contains { $0.contains("--chapters") })
    }

    func testMismatchedExtractedOutputNeverCommits() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let runner = ChapterToolRunner(
            sourceURL: fixture.source.sourceURL,
            originalXML: fixture.originalXML,
            returnWrongEditedChapters: true
        )
        let executor = makeExecutor(runner: runner, source: fixture.source)
        let preview = try await executor.preview(source: fixture.source)
        let destination = fixture.directory.appendingPathComponent("mismatch.mkv")

        do {
            _ = try await executor.execute(
                preview: preview,
                desired: fixture.desired,
                destinationURL: destination
            )
            XCTFail("Expected chapter verification refusal")
        } catch {
            XCTAssertEqual(error as? ChapterEditExecutionError, .chapterVerificationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testUnchangedDocumentIsRejectedBeforeACloneIsCreated() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let runner = ChapterToolRunner(
            sourceURL: fixture.source.sourceURL,
            originalXML: fixture.originalXML
        )
        let executor = makeExecutor(runner: runner, source: fixture.source)
        let preview = try await executor.preview(source: fixture.source)

        do {
            _ = try await executor.execute(
                preview: preview,
                desired: preview.original,
                destinationURL: fixture.directory.appendingPathComponent("unchanged.mkv")
            )
            XCTFail("Expected no-change refusal")
        } catch {
            XCTAssertEqual(error as? ChapterEditExecutionError, .noChanges)
        }
        let calls = await runner.calls()
        XCTAssertEqual(calls.count, 1)
    }

    private func makeExecutor(
        runner: ChapterToolRunner,
        source: MediaAsset
    ) -> ChapterEditExecutor<ChapterToolRunner, ChapterInspector> {
        ChapterEditExecutor(
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: ChapterInspector(source: source)
        )
    }

    private func makeFixture() throws -> (
        directory: URL,
        source: MediaAsset,
        originalXML: Data,
        desired: MatroskaChapterDocument
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-chapter-unit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let sourceURL = directory.appendingPathComponent("source.mkv")
        try Data("source fixture".utf8).write(to: sourceURL)
        let original = MatroskaChapterDocument(
            editions: [
                MatroskaChapterEdition(
                    uid: 1,
                    chapters: [
                        MatroskaChapterAtom(
                            uid: 10,
                            start: .zero,
                            displays: [ChapterDisplay(title: "Opening")]
                        )
                    ]
                )
            ]
        )
        let desired = MatroskaChapterDocument(
            editions: [
                MatroskaChapterEdition(
                    uid: 1,
                    chapters: [
                        MatroskaChapterAtom(
                            uid: 10,
                            start: .zero,
                            end: MediaTime(nanoseconds: 30_000_000_000),
                            displays: [ChapterDisplay(title: "Part One")],
                            children: [
                                MatroskaChapterAtom(
                                    uid: 11,
                                    start: .zero,
                                    displays: [ChapterDisplay(title: "Opening")]
                                )
                            ]
                        )
                    ]
                )
            ]
        )
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 60_000_000_000),
            fileSize: 14,
            tracks: [MediaTrack(id: 0, kind: .audio, codec: "aac", uid: 100)],
            attachments: [],
            metadata: ["title": "Fixture"],
            chapterEntryCount: 1,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "001122"
        )
        return (directory, source, try MatroskaChapterXMLCodec().serialize(original), desired)
    }
}
