import CryptoKit
import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicExecution

private enum SubtitleStageStop: Error, Equatable {
    case beforeCommit
}

private actor SubtitleStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()

    func append(_ stage: VerifiedOutputExecutionStage) {
        stages.append(stage)
    }

    func snapshot() -> [VerifiedOutputExecutionStage] {
        stages
    }
}

final class SubtitleCleanupExecutorTests: XCTestCase {
    func testWritesVerifiedUTF8CopyAndPreservesOriginalBytes() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.en.srt")
        let output = root.appendingPathComponent("Movie.en — Clean.srt")
        let sourceData = Data(
            ("\u{FEFF}1\r\n00:00:00,000 --> 00:00:01,000\r\nDownloaded from\r\nYTS.MX\r\n\r\n"
                + "2\r\n00:00:01,000 --> 00:00:02,000\r\n  Dialogue  \r\n").utf8
        )
        try sourceData.write(to: source)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: source)
        let digest = SHA256.hash(data: sourceData)
        let recorder = SubtitleStageRecorder()

        let result = try await SubtitleCleanupExecutor().execute(
            preview: preview,
            restoringCueIDs: [],
            destinationURL: output,
            onStage: { stage in await recorder.append(stage) }
        )
        let observedStages = await recorder.snapshot()

        XCTAssertEqual(result.removedCueCount, 1)
        XCTAssertEqual(result.changedCueCount, 1)
        XCTAssertEqual(observedStages, [.verifying, .committing])
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), digest)
        XCTAssertEqual(
            String(decoding: try Data(contentsOf: output), as: UTF8.self),
            "1\n00:00:01,000 --> 00:00:02,000\nDialogue\n"
        )
    }

    func testRestorationKeepsOriginalCueAndRenumbersOutput() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.srt")
        let output = root.appendingPathComponent("Restored.srt")
        let sourceData = Data(
            ("4\n00:00:00,000 --> 00:00:01,000\nDownloaded from\nYTS.LT\n\n"
                + "8\n00:00:01,000 --> 00:00:02,000\nText\n").utf8
        )
        try sourceData.write(to: source)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: source)

        let result = try await SubtitleCleanupExecutor().execute(
            preview: preview,
            restoringCueIDs: [0],
            destinationURL: output
        )

        XCTAssertEqual(result.removedCueCount, 0)
        XCTAssertEqual(result.document.cues.map(\.id), [0, 1])
        let outputText = String(decoding: try Data(contentsOf: output), as: UTF8.self)
        XCTAssertTrue(outputText.hasPrefix("1\n00:00:00,000"))
        XCTAssertTrue(outputText.contains("\n\n2\n00:00:01,000"))
    }

    func testStalePreviewAndProgressFailureLeaveNoDestination() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.srt")
        let output = root.appendingPathComponent("Clean.srt")
        let original = Data("1\n00:00:00,000 --> 00:00:01,000\n Text \n".utf8)
        try original.write(to: source)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: source)
        try Data("1\n00:00:00,000 --> 00:00:01,000\nChanged\n".utf8).write(to: source)

        do {
            _ = try await SubtitleCleanupExecutor().execute(
                preview: preview,
                restoringCueIDs: [],
                destinationURL: output
            )
            XCTFail("Expected stale preview refusal")
        } catch {
            XCTAssertEqual(error as? SubtitleCleanupExecutionError, .stalePreview)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))

        try original.write(to: source)
        do {
            _ = try await SubtitleCleanupExecutor().execute(
                preview: preview,
                restoringCueIDs: [],
                destinationURL: output,
                onStage: { stage in
                    if stage == .committing { throw SubtitleStageStop.beforeCommit }
                }
            )
            XCTFail("Expected progress refusal")
        } catch {
            XCTAssertEqual(error as? SubtitleStageStop, .beforeCommit)
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testByteOnlySourceChangeMakesPreviewStale() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.srt")
        let output = root.appendingPathComponent("Clean.srt")
        let original = Data("1\n00:00:00,000 --> 00:00:01,000\nText\n".utf8)
        try original.write(to: source)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: source)
        let byteOnlyChange = Data(
            "1\r\n00:00:00,000 --> 00:00:01,000\r\nText\r\n".utf8
        )
        try byteOnlyChange.write(to: source)

        do {
            _ = try await SubtitleCleanupExecutor().execute(
                preview: preview,
                restoringCueIDs: [],
                destinationURL: output
            )
            XCTFail("Expected byte-exact stale preview refusal")
        } catch {
            XCTAssertEqual(error as? SubtitleCleanupExecutionError, .stalePreview)
        }
        XCTAssertEqual(try Data(contentsOf: source), byteOnlyChange)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testRefusesRemovingEveryCueAndUnsafeOrOversizedInputs() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Only Ad.srt")
        let output = root.appendingPathComponent("Clean.srt")
        try Data(
            "1\n00:00:00,000 --> 00:00:01,000\nDownloaded from\nYTS.BZ\n".utf8
        ).write(to: source)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: source)

        do {
            _ = try await SubtitleCleanupExecutor().execute(
                preview: preview,
                restoringCueIDs: [],
                destinationURL: output
            )
            XCTFail("Expected empty subtitle refusal")
        } catch {
            XCTAssertEqual(error as? SubtitleCleanupExecutionError, .noCuesRemaining)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))

        let symlink = root.appendingPathComponent("Linked.srt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        do {
            _ = try await SubtitleCleanupExecutor().preview(sourceURL: symlink)
            XCTFail("Expected symbolic-link refusal")
        } catch {
            XCTAssertEqual(error as? SubtitleCleanupExecutionError, .unsafeInput)
        }

        let oversized = root.appendingPathComponent("Oversized.srt")
        try Data(count: SubtitleCleanupExecutor.maximumInputBytes + 1).write(to: oversized)
        do {
            _ = try await SubtitleCleanupExecutor().preview(sourceURL: oversized)
            XCTFail("Expected oversized-input refusal")
        } catch {
            XCTAssertEqual(error as? SubtitleCleanupExecutionError, .oversizedInput)
        }
    }

    func testCanonicalUTF8PreviewNeedsNoNormalization() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Canonical.srt")
        try Data("1\n00:00:00,000 --> 00:00:01,000\nText\n".utf8).write(to: source)

        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: source)

        XCTAssertEqual(preview.encoding, .utf8)
        XCTAssertTrue(preview.diagnostics.isEmpty)
        XCTAssertTrue(preview.cleanup.changes.isEmpty)
        XCTAssertFalse(preview.normalizationNeeded)
    }

    func testFilenameLanguageSuffixControlsEnglishOCRWithoutAffectingParsing() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let english = root.appendingPathComponent("Movie.en.srt")
        let french = root.appendingPathComponent("Movie.fr.srt")
        let data = Data("1\n00:00:00,000 --> 00:00:01,000\ny0u\n".utf8)
        try data.write(to: english)
        try data.write(to: french)

        let englishPreview = try await SubtitleCleanupExecutor().preview(sourceURL: english)
        let frenchPreview = try await SubtitleCleanupExecutor().preview(sourceURL: french)

        XCTAssertTrue(englishPreview.appliesEnglishOCRRules)
        XCTAssertEqual(englishPreview.cleanup.changes.map(\.reasons), [[.ocrHighConfidence]])
        XCTAssertFalse(frenchPreview.appliesEnglishOCRRules)
        XCTAssertTrue(frenchPreview.cleanup.changes.isEmpty)
        XCTAssertEqual(frenchPreview.cleanup.original.cues[0].lines, ["y0u"])
    }

    func testRefusesNonSRTDestinationBeforeCreatingOutput() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.srt")
        let output = root.appendingPathComponent("Movie.txt")
        try Data("1\n00:00:00,000 --> 00:00:01,000\n Text \n".utf8).write(to: source)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: source)

        do {
            _ = try await SubtitleCleanupExecutor().execute(
                preview: preview,
                restoringCueIDs: [],
                destinationURL: output
            )
            XCTFail("Expected non-SRT destination refusal")
        } catch {
            XCTAssertEqual(error as? SubtitleCleanupExecutionError, .unsupportedFormat)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-subtitle-cleanup-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
