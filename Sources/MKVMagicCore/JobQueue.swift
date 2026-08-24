import Foundation

public enum MediaQueueJobState: String, Codable, CaseIterable, Hashable, Sendable {
    case waiting
    case held
    case running
    case cancelling
    case needsReview
    case succeeded
    case failed
    case cancelled

    public var isFinished: Bool {
        switch self {
        case .succeeded, .cancelled: true
        default: false
        }
    }

    public var isPending: Bool {
        switch self {
        case .waiting, .held: true
        default: false
        }
    }
}

public enum MediaQueueResourceClass: String, Codable, CaseIterable, Hashable, Sendable {
    case lightweight
    case audioHeavy
    case videoHeavy

    public init(impact: PlanImpact) {
        if impact.videoEncodeCount > 0 {
            self = .videoHeavy
        } else if impact.audioEncodeCount > 0 {
            self = .audioHeavy
        } else {
            self = .lightweight
        }
    }
}

public enum MediaQueueEventReason: String, Codable, CaseIterable, Hashable, Sendable {
    case userAction
    case executionFailed
    case interruptedBeforeVerification
    case staleReview
    case automaticExecutionUnavailable
}

public enum MediaQueueOutputFilenamePolicy {
    public static func isSafe(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= 1_024
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\0")
    }

    public static func outputURL(
        filename: String,
        in rawDirectoryURL: URL
    ) -> URL? {
        guard isSafe(filename) else { return nil }
        let directoryURL = rawDirectoryURL.standardizedFileURL
        guard directoryURL.isFileURL, directoryURL.path.hasPrefix("/") else { return nil }
        let outputURL = directoryURL.appendingPathComponent(filename).standardizedFileURL
        guard outputURL.deletingLastPathComponent() == directoryURL else { return nil }
        return outputURL
    }
}

public struct MediaQueueFileReference: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let securityScopedBookmark: Data
    public let reviewedRevision: MediaQueueFileRevision?

    public init(
        id: UUID = UUID(),
        displayName: String,
        securityScopedBookmark: Data,
        reviewedRevision: MediaQueueFileRevision? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.securityScopedBookmark = securityScopedBookmark
        self.reviewedRevision = reviewedRevision
    }
}

public enum MediaQueueWorkflowIntent: Codable, Hashable, Sendable {
    case saved(SavedWorkflow)
    case builtIn(id: UUID, name: String)

    public var id: UUID {
        switch self {
        case .saved(let workflow): workflow.id
        case .builtIn(let id, _): id
        }
    }

    public var name: String {
        switch self {
        case .saved(let workflow): workflow.name
        case .builtIn(_, let name): name
        }
    }
}

public enum MediaQueueSourceDisposition: String, Codable, CaseIterable, Hashable, Sendable {
    case keepOriginal
    case trashAfterVerifiedSuccess
}

public enum MediaQueueSourceDispositionOutcome: String, Codable, CaseIterable, Hashable, Sendable {
    case applied
    case failed
    case uncertain
}

public struct MediaQueueSourceDispositionResult: Codable, Hashable, Sendable {
    public let outcome: MediaQueueSourceDispositionOutcome
    public let timestamp: Date

    public init(outcome: MediaQueueSourceDispositionOutcome, timestamp: Date) {
        self.outcome = outcome
        self.timestamp = timestamp
    }
}

public struct MediaQueueJobEvent: Codable, Hashable, Sendable {
    public let state: MediaQueueJobState
    public let timestamp: Date
    public let reason: MediaQueueEventReason?

    public init(
        state: MediaQueueJobState,
        timestamp: Date,
        reason: MediaQueueEventReason? = nil
    ) {
        self.state = state
        self.timestamp = timestamp
        self.reason = reason
    }
}

public enum MediaQueueTransitionError: Error, Equatable, Sendable {
    case finished(MediaQueueJobState)
    case invalidTransition(from: MediaQueueJobState, to: MediaQueueJobState)
    case timestampMovedBackward
    case missingFailureReason
    case unexpectedReason
    case replanRequiresReviewState
    case sourceDispositionNotRequested
    case sourceDispositionRequiresVerifiedSuccess
    case sourceDispositionAlreadyRecorded
}

