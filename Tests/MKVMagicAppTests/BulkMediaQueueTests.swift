import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

@testable import MKVMagic

final class BulkMediaQueueTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bulk-media-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    @MainActor private func model() -> AppModel {
        let queue = root.appendingPathComponent("job-queue.json")
        let history = root.appendingPathComponent("job-history.json")
        return AppModel(
            historyRecorderFactory: { try JSONJobHistoryStore(fileURL: history) },
            queueStoreFactory: { try JSONJobQueueStore(fileURL: queue) },
            queueEnvironmentReader: BulkQueueEnvironment())
    }

    @MainActor
    func testAllNewBatchOperationsSurviveColdReloadAndVerifyIndependentOutputs() async throws {
        let initial = model()
        let urls = try await [source("One", seconds: 10), source("Two", seconds: 12)]
        let originals = try urls.map { try Data(contentsOf: $0) }
        await initial.addFiles(urls)
        let assets = initial.assets
        let change = BulkTrackMetadataChange(
            kind: .audio, language: "fr", flags: [.commentary: true])
        let operations: [BatchMediaEditOperation] = [
            .metadata(change), .subtitles,
            .trim(
                BatchTrimAmounts(
                    beginning: MediaTime(nanoseconds: 3_000_000_000),
                    end: MediaTime(nanoseconds: 3_000_000_000))),
        ]
        var all = [(id: UUID, edit: ReviewedBatchEdit)]()
        for operation in operations {
            let prepared = try await BatchMediaEditPreparation.prepare(
                assets: assets, operation: operation, model: initial)
            XCTAssertTrue(
                prepared.presentations.allSatisfy { $0.status == .ready },
                prepared.presentations.map(\.detail).joined(separator: "\n"))
            all += prepared.items
        }
        XCTAssertEqual(all.count, 8)
        _ = try await initial.setQueuePaused(true)
        for item in all {
            _ = try await initial.enqueueReviewedEdit(
                item.edit, destinationURL: root.appendingPathComponent(item.edit.outputFilename))
        }
        let restored = model()
        let paused = try await restored.runAutomaticQueueCycle()
        XCTAssertEqual(paused.jobs.map(\.state), Array(repeating: .waiting, count: 8))
        _ = try await restored.setQueuePaused(false)
        let finished = try await restored.runAutomaticQueueCycle()
        XCTAssertEqual(
            finished.jobs.map(\.state), Array(repeating: .succeeded, count: 8),
            String(describing: finished.jobs))
        XCTAssertEqual(finished.jobs.map(\.attemptCount), Array(repeating: 1, count: 8))
        for item in all {
            let outputURL = root.appendingPathComponent(item.edit.outputFilename)
            switch item.edit {
            case .trackMetadata(let preview):
                let (output, _) = try await restored.inspectBatchSource(outputURL)
                try TrackMetadataOutputVerifier().verify(
                    original: preview.source, output: output, expectedEdits: preview.edits)
                XCTAssertEqual(
                    output.tracks.filter { $0.kind == .audio }.map(\.language), ["fr", "fr"])
                XCTAssertEqual(
                    output.tracks.filter { $0.kind == .audio }.map(\.title), ["Main", "Alternate"])
            case .subtitleExtraction(let preview):
                XCTAssertEqual(
                    Data(SHA256.hash(data: try Data(contentsOf: outputURL))), preview.outputSHA256)
            case .fastTrim(let preview):
                let (output, _) = try await restored.inspectBatchSource(outputURL)
                XCTAssertEqual(output.tracks.map(\.uid), preview.source.tracks.map(\.uid))
                XCTAssertEqual(
                    output.duration!.seconds, preview.plan.adjusted.duration.seconds, accuracy: 0.15
                )
                let chapters = try await restored.previewChapters(in: output)
                XCTAssertEqual(chapters.original.chapterCount, preview.trimmedChapters.chapterCount)
                XCTAssertEqual(
                    chapters.original.editions.flatMap(\.chapters).map(\.start),
                    preview.trimmedChapters.editions.flatMap(\.chapters).map(\.start))
            default: XCTFail("Unexpected operation")
            }
        }
        for (url, original) in zip(urls, originals) {
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
        let history = try await restored.loadHistory()
        XCTAssertEqual(history.count, 8)
        XCTAssertTrue(history.allSatisfy { $0.events.last?.state == .succeeded })
    }

    @MainActor
    func testChangedSourceInvalidatesNewReviewsAndCannotReuseOldTrackOrTrimIdentity() async throws {
        let initial = model()
        let url = try await source("Changed", seconds: 10)
        await initial.addFiles([url])
        let assets = initial.assets
        let operations: [BatchMediaEditOperation] = [
            .metadata(.init(kind: .audio, language: "fr")), .subtitles,
            .trim(.init(beginning: MediaTime(nanoseconds: 2_000_000_000), end: .zero)),
        ]
        for operation in operations {
            let prepared = try await BatchMediaEditPreparation.prepare(
                assets: assets, operation: operation, model: initial)
            for item in prepared.items {
                _ = try await initial.enqueueReviewedEdit(
                    item.edit, destinationURL: root.appendingPathComponent(item.edit.outputFilename)
                )
            }
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: url.path)
        let restored = model()
        let result = try await restored.runAutomaticQueueCycle()
        XCTAssertEqual(result.jobs.count, 4)
        XCTAssertTrue(result.jobs.allSatisfy { $0.state == .needsReview })
        for job in result.jobs {
            do {
                _ = try await restored.reviewedEditForRetry(job)
                XCTFail("Accepted stale file-specific review")
            } catch {}
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(job.outputDisplayName).path))
        }
    }

    @MainActor
    func testMixedAndNoOpFilesAreExplainedAndCancellationNeverQueuesWork() async throws {
        let initial = model()
        let url = try await source("No-op", seconds: 10)
        await initial.addFiles([url])
        let other = MediaAsset(
            sourceURL: root.appendingPathComponent("Other.mp4"), container: "mov")
        let noOp = try await BatchMediaEditPreparation.prepare(
            assets: initial.assets + [other],
            operation: .metadata(.init(kind: .video, language: "und")), model: initial)
        XCTAssertTrue(noOp.items.isEmpty)
        XCTAssertEqual(noOp.presentations.map(\.status), [.noChanges, .blocked])
        let tooShort = try await BatchMediaEditPreparation.prepare(
            assets: initial.assets,
            operation: .trim(.init(beginning: MediaTime(nanoseconds: 20_000_000_000), end: .zero)),
            model: initial)
        XCTAssertTrue(tooShort.items.isEmpty)
        XCTAssertEqual(tooShort.presentations.first?.status, .blocked)
        let task = Task {
            try await BatchMediaEditPreparation.prepare(
                assets: initial.assets, operation: .subtitles, model: initial)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Ignored cancellation")
        } catch is CancellationError {} catch { XCTFail("\(error)") }
        let queue = try await initial.loadQueue()
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    @MainActor private func source(_ name: String, seconds: Int) async throws -> URL {
        guard let runtime = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT for bundled media tools")
        }
        let catalog = try ToolCatalog(rootURL: URL(fileURLWithPath: runtime))
        let raw = root.appendingPathComponent("\(name).yuv")
        let audio = root.appendingPathComponent("\(name).pcm")
        let srt = root.appendingPathComponent("\(name).en.srt")
        let ass = root.appendingPathComponent("\(name).es.ass")
        try Data(repeating: 32, count: 64 * 48 * 3 / 2 * seconds * 10).write(to: raw)
        try Data(repeating: 0, count: 96_000 * seconds).write(to: audio)
        try Data("1\n00:00:00,000 --> 00:00:01,000\nKeep this dialogue\n".utf8).write(to: srt)
        try Data(
            ("[Script Info]\nScriptType: v4.00+\n[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
                + "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
                + "Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,{\\an8}Keep styled dialogue\n")
                .utf8
        ).write(to: ass)
        let output = root.appendingPathComponent("\(name).mkv")
        let result = try await FoundationCommandRunner().run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-nostdin", "-loglevel", "error", "-f", "rawvideo",
                    "-pixel_format", "yuv420p", "-video_size", "64x48", "-framerate", "10", "-i",
                    raw.path,
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", audio.path, "-i", srt.path,
                    "-i", ass.path,
                    "-map", "0:v", "-map", "1:a", "-map", "1:a", "-map", "2:s", "-map", "3:s",
                    "-c:v", "mpeg4", "-g", "20", "-bf", "0", "-q:v", "5", "-c:a", "aac", "-c:s",
                    "copy",
                    "-metadata:s:a:0", "language=eng", "-metadata:s:a:0", "title=Main",
                    "-metadata:s:a:1", "language=spa", "-metadata:s:a:1", "title=Alternate",
                    output.path,
                ], timeout: 120))
        XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        let chapters = MatroskaChapterDocument(editions: [
            .init(chapters: [
                .init(start: .zero, displays: [.init(title: "Opening")]),
                .init(
                    start: MediaTime(nanoseconds: 4_000_000_000), displays: [.init(title: "Middle")]
                ),
                .init(
                    start: MediaTime(nanoseconds: 8_000_000_000), displays: [.init(title: "Ending")]
                ),
            ])
        ])
        let xml = root.appendingPathComponent("\(name).xml")
        try MatroskaChapterXMLCodec().serialize(chapters).write(to: xml)
        let applied = try await FoundationCommandRunner().run(
            CommandRequest(
                executableURL: try catalog.url(for: .mkvpropedit),
                arguments: ["--abort-on-warnings", output.path, "--chapters", xml.path], timeout: 60
            ))
        XCTAssertEqual(applied.exitCode, 0, applied.standardError.text)
        return output
    }
}

private struct BulkQueueEnvironment: MediaQueueSchedulingEnvironmentReading {
    func read() -> MediaQueueSchedulingEnvironment {
        .init(isOnBattery: false, thermalPressure: .nominal)
    }
}
