import Foundation
import MKVMagicCore

public enum MediaQueueAdmissionResolutionError: Error, Equatable, Sendable {
    case missingInput
    case changedOrUnavailableInput
    case unavailableDestination
    case unsafeOutput
    case outputAlreadyExists
}

public struct MediaQueueAdmission: Equatable, Sendable {
    public let job: MediaQueueJob
    public let inputURLs: [URL]
    public let destinationDirectoryURL: URL
    public let outputURL: URL

    public init(
        job: MediaQueueJob,
        inputURLs: [URL],
        destinationDirectoryURL: URL,
        outputURL: URL
    ) {
        self.job = job
        self.inputURLs = inputURLs
        self.destinationDirectoryURL = destinationDirectoryURL
        self.outputURL = outputURL
    }
}

public struct MediaQueueAdmissionResolver: Sendable {
    private let bookmarkCodec: SecurityScopedBookmarkCodec
    private let fileExistsAtPath: @Sendable (String) -> Bool

    public init(
        bookmarkCodec: SecurityScopedBookmarkCodec = SecurityScopedBookmarkCodec(),
        fileExistsAtPath: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) {
        self.bookmarkCodec = bookmarkCodec
        self.fileExistsAtPath = fileExistsAtPath
    }

    public func resolve(_ job: MediaQueueJob) throws -> MediaQueueAdmission {
        guard !job.inputs.isEmpty else {
            throw MediaQueueAdmissionResolutionError.missingInput
        }
        let inputURLs: [URL]
        do {
            inputURLs = try job.inputs.enumerated().map { index, reference in
                let access: SecurityScopedBookmarkAccess =
                    index == 0 && job.sourceDisposition == .trashAfterVerifiedSuccess
                    ? .readWriteFile : .readOnlyFile
                return try bookmarkCodec.resolveUnchangedFile(reference, access: access)
            }
        } catch {
            throw MediaQueueAdmissionResolutionError.changedOrUnavailableInput
        }

        let destinationDirectoryURL: URL
        do {
            destinationDirectoryURL = try bookmarkCodec.resolve(
                job.destinationDirectory,
                access: .readWriteDirectory
            )
        } catch {
            throw MediaQueueAdmissionResolutionError.unavailableDestination
        }
        guard
            let outputURL = MediaQueueOutputFilenamePolicy.outputURL(
                filename: job.outputDisplayName,
                in: destinationDirectoryURL
            )
        else {
            throw MediaQueueAdmissionResolutionError.unsafeOutput
        }
        let accessed = destinationDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { destinationDirectoryURL.stopAccessingSecurityScopedResource() }
        }
        guard !fileExistsAtPath(outputURL.path) else {
            throw MediaQueueAdmissionResolutionError.outputAlreadyExists
        }
        return MediaQueueAdmission(
            job: job,
            inputURLs: inputURLs,
            destinationDirectoryURL: destinationDirectoryURL,
            outputURL: outputURL
        )
    }
}

public enum MediaQueueAutomaticExecutionOutcome: Equatable, Sendable {
    case verifiedSuccess
    case failed
    case cancelled
    case needsReview
}

public struct MediaQueueAdmissionCycleReport: Equatable, Sendable {
    public let admittedJobIDs: [UUID]
    public let needsReviewJobIDs: [UUID]
    public let outcomes: [UUID: MediaQueueAutomaticExecutionOutcome]
    public let snapshot: MediaQueueSnapshot

    public init(
        admittedJobIDs: [UUID],
        needsReviewJobIDs: [UUID],
        outcomes: [UUID: MediaQueueAutomaticExecutionOutcome],
        snapshot: MediaQueueSnapshot
    ) {
        self.admittedJobIDs = admittedJobIDs
        self.needsReviewJobIDs = needsReviewJobIDs
        self.outcomes = outcomes
        self.snapshot = snapshot
    }
}

