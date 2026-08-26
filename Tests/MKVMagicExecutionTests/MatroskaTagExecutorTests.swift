import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor TagToolRunner: CommandRunning {
    private let originalXML: Data
    private let changedXML: Data?
    private let propertyEditExitCode: Int32
    private let truncatedPropertyEditLog: Bool
    private var sourceExtractionCount = 0
    private var hasClearedTags = false
    private var requests = [CommandRequest]()

    init(
        originalXML: Data,
        changedXML: Data? = nil,
        propertyEditExitCode: Int32 = 0,
        truncatedPropertyEditLog: Bool = false
    ) {
        self.originalXML = originalXML
        self.changedXML = changedXML
        self.propertyEditExitCode = propertyEditExitCode
        self.truncatedPropertyEditLog = truncatedPropertyEditLog
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        switch request.executableURL.lastPathComponent {
        case "mkvextract":
            let outputURL = URL(fileURLWithPath: request.arguments.last!)
            let data: Data
            if hasClearedTags {
                data = Self.emptyXML
            } else {
                sourceExtractionCount += 1
                data = sourceExtractionCount > 1 ? changedXML ?? originalXML : originalXML
            }
            try data.write(to: outputURL)
            return success()
        case "mkvpropedit":
            if propertyEditExitCode == 0 {
                hasClearedTags = true
            }
            return CommandResult(
                exitCode: propertyEditExitCode,
                standardOutput: CommandOutput(
                    data: Data(),
                    wasTruncated: truncatedPropertyEditLog
                ),
                standardError: CommandOutput(
                    data: Data(propertyEditExitCode == 0 ? "".utf8 : "bounded failure".utf8),
                    wasTruncated: false
                )
            )
        default:
            return CommandResult(
                exitCode: 2,
                standardOutput: CommandOutput(data: Data(), wasTruncated: false),
                standardError: CommandOutput(
                    data: Data("unexpected tool".utf8),
                    wasTruncated: false
                )
            )
        }
    }

    func capturedRequests() -> [CommandRequest] { requests }

    private func success() -> CommandResult {
        CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }

    private static let emptyXML = Data(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Tags>\n</Tags>\n".utf8
    )
}

private struct TagInspector: MediaInspecting {
    let source: MediaAsset
    let output: MediaAsset

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        tagAssetCopy(inputURL == source.sourceURL ? source : output, sourceURL: inputURL)
    }
}

private actor TagStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()

    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func snapshot() -> [VerifiedOutputExecutionStage] { stages }
}

final class MatroskaTagExecutorTests: XCTestCase {
    func testPreviewsAndExportsExactTagXMLWithoutChangingSource() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let originalBytes = try Data(contentsOf: fixture.source.sourceURL)
        let runner = TagToolRunner(originalXML: fixture.tagXML)
        let executor = makeExecutor(runner: runner, source: fixture.source, output: fixture.output)
        let preview = try await executor.preview(source: fixture.source)
        let stages = TagStageRecorder()

        let result = try await executor.export(
            preview: preview,
            destinationURL: fixture.exportURL,
            onStage: { stage in await stages.append(stage) }
        )