public struct MediaQueueJob: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let createdAt: Date
    public private(set) var workflow: MediaQueueWorkflowIntent
    public private(set) var inputs: [MediaQueueFileReference]
    public private(set) var destinationDirectory: MediaQueueFileReference
    public private(set) var outputDisplayName: String
    public private(set) var sourceDisposition: MediaQueueSourceDisposition
    public private(set) var sourceDispositionResult: MediaQueueSourceDispositionResult?
    public private(set) var reviewedPlan: ExecutionPlan
    public private(set) var resourceClass: MediaQueueResourceClass
    public private(set) var events: [MediaQueueJobEvent]
    public private(set) var attemptCount: Int

    public init(
        schemaVersion: Int = MediaQueueJob.currentSchemaVersion,
        id: UUID = UUID(),
        createdAt: Date,
        workflow: MediaQueueWorkflowIntent,
        inputs: [MediaQueueFileReference],
        destinationDirectory: MediaQueueFileReference,
        outputDisplayName: String,
        sourceDisposition: MediaQueueSourceDisposition = .keepOriginal,
        sourceDispositionResult: MediaQueueSourceDispositionResult? = nil,
        reviewedPlan: ExecutionPlan,
        resourceClass: MediaQueueResourceClass? = nil,
        events: [MediaQueueJobEvent]? = nil,
        attemptCount: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.workflow = workflow
        self.inputs = inputs
        self.destinationDirectory = destinationDirectory
        self.outputDisplayName = outputDisplayName
        self.sourceDisposition = sourceDisposition
        self.sourceDispositionResult = sourceDispositionResult
        self.reviewedPlan = reviewedPlan
        self.resourceClass = resourceClass ?? MediaQueueResourceClass(impact: reviewedPlan.impact)
        self.events = events ?? [MediaQueueJobEvent(state: .waiting, timestamp: createdAt)]
        self.attemptCount = attemptCount
    }

    public var state: MediaQueueJobState {
        events.last?.state ?? .waiting
    }

    public var updatedAt: Date {
        max(events.last?.timestamp ?? createdAt, sourceDispositionResult?.timestamp ?? createdAt)
    }

    public mutating func transition(
        to nextState: MediaQueueJobState,
        at timestamp: Date,
        reason: MediaQueueEventReason? = nil
    ) throws {
        let currentState = state
        guard !currentState.isFinished else {
            throw MediaQueueTransitionError.finished(currentState)
        }
        guard timestamp >= updatedAt else {
            throw MediaQueueTransitionError.timestampMovedBackward
        }
        guard Self.allowedTransitions[currentState, default: []].contains(nextState) else {
            throw MediaQueueTransitionError.invalidTransition(from: currentState, to: nextState)
        }
        if nextState == .failed, reason != .executionFailed {
            throw MediaQueueTransitionError.missingFailureReason
        }
        if nextState != .failed, reason == .executionFailed {
            throw MediaQueueTransitionError.unexpectedReason
        }
        if nextState == .running { attemptCount += 1 }
        events.append(MediaQueueJobEvent(state: nextState, timestamp: timestamp, reason: reason))
    }

    @discardableResult
    public mutating func recoverAfterInterruption(at timestamp: Date) throws -> Bool {
        guard state == .running || state == .cancelling else { return false }
        try transition(
            to: .needsReview,
            at: timestamp,
            reason: .interruptedBeforeVerification
        )
        return true
    }

    public mutating func approveReplan(
        workflow: MediaQueueWorkflowIntent,
        inputs: [MediaQueueFileReference],
        destinationDirectory: MediaQueueFileReference,
        outputDisplayName: String,
        sourceDisposition: MediaQueueSourceDisposition,
        reviewedPlan: ExecutionPlan,
        at timestamp: Date
    ) throws {
        guard state == .failed || state == .needsReview else {
            throw MediaQueueTransitionError.replanRequiresReviewState
        }
        guard timestamp >= updatedAt else {
            throw MediaQueueTransitionError.timestampMovedBackward
        }
        var replacement = self
        replacement.workflow = workflow
        replacement.inputs = inputs
        replacement.destinationDirectory = destinationDirectory
        replacement.outputDisplayName = outputDisplayName
        replacement.sourceDisposition = sourceDisposition
        replacement.sourceDispositionResult = nil
        replacement.reviewedPlan = reviewedPlan
        replacement.resourceClass = MediaQueueResourceClass(impact: reviewedPlan.impact)
        replacement.events.append(
            MediaQueueJobEvent(state: .waiting, timestamp: timestamp, reason: .userAction)
        )
        self = replacement
    }

    public mutating func recordSourceDisposition(
        _ outcome: MediaQueueSourceDispositionOutcome,
        at timestamp: Date
    ) throws {
        guard sourceDisposition == .trashAfterVerifiedSuccess else {
            throw MediaQueueTransitionError.sourceDispositionNotRequested
        }
        guard state == .succeeded else {
            throw MediaQueueTransitionError.sourceDispositionRequiresVerifiedSuccess
        }
        guard sourceDispositionResult == nil else {
            throw MediaQueueTransitionError.sourceDispositionAlreadyRecorded
        }
        guard timestamp >= updatedAt else {
            throw MediaQueueTransitionError.timestampMovedBackward
        }
        sourceDispositionResult = MediaQueueSourceDispositionResult(
            outcome: outcome,
            timestamp: timestamp
        )
    }

    private static let allowedTransitions: [MediaQueueJobState: Set<MediaQueueJobState>] = [
        .waiting: [.held, .running, .cancelled, .needsReview],
        .held: [.waiting, .cancelled, .needsReview],
        .running: [.cancelling, .succeeded, .failed, .needsReview],
        // Cancellation is cooperative. A job may cross its verified commit boundary
        // before the runner observes cancellation; that truthful outcome is success.
        .cancelling: [.cancelled, .succeeded, .failed, .needsReview],
        .needsReview: [.cancelled],
        .failed: [.cancelled],
    ]
}

