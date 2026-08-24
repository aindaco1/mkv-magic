import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor AttachmentExtractionRunner: CommandRunning {
    private let outputs: [Data]
    private let exitCode: Int32
    private let truncated: Bool
    private var requests = [CommandRequest]()

    init(outputs: [Data], exitCode: Int32 = 0, truncated: Bool = false) {
        self.outputs = outputs
        self.exitCode = exitCode
        self.truncated = truncated
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        let call = requests.count
        requests.append(request)
        if exitCode == 0,
            let extraction = request.arguments.last,
            let separator = extraction.firstIndex(of: ":")
        {
            let outputPath = String(extraction[extraction.index(after: separator)...])
            try outputs[min(call, outputs.count - 1)].write(
                to: URL(fileURLWithPath: outputPath)
            )
        }
        return CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: truncated),
            standardError: CommandOutput(
                data: Data(exitCode == 0 ? "".utf8 : "bounded failure".utf8),
                wasTruncated: false
            )
        )
    }

    func capturedRequests() -> [CommandRequest] { requests }
}

private struct AttachmentExtractionInspector: MediaInspecting {
    let asset: MediaAsset

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            id: asset.id,
            sourceURL: inputURL,
            container: asset.container,
            duration: asset.duration,
            fileSize: asset.fileSize,
            bitrate: asset.bitrate,
            tracks: asset.tracks,
            chapters: asset.chapters,
            attachments: asset.attachments,
            metadata: asset.metadata,
            chapterEntryCount: asset.chapterEntryCount,
            globalTagCount: asset.globalTagCount,
            trackTagCount: asset.trackTagCount,
            segmentUID: asset.segmentUID
        )
    }
}

private actor AttachmentExtractionStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()

    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func snapshot() -> [VerifiedOutputExecutionStage] { stages }
}

final class MatroskaAttachmentExtractionExecutorTests: XCTestCase {
    func testPreviewsAndCommitsExactBinaryAttachment() async throws {
        let payload = Data([0, 1, 2, 255, 0, 64, 128, 7])
        let fixture = try makeFixture(payloadSize: payload.count)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceData = try Data(contentsOf: fixture.sourceURL)
        let runner = AttachmentExtractionRunner(outputs: [payload, payload])
        let executor = makeExecutor(runner: runner, asset: fixture.asset)

        let preview = try await executor.preview(source: fixture.asset, attachmentUID: 42)
        XCTAssertEqual(preview.attachment.filename, "Poster Artwork.png")
        XCTAssertEqual(preview.byteCount, Int64(payload.count))
        let previewRequests = await runner.capturedRequests()
        let previewRequest = try XCTUnwrap(previewRequests.first)
        let previewOutputPath = try extractionOutputPath(previewRequest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewOutputPath))
        let stages = AttachmentExtractionStageRecorder()
        let result = try await executor.execute(
            preview: preview,
            destinationURL: fixture.destinationURL,
            onStage: { stage in await stages.append(stage) }
        )

