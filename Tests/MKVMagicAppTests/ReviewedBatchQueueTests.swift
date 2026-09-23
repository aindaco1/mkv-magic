import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

@testable import MKVMagic

final class ReviewedBatchQueueTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reviewed-batch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    @MainActor
    private func model() throws -> AppModel {
        let queueURL = root.appendingPathComponent("job-queue.json")
        let historyURL = root.appendingPathComponent("job-history.json")
        return AppModel(
            historyRecorderFactory: { try JSONJobHistoryStore(fileURL: historyURL) },
            queueStoreFactory: { try JSONJobQueueStore(fileURL: queueURL) },
            queueEnvironmentReader: ReviewedQueueEnvironment())
    }

    @MainActor
    private func subtitle(_ name: String, text: String = "HE11O") async throws -> ReviewedBatchEdit
    {
        let url = root.appendingPathComponent(name)
        let data: Data
        if url.pathExtension == "srt" {
            data = Data("1\n00:00:00,000 --> 00:00:00,500\n\(text)\n".utf8)
        } else {
            data = Data(
                ("[Script Info]\nScriptType: v4.00+\n"
                    + "[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
                    + "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
                    + "Dialogue: 0,0:00:00.00,0:00:00.50,Default,,0,0,0,,{\\an8}\(text)\n").utf8)
        }
        try data.write(to: url)
        let preview: ExternalSubtitleFilePreview =
            if url.pathExtension == "srt" {
                .subRip(try await SubtitleCleanupExecutor().preview(sourceURL: url))
            } else {
                .advanced(try await AdvancedSubtitleCleanupExecutor().preview(sourceURL: url))
            }
        return .subtitleCleanup(preview, restoringIDs: [])
    }

    @MainActor
    func testSubtitleJobsSurviveColdReloadPauseAndDrainWithExactReviewedBytes() async throws {
        let initial = try model()
        _ = try await initial.setQueuePaused(true)
        let edits = try await [
            subtitle("One.en.srt"), subtitle("Two.en.ass"), subtitle("Three.en.srt"),
            subtitle("Four.en.ass"),
        ]
        let originals = try edits.map { try Data(contentsOf: $0.sourceURL) }
        for edit in edits {
            _ = try await initial.enqueueReviewedEdit(
                edit, destinationURL: root.appendingPathComponent(edit.outputFilename))
        }
        let restored = try model()
        let paused = try await restored.runAutomaticQueueCycle()
        XCTAssertEqual(paused.jobs.map(\.state), Array(repeating: .waiting, count: 4))
        XCTAssertEqual(paused.jobs.map(\.attemptCount), [0, 0, 0, 0])
        _ = try await restored.setQueuePaused(false)
        let completed = try await restored.runAutomaticQueueCycle()
        XCTAssertEqual(completed.jobs.map(\.state), Array(repeating: .succeeded, count: 4))
        XCTAssertEqual(completed.jobs.map(\.attemptCount), [1, 1, 1, 1])
        for (index, edit) in edits.enumerated() {
            XCTAssertEqual(try Data(contentsOf: edit.sourceURL), originals[index])
            guard case .subtitleCleanup(_, _, let expected, _) = try edit.reviewedIntent() else {
                return XCTFail("Wrong intent")
            }
            let output = try Data(contentsOf: root.appendingPathComponent(edit.outputFilename))
            XCTAssertEqual(Data(SHA256.hash(data: output)), expected)
        }
        let history = try await restored.loadHistory()
        XCTAssertEqual(history.count, 4)
        XCTAssertTrue(history.allSatisfy { $0.events.last?.state == .succeeded })
        let report = String(
            decoding: try Data(contentsOf: root.appendingPathComponent("job-history.json")),
            as: UTF8.self)
        XCTAssertFalse(report.contains("HE11O"))
        XCTAssertFalse(report.contains(root.path))
        try WorkflowEvidence.record(
            "subtitle-cold-queue",
            facts: [
                "four_jobs_waited_without_attempts": paused.jobs.count == 4
                    && paused.jobs.allSatisfy { $0.state == .waiting && $0.attemptCount == 0 },
                "four_verified_outputs_after_reload": completed.jobs.count == 4
                    && completed.jobs.allSatisfy { $0.state == .succeeded && $0.attemptCount == 1 },
                "originals_unchanged": try edits.enumerated().allSatisfy {
                    try Data(contentsOf: $0.element.sourceURL) == originals[$0.offset]
                },
            ],
            explanation: completed.jobs.map { QueuePresentation.selectedJobDetail($0) }
                .joined(separator: "\n"))
    }

    @MainActor
    func testChangedSourceNeedsReviewWhileOtherJobCompletesAndRetryKeepsIdentity() async throws {
        let initial = try model()
        let stale = try await subtitle("Changed.en.srt")
        let healthy = try await subtitle("Healthy.en.srt")
        for edit in [stale, healthy] {
            _ = try await initial.enqueueReviewedEdit(
                edit, destinationURL: root.appendingPathComponent(edit.outputFilename))
        }
        try Data("1\n00:00:00,000 --> 00:00:00,500\nDifferent dialogue\n".utf8).write(
            to: stale.sourceURL)
        let restored = try model()
        let first = try await restored.runAutomaticQueueCycle()
        XCTAssertEqual(first.jobs.map(\.state), [.needsReview, .succeeded])
        let job = try XCTUnwrap(first.jobs.first)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(stale.outputFilename).path))
        let refreshed = try await restored.reviewedEditForRetry(job)
        _ = try await restored.enqueueReviewedEdit(
            refreshed.edit, destinationURL: root.appendingPathComponent(stale.outputFilename),
            retryingJobID: job.id)
        let result = try await restored.runAutomaticQueueCycle()
        XCTAssertEqual(result.jobs.count, 2)
        XCTAssertEqual(result.jobs[0].id, job.id)
        XCTAssertEqual(result.jobs[0].attemptCount, job.attemptCount + 1)
        XCTAssertEqual(result.jobs.map(\.state), [.succeeded, .succeeded])
        try WorkflowEvidence.record(
            "stale-source-retry",
            facts: [
                "changed_input_required_review": job.state == .needsReview,
                "other_job_completed_independently": first.jobs[1].state == .succeeded,
                "retry_preserved_identity": result.jobs[0].id == job.id,
                "retry_started_one_new_attempt": result.jobs[0].attemptCount == job.attemptCount
                    + 1,
            ], explanation: QueuePresentation.selectedJobDetail(job))
    }

    @MainActor
    func testInterruptedJobRequiresReviewAndRetainsTries() async throws {
        let initial = try model()
        let edit = try await subtitle("Interrupted.en.srt")
        let snapshot = try await initial.enqueueReviewedEdit(
            edit, destinationURL: root.appendingPathComponent(edit.outputFilename))
        let id = try XCTUnwrap(snapshot.jobs.first?.id)
        _ = try await initial.transitionQueueJob(id, to: .running)
        let restored = try model()
        let loaded = try await restored.loadQueue()
        let interrupted = try XCTUnwrap(loaded.jobs.first)
        XCTAssertEqual(interrupted.state, .needsReview)
        XCTAssertEqual(interrupted.attemptCount, 1)
        let prepared = try await restored.reviewedEditForRetry(interrupted)
        let requeued = try await restored.enqueueReviewedEdit(
            prepared.edit, destinationURL: root.appendingPathComponent(edit.outputFilename),
            retryingJobID: id)
        XCTAssertEqual(requeued.jobs.first?.attemptCount, 1)
        let completed = try await restored.runAutomaticQueueCycle()
        XCTAssertEqual(completed.jobs.first?.attemptCount, 2)
        XCTAssertEqual(completed.jobs.first?.state, .succeeded)
    }

    @MainActor
    func testFailedExecutionCanBeReviewedAndRetriedWithoutResettingTries() async throws {
        let initial = try model()
        let edit = try await subtitle("Failure.en.srt")
        _ = try await initial.enqueueReviewedEdit(
            edit, destinationURL: root.appendingPathComponent(edit.outputFilename))
        let queueURL = root.appendingPathComponent("job-queue.json")
        let failing = AppModel(
            historyRecorderFactory: { throw CocoaError(.fileWriteNoPermission) },
            queueStoreFactory: { try JSONJobQueueStore(fileURL: queueURL) },
            queueEnvironmentReader: ReviewedQueueEnvironment())
        let failed = try await failing.runAutomaticQueueCycle()
        let job = try XCTUnwrap(failed.jobs.first)
        XCTAssertEqual(job.state, .failed)
        XCTAssertEqual(job.attemptCount, 1)
        XCTAssertNotNil(job.events.last?.failure)
        let restored = try model()
        let retry = try await restored.reviewedEditForRetry(job)
        _ = try await restored.enqueueReviewedEdit(
            retry.edit, destinationURL: root.appendingPathComponent(edit.outputFilename),
            retryingJobID: job.id)
        let completed = try await restored.runAutomaticQueueCycle()
        XCTAssertEqual(completed.jobs.first?.id, job.id)
        XCTAssertEqual(completed.jobs.first?.attemptCount, 2)
        XCTAssertEqual(completed.jobs.first?.state, .succeeded)
        try WorkflowEvidence.record(
            "failed-job-retry",
            facts: [
                "first_attempt_failed": job.state == .failed && job.attemptCount == 1,
                "retry_kept_job_identity": completed.jobs.first?.id == job.id,
                "second_attempt_succeeded": completed.jobs.first?.state == .succeeded
                    && completed.jobs.first?.attemptCount == 2,
            ],
            explanation: "Before retry: " + QueuePresentation.selectedJobDetail(job)
                + "\nAfter retry: "
                + QueuePresentation.selectedJobDetail(try XCTUnwrap(completed.jobs.first)))
    }

    @MainActor
    func testCancelledSubtitleExecutionRecordsCancellationAndKeepsOriginal() async throws {
        let model = try model()
        let edit = try await subtitle("Cancel.en.srt")
        let original = try Data(contentsOf: edit.sourceURL)
        let destination = root.appendingPathComponent(edit.outputFilename)
        let task = Task {
            try await edit.execute(using: model, destinationURL: destination) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do {
            try await task.value
            XCTFail("Cancelled execution succeeded")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: edit.sourceURL), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let history = try await model.loadHistory()
        XCTAssertEqual(history.first?.events.last?.state, .cancelled)
        try WorkflowEvidence.record(
            "cancelled-output",
            facts: [
                "source_unchanged": try Data(contentsOf: edit.sourceURL) == original,
                "no_output_committed": !FileManager.default.fileExists(atPath: destination.path),
                "history_cancelled": history.first?.events.last?.state == .cancelled,
            ], explanation: HistoryPresentation.stateLabel(.cancelled))
    }

    @MainActor
    func testChangedCleanupContractFailsClosedEvenWithUnchangedSource() async throws {
        let initial = try model()
        let edit = try await subtitle("Contract.en.srt")
        guard case .subtitleCleanup(let format, let source, _, let ids) = try edit.reviewedIntent()
        else {
            return XCTFail("Wrong intent")
        }
        let review = MediaQueueReviewedEdit.subtitleCleanup(
            format: format, sourceSHA256: source, outputSHA256: Data(repeating: 9, count: 32),
            restoringIDs: ids)
        let codec = SecurityScopedBookmarkCodec()
        let job = MediaQueueJob(
            createdAt: Date(), workflow: .reviewedEdit(review),
            inputs: [try codec.makeReference(for: edit.sourceURL, access: .readOnlyFile)],
            destinationDirectory: try codec.makeReference(for: root, access: .readWriteDirectory),
            outputDisplayName: edit.outputFilename, reviewedPlan: ReviewedEditPlanner().plan(review)
        )
        let store = try JSONJobQueueStore(fileURL: root.appendingPathComponent("job-queue.json"))
        _ = try await store.append(job, at: job.createdAt)
        let result = try await initial.runAutomaticQueueCycle()
        XCTAssertEqual(result.jobs.first?.state, .needsReview)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(edit.outputFilename).path))
        let history = try await initial.loadHistory()
        XCTAssertTrue(history.isEmpty)
    }

    @MainActor
    func testStaleReviewCannotBeEnqueuedAndAllRemovedSubtitlesAreRejected() async throws {
        let model = try model()
        let edit = try await subtitle("Old.en.srt")
        try Data("changed".utf8).write(to: edit.sourceURL)
        do {
            _ = try await model.enqueueReviewedEdit(
                edit, destinationURL: root.appendingPathComponent(edit.outputFilename))
            XCTFail("Accepted stale cleanup")
        } catch {}
        let allRemoved = try await subtitle("Empty.en.srt", text: "Downloaded from\nYTS.BZ")
        XCTAssertThrowsError(try allRemoved.reviewedIntent())
        let snapshot = try await model.loadQueue()
        XCTAssertTrue(snapshot.jobs.isEmpty)
    }

    @MainActor
    func testTagsAndExactNestedChaptersSurviveColdReloadAndPreserveOriginals() async throws {
        guard let runtime = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT for bundled media tools")
        }
        let catalog = try ToolCatalog(rootURL: URL(fileURLWithPath: runtime))
        let source = root.appendingPathComponent("Source.mkv")
        let raw = root.appendingPathComponent("audio.pcm")
        try Data(repeating: 0, count: 96_000).write(to: raw)
        let generated = try await FoundationCommandRunner().run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-nostdin", "-loglevel", "error", "-f", "s16le", "-ar", "48000",
                    "-ac", "1",
                    "-i", raw.path, "-c:a", "aac", "-metadata", "title=Keep Title", "-metadata",
                    "comment=Remove tag", source.path,
                ], timeout: 60))
        XCTAssertEqual(generated.exitCode, 0, generated.standardError.text)
        let original = try Data(contentsOf: source)
        let initial = try model()
        await initial.addFiles([source])
        let asset = try XCTUnwrap(initial.assets.first)
        let tags = try await initial.previewMatroskaTags(in: asset)
        let chapters = try await initial.previewChapters(in: asset)
        let desired = MatroskaChapterDocument(editions: [
            .init(chapters: [
                .init(
                    start: .zero, displays: [.init(title: "Part One")],
                    children: [
                        .init(start: .zero, displays: [.init(title: "Opening", language: "en")]),
                        .init(
                            start: MediaTime(nanoseconds: 500_000_000),
                            displays: [.init(title: "Second", language: "es")]),
                    ])
            ])
        ])
        let edits: [ReviewedBatchEdit] = [.tagRemoval(tags), .chapters(chapters, desired)]
        for edit in edits {
            _ = try await initial.enqueueReviewedEdit(
                edit, destinationURL: root.appendingPathComponent(edit.outputFilename))
        }
        let restored = try model()
        let completed = try await restored.runAutomaticQueueCycle()
        XCTAssertEqual(completed.jobs.map(\.state), [.succeeded, .succeeded])
        let tagOutput = try XCTUnwrap(
            restored.assets.first { $0.sourceURL.lastPathComponent == edits[0].outputFilename })
        XCTAssertEqual(tagOutput.globalTagCount, 0)
        XCTAssertEqual(tagOutput.trackTagCount, 0)
        XCTAssertEqual(tagOutput.metadata["title"], asset.metadata["title"])
        let chapterOutput = try XCTUnwrap(
            restored.assets.first { $0.sourceURL.lastPathComponent == edits[1].outputFilename })
        let reopened = try await restored.previewChapters(in: chapterOutput)
        XCTAssertEqual(
            try MatroskaChapterXMLCodec().serialize(reopened.original),
            try MatroskaChapterXMLCodec().serialize(desired))
        XCTAssertEqual(try Data(contentsOf: source), original)
        // A changed source must not inherit old suggestion timestamps on retry.
        let pending = try await initial.enqueueReviewedEdit(
            edits[1], destinationURL: root.appendingPathComponent("Retry.mkv"))
        let job = try XCTUnwrap(pending.jobs.last)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: source.path)
        do {
            _ = try await restored.reviewedEditForRetry(job)
            XCTFail("Reused chapter suggestions on changed source")
        } catch {}
    }
}

private struct ReviewedQueueEnvironment: MediaQueueSchedulingEnvironmentReading {
    func read() -> MediaQueueSchedulingEnvironment {
        .init(isOnBattery: false, thermalPressure: .nominal)
    }
}
