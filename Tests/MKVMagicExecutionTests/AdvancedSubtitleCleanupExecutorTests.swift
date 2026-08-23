import CryptoKit
import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicExecution

private enum InjectedAdvancedSubtitleFailure: Error {
    case historyWrite
}

final class AdvancedSubtitleCleanupExecutorTests: XCTestCase {
    func testWritesVerifiedStylePreservingUTF8CopyAndPreservesOriginalBytes() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.ass")
        let output = root.appendingPathComponent("Movie — Clean.ass")
        let sourceText =
            "[Script Info]\r\nTitle: Café\r\n"
            + "[V4+ Styles]\r\nFormat: Name, Fontname\r\nStyle: Default,Arial\r\n"
            + "[Events]\r\n"
            + "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\r\n"
            + "Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,  Café  \r\n"
            + "Dialogue: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,{\\i1}Downloaded from YTS.MX{\\i0}\r\n"
        let sourceData = try XCTUnwrap(sourceText.data(using: .windowsCP1252))
        try sourceData.write(to: source)
        let sourceDigest = SHA256.hash(data: sourceData)
        let executor = AdvancedSubtitleCleanupExecutor()
        let preview = try await executor.preview(sourceURL: source)

        XCTAssertEqual(preview.encoding, .windows1252)
        XCTAssertTrue(preview.normalizationNeeded)
        XCTAssertEqual(preview.cleanup.changes.count, 2)
        let result = try await executor.execute(
            preview: preview,
            restoringEventIDs: [],
            destinationURL: output
        )

