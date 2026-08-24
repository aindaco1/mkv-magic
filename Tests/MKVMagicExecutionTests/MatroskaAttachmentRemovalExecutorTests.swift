import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor AttachmentRemovalRunner: CommandRunning {
    private let exitCode: Int32
    private let truncated: Bool
    private var requests = [CommandRequest]()

    init(exitCode: Int32 = 0, truncated: Bool = false) {
        self.exitCode = exitCode
        self.truncated = truncated
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        if exitCode == 0,
            let outputIndex = request.arguments.firstIndex(of: "--output"),
            request.arguments.indices.contains(outputIndex + 1)
        {
            try Data("temporary Matroska output".utf8).write(
                to: URL(fileURLWithPath: request.arguments[outputIndex + 1])
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

private struct AttachmentRemovalInspector: MediaInspecting {
    let source: MediaAsset
    let output: MediaAsset

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        assetCopy(inputURL == source.sourceURL ? source : output, sourceURL: inputURL)
    }
}

private actor AttachmentRemovalStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()

    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func snapshot() -> [VerifiedOutputExecutionStage] { stages }
}

final class MatroskaAttachmentRemovalExecutorTests: XCTestCase {
    func testPreviewsAndCommitsOneVerifiedAttachmentOmission() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceBytes = try Data(contentsOf: fixture.source.sourceURL)
        let runner = AttachmentRemovalRunner()
        let executor = makeExecutor(
            runner: runner,
            source: fixture.source,
            output: fixture.output
        )
        let removal = MatroskaAttachmentRemoval(attachmentUIDs: [22])
        let preview = try await executor.preview(source: fixture.source, removal: removal)

        XCTAssertEqual(preview.removedAttachments.map(\.uid), [22])
        XCTAssertEqual(preview.retainedAttachments.map(\.uid), [44])
        let stages = AttachmentRemovalStageRecorder()
        let result = try await executor.execute(
            preview: preview,
            destinationURL: fixture.destinationURL,
            onStage: { stage in await stages.append(stage) }
        )

        XCTAssertEqual(result.sourceURL, fixture.destinationURL)
        XCTAssertEqual(result.attachments.map(\.uid), [44])
        XCTAssertEqual(try Data(contentsOf: fixture.source.sourceURL), sourceBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
        let recordedStages = await stages.snapshot()
        XCTAssertEqual(recordedStages, [.verifying, .committing])
        let requests = await runner.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.executableURL.path, "/tools/mkvmerge")
        XCTAssertEqual(request.timeout, 24 * 60 * 60)
        XCTAssertTrue(containsPair("--attachments", "4", in: request.arguments))
        XCTAssertTrue(containsPair("--track-order", "0:0", in: request.arguments))
        XCTAssertEqual(request.arguments.last, fixture.source.sourceURL.path)
        XCTAssertFalse(request.arguments.contains("--no-attachments"))
    }

    func testAllAttachmentRemovalUsesExplicitNoAttachmentsSelector() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let arguments = try MKVAttachmentRemover<AttachmentRemovalRunner>.arguments(
            source: fixture.source,
            removal: MatroskaAttachmentRemoval(attachmentUIDs: [22, 44]),
            outputURL: fixture.destinationURL
        )

        XCTAssertTrue(arguments.contains("--no-attachments"))
        XCTAssertFalse(arguments.contains("--attachments"))
        XCTAssertTrue(containsPair("--track-order", "0:0", in: arguments))
    }

    func testStaleInspectionFailsBeforeMkvmerge() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = AttachmentRemovalRunner()
        let staleSource = assetCopy(
            fixture.source,
            sourceURL: fixture.source.sourceURL,
            attachments: [
                MediaAttachment(id: 2, filename: "Changed.jpg", size: 12, uid: 22),
                fixture.source.attachments[1],
            ]
        )
        let executor = makeExecutor(
            runner: runner,
            source: staleSource,
            output: fixture.output
        )

        await XCTAssertThrowsAttachmentRemovalError(
            try await executor.preview(
                source: fixture.source,
                removal: MatroskaAttachmentRemoval(attachmentUIDs: [22])
            ),
            expected: .staleSource
        )
        let requests = await runner.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testSourceMutationDuringVerificationNeverCommits() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = AttachmentRemovalRunner()
        let executor = makeExecutor(
            runner: runner,
            source: fixture.source,
            output: fixture.output
        )
        let preview = try await executor.preview(
            source: fixture.source,
            removal: MatroskaAttachmentRemoval(attachmentUIDs: [22])
        )

        await XCTAssertThrowsAttachmentRemovalError(
            try await executor.execute(
                preview: preview,
                destinationURL: fixture.destinationURL,
                onStage: { stage in
                    if stage == .verifying {
                        try Data("changed during verification".utf8).write(
                            to: fixture.source.sourceURL
                        )
                    }
                }
            ),
            expected: .staleSource
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    func testWrongOutputAttachmentFailsBeforeCommit() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = AttachmentRemovalRunner()
        let wrongOutput = assetCopy(
            fixture.output,
            sourceURL: fixture.output.sourceURL,
            attachments: fixture.source.attachments
        )
        let executor = makeExecutor(
            runner: runner,
            source: fixture.source,
            output: wrongOutput
        )
        let preview = try await executor.preview(
            source: fixture.source,
            removal: MatroskaAttachmentRemoval(attachmentUIDs: [22])
        )

        do {
            _ = try await executor.execute(
                preview: preview,
                destinationURL: fixture.destinationURL
            )
            XCTFail("Expected attachment verification to fail")
        } catch {
            XCTAssertEqual(error as? OutputVerificationError, .attachmentsChanged)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    func testToolFailureAndTruncationFailClosed() async throws {
        for (runner, expected) in [
            (
                AttachmentRemovalRunner(exitCode: 3),
                MatroskaAttachmentRemovalError.toolFailed(
                    exitCode: 3,
                    message: "bounded failure"
                )
            ),
            (
                AttachmentRemovalRunner(truncated: true),
                MatroskaAttachmentRemovalError.toolFailed(
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
            let preview = try await executor.preview(
                source: fixture.source,
                removal: MatroskaAttachmentRemoval(attachmentUIDs: [22])
            )
            await XCTAssertThrowsAttachmentRemovalError(
                try await executor.execute(
                    preview: preview,
                    destinationURL: fixture.destinationURL
                ),
                expected: expected
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
        }
    }

    private func makeExecutor(
        runner: AttachmentRemovalRunner,
        source: MediaAsset,
        output: MediaAsset
    ) -> MatroskaAttachmentRemovalExecutor<
        AttachmentRemovalRunner, AttachmentRemovalInspector
    > {
        MatroskaAttachmentRemovalExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            runner: runner,
            inspector: AttachmentRemovalInspector(source: source, output: output)
        )
    }

    private func makeFixture() throws -> (
        root: URL,
        source: MediaAsset,
        output: MediaAsset,
        destinationURL: URL
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-attachment-removal-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        try Data("bounded fake source Matroska".utf8).write(to: sourceURL)
        let destinationURL = root.appendingPathComponent("Movie — Attachments Removed.mkv")
        let track = MediaTrack(
            id: 0,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            uid: 100,
            language: "eng",
            title: "Main Video"
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
            attachments: [
                MediaAttachment(
                    id: 2,
                    filename: "Poster.jpg",
                    mimeType: "image/jpeg",
                    size: 12,
                    description: "Poster",
                    uid: 22
                ),
                MediaAttachment(
                    id: 4,
                    filename: "Font.ttf",
                    mimeType: "font/ttf",
                    size: 14,
                    description: "Subtitle font",
                    uid: 44
                ),
            ],
            metadata: ["title": "Fixture Movie"],
            chapterEntryCount: 1,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "old-segment",
            muxingApplication: "libebml",
            writingApplication: "mkvmerge",
            warnings: []
        )
        let output = MediaAsset(
            sourceURL: destinationURL,
            container: source.container,
            formatLongName: source.formatLongName,
            duration: source.duration,
            fileSize: 24,
            bitrate: source.bitrate,
            tracks: [track],
            chapters: source.chapters,
            attachments: [
                MediaAttachment(
                    id: 1,
                    filename: "Font.ttf",
                    mimeType: "font/ttf",
                    size: 14,
                    description: "Subtitle font",
                    uid: 44
                )
            ],
            metadata: source.metadata,
            chapterEntryCount: source.chapterEntryCount,
            globalTagCount: source.globalTagCount,
            trackTagCount: source.trackTagCount,
            segmentUID: "new-segment",
            muxingApplication: "libebml",
            writingApplication: "mkvmerge",
            warnings: []
        )
        return (root, source, output, destinationURL)
    }
}

private func containsPair(_ first: String, _ second: String, in arguments: [String]) -> Bool {
    zip(arguments, arguments.dropFirst()).contains { $0 == first && $1 == second }
}

private func assetCopy(
    _ asset: MediaAsset,
    sourceURL: URL,
    attachments: [MediaAttachment]? = nil
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
        attachments: attachments ?? asset.attachments,
        metadata: asset.metadata,
        chapterEntryCount: asset.chapterEntryCount,
        globalTagCount: asset.globalTagCount,
        trackTagCount: asset.trackTagCount,
        segmentUID: asset.segmentUID,
        muxingApplication: asset.muxingApplication,
        writingApplication: asset.writingApplication,
        warnings: asset.warnings
    )
}

private func XCTAssertThrowsAttachmentRemovalError<T>(
    _ expression: @autoclosure () async throws -> T,
    expected: MatroskaAttachmentRemovalError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        XCTAssertEqual(
            error as? MatroskaAttachmentRemovalError,
            expected,
            file: file,
            line: line
        )
    }
}
