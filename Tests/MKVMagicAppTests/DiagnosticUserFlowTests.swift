import AppKit
import Foundation
import MKVMagicCore
import MKVMagicPlanning
import MKVMagicReporting
import MKVMagicSystem
import XCTest

@testable import MKVMagic

final class DiagnosticUserFlowTests: XCTestCase {
    @MainActor
    func testReportRequiresExplicitInAppSendAndEmptyStateCannotSend() async throws {
        var opened: [URL] = []
        var sent: [UUID] = []
        let report = DiagnosticIssueReport(
            id: UUID(), kind: .operationFailure, version: "0.3.0", build: "19",
            operatingSystem: "15.7.4", architecture: .x86_64, action: .verifyAndRun,
            stage: .queueAdmission, failure: .bookmarkUnavailable)
        let controller = DiagnosticReportViewController(
            reports: [report],
            submit: { report in
                sent.append(report.id)
                return try Self.receipt(for: report.id)
            },
            openURL: {
                opened.append($0)
                return true
            })
        _ = controller.view
        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(sent.isEmpty)
        await controller.sendReport()
        await controller.sendReport()
        XCTAssertEqual(sent, [report.id])
        XCTAssertTrue(opened.isEmpty, "Sending never opens a browser")
        func buttons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        XCTAssertFalse(
            buttons(controller.view).contains {
                $0.title.contains("Import") || $0.title.contains("Browser")
            })
        let empty = DiagnosticReportViewController(
            reports: [],
            submit: { report in
                sent.append(report.id)
                return try Self.receipt(for: report.id)
            },
            openURL: {
                opened.append($0)
                return true
            })
        _ = empty.view
        await empty.sendReport()
        XCTAssertEqual(sent, [report.id])
        XCTAssertTrue(opened.isEmpty)
    }

    private static func receipt(for id: UUID) throws -> ReportReceipt {
        try ReportReceipt.validated(
            Data(
                "{\"ok\":true,\"reportId\":\"\(id.uuidString)\",\"issueNumber\":2,\"action\":\"created\"}"
                    .utf8), for: id)
    }

    @MainActor
    func testUnconfirmedSubmissionRetainsIDAndRequiresManualRetry() async throws {
        var attempts = [UUID]()
        let report = DiagnosticIssueReport(
            id: UUID(), kind: .operationFailure, version: "0.3.0", build: "20",
            operatingSystem: "15.7.4", architecture: .x86_64, action: .verifyAndRun,
            stage: .destination, failure: .destinationUnavailable)
        let controller = DiagnosticReportViewController(
            reports: [report],
            submit: { report in
                attempts.append(report.id)
                if attempts.count == 1 { throw ReportSubmissionError.unavailable }
                return try Self.receipt(for: report.id)
            })
        _ = controller.view
        await controller.sendReport()
        XCTAssertEqual(attempts.count, 1)
        await controller.sendReport()
        XCTAssertEqual(attempts, [report.id, report.id])
    }

    @MainActor
    func testFileSavePermissionRequestsExactFolderAndRetainsScope() throws {
        let directory = URL(fileURLWithPath: "/fixture/Movies")
        let output = directory.appendingPathComponent("movie.mkv")
        var authorized = false
        var prompts = 0
        var held: OutputDirectorySecurityScope? = try OutputDirectoryAuthorization.authorize(
            destinationURL: output,
            requestAccess: { requested in
                XCTAssertEqual(requested.path, directory.path)
                prompts += 1
                authorized = true
                return requested
            },
            acquire: { selected in
                guard authorized else { return nil }
                return OutputDirectorySecurityScope(
                    directoryURL: selected,
                    startAccessing: { _ in true }, stopAccessing: { _ in })
            })
        XCTAssertNotNil(held)
        XCTAssertEqual(prompts, 1)
        held = nil
        // Cancellation and a different folder never yield an execution capability.
        XCTAssertNil(
            try OutputDirectoryAuthorization.authorize(
                destinationURL: output,
                requestAccess: { _ in nil }, acquire: { _ in nil }))
        XCTAssertThrowsError(
            try OutputDirectoryAuthorization.authorize(
                destinationURL: output,
                requestAccess: { _ in directory.deletingLastPathComponent() }, acquire: { _ in nil }
            ))
    }

    @MainActor
    func testVerifyAndRunReportsAdmissionFailureBeforeHistoryExists() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = DiagnosticJournal(directory: root.appendingPathComponent("Diagnostics"))
        let history = try JSONJobHistoryStore(
            fileURL: root.appendingPathComponent("job-history.json"))
        let model = AppModel(
            diagnosticJournal: journal, historyRecorderFactory: { history },
            queueStoreFactory: { throw JobQueueStoreError.unsafePath })
        let asset = MediaAsset(
            sourceURL: root.appendingPathComponent("Movie.mp4"),
            container: "mov,mp4", duration: MediaTime(nanoseconds: 4_000_000_000),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "h264")])
        let recipe = SavedWorkflow(name: "Remux", steps: [.init(action: .remuxToMKV)])
        let compiled = try SavedWorkflowCompiler().compile(recipe, for: asset)
        let context = try XCTUnwrap(model.makeDiagnosticContext(.verifyAndRun))
        let destination = root.appendingPathComponent("Output.mkv")
        await DiagnosticContext.$current.withValue(context) {
            do {
                _ = try await model.runSavedWorkflow(
                    compiled, recipe: recipe,
                    externalSubtitlePayload: nil, in: asset, destinationURL: destination)
                XCTFail("Queue preparation must fail")
            } catch { XCTAssertEqual(error as? JobQueueStoreError, .unsafePath) }
        }
        guard case .failed(let message) = model.state else {
            return XCTFail("Pre-History failures must be visible, not silently discarded")
        }
        XCTAssertTrue(message.contains("Could not create a verified output"))
        let records = try await history.load()
        XCTAssertTrue(records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let snapshot = await journal.snapshot()
        XCTAssertEqual(snapshot.events.last?.stage, .queueAdmission)
        XCTAssertEqual(snapshot.events.last?.failure, .queueUnsafePath)
    }

    @MainActor
    func testFinalRunErrorRemainsVisibleAfterReadinessRefresh() throws {
        let controller = MainViewController(model: AppModel())
        _ = controller.view
        let activity = controller.beginInterfaceActivity("Preparing…")
        controller.presentVerifiedRunFailure(SecurityScopedBookmarkError.stale)
        controller.endInterfaceActivity(activity)
        func labels(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(labels)
        }
        XCTAssertTrue(
            labels(controller.view).contains {
                $0.stringValue.contains("Verify & Run could not complete")
            })
    }
}