        XCTAssertEqual(result.removedEventCount, 1)
        XCTAssertEqual(result.changedEventCount, 1)
        XCTAssertEqual(result.document.events.map(\.text), ["Café"])
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)
        let outputData = try Data(contentsOf: output)
        XCTAssertNotNil(String(data: outputData, encoding: .utf8))
        XCTAssertFalse(outputData.contains(0x0D))
        let serialized = try XCTUnwrap(String(data: outputData, encoding: .utf8))
        XCTAssertTrue(serialized.contains("Style: Default,Arial"))
        XCTAssertTrue(serialized.contains("Title: Café"))
        XCTAssertFalse(serialized.contains("YTS.MX"))
    }

    func testRestorationKeepsOriginalEventTextAndStyleFields() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.ssa")
        let output = root.appendingPathComponent("Movie — Clean.ssa")
        let sourceText = fixture(
            events: [
                "Dialogue: Marked=0,0:00:01.00,0:00:02.00,Signs,,0010,0020,0030,fx,  Keep me  ",
                "Dialogue: Marked=0,0:00:03.00,0:00:04.00,Default,,0,0,0,,Downloaded from YTS.MX",
            ],
            legacy: true
        )
        try Data(sourceText.utf8).write(to: source)
        let executor = AdvancedSubtitleCleanupExecutor()
        let preview = try await executor.preview(sourceURL: source)

        let result = try await executor.execute(
            preview: preview,
            restoringEventIDs: [0, 1],
            destinationURL: output
        )

        XCTAssertEqual(result.removedEventCount, 0)
        XCTAssertEqual(result.changedEventCount, 0)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), sourceText)
    }

    func testRejectsWrongDestinationAndRemovingEveryEventBeforeOutput() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Ads.ass")
        try Data(
            fixture(events: [
                "Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Downloaded from YTS.MX"
            ])
            .utf8
        ).write(to: source)
        let executor = AdvancedSubtitleCleanupExecutor()
        let preview = try await executor.preview(sourceURL: source)
        let wrongOutput = root.appendingPathComponent("Ads.srt")
        let emptyOutput = root.appendingPathComponent("Ads — Clean.ass")

        do {
            _ = try await executor.execute(
                preview: preview,
                restoringEventIDs: [],
                destinationURL: wrongOutput
            )
            XCTFail("Expected format refusal")
        } catch {
            XCTAssertEqual(
                error as? AdvancedSubtitleCleanupExecutionError,
                .unsupportedFormat
            )
        }
        do {
            _ = try await executor.execute(
                preview: preview,
                restoringEventIDs: [],
                destinationURL: emptyOutput
            )
            XCTFail("Expected empty subtitle refusal")
        } catch {
            XCTAssertEqual(
                error as? AdvancedSubtitleCleanupExecutionError,
                .noEventsRemaining
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: wrongOutput.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyOutput.path))
    }

    func testStalePreviewLeavesNoDestination() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.ass")
        let staleOutput = root.appendingPathComponent("Stale.ass")
        let initial = fixture(
            events: ["Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,  Text  "])
        try Data(initial.utf8).write(to: source)
        let executor = AdvancedSubtitleCleanupExecutor()
        let stalePreview = try await executor.preview(sourceURL: source)
        try Data(initial.replacingOccurrences(of: "Text", with: "Changed").utf8).write(to: source)

        do {
            _ = try await executor.execute(
                preview: stalePreview,
                restoringEventIDs: [],
                destinationURL: staleOutput
            )
            XCTFail("Expected stale preview refusal")
        } catch {
            guard case AdvancedSubtitleCleanupExecutionError.stalePreview = error else {
                return XCTFail("Expected stalePreview, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleOutput.path))
        XCTAssertEqual(
            try String(contentsOf: source, encoding: .utf8),
            initial.replacingOccurrences(of: "Text", with: "Changed"))
    }

    func testProgressFailureLeavesNoDestinationAndPreservesSource() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.ass")
        let progressOutput = root.appendingPathComponent("Progress.ass")
        let sourceText = fixture(
            events: ["Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,  Text  "])
        let sourceData = Data(sourceText.utf8)
        try sourceData.write(to: source)
        let executor = AdvancedSubtitleCleanupExecutor()
        let currentPreview = try await executor.preview(sourceURL: source)

        do {
            _ = try await executor.execute(
                preview: currentPreview,
                restoringEventIDs: [],
                destinationURL: progressOutput,
                onStage: { _ in throw InjectedAdvancedSubtitleFailure.historyWrite }
            )
            XCTFail("Expected injected progress failure")
        } catch {
            guard error is InjectedAdvancedSubtitleFailure else {
                return XCTFail("Expected injected history failure, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: progressOutput.path))
        XCTAssertEqual(try Data(contentsOf: source), sourceData)
    }

    func testRejectsSymlinkedAndOversizedInputs() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Target.ass")
        let link = root.appendingPathComponent("Link.ass")
        try Data(fixture(events: ["Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Text"]).utf8)
            .write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        do {
            _ = try await AdvancedSubtitleCleanupExecutor().preview(sourceURL: link)
            XCTFail("Expected symlink refusal")
        } catch {
            XCTAssertEqual(
                error as? AdvancedSubtitleCleanupExecutionError,
                .unsafeInput
            )
        }
        let oversized = root.appendingPathComponent("Large.ass")
        try Data(repeating: 0x20, count: AdvancedSubtitleCleanupExecutor.maximumInputBytes + 1)
            .write(to: oversized)
        do {
            _ = try await AdvancedSubtitleCleanupExecutor().preview(sourceURL: oversized)
            XCTFail("Expected size refusal")
        } catch {
            XCTAssertEqual(
                error as? AdvancedSubtitleCleanupExecutionError,
                .oversizedInput
            )
        }
    }

    func testFilenameLanguageSuffixControlsAdvancedEnglishOCR() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let english = root.appendingPathComponent("Movie.en.ass")
        let spanish = root.appendingPathComponent("Movie.es.ass")
        let data = Data(
            fixture(events: [
                "Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,y0u"
            ]).utf8
        )
        try data.write(to: english)
        try data.write(to: spanish)

        let englishPreview = try await AdvancedSubtitleCleanupExecutor().preview(
            sourceURL: english
        )
        let spanishPreview = try await AdvancedSubtitleCleanupExecutor().preview(
            sourceURL: spanish
        )

        XCTAssertTrue(englishPreview.appliesEnglishOCRRules)
        XCTAssertEqual(englishPreview.cleanup.changes.map(\.reasons), [[.ocrHighConfidence]])
        XCTAssertFalse(spanishPreview.appliesEnglishOCRRules)
        XCTAssertTrue(spanishPreview.cleanup.changes.isEmpty)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-ass-cleanup-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func fixture(events: [String], legacy: Bool = false) -> String {
        let format =
            legacy
            ? "Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
            : "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
        return
            "[Script Info]\nScriptType: \(legacy ? "v4.00" : "v4.00+")\n"
            + "[Events]\n\(format)\n"
            + events.joined(separator: "\n") + "\n"
    }
}
