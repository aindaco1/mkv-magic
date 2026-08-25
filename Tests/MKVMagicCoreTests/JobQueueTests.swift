import Foundation
import XCTest

@testable import MKVMagicCore

final class JobQueueTests: XCTestCase {
    func testReviewedPlanComparisonIgnoresOnlyEphemeralStageIdentifiers() {
        let impact = PlanImpact(
            videoEncodeCount: 0,
            audioEncodeCount: 0,
            copiesVideo: true
        )
        let reviewed = ExecutionPlan(
            stages: [
                PlanStage(id: id(1), mechanism: .mkvPropEdit, summary: "Remove title"),
                PlanStage(id: id(2), mechanism: .verify, summary: "Verify output"),
            ],
            impact: impact
        )
        let recompiled = ExecutionPlan(
            stages: [
                PlanStage(id: id(3), mechanism: .mkvPropEdit, summary: "Remove title"),
                PlanStage(id: id(4), mechanism: .verify, summary: "Verify output"),
            ],
            impact: impact
        )

        XCTAssertNotEqual(reviewed, recompiled)
        XCTAssertTrue(reviewed.hasSameReviewedWork(as: recompiled))
        XCTAssertFalse(
            reviewed.hasSameReviewedWork(
                as: ExecutionPlan(
                    stages: [
                        PlanStage(mechanism: .mkvMerge, summary: "Remove title"),
                        PlanStage(mechanism: .verify, summary: "Verify output"),
                    ],
                    impact: impact
                )
            )
        )
        XCTAssertFalse(
            reviewed.hasSameReviewedWork(
                as: ExecutionPlan(
                    stages: [
                        PlanStage(mechanism: .mkvPropEdit, summary: "Change title"),
                        PlanStage(mechanism: .verify, summary: "Verify output"),
                    ],
                    impact: impact
                )
            )
        )
        XCTAssertFalse(
            reviewed.hasSameReviewedWork(
                as: ExecutionPlan(
                    stages: recompiled.stages,
                    impact: PlanImpact(
                        videoEncodeCount: 1,
                        audioEncodeCount: 0,
                        copiesVideo: false
                    )
                )
            )
        )
    }

