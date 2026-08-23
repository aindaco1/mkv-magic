import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private struct CreatingRemuxRunner: CommandRunning {
    func run(_ request: CommandRequest) async throws -> CommandResult {
        guard request.arguments.first == "--output", request.arguments.count > 1 else {
            throw CocoaError(.fileWriteUnknown)
        }
        try Data("remuxed".utf8).write(
            to: URL(fileURLWithPath: request.arguments[1]),
            options: .withoutOverwriting
        )
        return CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
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

        do {
            _ = try await executor.execute(
                source: source,
                removal: TrackRemoval(trackUIDs: [20]),
                destinationURL: destinationURL
            )
            XCTFail("Expected retained-track verification failure")
        } catch {
            XCTAssertEqual(error as? OutputVerificationError, .tracksChanged)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }
}
