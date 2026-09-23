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
    func testReviewedRevisionIsCheckedBeforePreparationAndAgainBeforeCommit() async throws {
        for changeBeforeStart in [true, false] {
            try await PrivateTemporaryDirectory.withDirectory(prefix: "reviewed-metadata-guard") {
                root in
                let sourceURL = root.appendingPathComponent("Source.mkv")
                let destination = root.appendingPathComponent("Output.mkv")
                try Data("original".utf8).write(to: sourceURL)
                let revision = try MediaFileRevisionReader().read(sourceURL)
                let source = try await MatchingInspector().inspect(sourceURL)
                let executor = MatroskaMetadataEditExecutor(
                    mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
                    runner: SuccessfulPropertyEditRunner(), inspector: MatchingInspector())
                let externalChange = Data("externally changed".utf8)
                if changeBeforeStart { try externalChange.write(to: sourceURL) }
                do {
                    _ = try await executor.execute(
                        source: source, edit: .segmentTitle("New"),
                        destinationURL: destination, expectedSourceRevision: revision,
                        onStage: { stage in
                            if !changeBeforeStart, stage == .committing {
                                try externalChange.write(to: sourceURL)
                            }
                        })
                    XCTFail("Committed after the reviewed source changed")
                } catch {
                    XCTAssertEqual(error as? SavedWorkflowExecutionError, .sourceChangedSinceReview)
                }
                XCTAssertEqual(try Data(contentsOf: sourceURL), externalChange)
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
                XCTAssertEqual(
                    try FileManager.default.contentsOfDirectory(atPath: root.path), ["Source.mkv"])
            }
        }
    }

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
