import Foundation
import MKVMagicCore

public enum JobQueueStoreError: Error, Equatable, Sendable {
    case unsafePath
    case oversizedDocument
    case tooManyJobs
    case duplicateJob
    case jobNotFound
    case unexpectedFields
    case unsupportedSchema
    case malformedQueue
}

public protocol JobQueuePersisting: Sendable {
    func load() async throws -> MediaQueueSnapshot
    func save(_ snapshot: MediaQueueSnapshot) async throws
}

public protocol JobQueueManaging: JobQueuePersisting {
    @discardableResult
    func append(_ job: MediaQueueJob, at timestamp: Date) async throws -> MediaQueueSnapshot
    @discardableResult
    func setPaused(_ paused: Bool, at timestamp: Date) async throws -> MediaQueueSnapshot
    @discardableResult
    func transition(
        jobID: UUID,
        to state: MediaQueueJobState,
        at timestamp: Date,
        reason: MediaQueueEventReason?
    ) async throws -> MediaQueueSnapshot
    @discardableResult
    func approveReplan(
        jobID: UUID,
        workflow: MediaQueueWorkflowIntent,
        inputs: [MediaQueueFileReference],
        destinationDirectory: MediaQueueFileReference,
        outputDisplayName: String,
        sourceDisposition: MediaQueueSourceDisposition,
        reviewedPlan: ExecutionPlan,
        at timestamp: Date
    ) async throws -> MediaQueueSnapshot
    @discardableResult
    func recordSourceDisposition(
        jobID: UUID,
        outcome: MediaQueueSourceDispositionOutcome,
        at timestamp: Date
    ) async throws -> MediaQueueSnapshot
    @discardableResult
    func reorderPending(_ orderedIDs: [UUID], at timestamp: Date) async throws
        -> MediaQueueSnapshot
    @discardableResult
    func recoverInterruptedJobs(at timestamp: Date) async throws -> MediaQueueSnapshot
}

