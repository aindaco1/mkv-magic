import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicSystem

final class JobHistoryStoreTests: XCTestCase {
    private var rootURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        fileURL = rootURL.appendingPathComponent("job-history.json")
    }

    override func tearDownWithError() throws {
        if rootURL != nil { try FileManager.default.removeItem(at: rootURL) }
    }

    func testRoundTripsVersionedJobHistoryWithPrivatePermissions() async throws {
        let store = try JSONJobHistoryStore(fileURL: fileURL)
        let record = makeRecord()

        try await store.save([record])
        let loaded = try await store.load()

        XCTAssertEqual(loaded, [record])
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testCreatesAndAtomicallyAdvancesPersistedJob() async throws {
        let store = try JSONJobHistoryStore(fileURL: fileURL)
        var record = makeRecord()
        for state in [MediaJobState.inspecting, .planned, .ready] {
            try record.transition(to: state, at: record.createdAt)
        }

        try await store.create(record)
        for state in [
            MediaJobState.running, .verifying, .committing, .succeeded,
        ] {
            _ = try await store.transition(
                jobID: record.id,
                to: state,
                at: record.createdAt,
                message: "Sanitized progress"
            )
        }

        let records = try await store.load()
        let loaded = try XCTUnwrap(records.first)
        XCTAssertEqual(loaded.state, .succeeded)
        XCTAssertEqual(loaded.events.last?.message, "Sanitized progress")
        XCTAssertFalse(String(data: try Data(contentsOf: fileURL), encoding: .utf8)!.contains("/"))
    }

    func testCreateRejectsDuplicateAndTransitionRejectsMissingRecord() async throws {
        let store = try JSONJobHistoryStore(fileURL: fileURL)
        let record = makeRecord()
        try await store.create(record)

        do {
            try await store.create(record)
            XCTFail("Expected duplicate refusal")
        } catch {
            XCTAssertEqual(error as? JobHistoryStoreError, .duplicateRecord)
        }

        do {
            _ = try await store.transition(
                jobID: UUID(),
                to: .inspecting,
                at: record.createdAt,
                message: nil
            )
            XCTFail("Expected missing-record refusal")
        } catch {
            XCTAssertEqual(error as? JobHistoryStoreError, .recordNotFound)
        }
    }

    func testUnexpectedTopLevelFieldsFailClosed() async throws {
        let store = try JSONJobHistoryStore(fileURL: fileURL)
        try Data(#"{"schema":"mkv-magic-job-history-v1","records":[],"extra":true}"#.utf8)
            .write(to: fileURL)

        do {
            _ = try await store.load()
            XCTFail("Expected unexpected fields")
        } catch {
            XCTAssertEqual(error as? JobHistoryStoreError, .unexpectedFields)
        }
    }

    func testSymlinkedHistoryFileFailsClosed() async throws {
        let target = rootURL.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: target)
        let store = try JSONJobHistoryStore(fileURL: fileURL)

        do {
            _ = try await store.load()
            XCTFail("Expected unsafe path")
        } catch {
            XCTAssertEqual(error as? JobHistoryStoreError, .unsafePath)
        }
    }

    func testDuplicateRecordIdentifiersFailClosed() async throws {
        let store = try JSONJobHistoryStore(fileURL: fileURL)
        let record = makeRecord()

        do {
            try await store.save([record, record])
            XCTFail("Expected malformed record")
        } catch {
            XCTAssertEqual(error as? JobHistoryStoreError, .malformedRecord)
        }
    }

    func testHistoryCannotSkipVerificationAndCommitStates() async throws {
        let store = try JSONJobHistoryStore(fileURL: fileURL)
        let base = makeRecord()
        let invalid = MediaJobRecord(
            id: base.id,
            createdAt: base.createdAt,
            workflowID: base.workflowID,
            workflowName: base.workflowName,
            inputs: base.inputs,
            events: [
                MediaJobEvent(state: .queued, timestamp: base.createdAt),
                MediaJobEvent(
                    state: .succeeded,
                    timestamp: base.createdAt.addingTimeInterval(1)
                ),
            ]
        )

        do {
            try await store.save([invalid])
            XCTFail("Expected malformed record")
        } catch {
            XCTAssertEqual(error as? JobHistoryStoreError, .malformedRecord)
        }
    }

    private func makeRecord() -> MediaJobRecord {
        MediaJobRecord(
            id: UUID(uuidString: "1944C3AF-11DA-431D-A4BD-F88E560A8729")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            workflowID: UUID(uuidString: "0615B0AD-12E8-467C-94FB-DF20A27CFF3F")!,
            workflowName: "Clean MKV",
            inputs: [
                MediaJobInput(
                    id: UUID(uuidString: "1F39E3C2-FF14-4B7F-8176-61485468FE9C")!,
                    displayName: "Movie.mkv",
                    bookmarkID: UUID(uuidString: "F9B1AC8F-1B94-4653-9F21-05133130E0C0")!
                )
            ]
        )
    }
}