    func testAutomaticWorkflowPolicyRejectsInteractiveOrAmbiguousInputs() {
        let supported = SavedWorkflow(
            name: "Clean metadata",
            steps: [SavedWorkflowStep(action: .removeSegmentTitle)]
        )
        let disabledInteractiveStep = SavedWorkflow(
            name: "Disabled subtitle step",
            steps: [
                SavedWorkflowStep(isEnabled: false, action: .addExternalSubtitle),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )

        XCTAssertTrue(MediaQueueAutomaticWorkflowPolicy.supports(supported, inputCount: 1))
        XCTAssertTrue(
            MediaQueueAutomaticWorkflowPolicy.supports(
                SavedWorkflow(
                    name: "Clear Matroska tags",
                    steps: [SavedWorkflowStep(action: .clearAllTags)]
                ),
                inputCount: 1
            )
        )
        XCTAssertTrue(
            MediaQueueAutomaticWorkflowPolicy.supports(
                SavedWorkflow(
                    name: "Remove embedded images",
                    steps: [SavedWorkflowStep(action: .removeImageAttachments)]
                ),
                inputCount: 1
            )
        )
        XCTAssertTrue(
            MediaQueueAutomaticWorkflowPolicy.supports(
                SavedWorkflow(
                    name: "Convert once",
                    steps: [
                        SavedWorkflowStep(action: .convertVideoRecommended),
                        SavedWorkflowStep(action: .convertAudioAAC),
                    ]
                ),
                inputCount: 1
            )
        )
        XCTAssertTrue(
            MediaQueueAutomaticWorkflowPolicy.supports(disabledInteractiveStep, inputCount: 1)
        )
        XCTAssertFalse(MediaQueueAutomaticWorkflowPolicy.supports(supported, inputCount: 0))
        XCTAssertFalse(MediaQueueAutomaticWorkflowPolicy.supports(supported, inputCount: 2))

        let reviewedExternalSubtitle = SavedWorkflow(
            name: "Clean and add English subtitles",
            steps: [
                SavedWorkflowStep(action: .cleanExternalSubtitleText),
                SavedWorkflowStep(action: .addExternalSubtitle),
            ]
        )
        XCTAssertFalse(
            MediaQueueAutomaticWorkflowPolicy.supports(
                reviewedExternalSubtitle,
                inputCount: 1
            )
        )
        XCTAssertTrue(
            MediaQueueAutomaticWorkflowPolicy.supports(
                reviewedExternalSubtitle,
                inputCount: 2
            )
        )

        let builtInJob = makeJob(id: id(20), createdAt: Date(timeIntervalSince1970: 0))
        let savedJob = MediaQueueJob(
            id: id(21),
            createdAt: builtInJob.createdAt,
            workflow: .saved(supported),
            inputs: builtInJob.inputs,
            destinationDirectory: builtInJob.destinationDirectory,
            outputDisplayName: builtInJob.outputDisplayName,
            reviewedPlan: builtInJob.reviewedPlan
        )
        XCTAssertFalse(MediaQueueAutomaticWorkflowPolicy.supports(builtInJob))
        XCTAssertTrue(MediaQueueAutomaticWorkflowPolicy.supports(savedJob))

        let subtitleReference = MediaQueueFileReference(
            id: id(22),
            displayName: "Movie.en.srt",
            securityScopedBookmark: Data([7, 8, 9])
        )
        let review = MediaQueueExternalSubtitleReview(
            format: .subRip,
            metadata: ExternalSubtitleTrackMetadata(
                language: "en",
                name: "English",
                isDefault: true
            ),
            restoredCleanupChangeIDs: [2],
            sourceSHA256: Data(repeating: 1, count: 32)
        )
        let reviewedExternalJob = MediaQueueJob(
            id: id(23),
            createdAt: builtInJob.createdAt,
            workflow: .savedWithExternalSubtitle(reviewedExternalSubtitle, review),
            inputs: builtInJob.inputs + [subtitleReference],
            destinationDirectory: builtInJob.destinationDirectory,
            outputDisplayName: builtInJob.outputDisplayName,
            reviewedPlan: builtInJob.reviewedPlan
        )
        XCTAssertTrue(MediaQueueAutomaticWorkflowPolicy.supports(reviewedExternalJob))

        let missingPrivateReviewJob = MediaQueueJob(
            id: id(24),
            createdAt: builtInJob.createdAt,
            workflow: .saved(reviewedExternalSubtitle),
            inputs: builtInJob.inputs + [subtitleReference],
            destinationDirectory: builtInJob.destinationDirectory,
            outputDisplayName: builtInJob.outputDisplayName,
            reviewedPlan: builtInJob.reviewedPlan
        )
        XCTAssertFalse(MediaQueueAutomaticWorkflowPolicy.supports(missingPrivateReviewJob))

        let missingCleanupSelection = MediaQueueExternalSubtitleReview(
            format: .subRip,
            metadata: review.metadata,
            sourceSHA256: review.sourceSHA256
        )
        let mismatchedCleanupJob = MediaQueueJob(
            id: id(25),
            createdAt: builtInJob.createdAt,
            workflow: .savedWithExternalSubtitle(
                reviewedExternalSubtitle,
                missingCleanupSelection
            ),
            inputs: builtInJob.inputs + [subtitleReference],
            destinationDirectory: builtInJob.destinationDirectory,
            outputDisplayName: builtInJob.outputDisplayName,
            reviewedPlan: builtInJob.reviewedPlan
        )
        XCTAssertFalse(MediaQueueAutomaticWorkflowPolicy.supports(mismatchedCleanupJob))

        let noncanonicalReview = MediaQueueExternalSubtitleReview(
            format: .subRip,
            metadata: review.metadata,
            restoredCleanupChangeIDs: [2, 1],
            sourceSHA256: review.sourceSHA256
        )
        let noncanonicalReviewJob = MediaQueueJob(
            id: id(26),
            createdAt: builtInJob.createdAt,
            workflow: .savedWithExternalSubtitle(reviewedExternalSubtitle, noncanonicalReview),
            inputs: builtInJob.inputs + [subtitleReference],
            destinationDirectory: builtInJob.destinationDirectory,
            outputDisplayName: builtInJob.outputDisplayName,
            reviewedPlan: builtInJob.reviewedPlan
        )
        XCTAssertFalse(MediaQueueAutomaticWorkflowPolicy.supports(noncanonicalReviewJob))

        let invalidDigestReview = MediaQueueExternalSubtitleReview(
            format: .subRip,
            metadata: review.metadata,
            restoredCleanupChangeIDs: [2],
            sourceSHA256: Data(repeating: 1, count: 31)
        )
        let invalidDigestJob = MediaQueueJob(
            id: id(27),
            createdAt: builtInJob.createdAt,
            workflow: .savedWithExternalSubtitle(reviewedExternalSubtitle, invalidDigestReview),
            inputs: builtInJob.inputs + [subtitleReference],
            destinationDirectory: builtInJob.destinationDirectory,
            outputDisplayName: builtInJob.outputDisplayName,
            reviewedPlan: builtInJob.reviewedPlan
        )
        XCTAssertFalse(MediaQueueAutomaticWorkflowPolicy.supports(invalidDigestJob))
        for invalidReview in [
            MediaQueueExternalSubtitleReview(
                format: .subRip,
                metadata: ExternalSubtitleTrackMetadata(language: "not valid!"),
                restoredCleanupChangeIDs: [2],
                sourceSHA256: review.sourceSHA256
            ),
            MediaQueueExternalSubtitleReview(
                format: .subRip,
                metadata: review.metadata,
                restoredCleanupChangeIDs: [1, 1],
                sourceSHA256: review.sourceSHA256
            ),
            MediaQueueExternalSubtitleReview(
                format: .subRip,
                metadata: review.metadata,
                restoredCleanupChangeIDs: [-1],
                sourceSHA256: review.sourceSHA256
            ),
        ] {
            XCTAssertFalse(invalidReview.hasCanonicalStructure)
        }

        for action in [
            SavedWorkflowAction.addExternalSubtitle,
            .cleanExternalSubtitleText,
        ] {
            XCTAssertFalse(
                MediaQueueAutomaticWorkflowPolicy.supports(
                    SavedWorkflow(
                        name: "Interactive",
                        steps: [SavedWorkflowStep(action: action)]
                    ),
                    inputCount: 1
                )
            )
        }
    }

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
        XCTAssertThrowsError(
            try job.transition(
                to: .waiting,
                at: base.addingTimeInterval(3),
                reason: .userAction
            )
        ) {
            XCTAssertEqual(
                $0 as? MediaQueueTransitionError,
                .invalidTransition(from: .failed, to: .waiting)
            )
        }
        try job.approveReplan(
            workflow: job.workflow,
            inputs: job.inputs,
            destinationDirectory: job.destinationDirectory,
            outputDisplayName: job.outputDisplayName,
            sourceDisposition: job.sourceDisposition,
            reviewedPlan: job.reviewedPlan,
            at: base.addingTimeInterval(3)
        )
        try job.transition(to: .running, at: base.addingTimeInterval(4))

        XCTAssertEqual(job.attemptCount, 2)
        XCTAssertEqual(job.resourceClass, .videoHeavy)
        XCTAssertFalse(job.state.isFinished)
    }