public struct MediaQueueSnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public private(set) var isPaused: Bool
    public private(set) var jobs: [MediaQueueJob]
    public private(set) var updatedAt: Date

    public init(
        schemaVersion: Int = MediaQueueSnapshot.currentSchemaVersion,
        isPaused: Bool = false,
        jobs: [MediaQueueJob] = [],
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.isPaused = isPaused
        self.jobs = jobs
        self.updatedAt = updatedAt
    }

    public mutating func setPaused(_ paused: Bool, at timestamp: Date) throws {
        let timestamp = try normalizedTimestamp(timestamp)
        isPaused = paused
        updatedAt = timestamp
    }

    public mutating func append(_ job: MediaQueueJob, at timestamp: Date) throws {
        let timestamp = try normalizedTimestamp(timestamp)
        guard !jobs.contains(where: { $0.id == job.id }) else {
            throw MediaQueueMutationError.duplicateJob
        }
        jobs.append(job)
        updatedAt = timestamp
    }

    public mutating func transition(
        jobID: UUID,
        to state: MediaQueueJobState,
        at timestamp: Date,
        reason: MediaQueueEventReason? = nil
    ) throws {
        let timestamp = try normalizedTimestamp(timestamp)
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            throw MediaQueueMutationError.jobNotFound
        }
        try jobs[index].transition(to: state, at: timestamp, reason: reason)
        updatedAt = timestamp
    }

    public mutating func approveReplan(
        jobID: UUID,
        workflow: MediaQueueWorkflowIntent,
        inputs: [MediaQueueFileReference],
        destinationDirectory: MediaQueueFileReference,
        outputDisplayName: String,
        sourceDisposition: MediaQueueSourceDisposition,
        reviewedPlan: ExecutionPlan,
        at timestamp: Date
    ) throws {
        let timestamp = try normalizedTimestamp(timestamp)
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            throw MediaQueueMutationError.jobNotFound
        }
        try jobs[index].approveReplan(
            workflow: workflow,
            inputs: inputs,
            destinationDirectory: destinationDirectory,
            outputDisplayName: outputDisplayName,
            sourceDisposition: sourceDisposition,
            reviewedPlan: reviewedPlan,
            at: timestamp
        )
        updatedAt = timestamp
    }

    public mutating func recordSourceDisposition(
        jobID: UUID,
        outcome: MediaQueueSourceDispositionOutcome,
        at timestamp: Date
    ) throws {
        let timestamp = try normalizedTimestamp(timestamp)
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            throw MediaQueueMutationError.jobNotFound
        }
        try jobs[index].recordSourceDisposition(outcome, at: timestamp)
        updatedAt = timestamp
    }

    public mutating func reorderPending(_ orderedIDs: [UUID], at timestamp: Date) throws {
        let timestamp = try normalizedTimestamp(timestamp)
        let pending = jobs.filter { $0.state.isPending }
        guard orderedIDs.count == pending.count,
            Set(orderedIDs).count == orderedIDs.count,
            Set(orderedIDs) == Set(pending.map(\.id))
        else {
            throw MediaQueueMutationError.invalidPendingOrder
        }
        let byID = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0) })
        jobs.removeAll { $0.state.isPending }
        jobs.append(contentsOf: orderedIDs.compactMap { byID[$0] })
        updatedAt = timestamp
    }

    @discardableResult
    public mutating func recoverInterruptedJobs(at timestamp: Date) throws -> Int {
        let timestamp = try normalizedTimestamp(timestamp)
        var recovered = 0
        for index in jobs.indices {
            if try jobs[index].recoverAfterInterruption(at: timestamp) { recovered += 1 }
        }
        if recovered > 0 { updatedAt = timestamp }
        return recovered
    }

    private func normalizedTimestamp(_ timestamp: Date) throws -> Date {
        if timestamp >= updatedAt { return timestamp }
        // JSON date round trips and wall-clock reads can differ by a fraction of
        // a millisecond. Clamp only that serialization-sized skew; larger
        // rollback remains a hard failure.
        guard updatedAt.timeIntervalSince(timestamp) <= 0.001 else {
            throw MediaQueueMutationError.timestampMovedBackward
        }
        return updatedAt
    }
}

