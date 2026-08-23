import CryptoKit
import Foundation
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

private actor SegmentTitleStageRecorder {
    private var stages = [SegmentTitleExecutionStage]()

    func append(_ stage: SegmentTitleExecutionStage) {
        stages.append(stage)
    }

    func snapshot() -> [SegmentTitleExecutionStage] {
        stages
    }
}

final class RealToolSegmentTitleEditTests: XCTestCase {
    func testRealToolsEditVerifiedCloneAndPreserveOriginalByteForByte() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-real-edit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let rawAudio = fixtureRoot.appendingPathComponent("silence.pcm")
        let source = fixtureRoot.appendingPathComponent("source.mkv")
        let output = fixtureRoot.appendingPathComponent("source — Edited.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)

        let createResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-c:a", "aac",
                    "-metadata", "title=Original Title",
                    source.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(createResult.exitCode, 0, createResult.standardError.text)
        let sourceDigest = SHA256.hash(data: try Data(contentsOf: source))

        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        let originalAsset = try await inspector.inspect(source)
        let executor = SegmentTitleEditExecutor(
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        )
        let stageRecorder = SegmentTitleStageRecorder()

        let outputAsset = try await executor.execute(
            source: originalAsset,
            title: "Verified Title",
            destinationURL: output,
            onStage: { stage in await stageRecorder.append(stage) }
        )

        XCTAssertEqual(outputAsset.metadata["title"], "Verified Title")
        let observedStages = await stageRecorder.snapshot()
        XCTAssertEqual(observedStages, [.verifying, .committing])
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)
        let sourceAfterEdit = try await inspector.inspect(source)
        XCTAssertEqual(sourceAfterEdit.metadata["title"], "Original Title")
    }
}
