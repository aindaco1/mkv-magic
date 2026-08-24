import Foundation
import MKVMagicCore
import MKVMagicMedia
import XCTest

@testable import MKVMagicExecution

private enum PipelineSourceGuardTestError: Error, Equatable, LocalizedError {
    case sourceChanged
    case committedAuditFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .sourceChanged:
            "The reviewed source changed."
        case .committedAuditFailed(let reason):
            "The committed audit failed: \(reason)"
        }
    }
}

private struct ReopenMutatingInspector: MediaInspecting {
    let sourceURL: URL
    let committedURL: URL

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        if inputURL.standardizedFileURL == committedURL.standardizedFileURL {
            try Data("changed during final reopen".utf8).write(to: sourceURL)
        }
        return MediaAsset(
            sourceURL: inputURL,
            container: "matroska",
            duration: MediaTime(seconds: 1),
            fileSize: Int64((try? Data(contentsOf: inputURL).count) ?? 0),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
    }
}

final class VerifiedOutputPipelineTests: XCTestCase {
    func testSourceChangeAfterProductionPreventsCommit() async throws {
        let root = try makeTemporaryDirectory(named: "before-commit")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Source.mkv")
        let destinationURL = root.appendingPathComponent("Output.mkv")
        try Data("reviewed source".utf8).write(to: sourceURL)
        let source = sourceAsset(at: sourceURL)
        let guardValue = try MediaFileRevisionGuard(
            sourceURL: sourceURL,
            expectedRevision: nil
        )

        do {
            _ = try await VerifiedOutputPipeline(
                inspector: ReopenMutatingInspector(
                    sourceURL: sourceURL,
                    committedURL: destinationURL
                )
            ).execute(
                source: source,
                destinationURL: destinationURL,
                preparation: .empty,
                produce: { temporaryURL in
                    try Data("candidate".utf8).write(to: temporaryURL)
                    try Data("changed during production".utf8).write(to: sourceURL)
                },
                verify: { _ in },
                validateSource: {
                    guard guardValue.isCurrent() else {
                        throw PipelineSourceGuardTestError.sourceChanged
                    }
                },
                committedAuditError: { _, reason in
                    PipelineSourceGuardTestError.committedAuditFailed(reason: reason)
                },
                onStage: { _ in }
            )
            XCTFail("Expected the changed source to prevent commit")
        } catch {
            XCTAssertEqual(error as? PipelineSourceGuardTestError, .sourceChanged)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testSourceChangeDuringCommittedReopenFailsTheFinalAudit() async throws {
        let root = try makeTemporaryDirectory(named: "final-reopen")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Source.mkv")
        let destinationURL = root.appendingPathComponent("Output.mkv")
        try Data("reviewed source".utf8).write(to: sourceURL)
        let source = sourceAsset(at: sourceURL)
        let guardValue = try MediaFileRevisionGuard(
            sourceURL: sourceURL,
            expectedRevision: nil
        )

        do {
            _ = try await VerifiedOutputPipeline(
                inspector: ReopenMutatingInspector(
                    sourceURL: sourceURL,
                    committedURL: destinationURL
                )
            ).execute(
                source: source,
                destinationURL: destinationURL,
                preparation: .empty,
                produce: { temporaryURL in
                    try Data("candidate".utf8).write(to: temporaryURL)
                },
                verify: { _ in },
                validateSource: {
                    guard guardValue.isCurrent() else {
                        throw PipelineSourceGuardTestError.sourceChanged
                    }
                },
                committedAuditError: { _, reason in
                    PipelineSourceGuardTestError.committedAuditFailed(reason: reason)
                },
                onStage: { _ in }
            )
            XCTFail("Expected the final reopen audit to observe the changed source")
        } catch let PipelineSourceGuardTestError.committedAuditFailed(reason) {
            XCTAssertTrue(reason.contains("reviewed source changed"), reason)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    private func makeTemporaryDirectory(named suffix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-output-pipeline-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func sourceAsset(at sourceURL: URL) -> MediaAsset {
        MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 1),
            fileSize: 15,
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
    }
}
