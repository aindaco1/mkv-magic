import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

@testable import MKVMagic

final class AppHistoryConcurrencyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-concurrent-history-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    @MainActor
    func testConcurrentExecutionsAndHistoryReadsShareOneRecorder() async throws {
        let factory = HistoryRecorderFactoryProbe(
            fileURL: root.appendingPathComponent("job-history.json"))
        let model = AppModel(historyRecorderFactory: { try factory.makeStore() })
        let source = root.appendingPathComponent("Movie.en.srt")
        let original = Data("1\n00:00:00,000 --> 00:00:01,000\n  Dialogue  \n".utf8)
        try original.write(to: source)
        let preview = try await model.previewSubtitleCleanup(at: source)
        let destinations = (0..<4).map { root.appendingPathComponent("Clean \($0).srt") }

        _ = try await model.loadHistory()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for destination in destinations {
                group.addTask {
                    _ = try await model.cleanSubtitle(
                        preview: preview, restoringCueIDs: [], destinationURL: destination
                    )
                    _ = try await model.loadHistory()
                }
            }
            try await group.waitForAll()
        }

        XCTAssertEqual(
            factory.creationCount, 1, "Readers and jobs must share the same serial writer")
        let records = try await model.loadHistory()
        assertSuccessfulHistory(records, outputNames: destinations.map(\.lastPathComponent))
        XCTAssertEqual(try Data(contentsOf: source), original)
        for destination in destinations {
            XCTAssertEqual(
                String(decoding: try Data(contentsOf: destination), as: UTF8.self),
                "1\n00:00:00,000 --> 00:00:01,000\nDialogue\n"
            )
        }
    }

    @MainActor
    func testConcurrentCleanMKVQueuePreservesEveryHistoryRecordAndOriginal() async throws {
        try await assertCleanMKVQueue(environment: HistoryTestQueueEnvironment())
    }

    @MainActor
    func testAutomaticQueueDrainsSuccessiveSingleSlotsOnBattery() async throws {
        try await assertCleanMKVQueue(
            environment: HistoryTestQueueEnvironment(isOnBattery: true))
    }

    @MainActor
    func testAutomaticQueueRechecksThermalPressureBeforeRefilling() async throws {
        let environment = WarmingQueueEnvironment()
        try await assertCleanMKVQueue(environment: environment, completedCount: 3)
        XCTAssertEqual(environment.readCount, 2)
    }

    @MainActor
    private func assertCleanMKVQueue(
        environment: any MediaQueueSchedulingEnvironmentReading,
        completedCount: Int = 4
    ) async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        let rawAudio = root.appendingPathComponent("silence.pcm")
        let base = root.appendingPathComponent("base.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)
        let result = try await FoundationCommandRunner().run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-nostdin", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-c:a", "aac", "-metadata", "title=Remove Me",
                    "-metadata", "comment=Remove this tag", base.path,
                ], timeout: 60
            )
        )
        XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        let originalDigest = SHA256.hash(data: try Data(contentsOf: base))
        let sources = (0..<4).map { root.appendingPathComponent("Movie \($0).mkv") }
        for source in sources { try FileManager.default.copyItem(at: base, to: source) }
        let destinations = (0..<4).map { root.appendingPathComponent("Clean \($0).mkv") }
        let factory = HistoryRecorderFactoryProbe(
            fileURL: root.appendingPathComponent("job-history.json"))
        let queue = try JSONJobQueueStore(fileURL: root.appendingPathComponent("job-queue.json"))
        let model = AppModel(
            historyRecorderFactory: { try factory.makeStore() },
            queueStoreFactory: { queue },
            queueEnvironmentReader: environment
        )
        try await queue.save(MediaQueueSnapshot(isPaused: true, updatedAt: Date()))
        await model.addFiles(sources)
        let workflow = SavedWorkflowPresetCatalog.cleanMKV
        for (source, destination) in zip(sources, destinations) {
            let asset = try XCTUnwrap(model.assets.first { $0.sourceURL == source })
            XCTAssertFalse(asset.tracks.contains { $0.kind == .subtitle })
            let compiled = try SavedWorkflowCompiler().compile(workflow, for: asset)
            XCTAssertNil(compiled.trackRemoval)
            XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
            XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 0)
            _ = try await model.enqueueSavedWorkflow(
                compiled, recipe: workflow, in: asset, destinationURL: destination
            )
        }
        _ = try await queue.setPaused(false, at: Date())
        // One start must drain the queue, including jobs beyond the scheduler's
        // three lightweight slots; no extra UI action should be required.
        _ = try await model.runAutomaticQueueCycle()

        let snapshot = try await queue.load()
        XCTAssertEqual(snapshot.jobs.count, sources.count)
        XCTAssertEqual(
            snapshot.jobs.map(\.state),
            sources.indices.map { $0 < completedCount ? .succeeded : .waiting })
        XCTAssertEqual(
            snapshot.jobs.map(\.attemptCount),
            sources.indices.map { $0 < completedCount ? 1 : 0 })
        XCTAssertEqual(factory.creationCount, 1)
        let records = try await model.loadHistory()
        assertSuccessfulHistory(
            records, outputNames: destinations.prefix(completedCount).map(\.lastPathComponent))
        for (source, destination) in zip(sources, destinations) {
            XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), originalDigest)
            guard destinations.prefix(completedCount).contains(destination) else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
                continue
            }
            let output = try XCTUnwrap(model.assets.first { $0.sourceURL == destination })
            XCTAssertNil(output.metadata["title"])
            XCTAssertEqual(output.globalTagCount, 0)
            XCTAssertEqual(output.trackTagCount, 0)
            XCTAssertEqual(output.tracks.map(\.kind), [.audio])
        }
    }

    private func assertSuccessfulHistory(
        _ records: [MediaJobRecord], outputNames: [String],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(records.count, outputNames.count, file: file, line: line)
        XCTAssertEqual(
            Set(records.map(\.outputDisplayName)), Set(outputNames), file: file, line: line)
        for record in records {
            XCTAssertEqual(
                record.events.map(\.state),
                [
                    .queued, .inspecting, .planned, .ready, .running, .verifying, .committing,
                    .succeeded,
                ],
                file: file, line: line
            )
        }
    }
}

// Match the production factory: a new actor each time, targeting the same file.
// Most older tests injected a singleton actor, masking per-job writer races.
private final class HistoryRecorderFactoryProbe: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var count = 0

    init(fileURL: URL) { self.fileURL = fileURL }

    var creationCount: Int { lock.withLock { count } }

    func makeStore() throws -> JSONJobHistoryStore {
        lock.withLock { count += 1 }
        return try JSONJobHistoryStore(fileURL: fileURL)
    }
}

private struct HistoryTestQueueEnvironment: MediaQueueSchedulingEnvironmentReading {
    var isOnBattery = false

    func read() -> MediaQueueSchedulingEnvironment {
        .init(isOnBattery: isOnBattery, thermalPressure: .nominal)
    }
}

private final class WarmingQueueEnvironment: MediaQueueSchedulingEnvironmentReading,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var count = 0

    var readCount: Int { lock.withLock { count } }

    func read() -> MediaQueueSchedulingEnvironment {
        lock.withLock {
            count += 1
            return .init(isOnBattery: false, thermalPressure: count == 1 ? .nominal : .serious)
        }
    }
}
