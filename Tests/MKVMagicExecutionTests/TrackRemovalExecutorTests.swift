import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private struct CreatingRemuxRunner: CommandRunning {
    func run(_ request: CommandRequest) async throws -> CommandResult {
        let arguments = Array(request.arguments.dropFirst())
        guard request.arguments.first == "--gui-mode",
            arguments.first == "--output", arguments.count > 1
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        await request.progressReporting?.handler(
            CommandProgressUpdate(completedUnitCount: 33, totalUnitCount: 100)
        )
        await request.progressReporting?.handler(
            CommandProgressUpdate(completedUnitCount: 100, totalUnitCount: 100)
        )
        try Data("remuxed".utf8).write(
            to: URL(fileURLWithPath: arguments[1]),
            options: .withoutOverwriting
        )
        return CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}

private actor RemovalProgressRecorder {
    private var updates = [VerifiedOutputToolProgress]()

    func append(_ update: VerifiedOutputToolProgress) { updates.append(update) }
    func snapshot() -> [VerifiedOutputToolProgress] { updates }
}

private struct MutatingRemovalInspector: MediaInspecting {
    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: "matroska",
            fileSize: 7,
            tracks: [MediaTrack(id: 0, kind: .video, codec: "hevc", uid: 10)],
            segmentUID: "new-segment"
        )
    }
}

final class TrackRemovalExecutorTests: XCTestCase {
    func testVerificationFailureDeletesRemuxAndPreservesOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-removal-fault-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.mkv")
        let destinationURL = root.appendingPathComponent("output.mkv")
        let sourceBytes = Data("original".utf8)
        try sourceBytes.write(to: sourceURL)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            fileSize: Int64(sourceBytes.count),
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10),
                MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 20),
            ],
            segmentUID: "source-segment"
        )
        let executor = TrackRemovalExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            runner: CreatingRemuxRunner(),
            inspector: MutatingRemovalInspector()
        )
        let progress = RemovalProgressRecorder()

        do {
            _ = try await executor.execute(
                source: source,
                removal: TrackRemoval(trackUIDs: [20]),
                destinationURL: destinationURL,
                onProgress: { await progress.append($0) }
            )
            XCTFail("Expected retained-track verification failure")
        } catch {
            XCTAssertEqual(error as? OutputVerificationError, .tracksChanged)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        let progressUpdates = await progress.snapshot()
        XCTAssertEqual(
            progressUpdates,
            [
                VerifiedOutputToolProgress(phase: .multiplexing, percentage: 33),
                VerifiedOutputToolProgress(phase: .multiplexing, percentage: 100),
            ]
        )
    }
}
