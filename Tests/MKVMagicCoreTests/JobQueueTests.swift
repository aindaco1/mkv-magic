import Foundation
import XCTest

@testable import MKVMagicCore

final class JobQueueTests: XCTestCase {
    func testRetryableStateMachineCountsOnlyStartedAttemptsAndRequiresSafeFailureReason() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var job = makeJob(id: id(1), createdAt: base, videoEncodes: 1)

        try job.transition(to: .running, at: base.addingTimeInterval(1))
        XCTAssertEqual(job.attemptCount, 1)
        XCTAssertThrowsError(
            try job.transition(to: .failed, at: base.addingTimeInterval(2))
        ) {
            XCTAssertEqual($0 as? MediaQueueTransitionError, .missingFailureReason)
        }
        try job.transition(
            to: .failed,
            at: base.addingTimeInterval(2),
            reason: .executionFailed
        )
        try job.transition(
            to: .waiting,
            at: base.addingTimeInterval(3),
            reason: .userAction
        )
        try job.transition(to: .running, at: base.addingTimeInterval(4))

        XCTAssertEqual(job.attemptCount, 2)
        XCTAssertEqual(job.resourceClass, .videoHeavy)
        XCTAssertFalse(job.state.isFinished)
    }

    func testInterruptedRunningAndCancellingJobsRequireReviewInsteadOfAutoRun() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var running = makeJob(id: id(1), createdAt: base)
        var cancelling = makeJob(id: id(2), createdAt: base)
        try running.transition(to: .running, at: base)
        try cancelling.transition(to: .running, at: base)
        try cancelling.transition(
            to: .cancelling,
            at: base,
            reason: .userAction
        )
        var snapshot = MediaQueueSnapshot(
            jobs: [running, cancelling, makeJob(id: id(3), createdAt: base)],
            updatedAt: base
        )

        XCTAssertEqual(
            try snapshot.recoverInterruptedJobs(at: base.addingTimeInterval(1)),
            2
        )
        XCTAssertEqual(snapshot.jobs.map(\.state), [.needsReview, .needsReview, .waiting])
        XCTAssertTrue(
            snapshot.jobs.prefix(2).allSatisfy {
                $0.events.last?.reason == .interruptedBeforeVerification
            }
        )
    }

    func testPendingReorderIsExactAndCannotSmuggleRunningOrDuplicateJobs() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var running = makeJob(id: id(1), createdAt: base)
        try running.transition(to: .running, at: base)
        var snapshot = MediaQueueSnapshot(
            jobs: [
                makeJob(id: id(2), createdAt: base),
                running,
                makeJob(id: id(3), createdAt: base),
            ],
            updatedAt: base
        )

        try snapshot.reorderPending([id(3), id(2)], at: base)
        XCTAssertEqual(snapshot.jobs.map(\.id), [id(1), id(3), id(2)])
        XCTAssertThrowsError(try snapshot.reorderPending([id(1), id(2)], at: base)) {
            XCTAssertEqual($0 as? MediaQueueMutationError, .invalidPendingOrder)
        }
        XCTAssertThrowsError(try snapshot.reorderPending([id(2), id(2)], at: base)) {
            XCTAssertEqual($0 as? MediaQueueMutationError, .invalidPendingOrder)
        }
    }

    func testSchedulerAdmitsOneHeavyAndBoundedLightweightWorkInQueueOrder() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var jobs = [
            makeJob(id: id(1), createdAt: base, videoEncodes: 1),
            makeJob(id: id(2), createdAt: base),
            makeJob(id: id(3), createdAt: base, videoEncodes: 1),
            makeJob(id: id(4), createdAt: base),
            makeJob(id: id(5), createdAt: base),
            makeJob(id: id(6), createdAt: base),
        ]
        try jobs[5].transition(to: .held, at: base, reason: .userAction)
        let snapshot = MediaQueueSnapshot(jobs: jobs, updatedAt: base)
        let scheduler = MediaQueueScheduler()

        XCTAssertEqual(
            scheduler.jobsToStart(
                in: snapshot,
                environment: .init(isOnBattery: false, thermalPressure: .nominal)
            ),
            [id(1), id(2), id(4), id(5)]
        )
        XCTAssertEqual(
            scheduler.jobsToStart(
                in: snapshot,
                environment: .init(isOnBattery: true, thermalPressure: .nominal)
            ),
            [id(2)]
        )
        XCTAssertEqual(
            scheduler.jobsToStart(
                in: snapshot,
                environment: .init(isOnBattery: false, thermalPressure: .serious)
            ),
            []
        )
    }

    func testPausedQueueStartsNothingAndRunningJobsConsumeCapacity() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var runningHeavy = makeJob(id: id(1), createdAt: base, videoEncodes: 1)
        var runningLight = makeJob(id: id(2), createdAt: base)
        try runningHeavy.transition(to: .running, at: base)
        try runningLight.transition(to: .running, at: base)
        var snapshot = MediaQueueSnapshot(
            jobs: [
                runningHeavy,
                runningLight,
                makeJob(id: id(3), createdAt: base, videoEncodes: 1),
                makeJob(id: id(4), createdAt: base),
                makeJob(id: id(5), createdAt: base),
                makeJob(id: id(6), createdAt: base),
            ],
            updatedAt: base
        )
        let scheduler = MediaQueueScheduler()
        let pluggedIn = MediaQueueSchedulingEnvironment(
            isOnBattery: false,
            thermalPressure: .fair
        )

        XCTAssertEqual(
            scheduler.jobsToStart(in: snapshot, environment: pluggedIn),
            [id(4), id(5)]
        )
        try snapshot.setPaused(true, at: base)
        XCTAssertEqual(scheduler.jobsToStart(in: snapshot, environment: pluggedIn), [])
    }

    func testAudioEncodingUsesItsOwnBoundedPoolAndDoesNotRunOnBattery() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = MediaQueueSnapshot(
            jobs: [
                makeJob(id: id(1), createdAt: base, audioEncodes: 1),
                makeJob(id: id(2), createdAt: base, audioEncodes: 2),
                makeJob(id: id(3), createdAt: base, audioEncodes: 1),
                makeJob(id: id(4), createdAt: base),
            ],
            updatedAt: base
        )
        let scheduler = MediaQueueScheduler()

        XCTAssertEqual(snapshot.jobs[0].resourceClass, .audioHeavy)
        XCTAssertEqual(
            scheduler.jobsToStart(
                in: snapshot,
                environment: .init(isOnBattery: false, thermalPressure: .nominal)
            ),
            [id(1), id(2), id(4)]
        )
        XCTAssertEqual(
            scheduler.jobsToStart(
                in: snapshot,
                environment: .init(isOnBattery: true, thermalPressure: .nominal)
            ),
            [id(4)]
        )
    }

    private func makeJob(
        id: UUID,
        createdAt: Date,
        videoEncodes: Int = 0,
        audioEncodes: Int = 0
    ) -> MediaQueueJob {
        let impact = PlanImpact(
            videoEncodeCount: videoEncodes,
            audioEncodeCount: audioEncodes,
            copiesVideo: videoEncodes == 0
        )
        return MediaQueueJob(
            id: id,
            createdAt: createdAt,
            workflow: .builtIn(id: self.id(90), name: "Verified workflow"),
            inputs: [
                MediaQueueFileReference(
                    id: self.id(91),
                    displayName: "Input.mkv",
                    securityScopedBookmark: Data([1, 2, 3])
                )
            ],
            destinationDirectory: MediaQueueFileReference(
                id: self.id(92),
                displayName: "Output Folder",
                securityScopedBookmark: Data([4, 5, 6])
            ),
            outputDisplayName: "Input — Edited.mkv",
            reviewedPlan: ExecutionPlan(
                stages: [
                    PlanStage(
                        id: self.id(93),
                        mechanism: videoEncodes == 0 ? .mkvMerge : .ffmpegEncode,
                        summary: "Create one verified output"
                    )
                ],
                impact: impact
            )
        )
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
