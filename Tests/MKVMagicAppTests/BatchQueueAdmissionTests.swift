import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagic

final class BatchQueueAdmissionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("batch-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    private func decision(includedIDs: Set<UUID>? = nil) throws -> BatchReviewDecision {
        return BatchReviewDecision(
            commonDestinationDirectory: directory, sourceDisposition: .keepOriginal,
            directoryAccess: try XCTUnwrap(
                OutputDirectorySecurityScope(
                    directoryURL: directory, startAccessing: { _ in true }, stopAccessing: { _ in })
            ),
            includedItemIDs: includedIDs)
    }

    @MainActor
    func testAdmissionHonorsExclusionsReservesNamesAndReportsEachFailure() async throws {
        let ids = (0..<4).map { _ in UUID() }
        var destinations = [URL]()
        let requests = ids.enumerated().map { index, id in
            BatchQueueRequest(
                id: id, sourceURL: URL(fileURLWithPath: "/Media/Item \(index).srt"),
                outputFilename: "Same.srt",
                enqueue: { url in
                    if index == 1 { throw CocoaError(.fileWriteNoPermission) }
                    destinations.append(url)
                })
        }
        var completed = [Int]()
        let result = await BatchQueueAdmission.enqueue(
            requests, decision: try decision(includedIDs: Set(ids.prefix(3)))
        ) { count, _ in completed.append(count) }
        XCTAssertEqual(result.queuedCount, 2)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.failures[0].contains("Item 1.srt"))
        XCTAssertEqual(result.unattemptedCount, 0)
        XCTAssertEqual(Set(destinations).count, 2)
        XCTAssertEqual(completed.last, 3)
    }

    @MainActor
    func testCancellingAdmissionKeepsCommittedJobsAndDoesNotAttemptRemainingItems() async throws {
        var calls = 0
        let requests = (0..<3).map { _ in
            BatchQueueRequest(
                id: UUID(), sourceURL: URL(fileURLWithPath: "/Media/Source.srt"),
                outputFilename: "Output.srt",
                enqueue: { _ in
                    calls += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                })
        }
        let decision = try decision()
        let task = Task {
            await BatchQueueAdmission.enqueue(requests, decision: decision) { _, _ in }
        }
        let result = await task.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(result.queuedCount, 1)
        XCTAssertEqual(result.unattemptedCount, 2)
        XCTAssertTrue(result.failures.isEmpty)
    }
}