public actor JSONJobQueueStore: JobQueueManaging {
    public static let currentSchema = "mkv-magic-job-queue-v1"
    public static let maximumJobs = 1_000
    public static let maximumDocumentBytes = 33_554_432
    public static let maximumBookmarkBytes = 262_144
    public static let maximumDisplayNameBytes = 1_024

    private let fileURL: URL

    public init(fileURL: URL) throws {
        let standardized = fileURL.standardizedFileURL
        guard standardized.isFileURL,
            standardized.path.hasPrefix("/"),
            !standardized.path.hasSuffix("/"),
            standardized.lastPathComponent == "job-queue.json"
        else {
            throw JobQueueStoreError.unsafePath
        }
        self.fileURL = standardized
    }

    public func load() async throws -> MediaQueueSnapshot {
        try readSnapshot()
    }

    public func save(_ snapshot: MediaQueueSnapshot) async throws {
        try writeSnapshot(snapshot)
    }

    @discardableResult
    public func append(_ job: MediaQueueJob, at timestamp: Date) async throws
        -> MediaQueueSnapshot
    {
        var snapshot = try readSnapshot(defaultTimestamp: timestamp)
        do {
            try snapshot.append(job, at: timestamp)
        } catch MediaQueueMutationError.duplicateJob {
            throw JobQueueStoreError.duplicateJob
        }
        try writeSnapshot(snapshot)
        return snapshot
    }

    @discardableResult
    public func setPaused(_ paused: Bool, at timestamp: Date) async throws -> MediaQueueSnapshot {
        var snapshot = try readSnapshot(defaultTimestamp: timestamp)
        try snapshot.setPaused(paused, at: timestamp)
        try writeSnapshot(snapshot)
        return snapshot
    }

    @discardableResult
    public func transition(
        jobID: UUID,
        to state: MediaQueueJobState,
        at timestamp: Date,
        reason: MediaQueueEventReason? = nil
    ) async throws -> MediaQueueSnapshot {
        var snapshot = try readSnapshot(defaultTimestamp: timestamp)
        do {
            try snapshot.transition(
                jobID: jobID,
                to: state,
                at: timestamp,
                reason: reason
            )
        } catch MediaQueueMutationError.jobNotFound {
            throw JobQueueStoreError.jobNotFound
        }
        try writeSnapshot(snapshot)
        return snapshot
    }

    @discardableResult
    public func approveReplan(
        jobID: UUID,
        workflow: MediaQueueWorkflowIntent,
        inputs: [MediaQueueFileReference],
        destinationDirectory: MediaQueueFileReference,
        outputDisplayName: String,
        sourceDisposition: MediaQueueSourceDisposition,
        reviewedPlan: ExecutionPlan,
        at timestamp: Date
    ) async throws -> MediaQueueSnapshot {
        var snapshot = try readSnapshot(defaultTimestamp: timestamp)
        do {
            try snapshot.approveReplan(
                jobID: jobID,
                workflow: workflow,
                inputs: inputs,
                destinationDirectory: destinationDirectory,
                outputDisplayName: outputDisplayName,
                sourceDisposition: sourceDisposition,
                reviewedPlan: reviewedPlan,
                at: timestamp
            )
        } catch MediaQueueMutationError.jobNotFound {
            throw JobQueueStoreError.jobNotFound
        }
        try writeSnapshot(snapshot)
        return snapshot
    }

    @discardableResult
    public func recordSourceDisposition(
        jobID: UUID,
        outcome: MediaQueueSourceDispositionOutcome,
        at timestamp: Date
    ) async throws -> MediaQueueSnapshot {
        var snapshot = try readSnapshot(defaultTimestamp: timestamp)
        do {
            try snapshot.recordSourceDisposition(
                jobID: jobID,
                outcome: outcome,
                at: timestamp
            )
        } catch MediaQueueMutationError.jobNotFound {
            throw JobQueueStoreError.jobNotFound
        }
        try writeSnapshot(snapshot)
        return snapshot
    }

    @discardableResult
    public func reorderPending(_ orderedIDs: [UUID], at timestamp: Date) async throws
        -> MediaQueueSnapshot
    {
        var snapshot = try readSnapshot(defaultTimestamp: timestamp)
        try snapshot.reorderPending(orderedIDs, at: timestamp)
        try writeSnapshot(snapshot)
        return snapshot
    }

    @discardableResult
    public func recoverInterruptedJobs(at timestamp: Date) async throws -> MediaQueueSnapshot {
        var snapshot = try readSnapshot(defaultTimestamp: timestamp)
        _ = try snapshot.recoverInterruptedJobs(at: timestamp)
        try writeSnapshot(snapshot)
        return snapshot
    }

    private func readSnapshot(defaultTimestamp: Date = Date(timeIntervalSince1970: 0)) throws
        -> MediaQueueSnapshot
    {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return MediaQueueSnapshot(updatedAt: defaultTimestamp)
        }
        guard !isSymbolicLink(fileURL) else {
            throw JobQueueStoreError.unsafePath
        }
        let values = try fileURL.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw JobQueueStoreError.unsafePath
        }
        guard values.fileSize ?? 0 <= Self.maximumDocumentBytes else {
            throw JobQueueStoreError.oversizedDocument
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard let topLevel = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(topLevel.keys) == Set(["schema", "snapshot"])
        else {
            throw JobQueueStoreError.unexpectedFields
        }
        let document = try decoder.decode(JobQueueDocument.self, from: data)
        guard document.schema == Self.currentSchema else {
            throw JobQueueStoreError.unsupportedSchema
        }
        try validate(document.snapshot)
        return document.snapshot
    }

    private func writeSnapshot(_ snapshot: MediaQueueSnapshot) throws {
        try validate(snapshot)
        let parent = fileURL.deletingLastPathComponent()
        guard !isSymbolicLink(parent) else {
            throw JobQueueStoreError.unsafePath
        }
        let parentValues = try parent.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard parentValues.isDirectory == true, parentValues.isSymbolicLink != true else {
            throw JobQueueStoreError.unsafePath
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard !isSymbolicLink(fileURL) else {
                throw JobQueueStoreError.unsafePath
            }
            let values = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw JobQueueStoreError.unsafePath
            }
        }
        let data = try encoder.encode(
            JobQueueDocument(schema: Self.currentSchema, snapshot: snapshot)
        )
        guard data.count <= Self.maximumDocumentBytes else {
            throw JobQueueStoreError.oversizedDocument
        }
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private func validate(_ snapshot: MediaQueueSnapshot) throws {
        guard snapshot.schemaVersion == MediaQueueSnapshot.currentSchemaVersion else {
            throw JobQueueStoreError.unsupportedSchema
        }
        guard snapshot.jobs.count <= Self.maximumJobs else {
            throw JobQueueStoreError.tooManyJobs
        }
        var jobIDs = Set<UUID>()
        for job in snapshot.jobs {
            guard job.schemaVersion == MediaQueueJob.currentSchemaVersion,
                jobIDs.insert(job.id).inserted,
                !job.inputs.isEmpty,
                isValidDisplayName(job.workflow.name),
                isValidOutputFilename(job.outputDisplayName),
                job.events.first?.state == .waiting,
                job.events.first?.timestamp == job.createdAt,
                job.attemptCount >= 0,
                job.reviewedPlan.impact.videoEncodeCount >= 0,
                job.reviewedPlan.impact.audioEncodeCount >= 0,
                !job.reviewedPlan.impact.changesSourceBeforeVerification,
                job.resourceClass == MediaQueueResourceClass(impact: job.reviewedPlan.impact)
            else {
                throw JobQueueStoreError.malformedQueue
            }
            let references = job.inputs + [job.destinationDirectory]
            var referenceIDs = Set<UUID>()
            guard
                job.destinationDirectory.reviewedRevision == nil,
                references.allSatisfy({ reference in
                    referenceIDs.insert(reference.id).inserted
                        && isValidDisplayName(reference.displayName)
                        && !reference.securityScopedBookmark.isEmpty
                        && reference.securityScopedBookmark.count <= Self.maximumBookmarkBytes
                        && isValidRevision(reference.reviewedRevision)
                })
            else {
                throw JobQueueStoreError.malformedQueue
            }
            var replay = MediaQueueJob(
                schemaVersion: job.schemaVersion,
                id: job.id,
                createdAt: job.createdAt,
                workflow: job.workflow,
                inputs: job.inputs,
                destinationDirectory: job.destinationDirectory,
                outputDisplayName: job.outputDisplayName,
                sourceDisposition: job.sourceDisposition,
                reviewedPlan: job.reviewedPlan,
                resourceClass: job.resourceClass
            )
            do {
                for event in job.events.dropFirst() {
                    if event.state == .waiting,
                        replay.state == .failed || replay.state == .needsReview
                    {
                        guard event.reason == .userAction else {
                            throw JobQueueStoreError.malformedQueue
                        }
                        try replay.approveReplan(
                            workflow: job.workflow,
                            inputs: job.inputs,
                            destinationDirectory: job.destinationDirectory,
                            outputDisplayName: job.outputDisplayName,
                            sourceDisposition: job.sourceDisposition,
                            reviewedPlan: job.reviewedPlan,
                            at: event.timestamp
                        )
                    } else {
                        try replay.transition(
                            to: event.state,
                            at: event.timestamp,
                            reason: event.reason
                        )
                    }
                }
                if let result = job.sourceDispositionResult {
                    try replay.recordSourceDisposition(
                        result.outcome,
                        at: result.timestamp
                    )
                }
            } catch {
                throw JobQueueStoreError.malformedQueue
            }
            guard replay.state == job.state,
                replay.updatedAt == job.updatedAt,
                replay.attemptCount == job.attemptCount,
                replay.sourceDispositionResult == job.sourceDispositionResult,
                job.updatedAt <= snapshot.updatedAt
            else {
                throw JobQueueStoreError.malformedQueue
            }
            if case .savedWithExternalSubtitle = job.workflow,
                !MediaQueueAutomaticWorkflowPolicy.supports(job)
            {
                throw JobQueueStoreError.malformedQueue
            }
            if let workflow = job.workflow.savedWorkflow {
                do {
                    let migrated = try SavedWorkflowMigrator().migrate(workflow)
                    guard migrated == workflow else {
                        throw JobQueueStoreError.malformedQueue
                    }
                } catch {
                    throw JobQueueStoreError.malformedQueue
                }
            }
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func isValidDisplayName(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= Self.maximumDisplayNameBytes
            && !value.contains("\0")
    }

    private func isValidRevision(_ revision: MediaQueueFileRevision?) -> Bool {
        guard let revision else { return true }
        return revision.fileSize >= 0
            && revision.modificationDate.timeIntervalSinceReferenceDate.isFinite
    }

    private func isValidOutputFilename(_ value: String) -> Bool {
        MediaQueueOutputFilenamePolicy.isSafe(value)
    }
}

private struct JobQueueDocument: Codable {
    let schema: String
    let snapshot: MediaQueueSnapshot
}
