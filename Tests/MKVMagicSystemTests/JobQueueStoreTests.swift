import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicSystem

final class JobQueueStoreTests: XCTestCase {
    private var rootURL: URL!
    private var fileURL: URL!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-queue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        fileURL = rootURL.appendingPathComponent("job-queue.json")
    }

    override func tearDownWithError() throws {
        if rootURL != nil { try FileManager.default.removeItem(at: rootURL) }
    }

    func testRoundTripsPrivateVersionedQueueAndBookmarkAuthority() async throws {
        let store = try JSONJobQueueStore(fileURL: fileURL)
        let snapshot = MediaQueueSnapshot(jobs: [makeJob(id: id(1))], updatedAt: base)

        try await store.save(snapshot)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, snapshot)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        let encoded = try XCTUnwrap(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        XCTAssertTrue(encoded.contains("mkv-magic-job-queue-v1"))
        XCTAssertFalse(encoded.contains("/Users/"))
    }

    func testAtomicMutationsPersistPauseHoldReorderRetryAndCancel() async throws {
        let store = try JSONJobQueueStore(fileURL: fileURL)
        _ = try await store.append(makeJob(id: id(1)), at: base)
        _ = try await store.append(makeJob(id: id(2)), at: base)
        _ = try await store.setPaused(true, at: base)
        _ = try await store.transition(
            jobID: id(1),
            to: .held,
            at: base,
            reason: .userAction
        )
        _ = try await store.reorderPending([id(2), id(1)], at: base)
        _ = try await store.transition(jobID: id(2), to: .running, at: base, reason: nil)
        _ = try await store.transition(
            jobID: id(2),
            to: .failed,
            at: base,
            reason: .executionFailed
        )
        _ = try await store.transition(
            jobID: id(2),
            to: .waiting,
            at: base,
            reason: .userAction
        )
        let snapshot = try await store.transition(
            jobID: id(1),
            to: .cancelled,
            at: base,
            reason: .userAction
        )

        XCTAssertTrue(snapshot.isPaused)
        XCTAssertEqual(snapshot.jobs.map(\.id), [id(2), id(1)])
        XCTAssertEqual(snapshot.jobs.map(\.state), [.waiting, .cancelled])
        XCTAssertEqual(snapshot.jobs[0].attemptCount, 1)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, snapshot)
    }

    func testRecoveryRequiresFreshReviewForInterruptedJobs() async throws {
        let store = try JSONJobQueueStore(fileURL: fileURL)
        _ = try await store.append(makeJob(id: id(1)), at: base)
        _ = try await store.append(makeJob(id: id(2)), at: base)
        _ = try await store.transition(jobID: id(1), to: .running, at: base, reason: nil)
        _ = try await store.transition(jobID: id(2), to: .running, at: base, reason: nil)
        _ = try await store.transition(
            jobID: id(2),
            to: .cancelling,
            at: base,
            reason: .userAction
        )

        let recovered = try await store.recoverInterruptedJobs(
            at: base.addingTimeInterval(1)
        )

        XCTAssertEqual(recovered.jobs.map(\.state), [.needsReview, .needsReview])
        XCTAssertTrue(
            recovered.jobs.allSatisfy {
                $0.events.last?.reason == .interruptedBeforeVerification
            }
        )
    }

    func testStrictDocumentAndPathValidationFailClosed() async throws {
        let store = try JSONJobQueueStore(fileURL: fileURL)
        try Data(#"{"schema":"mkv-magic-job-queue-v1","snapshot":{},"extra":true}"#.utf8)
            .write(to: fileURL)
        do {
            _ = try await store.load()
            XCTFail("Expected unexpected fields")
        } catch {
            XCTAssertEqual(error as? JobQueueStoreError, .unexpectedFields)
        }

        try FileManager.default.removeItem(at: fileURL)
        let target = rootURL.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: target)
        do {
            _ = try await store.load()
            XCTFail("Expected symlink refusal")
        } catch {
            XCTAssertEqual(error as? JobQueueStoreError, .unsafePath)
        }
    }

    func testMalformedBookmarksDuplicateIDsAndForgedAttemptsFailClosed() async throws {
        let store = try JSONJobQueueStore(fileURL: fileURL)
        let emptyBookmark = makeJob(
            id: id(1),
            inputBookmark: Data(),
            attemptCount: 0
        )
        do {
            try await store.save(MediaQueueSnapshot(jobs: [emptyBookmark], updatedAt: base))
            XCTFail("Expected empty bookmark refusal")
        } catch {
            XCTAssertEqual(error as? JobQueueStoreError, .malformedQueue)
        }

        let duplicate = makeJob(id: id(2))
        do {
            try await store.save(
                MediaQueueSnapshot(jobs: [duplicate, duplicate], updatedAt: base)
            )
            XCTFail("Expected duplicate job refusal")
        } catch {
            XCTAssertEqual(error as? JobQueueStoreError, .malformedQueue)
        }

        let forgedAttempt = makeJob(id: id(3), attemptCount: 2)
        do {
            try await store.save(MediaQueueSnapshot(jobs: [forgedAttempt], updatedAt: base))
            XCTFail("Expected attempt replay refusal")
        } catch {
            XCTAssertEqual(error as? JobQueueStoreError, .malformedQueue)
        }
    }

    func testUnsafeOutputNamesAndForgedPlanImpactFailClosed() async throws {
        let store = try JSONJobQueueStore(fileURL: fileURL)
        for outputName in ["", "   ", ".", "..", "../Escape.mkv", "Folder/File.mkv"] {
            let job = makeJob(id: UUID(), outputDisplayName: outputName)
            do {
                try await store.save(MediaQueueSnapshot(jobs: [job], updatedAt: base))
                XCTFail("Expected unsafe output refusal for \(outputName)")
            } catch {
                XCTAssertEqual(error as? JobQueueStoreError, .malformedQueue)
            }
        }

        let unsafeImpact = makeJob(
            id: id(4),
            impact: PlanImpact(
                videoEncodeCount: 0,
                audioEncodeCount: 0,
                copiesVideo: true,
                changesSourceBeforeVerification: true
            )
        )
        do {
            try await store.save(MediaQueueSnapshot(jobs: [unsafeImpact], updatedAt: base))
            XCTFail("Expected unsafe plan refusal")
        } catch {
            XCTAssertEqual(error as? JobQueueStoreError, .malformedQueue)
        }
    }

    private func makeJob(
        id: UUID,
        inputBookmark: Data = Data([1, 2, 3]),
        attemptCount: Int = 0,
        outputDisplayName: String = "Input — Edited.mkv",
        impact: PlanImpact = PlanImpact(
            videoEncodeCount: 0,
            audioEncodeCount: 0,
            copiesVideo: true
        )
    ) -> MediaQueueJob {
        MediaQueueJob(
            id: id,
            createdAt: base,
            workflow: .builtIn(id: self.id(90), name: "Remove tracks"),
            inputs: [
                MediaQueueFileReference(
                    id: self.id(91),
                    displayName: "Input.mkv",
                    securityScopedBookmark: inputBookmark
                )
            ],
            destinationDirectory: MediaQueueFileReference(
                id: self.id(92),
                displayName: "Output Folder",
                securityScopedBookmark: Data([4, 5, 6])
            ),
            outputDisplayName: outputDisplayName,
            reviewedPlan: ExecutionPlan(
                stages: [
                    PlanStage(
                        id: self.id(93),
                        mechanism: .mkvMerge,
                        summary: "One verified remux"
                    )
                ],
                impact: impact
            ),
            attemptCount: attemptCount
        )
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
