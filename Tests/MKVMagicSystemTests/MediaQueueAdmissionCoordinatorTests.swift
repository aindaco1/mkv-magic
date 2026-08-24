import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicSystem

final class MediaQueueAdmissionCoordinatorTests: XCTestCase {
    private actor AdmissionRecorder {
        private(set) var admissions = [MediaQueueAdmission]()

        func append(_ admission: MediaQueueAdmission) {
            admissions.append(admission)
        }
    }

    private struct ExpectedFailure: Error {}

    private var rootURL: URL!
    private var queueURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-admission-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        queueURL = rootURL.appendingPathComponent("job-queue.json")
    }

    override func tearDownWithError() throws {
        if rootURL != nil { try FileManager.default.removeItem(at: rootURL) }
    }

    func testResolverRequiresUnchangedInputSafeDestinationAndUnusedOutput() throws {
        let sourceURL = try makeSource("Input.mkv")
        let job = try makeJob(
            id: id(1),
            name: "Safe",
            sourceURL: sourceURL,
            outputName: "Output.mkv"
        )
        let resolver = MediaQueueAdmissionResolver()

        let admission = try resolver.resolve(job)
        XCTAssertEqual(admission.inputURLs, [sourceURL.standardizedFileURL])
        XCTAssertEqual(admission.destinationDirectoryURL, rootURL.standardizedFileURL)
        XCTAssertEqual(admission.outputURL, rootURL.appendingPathComponent("Output.mkv"))

        try Data([9]).write(to: admission.outputURL)
        XCTAssertThrowsError(try resolver.resolve(job)) {
            XCTAssertEqual(
                $0 as? MediaQueueAdmissionResolutionError,
                .outputAlreadyExists
            )
        }
        try FileManager.default.removeItem(at: admission.outputURL)
        try Data([1, 2, 3, 4]).write(to: sourceURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: sourceURL.path
        )
        XCTAssertThrowsError(try resolver.resolve(job)) {
            XCTAssertEqual(
                $0 as? MediaQueueAdmissionResolutionError,
                .changedOrUnavailableInput
            )
        }
    }

    func testCoordinatorAdmitsOnlySupportedFreshJobsAndPersistsReviewReasons() async throws {
        let freshSource = try makeSource("Fresh.mkv")
        let staleSource = try makeSource("Stale.mkv")
        let unsupportedSource = try makeSource("Unsupported.mkv")
        let fresh = try makeJob(
            id: id(1),
            name: "Fresh",
            sourceURL: freshSource,
            outputName: "Fresh Output.mkv"
        )
        let stale = try makeJob(
            id: id(2),
            name: "Stale",
            sourceURL: staleSource,
            outputName: "Stale Output.mkv"
        )
        let unsupported = try makeJob(
            id: id(3),
            name: "Unsupported",
            sourceURL: unsupportedSource,
            outputName: "Unsupported Output.mkv"
        )
        try Data([7, 8, 9, 10]).write(to: staleSource)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: staleSource.path
        )
        let store = try JSONJobQueueStore(fileURL: queueURL)
        let timestamp = max(fresh.updatedAt, stale.updatedAt, unsupported.updatedAt)
        try await store.save(
            MediaQueueSnapshot(jobs: [fresh, stale, unsupported], updatedAt: timestamp)
        )
        let recorder = AdmissionRecorder()
        let coordinator = MediaQueueAdmissionCoordinator(store: store)

        let report = try await coordinator.runCycle(
            environment: .init(isOnBattery: false, thermalPressure: .nominal),
            supports: { $0.workflow.name != "Unsupported" },
            execute: { admission in
                await recorder.append(admission)
                return .verifiedSuccess
            }
        )

        XCTAssertEqual(report.admittedJobIDs, [fresh.id])
        XCTAssertEqual(report.needsReviewJobIDs, [stale.id, unsupported.id])
        XCTAssertEqual(report.outcomes, [fresh.id: .verifiedSuccess])
        XCTAssertEqual(report.snapshot.jobs.map(\.state), [.succeeded, .needsReview, .needsReview])
        XCTAssertEqual(report.snapshot.jobs[0].attemptCount, 1)
        XCTAssertEqual(report.snapshot.jobs[1].events.last?.reason, .staleReview)
        XCTAssertEqual(
            report.snapshot.jobs[2].events.last?.reason,
            .automaticExecutionUnavailable
        )
        let admissions = await recorder.admissions
        XCTAssertEqual(admissions.map(\.job.id), [fresh.id])
    }

    func testCoordinatorRepeatsSafetyChecksInsideExecutionScope() async throws {
        let sourceURL = try makeSource("Changed In Admission Gap.mkv")
        let job = try makeJob(
            id: id(1),
            name: "Admission gap",
            sourceURL: sourceURL,
            outputName: "Gap Output.mkv"
        )
        let store = try JSONJobQueueStore(fileURL: queueURL)
        try await store.save(MediaQueueSnapshot(jobs: [job], updatedAt: job.updatedAt))
        let recorder = AdmissionRecorder()
        let resolver = MediaQueueAdmissionResolver(fileExistsAtPath: { _ in
            try? Data([1, 2, 3, 4]).write(to: sourceURL)
            return false
        })
        let coordinator = MediaQueueAdmissionCoordinator(store: store, resolver: resolver)

        let report = try await coordinator.runCycle(
            environment: .init(isOnBattery: false, thermalPressure: .nominal),
            supports: { _ in true },
            execute: { admission in
                await recorder.append(admission)
                return .verifiedSuccess
            }
        )

        XCTAssertEqual(report.admittedJobIDs, [job.id])
        XCTAssertEqual(report.outcomes, [job.id: .needsReview])
        XCTAssertEqual(report.snapshot.jobs.count, 1)
        XCTAssertEqual(report.snapshot.jobs.first?.state, .needsReview)
        XCTAssertEqual(report.snapshot.jobs.first?.events.last?.reason, .staleReview)
        XCTAssertEqual(report.snapshot.jobs.first?.attemptCount, 1)
        let admissions = await recorder.admissions
        XCTAssertTrue(admissions.isEmpty)
    }

    func testCoordinatorMapsExecutorOutcomesAndHonorsPauseWithoutCallingExecutor() async throws {
        let jobs = try [
            makeJob(
                id: id(1),
                name: "Verified",
                sourceURL: makeSource("Verified.mkv"),
                outputName: "Verified Output.mkv"
            ),
            makeJob(
                id: id(2),
                name: "Failed",
                sourceURL: makeSource("Failed.mkv"),
                outputName: "Failed Output.mkv"
            ),
            makeJob(
                id: id(3),
                name: "Cancelled",
                sourceURL: makeSource("Cancelled.mkv"),
                outputName: "Cancelled Output.mkv"
            ),
            makeJob(
                id: id(4),
                name: "Review",
                sourceURL: makeSource("Review.mkv"),
                outputName: "Review Output.mkv"
            ),
        ]
        let timestamp = jobs.map(\.updatedAt).max() ?? Date()
        let store = try JSONJobQueueStore(fileURL: queueURL)
        try await store.save(
            MediaQueueSnapshot(isPaused: true, jobs: jobs, updatedAt: timestamp)
        )
        let recorder = AdmissionRecorder()
        let coordinator = MediaQueueAdmissionCoordinator(
            store: store,
            scheduler: MediaQueueScheduler(maximumLightweightJobs: 4)
        )

        let paused = try await coordinator.runCycle(
            environment: .init(isOnBattery: false, thermalPressure: .nominal),
            supports: { _ in true },
            execute: { admission in
                await recorder.append(admission)
                return .verifiedSuccess
            }
        )
        XCTAssertTrue(paused.admittedJobIDs.isEmpty)
        let pausedAdmissions = await recorder.admissions
        XCTAssertTrue(pausedAdmissions.isEmpty)

        _ = try await store.setPaused(false, at: Date())
        let report = try await coordinator.runCycle(
            environment: .init(isOnBattery: false, thermalPressure: .fair),
            supports: { _ in true },
            execute: { admission in
                switch admission.job.workflow.name {
                case "Verified": return .verifiedSuccess
                case "Failed": throw ExpectedFailure()
                case "Cancelled": throw CancellationError()
                default: return .needsReview
                }
            }
        )

        XCTAssertEqual(Set(report.admittedJobIDs), Set(jobs.map(\.id)))
        XCTAssertEqual(
            report.snapshot.jobs.map(\.state),
            [.succeeded, .failed, .cancelled, .needsReview]
        )
        XCTAssertEqual(
            report.outcomes,
            [
                jobs[0].id: .verifiedSuccess,
                jobs[1].id: .failed,
                jobs[2].id: .cancelled,
                jobs[3].id: .needsReview,
            ]
        )
        XCTAssertTrue(report.snapshot.jobs.allSatisfy { $0.attemptCount == 1 })
    }

    private func makeSource(_ filename: String) throws -> URL {
        let url = rootURL.appendingPathComponent(filename)
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    private func makeJob(
        id: UUID,
        name: String,
        sourceURL: URL,
        outputName: String
    ) throws -> MediaQueueJob {
        let codec = SecurityScopedBookmarkCodec()
        let workflow = SavedWorkflow(
            id: self.id(Int(id.uuid.15)),
            name: name,
            steps: [SavedWorkflowStep(action: .removeSegmentTitle)]
        )
        let createdAt = Date()
        return MediaQueueJob(
            id: id,
            createdAt: createdAt,
            workflow: .saved(workflow),
            inputs: [try codec.makeReference(for: sourceURL, access: .readOnlyFile)],
            destinationDirectory: try codec.makeReference(
                for: rootURL,
                access: .readWriteDirectory
            ),
            outputDisplayName: outputName,
            reviewedPlan: ExecutionPlan(
                stages: [PlanStage(mechanism: .mkvPropEdit, summary: "Remove title")],
                impact: PlanImpact(
                    videoEncodeCount: 0,
                    audioEncodeCount: 0,
                    copiesVideo: true
                )
            )
        )
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
