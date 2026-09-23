import Foundation
import XCTest

@testable import MKVMagicSystem

final class DiagnosticJournalTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func testGenericFolderErrorRetainsDestinationStageWithoutPrivateMessage() async throws {
        let journal = DiagnosticJournal(directory: root.appendingPathComponent("Diagnostics"))
        let context = DiagnosticContext(
            journal: journal, sessionID: UUID(),
            version: "0.3.0", build: "20", action: .verifyAndRun)
        do {
            try DiagnosticPreparationError.perform(
                stage: .destination, fallback: .destinationUnavailable
            ) {
                throw NSError(
                    domain: NSCocoaErrorDomain, code: 256,
                    userInfo: [NSLocalizedDescriptionKey: "Private Movies directory denied"])
            }
            XCTFail("Preparation must fail closed")
        } catch {
            let failure = try XCTUnwrap(error as? DiagnosticPreparationError)
            XCTAssertEqual(failure.stage, .destination)
            XCTAssertEqual(DiagnosticFailure.classify(error), .destinationUnavailable)
            await context.record(failure.stage, .failed, failure: .classify(error))
        }
        let snapshot = await journal.snapshot()
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Private Movies"))
        XCTAssertEqual(snapshot.events.last?.stage, .destination)
    }

    func testRetainsPreflightFailureWithoutHistoryAndAcrossRelaunch() async throws {
        let journal = DiagnosticJournal(directory: root.appendingPathComponent("Diagnostics"))
        let context = DiagnosticContext(
            journal: journal, sessionID: UUID(), version: "0.3.0-test.19",
            build: "19", action: .verifyAndRun)
        await context.record(.requested, .started)
        await context.record(.queueAdmission, .failed, failure: .bookmarkUnavailable)
        let reopened = DiagnosticJournal(directory: root.appendingPathComponent("Diagnostics"))
        let snapshot = await reopened.snapshot()
        XCTAssertEqual(snapshot.events.map(\.stage), [.requested, .queueAdmission])
        XCTAssertEqual(snapshot.events.last?.failure, .bookmarkUnavailable)
        XCTAssertEqual(Set(snapshot.events.map(\.attemptID)), [context.attemptID])
        XCTAssertFalse(snapshot.storageUnavailable)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("Diagnostics/events.jsonl").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testRotationIsBoundedAndRetainsMostRecentEvents() async throws {
        let journal = DiagnosticJournal(
            directory: root.appendingPathComponent("Diagnostics"), maximumBytes: 1_024)
        let context = DiagnosticContext(
            journal: journal, sessionID: UUID(), version: "0.3.0", build: "19",
            action: .verifyAndRun)
        for _ in 0..<30 { await context.record(.requested, .started) }
        await context.record(.finished, .failed, failure: .diskFull)
        let snapshot = await journal.snapshot()
        XCTAssertEqual(snapshot.events.last?.failure, .diskFull)
        XCTAssertLessThan(snapshot.events.count, 30)
        for name in ["events.jsonl", "events.previous.jsonl"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Diagnostics/\(name)"))
            XCTAssertLessThanOrEqual(data.count, 1_024)
        }
    }

    func testRejectsInjectedFieldsAndInvalidVersionsBeforeExport() async throws {
        let journal = DiagnosticJournal(directory: root.appendingPathComponent("Diagnostics"))
        let context = DiagnosticContext(
            journal: journal, sessionID: UUID(), version: "/private/film.mp4", build: "19",
            action: .verifyAndRun)
        await context.record(.requested, .started)
        let file = root.appendingPathComponent("Diagnostics/events.jsonl")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object["privatePath"] = "/private/film.mp4"
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try data.write(to: file)
        await context.record(.finished, .failed, failure: .unknown)
        let snapshot = await journal.snapshot()
        XCTAssertEqual(snapshot.skippedInvalidRecordCount, 1)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events[0].version, "unknown")
        XCTAssertFalse(
            String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self).contains("film.mp4")
        )
    }

    func testRejectsSymlinkAndDoesNotTouchItsTarget() async throws {
        let directory = root.appendingPathComponent("Diagnostics")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let target = root.appendingPathComponent("private.txt")
        let original = Data("private".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("events.jsonl"), withDestinationURL: target)
        let journal = DiagnosticJournal(directory: directory)
        let context = DiagnosticContext(
            journal: journal, sessionID: UUID(), version: "0.3.0", build: "19",
            action: .verifyAndRun)
        await context.record(.requested, .started)
        let snapshot = await journal.snapshot()
        XCTAssertTrue(snapshot.storageUnavailable)
        XCTAssertEqual(snapshot.droppedEventCount, 1)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testToolLaunchFailureKeepsSafeCauseNotArgumentsOrRawError() async throws {
        let journal = DiagnosticJournal(directory: root.appendingPathComponent("Diagnostics"))
        let context = DiagnosticContext(
            journal: journal, sessionID: UUID(), version: "0.3.0", build: "19",
            action: .verifyAndRun)
        await DiagnosticContext.$current.withValue(context) {
            do {
                _ = try await FoundationCommandRunner().run(
                    CommandRequest(
                        executableURL: URL(fileURLWithPath: "/missing/private/mkvmerge"),
                        arguments: ["private subtitle content"]
                    ))
                XCTFail("The missing tool must fail")
            } catch { XCTAssertEqual(error as? CommandRunnerError, .unsafeExecutable) }
        }
        let snapshot = await journal.snapshot()
        XCTAssertEqual(snapshot.events.last?.failure, .toolUnavailable)
        XCTAssertEqual(snapshot.events.last?.tool, .mkvmerge)
        XCTAssertFalse(
            String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self).contains("private"))
    }
}