    func testRetryRequiresACompleteFreshPlanAndBookmarkSet() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var job = makeJob(id: id(1), createdAt: base, videoEncodes: 1)
        let replacement = makeJob(id: id(2), createdAt: base, audioEncodes: 1)

        XCTAssertThrowsError(
            try job.approveReplan(
                workflow: replacement.workflow,
                inputs: replacement.inputs,
                destinationDirectory: replacement.destinationDirectory,
                outputDisplayName: replacement.outputDisplayName,
                sourceDisposition: replacement.sourceDisposition,
                reviewedPlan: replacement.reviewedPlan,
                at: base
            )
        ) {
            XCTAssertEqual(
                $0 as? MediaQueueTransitionError,
                .replanRequiresReviewState
            )
        }

        try job.transition(to: .running, at: base)
        try job.transition(to: .failed, at: base, reason: .executionFailed)
        let beforeStaleReplan = job
        XCTAssertThrowsError(
            try job.approveReplan(
                workflow: replacement.workflow,
                inputs: replacement.inputs,
                destinationDirectory: replacement.destinationDirectory,
                outputDisplayName: "Must Not Leak.mkv",
                sourceDisposition: .trashAfterVerifiedSuccess,
                reviewedPlan: replacement.reviewedPlan,
                at: base.addingTimeInterval(-1)
            )
        ) {
            XCTAssertEqual($0 as? MediaQueueTransitionError, .timestampMovedBackward)
        }
        XCTAssertEqual(job, beforeStaleReplan)
        try job.approveReplan(
            workflow: replacement.workflow,
            inputs: replacement.inputs,
            destinationDirectory: replacement.destinationDirectory,
            outputDisplayName: "Retried.mkv",
            sourceDisposition: .trashAfterVerifiedSuccess,
            reviewedPlan: replacement.reviewedPlan,
            at: base.addingTimeInterval(1)
        )

