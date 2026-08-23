import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor SavedWorkflowRecordingRunner: CommandRunning {
    private(set) var executableNames = [String]()

    func run(_ request: CommandRequest) async throws -> CommandResult {
        executableNames.append(request.executableURL.lastPathComponent)
        if request.executableURL.lastPathComponent == "mkvmerge" {
            guard request.arguments.first == "--output", request.arguments.count > 1 else {
                throw CocoaError(.fileWriteUnknown)
            }
            try Data("remuxed".utf8).write(
                to: URL(fileURLWithPath: request.arguments[1]),
                options: .withoutOverwriting
            )
        }
        return CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}

private struct CombinedWorkflowInspector: MediaInspecting {
    let retainedTrack: MediaTrack

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: 8,
            tracks: [retainedTrack],
            metadata: ["encoder": "mkvmerge"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "output-segment"
        )
    }
}

final class SavedWorkflowExecutorTests: XCTestCase {
    func testCleanupAndTitleRemovalShareOneVerifiedOutputPipeline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-saved-workflow-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.mkv")
        let destinationURL = root.appendingPathComponent("output.mkv")
        let sourceBytes = Data("original".utf8)
        try sourceBytes.write(to: sourceURL)
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)
        let audio = MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 20)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            tracks: [video, audio],
            metadata: ["title": "Movie", "encoder": "source"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )
        let runner = SavedWorkflowRecordingRunner()
        let executor = SavedWorkflowExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: CombinedWorkflowInspector(retainedTrack: video)
        )

        let output = try await executor.execute(
            source: source,
            trackRemoval: TrackRemoval(trackUIDs: [20]),
            removesSegmentTitle: true,
            destinationURL: destinationURL
        )
        let executableNames = await runner.executableNames

        XCTAssertEqual(executableNames, ["mkvmerge", "mkvpropedit"])
        XCTAssertEqual(output.metadata["title"], nil)
        XCTAssertEqual(output.tracks.map(\.uid), [10])
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }
}