        XCTAssertEqual(result.outputURL, fixture.exportURL)
        XCTAssertEqual(result.byteCount, fixture.tagXML.count)
        XCTAssertEqual(result.counts, MatroskaTagCounts(global: 1, track: 1))
        XCTAssertEqual(try Data(contentsOf: fixture.exportURL), fixture.tagXML)
        XCTAssertEqual(try Data(contentsOf: fixture.source.sourceURL), originalBytes)
        let recordedStages = await stages.snapshot()
        XCTAssertEqual(recordedStages, [.verifying, .committing])
        let requests = await runner.capturedRequests()
        let extractions = requests.filter { $0.executableURL.lastPathComponent == "mkvextract" }
        XCTAssertEqual(extractions.count, 3)
        XCTAssertTrue(extractions.allSatisfy { $0.arguments.contains("--no-bom") })
        XCTAssertTrue(extractions.allSatisfy { $0.timeout == 120 })
    }

    func testClearsAllTagsOnVerifiedCloneAndAuditsEmptyXML() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let originalBytes = try Data(contentsOf: fixture.source.sourceURL)
        let runner = TagToolRunner(originalXML: fixture.tagXML)
        let executor = makeExecutor(runner: runner, source: fixture.source, output: fixture.output)
        let preview = try await executor.preview(source: fixture.source)
        let stages = TagStageRecorder()

        let result = try await executor.removeAll(
            preview: preview,
            destinationURL: fixture.removedURL,
            onStage: { stage in await stages.append(stage) }
        )

        XCTAssertEqual(result.sourceURL, fixture.removedURL)
        XCTAssertEqual(result.globalTagCount, 0)
        XCTAssertEqual(result.trackTagCount, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.source.sourceURL), originalBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.removedURL.path))
        let recordedStages = await stages.snapshot()
        XCTAssertEqual(recordedStages, [.verifying, .committing])
        let requests = await runner.capturedRequests()
        let propertyEdit = try XCTUnwrap(
            requests.first { $0.executableURL.lastPathComponent == "mkvpropedit" }
        )
        XCTAssertEqual(
            Array(propertyEdit.arguments.suffix(2)),
            ["--tags", "all:"]
        )
        XCTAssertEqual(propertyEdit.timeout, 120)
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvextract" }.count,
            4
        )
    }

    func testPreviewUsesExactXMLWhenInspectionUndercountsFlattenedTrackTags() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let undercounted = tagAssetCopy(
            fixture.source,
            sourceURL: fixture.source.sourceURL,
            trackTagCount: 0
        )
        let runner = TagToolRunner(originalXML: fixture.tagXML)
        let executor = makeExecutor(
            runner: runner,
            source: undercounted,
            output: fixture.output
        )

        let preview = try await executor.preview(source: undercounted)

        XCTAssertEqual(preview.document.counts, MatroskaTagCounts(global: 1, track: 1))
    }

    func testStaleInspectionFailsBeforeTagExtraction() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = TagToolRunner(originalXML: fixture.tagXML)
        let stale = tagAssetCopy(
            fixture.source,
            sourceURL: fixture.source.sourceURL,
            metadata: ["title": "Changed"]
        )
        let executor = makeExecutor(runner: runner, source: stale, output: fixture.output)

        await assertTagError(
            try await executor.preview(source: fixture.source),
            expected: .staleSource
        )
        let requests = await runner.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testChangedExtractionNeverCreatesDestination() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let changed = fixture.tagXML.replacingOccurrences(of: "Fixture", with: "Changed")
        let runner = TagToolRunner(originalXML: fixture.tagXML, changedXML: changed)
        let executor = makeExecutor(runner: runner, source: fixture.source, output: fixture.output)
        let preview = try await executor.preview(source: fixture.source)

        await assertTagError(
            try await executor.export(
                preview: preview,
                destinationURL: fixture.exportURL
            ),
            expected: .extractionChanged
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.exportURL.path))
    }

    func testWrongTagRemovalOutputFailsBeforeCommit() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = TagToolRunner(originalXML: fixture.tagXML)
        let wrongOutput = tagAssetCopy(
            fixture.output,
            sourceURL: fixture.output.sourceURL,
            globalTagCount: 1
        )
        let executor = makeExecutor(runner: runner, source: fixture.source, output: wrongOutput)
        let preview = try await executor.preview(source: fixture.source)

        do {
            _ = try await executor.removeAll(
                preview: preview,
                destinationURL: fixture.removedURL
            )
            XCTFail("Expected tag verification to fail")
        } catch {
            XCTAssertEqual(error as? OutputVerificationError, .tagsChanged)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.removedURL.path))
    }

    func testPropertyEditFailureAndTruncationFailClosed() async throws {
        for (runner, expected) in [
            (
                TagToolRunner(originalXML: tagXML, propertyEditExitCode: 3),
                MatroskaTagExecutionError.toolFailed(
                    tool: "mkvpropedit",
                    exitCode: 3,
                    message: "bounded failure"
                )
            ),
            (
                TagToolRunner(originalXML: tagXML, truncatedPropertyEditLog: true),
                MatroskaTagExecutionError.toolFailed(
                    tool: "mkvpropedit",
                    exitCode: 0,
                    message: "Unknown tool error"
                )
            ),
        ] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let executor = makeExecutor(
                runner: runner,
                source: fixture.source,
                output: fixture.output
            )
            let preview = try await executor.preview(source: fixture.source)
            await assertTagError(
                try await executor.removeAll(
                    preview: preview,
                    destinationURL: fixture.removedURL
                ),
                expected: expected
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.removedURL.path))
        }
    }

    private var tagXML: Data {
        Self.makeTagXML(globalValue: "Fixture", trackValue: "Lead")
    }

    private func makeExecutor(
        runner: TagToolRunner,
        source: MediaAsset,
        output: MediaAsset
    ) -> MatroskaTagExecutor<TagToolRunner, TagInspector> {
        MatroskaTagExecutor(
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: TagInspector(source: source, output: output)
        )
    }

    private func makeFixture() throws -> (
        root: URL,
        source: MediaAsset,
        output: MediaAsset,
        tagXML: Data,
        exportURL: URL,
        removedURL: URL
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-tag-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        try Data("bounded fake Matroska source".utf8).write(to: sourceURL)
        let track = MediaTrack(
            id: 0,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            uid: 42,
            language: "eng",
            title: "Main Video",
            tags: ["TITLE": "Lead"]
        )
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska,webm",
            formatLongName: "Matroska / WebM",
            duration: MediaTime(seconds: 3),
            fileSize: 28,
            bitrate: 1_000_000,
            tracks: [track],
            chapters: [ChapterNode(title: "Opening", start: .zero)],
            attachments: [MediaAttachment(id: 1, filename: "Font.ttf", uid: 55)],
            metadata: ["title": "Fixture Movie", "artist": "Fixture"],
            chapterEntryCount: 1,
            globalTagCount: 1,
            trackTagCount: 1,
            segmentUID: "stable-segment",
            muxingApplication: "libebml",
            writingApplication: "mkvmerge",
            warnings: []
        )
        let output = MediaAsset(
            sourceURL: root.appendingPathComponent("temporary-output.mkv"),
            container: source.container,
            formatLongName: source.formatLongName,
            duration: source.duration,
            fileSize: 24,
            bitrate: source.bitrate,
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: "h264",
                    codecID: "V_MPEG4/ISO/AVC",
                    uid: 42,
                    language: "eng",
                    title: "Main Video"
                )
            ],
            chapters: source.chapters,
            attachments: source.attachments,
            metadata: ["title": "Fixture Movie"],
            chapterEntryCount: source.chapterEntryCount,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: source.segmentUID,
            muxingApplication: source.muxingApplication,
            writingApplication: source.writingApplication,
            warnings: []
        )
        return (
            root,
            source,
            output,
            tagXML,
            root.appendingPathComponent("Movie Tags.xml"),
            root.appendingPathComponent("Movie — Tags Removed.mkv")
        )
    }

    private static func makeTagXML(globalValue: String, trackValue: String) -> Data {
        Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE Tags SYSTEM "matroskatags.dtd">
            <Tags>
              <Tag><Targets /><Simple><Name>ARTIST</Name><String>\(globalValue)</String></Simple></Tag>
              <Tag><Targets><TrackUID>42</TrackUID></Targets><Simple><Name>TITLE</Name><String>\(trackValue)</String></Simple></Tag>
            </Tags>
            """.utf8
        )
    }
}

private func tagAssetCopy(
    _ asset: MediaAsset,
    sourceURL: URL,
    metadata: [String: String]? = nil,
    globalTagCount: Int? = nil,
    trackTagCount: Int? = nil
) -> MediaAsset {
    MediaAsset(
        id: asset.id,
        sourceURL: sourceURL,
        container: asset.container,
        formatLongName: asset.formatLongName,
        duration: asset.duration,
        fileSize: asset.fileSize,
        bitrate: asset.bitrate,
        tracks: asset.tracks,
        chapters: asset.chapters,
        attachments: asset.attachments,
        metadata: metadata ?? asset.metadata,
        chapterEntryCount: asset.chapterEntryCount,
        globalTagCount: globalTagCount ?? asset.globalTagCount,
        trackTagCount: trackTagCount ?? asset.trackTagCount,
        segmentUID: asset.segmentUID,
        muxingApplication: asset.muxingApplication,
        writingApplication: asset.writingApplication,
        warnings: asset.warnings
    )
}

extension Data {
    fileprivate func replacingOccurrences(of oldValue: String, with newValue: String) -> Data {
        let string = String(decoding: self, as: UTF8.self)
        return Data(string.replacingOccurrences(of: oldValue, with: newValue).utf8)
    }
}

private func assertTagError<T>(
    _ expression: @autoclosure () async throws -> T,
    expected: MatroskaTagExecutionError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        XCTAssertEqual(
            error as? MatroskaTagExecutionError,
            expected,
            file: file,
            line: line
        )
    }
}