        XCTAssertEqual(job.state, .waiting)
        XCTAssertEqual(job.attemptCount, 1)
        XCTAssertEqual(job.resourceClass, .audioHeavy)
        XCTAssertEqual(job.outputDisplayName, "Retried.mkv")
        XCTAssertEqual(job.sourceDisposition, .trashAfterVerifiedSuccess)
        XCTAssertEqual(job.inputs, replacement.inputs)
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

    func testLateCancellationCanTruthfullyFinishAsVerifiedSuccess() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var job = makeJob(id: id(1), createdAt: base)

        try job.transition(to: .running, at: base.addingTimeInterval(1))
        try job.transition(
            to: .cancelling,
            at: base.addingTimeInterval(2),
            reason: .userAction
        )
        try job.transition(to: .succeeded, at: base.addingTimeInterval(3))

        XCTAssertEqual(job.state, .succeeded)
        XCTAssertEqual(job.attemptCount, 1)
        XCTAssertTrue(job.state.isFinished)
    }

    func testSourceDispositionOutcomeRequiresOneVerifiedSuccessAndAdvancesTimestamp() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var trashJob = makeJob(
            id: id(1),
            createdAt: base,
            sourceDisposition: .trashAfterVerifiedSuccess
        )
        XCTAssertThrowsError(
            try trashJob.recordSourceDisposition(.applied, at: base)
        ) {
            XCTAssertEqual(
                $0 as? MediaQueueTransitionError,
                .sourceDispositionRequiresVerifiedSuccess
            )
        }
        try trashJob.transition(to: .running, at: base.addingTimeInterval(1))
        try trashJob.transition(to: .succeeded, at: base.addingTimeInterval(2))
        XCTAssertThrowsError(
            try trashJob.recordSourceDisposition(.applied, at: base.addingTimeInterval(1))
        ) {
            XCTAssertEqual(
                $0 as? MediaQueueTransitionError,
                .timestampMovedBackward
            )
        }
        XCTAssertNil(trashJob.sourceDispositionResult)
        try trashJob.recordSourceDisposition(.applied, at: base.addingTimeInterval(3))

        XCTAssertEqual(trashJob.sourceDispositionResult?.outcome, .applied)
        XCTAssertEqual(trashJob.updatedAt, base.addingTimeInterval(3))
        XCTAssertThrowsError(
            try trashJob.recordSourceDisposition(.failed, at: base.addingTimeInterval(4))
        ) {
            XCTAssertEqual(
                $0 as? MediaQueueTransitionError,
                .sourceDispositionAlreadyRecorded
            )
        }

        var keepJob = makeJob(id: id(2), createdAt: base)
        try keepJob.transition(to: .running, at: base)
        try keepJob.transition(to: .succeeded, at: base)
        XCTAssertThrowsError(try keepJob.recordSourceDisposition(.applied, at: base)) {
            XCTAssertEqual(
                $0 as? MediaQueueTransitionError,
                .sourceDispositionNotRequested
            )
        }
    }

    func testSnapshotClampsOnlySubMillisecondClockSkew() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var snapshot = MediaQueueSnapshot(
            updatedAt: base.addingTimeInterval(0.0005)
        )

        try snapshot.setPaused(true, at: base)
        XCTAssertEqual(snapshot.updatedAt, base.addingTimeInterval(0.0005))
        XCTAssertThrowsError(
            try snapshot.setPaused(false, at: base.addingTimeInterval(-0.001))
        ) {
            XCTAssertEqual($0 as? MediaQueueMutationError, .timestampMovedBackward)
        }
        XCTAssertTrue(snapshot.isPaused)
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
        audioEncodes: Int = 0,
        sourceDisposition: MediaQueueSourceDisposition = .keepOriginal
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
            sourceDisposition: sourceDisposition,
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
