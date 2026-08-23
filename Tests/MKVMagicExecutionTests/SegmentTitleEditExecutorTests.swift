import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

private struct SuccessfulPropertyEditRunner: CommandRunning {
    func run(_ request: CommandRequest) async throws -> CommandResult {
        CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}

private struct ChangedTrackInspector: MediaInspecting {
    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: 8,
            tracks: [MediaTrack(id: 0, kind: .audio, codec: "opus")],
            metadata: ["title": "New"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "0011"
        )
    }
}

private struct MatchingInspector: MediaInspecting {
    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: 8,
            tracks: [MediaTrack(id: 0, kind: .audio, codec: "aac")],
            metadata: ["title": "New"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "0011"
        )
    }
}

private enum StageObserverError: Error, Equatable {
    case stopBeforeCommit
}

final class SegmentTitleEditExecutorTests: XCTestCase {
    func testSharedPolicyRejectsNonMatroskaAsset() {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/tmp/Movie.mp4"),
            container: "QuickTime / MOV",
            tracks: []
        )

        XCTAssertFalse(MatroskaEditingPolicy.supports(asset))
    }

    func testSharedPolicyAcceptsMatroskaContainerWithUnknownExtension() {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/tmp/Movie.media"),
            container: "Matroska / WebM",
            tracks: []
        )

        XCTAssertTrue(MatroskaEditingPolicy.supports(asset))
    }

    func testVerificationFailureRemovesWorkingCopyAndPreservesOriginal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-executor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Source.mkv")
        let destinationURL = root.appendingPathComponent("Output.mkv")
        let originalData = Data("original".utf8)
        try originalData.write(to: sourceURL)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(originalData.count),
            tracks: [MediaTrack(id: 0, kind: .audio, codec: "aac")],
            metadata: ["title": "Old"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "0011"
        )
        let executor = SegmentTitleEditExecutor(
            mkvpropeditURL: URL(fileURLWithPath: "/usr/bin/true"),
            runner: SuccessfulPropertyEditRunner(),
            inspector: ChangedTrackInspector()
        )

        do {
            _ = try await executor.execute(
                source: source,
                title: "New",
                destinationURL: destinationURL
            )
            XCTFail("Expected verification failure")
        } catch {
            XCTAssertEqual(error as? OutputVerificationError, .tracksChanged)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testProgressPersistenceFailureBeforeCommitLeavesNoOutput() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Source.mkv")
        let destinationURL = root.appendingPathComponent("Output.mkv")
        let originalData = Data("original".utf8)
        try originalData.write(to: sourceURL)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(originalData.count),
            tracks: [MediaTrack(id: 0, kind: .audio, codec: "aac")],
            metadata: ["title": "Old"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "0011"
        )
        let executor = SegmentTitleEditExecutor(
            mkvpropeditURL: URL(fileURLWithPath: "/usr/bin/true"),
            runner: SuccessfulPropertyEditRunner(),
            inspector: MatchingInspector()
        )

        do {
            _ = try await executor.execute(
                source: source,
                title: "New",
                destinationURL: destinationURL,
                onStage: { stage in
                    if stage == .committing { throw StageObserverError.stopBeforeCommit }
                }
            )
            XCTFail("Expected progress observer refusal")
        } catch {
            XCTAssertEqual(error as? StageObserverError, .stopBeforeCommit)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }
}
