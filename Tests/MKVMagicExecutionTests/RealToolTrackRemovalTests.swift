import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

private actor TrackRemovalStageRecorder {
    private var stages = [TrackRemovalExecutionStage]()

    func append(_ stage: TrackRemovalExecutionStage) {
        stages.append(stage)
    }

    func snapshot() -> [TrackRemovalExecutionStage] {
        stages
    }
}

final class RealToolTrackRemovalTests: XCTestCase {
    func testRealToolsRemoveOneTrackWithoutEncodingAndPreserveOriginal() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "mkv-magic-real-track-removal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let firstAudio = fixtureRoot.appendingPathComponent("first.pcm")
        let secondAudio = fixtureRoot.appendingPathComponent("second.pcm")
        let base = fixtureRoot.appendingPathComponent("base.mkv")
        let font = fixtureRoot.appendingPathComponent("Fixture.ttf")
        let chapters = fixtureRoot.appendingPathComponent("chapters.ffmetadata")
        let source = fixtureRoot.appendingPathComponent("source.mkv")
        let output = fixtureRoot.appendingPathComponent("source — Track Removed.mkv")
        try Data(repeating: 0, count: 96_000).write(to: firstAudio)
        try Data(repeating: 1, count: 96_000).write(to: secondAudio)
        try Data("fixture font payload".utf8).write(to: font)
        try Data(
            ";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=500\ntitle=Opening\n"
                .utf8
        ).write(to: chapters)

        let createResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", firstAudio.path,
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", secondAudio.path,
                    "-f", "ffmetadata", "-i", chapters.path,
                    "-map", "0:a", "-map", "1:a", "-c:a", "aac",
                    "-map_chapters", "2",
                    "-metadata:s:a:0", "language=eng",
                    "-metadata:s:a:0", "title=Main Audio",
                    "-metadata:s:a:1", "language=spa",
                    "-metadata:s:a:1", "title=Spanish Audio",
                    "-metadata", "title=Fixture Movie",
                    base.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(createResult.exitCode, 0, createResult.standardError.text)
        let attachResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .mkvmerge),
                arguments: [
                    "--output", source.path,
                    "--attachment-mime-type", "font/ttf",
                    "--attachment-name", "Fixture.ttf",
                    "--attach-file", font.path,
                    base.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(attachResult.exitCode, 0, attachResult.standardError.text)
        let sourceDigest = SHA256.hash(data: try Data(contentsOf: source))

        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        let originalAsset = try await inspector.inspect(source)
        XCTAssertEqual(originalAsset.tracks.count, 2)
        XCTAssertEqual(originalAsset.attachments.count, 1)
        XCTAssertEqual(originalAsset.chapterEntryCount, 1)
        XCTAssertEqual(originalAsset.metadata["title"], "Fixture Movie")
        let retainedUID = try XCTUnwrap(originalAsset.tracks[0].uid)
        let removedUID = try XCTUnwrap(originalAsset.tracks[1].uid)
        let executor = TrackRemovalExecutor(
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner,
            inspector: inspector
        )
        let stageRecorder = TrackRemovalStageRecorder()

        let outputAsset = try await executor.execute(
            source: originalAsset,
            removal: TrackRemoval(trackUIDs: [removedUID]),
            destinationURL: output,
            onStage: { stage in await stageRecorder.append(stage) }
        )

        XCTAssertEqual(outputAsset.tracks.count, 1)
        XCTAssertEqual(outputAsset.tracks.first?.uid, retainedUID)
        XCTAssertEqual(outputAsset.tracks.first?.title, "Main Audio")
        XCTAssertEqual(outputAsset.attachments, originalAsset.attachments)
        XCTAssertEqual(outputAsset.chapterEntryCount, 1)
        XCTAssertEqual(outputAsset.chapters.first?.title, "Opening")
        XCTAssertEqual(outputAsset.metadata["title"], "Fixture Movie")
        let observedStages = await stageRecorder.snapshot()
        XCTAssertEqual(observedStages, [.verifying, .committing])
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)
        let sourceAfterRemoval = try await inspector.inspect(source)
        XCTAssertEqual(sourceAfterRemoval, originalAsset)
    }
}