public actor MediaQueueAdmissionCoordinator {
    public typealias SupportCheck = @Sendable (MediaQueueJob) -> Bool
    public typealias Executor =
        @Sendable (MediaQueueAdmission) async throws -> MediaQueueAutomaticExecutionOutcome

    private let store: any JobQueueManaging
    private let scheduler: MediaQueueScheduler
    private let resolver: MediaQueueAdmissionResolver

    public init(
        store: any JobQueueManaging,
        scheduler: MediaQueueScheduler = MediaQueueScheduler(),
        resolver: MediaQueueAdmissionResolver = MediaQueueAdmissionResolver()
    ) {
        self.store = store
        self.scheduler = scheduler
        self.resolver = resolver
    }

    public func runCycle(
        environment: MediaQueueSchedulingEnvironment,
        supports: @escaping SupportCheck,
        execute: @escaping Executor
    ) async throws -> MediaQueueAdmissionCycleReport {
        var admissions = [MediaQueueAdmission]()
        var needsReviewJobIDs = [UUID]()

        while true {
            let currentSnapshot = try await store.load()
            let selectedIDs = scheduler.jobsToStart(
                in: currentSnapshot,
                environment: environment
            )
            guard !selectedIDs.isEmpty else { break }
            let jobsByID = Dictionary(
                uniqueKeysWithValues: currentSnapshot.jobs.map { ($0.id, $0) }
            )
            for jobID in selectedIDs {
                guard let job = jobsByID[jobID] else { continue }
                guard supports(job) else {
                    _ = try await store.transition(
                        jobID: jobID,
                        to: .needsReview,
                        at: Date(),
                        reason: .automaticExecutionUnavailable
                    )
                    needsReviewJobIDs.append(jobID)
                    continue
                }
                do {
                    let admission = try resolver.resolve(job)
                    _ = try await store.transition(
                        jobID: jobID,
                        to: .running,
                        at: Date(),
                        reason: nil
                    )
                    admissions.append(admission)
                } catch is MediaQueueAdmissionResolutionError {
                    _ = try await store.transition(
                        jobID: jobID,
                        to: .needsReview,
                        at: Date(),
                        reason: .staleReview
                    )
                    needsReviewJobIDs.append(jobID)
                }
            }
        }

        var outcomes = [UUID: MediaQueueAutomaticExecutionOutcome]()
        try await withThrowingTaskGroup(
            of: (UUID, MediaQueueAutomaticExecutionOutcome).self
        ) { group in
            for admission in admissions {
                group.addTask {
                    let outcome = await Self.executeWithScopedAccess(
                        admission,
                        using: execute
                    )
                    return (admission.job.id, outcome)
                }
            }
            for try await (jobID, outcome) in group {
                outcomes[jobID] = outcome
                try await record(outcome, for: jobID)
            }
        }

        return MediaQueueAdmissionCycleReport(
            admittedJobIDs: admissions.map(\.job.id),
            needsReviewJobIDs: needsReviewJobIDs,
            outcomes: outcomes,
            snapshot: try await store.load()
        )
    }

    private func record(
        _ outcome: MediaQueueAutomaticExecutionOutcome,
        for jobID: UUID
    ) async throws {
        guard
            let state = try await store.load().jobs.first(where: { $0.id == jobID })?.state,
            state == .running || state == .cancelling
        else { return }

        switch outcome {
        case .verifiedSuccess:
            _ = try await store.transition(
                jobID: jobID,
                to: .succeeded,
                at: Date(),
                reason: nil
            )
        case .failed:
            _ = try await store.transition(
                jobID: jobID,
                to: .failed,
                at: Date(),
                reason: .executionFailed
            )
        case .cancelled:
            if state == .running {
                _ = try await store.transition(
                    jobID: jobID,
                    to: .cancelling,
                    at: Date(),
                    reason: .userAction
                )
            }
            _ = try await store.transition(
                jobID: jobID,
                to: .cancelled,
                at: Date(),
                reason: .userAction
            )
        case .needsReview:
            _ = try await store.transition(
                jobID: jobID,
                to: .needsReview,
                at: Date(),
                reason: .staleReview
            )
        }
    }

    private nonisolated static func executeWithScopedAccess(
        _ admission: MediaQueueAdmission,
        using execute: Executor
    ) async -> MediaQueueAutomaticExecutionOutcome {
        let urls = admission.inputURLs + [admission.destinationDirectoryURL]
        let uniqueURLs = Array(Set(urls.map(\.standardizedFileURL)))
        let accesses = uniqueURLs.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer {
            for (url, accessed) in accesses where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard isStillSafeToExecute(admission) else { return .needsReview }
        do {
            try Task.checkCancellation()
            return try await execute(admission)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
    }

    private nonisolated static func isStillSafeToExecute(
        _ admission: MediaQueueAdmission
    ) -> Bool {
        guard admission.inputURLs.count == admission.job.inputs.count else { return false }
        for (url, reference) in zip(admission.inputURLs, admission.job.inputs) {
            guard let reviewedRevision = reference.reviewedRevision,
                let currentRevision = try? MediaFileRevisionReader().read(url)
                    .atMillisecondPrecision,
                currentRevision == reviewedRevision
            else {
                return false
            }
        }
        guard
            let values = try? admission.destinationDirectoryURL.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey,
            ]),
            values.isDirectory == true,
            values.isSymbolicLink != true,
            MediaQueueOutputFilenamePolicy.outputURL(
                filename: admission.job.outputDisplayName,
                in: admission.destinationDirectoryURL
            ) == admission.outputURL,
            !FileManager.default.fileExists(atPath: admission.outputURL.path)
        else {
            return false
        }
        return true
    }
}
