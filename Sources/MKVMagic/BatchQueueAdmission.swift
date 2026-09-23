import Foundation

@MainActor
struct BatchQueueRequest {
    let id: UUID
    let sourceURL: URL
    let outputFilename: String
    let enqueue: (URL) async throws -> Void
}

struct BatchQueueAdmissionResult {
    let queuedCount: Int
    let unattemptedCount: Int
    let failures: [String]

    var summary: String {
        "Batch queued: \(queuedCount) ready, \(failures.count) failed, \(unattemptedCount) not queued."
            + (failures.isEmpty ? "" : "\n" + failures.joined(separator: "\n"))
    }
}

/// Queue preparation only. The existing durable scheduler owns actual execution.
enum BatchQueueAdmission {
    @MainActor
    static func enqueue(
        _ requests: [BatchQueueRequest], decision: BatchReviewDecision,
        onProgress: (Int, String) -> Void
    ) async -> BatchQueueAdmissionResult {
        let included = requests.filter { decision.includes($0.id) }
        var queued = 0
        var failures = [String]()
        var reservedPaths = Set<String>()
        defer { _ = decision.directoryAccess }
        for (index, request) in included.enumerated() {
            do {
                try Task.checkCancellation()
                onProgress(
                    index,
                    "Queueing \(index + 1) of \(included.count): \(request.sourceURL.lastPathComponent)"
                )
                let destination = try decision.destination(
                    for: request.id, filename: request.outputFilename, reservedPaths: reservedPaths)
                reservedPaths.insert(destination.path)
                try await request.enqueue(destination)
                queued += 1
            } catch is CancellationError {
                break
            } catch {
                failures.append(
                    UserFacingErrorPresentation.message(
                        failure: "Could not queue \(request.sourceURL.lastPathComponent).",
                        recovery:
                            "This item was not queued; review it after checking its source and destination.",
                        error: error))
            }
            onProgress(index + 1, "Prepared \(index + 1) of \(included.count) queue jobs.")
        }
        return BatchQueueAdmissionResult(
            queuedCount: queued, unattemptedCount: included.count - queued - failures.count,
            failures: failures)
    }
}
