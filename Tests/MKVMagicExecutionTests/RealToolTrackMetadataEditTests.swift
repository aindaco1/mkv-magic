import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

private actor TrackMetadataStageRecorder {
    private var stages = [MatroskaMetadataExecutionStage]()

    func append(_ stage: MatroskaMetadataExecutionStage) {
        stages.append(stage)
    }

    func snapshot() -> [MatroskaMetadataExecutionStage] {
        stages
    }
}

final class RealToolTrackMetadataEditTests: XCTestCase {
    func testRealToolsEditTrackMetadataOnVerifiedCloneAndPreserveOriginal() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "mkv-magic-real-track-edit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let rawAudio = fixtureRoot.appendingPathComponent("silence.pcm")
        let source = fixtureRoot.appendingPathComponent("source.mkv")
        let output = fixtureRoot.appendingPathComponent("source — Track Edited.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)

        let createResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-c:a", "aac",
                    "-metadata:s:a:0", "language=eng",
                    "-metadata:s:a:0", "title=Main Audio",
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
        let originalTrack = try XCTUnwrap(originalAsset.tracks.first)
        let trackUID = try XCTUnwrap(originalTrack.uid)
        let edit = TrackMetadataEdit(
            trackUID: trackUID,
            name: "Spanish Commentary",
            language: "es",
            isDefault: originalTrack.isDefault,
            isForced: true,
            isEnabled: originalTrack.isEnabled,
            isCommentary: true,
            isHearingImpaired: originalTrack.isHearingImpaired,
            isVisualImpaired: originalTrack.isVisualImpaired,
            isOriginal: originalTrack.isOriginal,
            isTextDescription: originalTrack.isTextDescription
        )
        let executor = MatroskaMetadataEditExecutor(
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        )
        let stageRecorder = TrackMetadataStageRecorder()

        let outputAsset = try await executor.execute(
            source: originalAsset,
            edit: .track(edit),
            destinationURL: output,
            onStage: { stage in await stageRecorder.append(stage) }
        )

        let outputTrack = try XCTUnwrap(outputAsset.tracks.first)
        XCTAssertEqual(outputTrack.uid, trackUID)
        XCTAssertEqual(outputTrack.title, "Spanish Commentary")
        XCTAssertEqual(outputTrack.language, "es")
        XCTAssertTrue(outputTrack.isForced)
        XCTAssertTrue(outputTrack.isCommentary)
        let observedStages = await stageRecorder.snapshot()
        XCTAssertEqual(observedStages, [.verifying, .committing])
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)
        let sourceAfterEdit = try await inspector.inspect(source)
        XCTAssertEqual(sourceAfterEdit.tracks.first, originalTrack)
    }
}