public enum MediaQueueMutationError: Error, Equatable, Sendable {
    case duplicateJob
    case jobNotFound
    case invalidPendingOrder
    case timestampMovedBackward
}

public enum MediaQueueThermalPressure: Int, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct MediaQueueSchedulingEnvironment: Equatable, Sendable {
    public let isOnBattery: Bool
    public let thermalPressure: MediaQueueThermalPressure

    public init(isOnBattery: Bool, thermalPressure: MediaQueueThermalPressure) {
        self.isOnBattery = isOnBattery
        self.thermalPressure = thermalPressure
    }
}

public struct MediaQueueScheduler: Sendable {
    public let maximumLightweightJobs: Int
    public let maximumAudioHeavyJobs: Int
    public let maximumVideoHeavyJobs: Int

    public init(
        maximumLightweightJobs: Int = 3,
        maximumAudioHeavyJobs: Int = 2,
        maximumVideoHeavyJobs: Int = 1
    ) {
        self.maximumLightweightJobs = max(1, maximumLightweightJobs)
        self.maximumAudioHeavyJobs = max(1, maximumAudioHeavyJobs)
        self.maximumVideoHeavyJobs = max(1, maximumVideoHeavyJobs)
    }

    public func jobsToStart(
        in snapshot: MediaQueueSnapshot,
        environment: MediaQueueSchedulingEnvironment
    ) -> [UUID] {
        guard !snapshot.isPaused, environment.thermalPressure < .serious else { return [] }
        let running = snapshot.jobs.filter { $0.state == .running || $0.state == .cancelling }
        var lightweightSlots = max(
            0,
            (environment.isOnBattery ? 1 : maximumLightweightJobs)
                - running.filter { $0.resourceClass == .lightweight }.count
        )
        var audioSlots = max(
            0,
            (environment.isOnBattery ? 0 : maximumAudioHeavyJobs)
                - running.filter { $0.resourceClass == .audioHeavy }.count
        )
        var videoSlots = max(
            0,
            (environment.isOnBattery ? 0 : maximumVideoHeavyJobs)
                - running.filter { $0.resourceClass == .videoHeavy }.count
        )
        var selected = [UUID]()
        for job in snapshot.jobs where job.state == .waiting {
            switch job.resourceClass {
            case .lightweight where lightweightSlots > 0:
                selected.append(job.id)
                lightweightSlots -= 1
            case .audioHeavy where audioSlots > 0:
                selected.append(job.id)
                audioSlots -= 1
            case .videoHeavy where videoSlots > 0:
                selected.append(job.id)
                videoSlots -= 1
            default:
                continue
            }
        }
        return selected
    }
}
