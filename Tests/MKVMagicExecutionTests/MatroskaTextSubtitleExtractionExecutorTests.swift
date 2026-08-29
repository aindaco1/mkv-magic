import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor TextSubtitleExtractionRunner: CommandRunning {
    private let outputs: [Data]
    private let mutateSourceURL: URL?
    private let mutationCall: Int?
    private let exitCode: Int32
    private let truncated: Bool
    private var requests = [CommandRequest]()

    init(
        outputs: [Data],
        mutateSourceURL: URL? = nil,
        mutationCall: Int? = nil,
        exitCode: Int32 = 0,
        truncated: Bool = false
    ) {
        self.outputs = outputs
        self.mutateSourceURL = mutateSourceURL
        self.mutationCall = mutationCall
        self.exitCode = exitCode
        self.truncated = truncated
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        let call = requests.count
        requests.append(request)
        if exitCode == 0,
            let trackArgument = request.arguments.last,
            let separator = trackArgument.firstIndex(of: ":")
        {
            let outputPath = String(trackArgument[trackArgument.index(after: separator)...])
            try outputs[min(call, outputs.count - 1)].write(
                to: URL(fileURLWithPath: outputPath)
            )
        }
        if mutationCall == call, let mutateSourceURL {
            try Data("changed source".utf8).write(to: mutateSourceURL)
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

private actor TextSubtitleExtractionStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()

    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func snapshot() -> [VerifiedOutputExecutionStage] { stages }
}

private struct TextSubtitleExtractionInspector: MediaInspecting {
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

final class MatroskaTextSubtitleExtractionExecutorTests: XCTestCase {
    func testStaleInspectionFailsBeforeExtraction() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let changedAsset = MediaAsset(
            id: fixture.asset.id,
            sourceURL: fixture.sourceURL,
            container: fixture.asset.container,
            duration: fixture.asset.duration,
            fileSize: fixture.asset.fileSize,
            tracks: fixture.asset.tracks.map { track in
                guard track.uid == 12 else { return track }
                return MediaTrack(
                    id: track.id,
                    kind: track.kind,
                    codec: track.codec,
                    codecID: track.codecID,
                    uid: track.uid,
                    language: "fra"
                )
            }
        )
        let runner = TextSubtitleExtractionRunner(outputs: [srtData("Exact cue")])
        let executor = MatroskaTextSubtitleExtractionExecutor(
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: TextSubtitleExtractionInspector(asset: changedAsset)
        )

        await XCTAssertThrowsTextSubtitleExtractionError(
            try await executor.preview(source: fixture.asset, trackUID: 12),
            expected: .staleSource
        )
        let requests = await runner.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testPreviewsAndCommitsExactVerifiedSRTSidecar() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceData = try Data(contentsOf: fixture.sourceURL)
        let subtitleData = srtData("Exact cue")
        let runner = TextSubtitleExtractionRunner(outputs: [subtitleData, subtitleData])
        let executor = MatroskaTextSubtitleExtractionExecutor(
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: TextSubtitleExtractionInspector(asset: fixture.asset)
        )

        let preview = try await executor.preview(source: fixture.asset, trackUID: 12)
        XCTAssertEqual(preview.format, .subRip)
        XCTAssertEqual(preview.itemCount, 1)
        XCTAssertEqual(preview.byteCount, subtitleData.count)
        let stageRecorder = TextSubtitleExtractionStageRecorder()
        let result = try await executor.execute(
            preview: preview,
            destinationURL: fixture.destinationURL,
            onStage: { stage in await stageRecorder.append(stage) }
        )

        let stages = await stageRecorder.snapshot()
        XCTAssertEqual(stages, [.verifying, .committing])
        XCTAssertEqual(result.outputURL, fixture.destinationURL)
        XCTAssertEqual(result.itemCount, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.destinationURL), subtitleData)
        XCTAssertEqual(try Data(contentsOf: fixture.sourceURL), sourceData)
        let requests = await runner.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(
            requests.allSatisfy { request in
                request.executableURL.path == "/tools/mkvextract"
                    && request.arguments.count == 4
                    && request.arguments[0] == "--gui-mode"
                    && request.arguments[1] == "tracks"
                    && request.arguments[2] == fixture.sourceURL.path
                    && request.arguments[3].hasPrefix("2:/")
                    && !request.arguments.contains("sh")
            }
        )
    }

    func testChangedSourceAfterPreviewNeverCreatesDestination() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = TextSubtitleExtractionRunner(outputs: [srtData("Exact cue")])
        let executor = MatroskaTextSubtitleExtractionExecutor(
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: TextSubtitleExtractionInspector(asset: fixture.asset)
        )
        let preview = try await executor.preview(source: fixture.asset, trackUID: 12)
        try Data("changed MKV".utf8).write(to: fixture.sourceURL)

        await XCTAssertThrowsTextSubtitleExtractionError(
            try await executor.execute(preview: preview, destinationURL: fixture.destinationURL),
            expected: .staleSource
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    func testPreservesExactASSAndSSAFormats() async throws {
        for format in [ExternalTextSubtitleFormat.ass, .ssa] {
            let fixture = try makeFixture(format: format)
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let subtitleData = advancedSubtitleData(format: format)
            let runner = TextSubtitleExtractionRunner(outputs: [subtitleData, subtitleData])
            let executor = MatroskaTextSubtitleExtractionExecutor(
                mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
                runner: runner,
                inspector: TextSubtitleExtractionInspector(asset: fixture.asset)
            )

            let preview = try await executor.preview(source: fixture.asset, trackUID: 12)
            XCTAssertEqual(preview.format, format)
            XCTAssertEqual(preview.itemCount, 1)
            _ = try await executor.execute(
                preview: preview,
                destinationURL: fixture.destinationURL
            )
            XCTAssertEqual(try Data(contentsOf: fixture.destinationURL), subtitleData)
        }
    }

    func testChangedRepeatedExtractionNeverCommits() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = TextSubtitleExtractionRunner(outputs: [
            srtData("Exact cue"), srtData("Different cue"),
        ])
        let executor = MatroskaTextSubtitleExtractionExecutor(
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: TextSubtitleExtractionInspector(asset: fixture.asset)
        )
        let preview = try await executor.preview(source: fixture.asset, trackUID: 12)

        await XCTAssertThrowsTextSubtitleExtractionError(
            try await executor.execute(preview: preview, destinationURL: fixture.destinationURL),
            expected: .extractionChanged
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    func testSourceMutationDuringVerificationNeverCommits() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let subtitleData = srtData("Exact cue")
        let runner = TextSubtitleExtractionRunner(outputs: [subtitleData, subtitleData])
        let executor = MatroskaTextSubtitleExtractionExecutor(
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: TextSubtitleExtractionInspector(asset: fixture.asset)
        )
        let preview = try await executor.preview(source: fixture.asset, trackUID: 12)

        await XCTAssertThrowsTextSubtitleExtractionError(
            try await executor.execute(
                preview: preview,
                destinationURL: fixture.destinationURL,
                onStage: { stage in
                    if stage == .verifying {
                        try Data("changed during verification".utf8).write(to: fixture.sourceURL)
                    }
                }
            ),
            expected: .staleSource
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    func testWrongExtensionToolFailureAndTruncationFailClosed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let subtitleData = srtData("Exact cue")
        let runner = TextSubtitleExtractionRunner(outputs: [subtitleData])
        let executor = MatroskaTextSubtitleExtractionExecutor(
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: TextSubtitleExtractionInspector(asset: fixture.asset)
        )
        let preview = try await executor.preview(source: fixture.asset, trackUID: 12)

        await XCTAssertThrowsTextSubtitleExtractionError(
            try await executor.execute(
                preview: preview,
                destinationURL: fixture.root.appendingPathComponent("Subtitle.ass")
            ),
            expected: .unsupportedDestination
        )

        for failingRunner in [
            TextSubtitleExtractionRunner(outputs: [subtitleData], exitCode: 3),
            TextSubtitleExtractionRunner(outputs: [subtitleData], truncated: true),
        ] {
            let failingExecutor = MatroskaTextSubtitleExtractionExecutor(
                mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
                runner: failingRunner,
                inspector: TextSubtitleExtractionInspector(asset: fixture.asset)
            )
            do {
                _ = try await failingExecutor.preview(source: fixture.asset, trackUID: 12)
                XCTFail("Expected extraction to fail")
            } catch let error as MatroskaTextSubtitleExtractionError {
                guard case .toolFailed = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationURL.path))
    }

    private func makeFixture(
        format: ExternalTextSubtitleFormat = .subRip
    ) throws -> (
        root: URL, sourceURL: URL, destinationURL: URL, asset: MediaAsset
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-text-extraction-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        try Data("bounded fake Matroska bytes".utf8).write(to: sourceURL)
        let trackFacts: (codec: String, codecID: String) =
            switch format {
            case .subRip: ("subrip", "S_TEXT/UTF8")
            case .ass: ("ass", "S_TEXT/ASS")
            case .ssa: ("ssa", "S_TEXT/SSA")
            }
        let asset = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska,webm",
            duration: MediaTime(seconds: 3),
            fileSize: 28,
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "h264", codecID: "V_MPEG4/ISO/AVC", uid: 10),
                MediaTrack(
                    id: 2,
                    kind: .subtitle,
                    codec: trackFacts.codec,
                    codecID: trackFacts.codecID,
                    uid: 12,
                    language: "eng"
                ),
            ]
        )
        return (
            root,
            sourceURL,
            root.appendingPathComponent("Movie.\(format.filenameExtension)"),
            asset
        )
    }

    private func srtData(_ text: String) -> Data {
        Data("1\n00:00:01,000 --> 00:00:02,000\n\(text)\n".utf8)
    }

    private func advancedSubtitleData(format: ExternalTextSubtitleFormat) -> Data {
        let header =
            format == .ass
            ? "[Script Info]\nScriptType: v4.00+\n"
                + "[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
                + "[Events]\nFormat: Layer, Start, End, Style, Text\n"
                + "Dialogue: 0,0:00:01.00,0:00:02.00,Default,{\\an8}Exact ASS\n"
            : "[Script Info]\nScriptType: v4.00\n"
                + "[V4 Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
                + "[Events]\n"
                + "Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
                + "Dialogue: Marked=0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Exact SSA\n"
        return Data(header.utf8)
    }
}

private func XCTAssertThrowsTextSubtitleExtractionError<T>(
    _ expression: @autoclosure () async throws -> T,
    expected: MatroskaTextSubtitleExtractionError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        XCTAssertEqual(
            error as? MatroskaTextSubtitleExtractionError,
            expected,
            file: file,
            line: line
        )
    }
}