        XCTAssertEqual(result.outputURL, fixture.destinationURL)
        XCTAssertEqual(result.byteCount, Int64(payload.count))
        XCTAssertEqual(try Data(contentsOf: fixture.destinationURL), payload)
        XCTAssertEqual(try Data(contentsOf: fixture.sourceURL), sourceData)
        let recordedStages = await stages.snapshot()
        XCTAssertEqual(recordedStages, [.verifying, .committing])
        let requests = await runner.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(
            requests.allSatisfy { request in
                request.executableURL.path == "/tools/mkvextract"
                    && request.arguments.count == 3
                    && request.arguments[0] == "attachments"
                    && request.arguments[1] == fixture.sourceURL.path
                    && request.arguments[2].hasPrefix("4:/")
            }
        )
    }

    func testStaleInspectionFailsBeforeExtraction() async throws {
        let payload = Data([1, 2, 3])
        let fixture = try makeFixture(payloadSize: payload.count)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let changed = MediaAsset(
            id: fixture.asset.id,
            sourceURL: fixture.sourceURL,
            container: fixture.asset.container,
            duration: fixture.asset.duration,
            fileSize: fixture.asset.fileSize,
            tracks: fixture.asset.tracks,
            attachments: [
                MediaAttachment(
                    id: 4,
                    filename: "Changed.png",
                    mimeType: "image/png",
                    size: Int64(payload.count),
                    uid: 42
                )
            ]
        )
        let runner = AttachmentExtractionRunner(outputs: [payload])
        let executor = makeExecutor(runner: runner, asset: changed)

        await XCTAssertThrowsAttachmentExtractionError(
            try await executor.preview(source: fixture.asset, attachmentUID: 42),
            expected: .staleSource
        )
        let requests = await runner.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testChangedSourceOrRepeatedExtractionNeverCommits() async throws {
        let payload = Data([1, 2, 3, 4])
        let fixture = try makeFixture(payloadSize: payload.count)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = AttachmentExtractionRunner(outputs: [payload, Data([4, 3, 2, 1])])
        let executor = makeExecutor(runner: runner, asset: fixture.asset)
        let preview = try await executor.preview(source: fixture.asset, attachmentUID: 42)

        await XCTAssertThrowsAttachmentExtractionError(
            try await executor.execute(
                preview: preview,
                destinationURL: fixture.destinationURL
            ),
            expected: .extractionChanged
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))

        let stableRunner = AttachmentExtractionRunner(outputs: [payload])
        let stableExecutor = makeExecutor(runner: stableRunner, asset: fixture.asset)
        let stablePreview = try await stableExecutor.preview(
            source: fixture.asset,
            attachmentUID: 42
        )
        try Data("changed source".utf8).write(to: fixture.sourceURL)
        await XCTAssertThrowsAttachmentExtractionError(
            try await stableExecutor.execute(
                preview: stablePreview,
                destinationURL: fixture.destinationURL
            ),
            expected: .staleSource
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    func testSourceMutationDuringVerificationNeverCommits() async throws {
        let payload = Data([1, 2, 3, 4])
        let fixture = try makeFixture(payloadSize: payload.count)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = AttachmentExtractionRunner(outputs: [payload, payload])
        let executor = makeExecutor(runner: runner, asset: fixture.asset)
        let preview = try await executor.preview(source: fixture.asset, attachmentUID: 42)

        await XCTAssertThrowsAttachmentExtractionError(
            try await executor.execute(
                preview: preview,
                destinationURL: fixture.destinationURL,
                onStage: { stage in
                    if stage == .verifying {
                        try Data("changed during verify".utf8).write(to: fixture.sourceURL)
                    }
                }
            ),
            expected: .staleSource
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    func testWrongSizeToolFailureAndTruncationFailClosed() async throws {
        let payload = Data([1, 2, 3, 4])
        let fixture = try makeFixture(payloadSize: payload.count)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        for (runner, expected) in [
            (
                AttachmentExtractionRunner(outputs: [Data([1, 2, 3])]),
                MatroskaAttachmentExtractionError.unsafeExtractedAttachment
            ),
            (
                AttachmentExtractionRunner(outputs: [payload], exitCode: 3),
                MatroskaAttachmentExtractionError.toolFailed(
                    exitCode: 3,
                    message: "bounded failure"
                )
            ),
            (
                AttachmentExtractionRunner(outputs: [payload], truncated: true),
                MatroskaAttachmentExtractionError.toolFailed(
                    exitCode: 0, message: "Unknown tool error")
            ),
        ] {
            let executor = makeExecutor(runner: runner, asset: fixture.asset)
            await XCTAssertThrowsAttachmentExtractionError(
                try await executor.preview(source: fixture.asset, attachmentUID: 42),
                expected: expected
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    private func makeExecutor(
        runner: AttachmentExtractionRunner,
        asset: MediaAsset
    ) -> MatroskaAttachmentExtractionExecutor<
        AttachmentExtractionRunner, AttachmentExtractionInspector
    > {
        MatroskaAttachmentExtractionExecutor(
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: AttachmentExtractionInspector(asset: asset)
        )
    }

    private func makeFixture(payloadSize: Int) throws -> (
        root: URL, sourceURL: URL, destinationURL: URL, asset: MediaAsset
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-attachment-extraction-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        try Data("bounded fake Matroska".utf8).write(to: sourceURL)
        let asset = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska,webm",
            duration: MediaTime(seconds: 3),
            fileSize: 21,
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "h264", codecID: "V_MPEG4/ISO/AVC", uid: 10)
            ],
            attachments: [
                MediaAttachment(
                    id: 4,
                    filename: "Poster Artwork.png",
                    mimeType: "image/png",
                    size: Int64(payloadSize),
                    description: "Poster",
                    uid: 42
                )
            ]
        )
        return (root, sourceURL, root.appendingPathComponent("Poster Artwork.png"), asset)
    }

    private func extractionOutputPath(_ request: CommandRequest) throws -> String {
        let argument = try XCTUnwrap(request.arguments.last)
        let separator = try XCTUnwrap(argument.firstIndex(of: ":"))
        return String(argument[argument.index(after: separator)...])
    }
}

private func XCTAssertThrowsAttachmentExtractionError<T>(
    _ expression: @autoclosure () async throws -> T,
    expected: MatroskaAttachmentExtractionError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        XCTAssertEqual(
            error as? MatroskaAttachmentExtractionError,
            expected,
            file: file,
            line: line
        )
    }
}
