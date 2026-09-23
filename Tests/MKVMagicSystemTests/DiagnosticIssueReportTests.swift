import Foundation
import XCTest

@testable import MKVMagicSystem

final class DiagnosticIssueReportTests: XCTestCase {
    private let session = UUID()
    private let attempt = UUID()

    private func event(
        _ stage: DiagnosticStage, _ outcome: DiagnosticOutcome,
        failure: DiagnosticFailure? = nil, tool: BundledTool? = nil
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            sessionID: session, attemptID: attempt, version: "0.3.0-test.19", build: "19",
            action: .verifyAndRun, stage: stage, outcome: outcome, failure: failure, tool: tool,
            operatingSystem: "15.7.4", architecture: .x86_64, elapsedMilliseconds: 100)
    }

    private func reports(_ events: [DiagnosticEvent], current: UUID? = nil)
        -> [DiagnosticIssueReport]
    {
        DiagnosticIssueReport.from(
            DiagnosticSnapshot(
                events: events, droppedEventCount: 0,
                skippedInvalidRecordCount: 0, omittedEventCount: 0, storageUnavailable: false),
            currentSessionID: current ?? session, operatingSystem: "26.0.0", architecture: .arm64)
    }

    func testPreHistoryFailurePreservesItsOriginalEnvironmentAndCrossClientFingerprint() throws {
        let report = try XCTUnwrap(
            reports([
                event(.requested, .started),
                event(.queueAdmission, .failed, failure: .bookmarkUnavailable),
                event(.finished, .failed, failure: .unknown),
            ]).first)
        XCTAssertEqual(report.stage, .queueAdmission)
        XCTAssertEqual(report.failure, .bookmarkUnavailable)
        XCTAssertEqual(report.operatingSystem, "15.7.4")
        XCTAssertEqual(report.architecture, .x86_64)
        XCTAssertEqual(
            report.fingerprint, "68d0856664ab12b0cbd5ca7f5612b3b1c2cec5ad7cbaebfaa7ba7754106e9b28")
        let url = try report.reviewURL()
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "crash.dustwave.xyz")
        XCTAssertEqual(components.path, "/mkv-magic/review")
        XCTAssertNil(components.query)
        let data = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(components.fragment)))
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticIssueReport.self, from: data), report)
    }

    func testActiveRecoveredCancelledAndCompletedAttemptsAreNotCrashReports() {
        let started = event(.execution, .started)
        let toolFailure = event(.tool, .failed, failure: .toolExited, tool: .ffprobe)
        XCTAssertTrue(reports([started, toolFailure]).isEmpty)
        XCTAssertTrue(reports([started, toolFailure, event(.finished, .succeeded)]).isEmpty)
        XCTAssertTrue(
            reports([started, event(.finished, .cancelled), event(.committing, .started)]).isEmpty)
        XCTAssertTrue(
            reports(
                [started, event(.finished, .succeeded), event(.verifying, .started)],
                current: UUID()
            ).isEmpty)
        XCTAssertTrue(reports([event(.review, .started)], current: UUID()).isEmpty)
        XCTAssertEqual(reports([started], current: UUID()).first?.kind, .interruptedOperation)
        XCTAssertEqual(
            reports([event(.selection, .blocked, failure: .missingReview)]).first?.kind,
            .operationFailure)
    }

    private func incident(bundleID: String = "com.dustwave.mkvmagic") throws -> Data {
        let header: [String: Any] = [
            "bundleID": bundleID, "incident_id": attempt.uuidString,
            "app_version": "0.3.0", "build_version": "19",
        ]
        let body: [String: Any] = [
            "procName": "MKVMagic", "cpuType": "X86-64",
            "procPath": "/Users/private/MKV Magic.app",
            "exception": ["type": "EXC_BAD_ACCESS", "signal": "SIGSEGV"],
            "osVersion": ["train": "macOS 15.7.4"], "faultingThread": 0,
            "threads": [
                ["frames": [["imageIndex": 0, "imageOffset": 128, "symbol": "private title"]]]
            ],
            "usedImages": [
                ["name": "MKVMagic", "path": "/Users/private/MKV Magic", "base": 123456789]
            ],
        ]
        var data = try JSONSerialization.data(withJSONObject: header)
        data.append(10)
        data.append(try JSONSerialization.data(withJSONObject: body))
        return data
    }

    func testCrashImportProjectsOnlyAllowlistedFactsAndRejectsOtherApps() throws {
        let report = try XCTUnwrap(DiagnosticCrashFacts.parse(try incident()))
        XCTAssertEqual(report.kind, .nativeCrash)
        XCTAssertEqual(report.crash?.imageOffset, 128)
        XCTAssertEqual(
            report.fingerprint, "02fb7f5d959100701ec47d5ef4c418225880c3fc895e7592d6588487fb11b6b7")
        let json = String(decoding: try report.encoded(), as: UTF8.self)
        for forbidden in ["private", "procPath", "symbol", "usedImages", "123456789"] {
            XCTAssertFalse(json.contains(forbidden))
        }
        XCTAssertNil(DiagnosticCrashFacts.parse(try incident(bundleID: "com.other.app")))
        XCTAssertNil(DiagnosticCrashFacts.parse(Data(repeating: 32, count: 2 * 1_024 * 1_024 + 1)))
        XCTAssertNil(DiagnosticCrashFacts.parse(Data("invalid".utf8)))
    }

    func testSelectedIncidentRejectsSymlinksAndLocalExportWorksWithoutHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("incident.ips")
        try incident().write(to: file)
        XCTAssertEqual(try DiagnosticCrashFacts.readSelectedIncident(file).kind, .nativeCrash)
        let link = root.appendingPathComponent("link.ips")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try DiagnosticCrashFacts.readSelectedIncident(link))
        let snapshot = DiagnosticSnapshot(
            events: [event(.queueAdmission, .failed, failure: .queueUnsafePath)],
            droppedEventCount: 1, skippedInvalidRecordCount: 2, omittedEventCount: 3,
            storageUnavailable: true)
        let output = root.appendingPathComponent("diagnostics.json")
        try PrivacySafeSupportReportWriter.writeDiagnostics(snapshot, to: output)
        XCTAssertEqual(
            try JSONDecoder().decode(DiagnosticSnapshot.self, from: Data(contentsOf: output)),
            snapshot)
    }
}
