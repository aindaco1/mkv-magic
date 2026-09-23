import AppKit
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

@testable import MKVMagic

final class BulkMediaUXTests: XCTestCase {
    @MainActor
    func testBatchFormsKeepFooterVisibleAtMinimumSizeInLightAndDark() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for kind in [BatchMediaOptionsKind.metadata, .trim] {
                let controller = BatchMediaOptionsWindowController(kind: kind)
                let window = try XCTUnwrap(controller.window)
                defer { window.close() }
                window.appearance = NSAppearance(named: appearance)
                window.setContentSize(NSSize(width: 540, height: 360))
                let content = try XCTUnwrap(window.contentView)
                content.layoutSubtreeIfNeeded()
                let review = try button("Review Batch…", content)
                let cancel = try button("Cancel", content)
                XCTAssertFalse(review.isEnabled)
                XCTAssertTrue(content.bounds.contains(review.convert(review.bounds, to: content)))
                XCTAssertTrue(content.bounds.contains(cancel.convert(cancel.bounds, to: content)))
                let scroll = try XCTUnwrap(
                    descendants(content).compactMap { $0 as? NSScrollView }.first)
                XCTAssertFalse(
                    scroll.convert(scroll.bounds, to: content).intersects(
                        review.convert(review.bounds, to: content)))
                if kind == .metadata {
                    let grid = try XCTUnwrap(
                        descendants(content).compactMap { $0 as? NSGridView }.first)
                    for row in 0..<grid.numberOfRows {
                        let field = try XCTUnwrap(
                            grid.cell(atColumnIndex: 1, rowIndex: row).contentView)
                        XCTAssertGreaterThan(field.frame.width, 120)
                    }
                }
            }
        }
    }

    @MainActor
    func testMetadataOptionsRequireExplicitChangeAndPreserveUnchosenFields() throws {
        let parent = NSWindow(contentViewController: NSViewController())
        defer { parent.close() }
        let controller = BatchMediaOptionsWindowController(kind: .metadata)
        var operation: BatchMediaEditOperation?
        controller.beginSheet(for: parent) { operation = $0 }
        let content = try XCTUnwrap(controller.window?.contentView)
        let popup = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSPopUpButton }.first {
                $0.accessibilityLabel() == "Commentary"
            })
        popup.selectItem(at: 2)
        NSApp.sendAction(try XCTUnwrap(popup.action), to: popup.target, from: popup)
        XCTAssertTrue(try button("Review Batch…", content).isEnabled)
        try button("Review Batch…", content).performClick(nil)
        guard case .metadata(let change) = operation else { return XCTFail("Missing review") }
        XCTAssertEqual(change.kind, .audio)
        XCTAssertNil(change.name)
        XCTAssertNil(change.language)
        XCTAssertEqual(change.flags, [.commentary: false])
    }

    @MainActor
    func testTrimOptionsAcceptSecondsAndRejectInvalidOrEmptyRemoval() throws {
        let controller = BatchMediaOptionsWindowController(kind: .trim)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let beginning = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Seconds to remove from beginning"
            })
        let review = try button("Review Batch…", content)
        for (value, enabled) in [
            ("3.5", true), ("00:01:00", true), ("-1", false), ("0", false),
            ("9223372036.854775808", false),
        ] {
            beginning.stringValue = value
            beginning.delegate?.controlTextDidChange?(
                Notification(name: NSControl.textDidChangeNotification, object: beginning))
            XCTAssertEqual(review.isEnabled, enabled, value)
        }
    }

    @MainActor
    func testActualAutomaticQueueAllowsBatchAuthoringAndIntakeButBlocksForegroundExecution()
        async throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "bulk-authoring-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let subtitle = root.appendingPathComponent("Source.srt")
        try Data("1\n00:00:00,000 --> 00:00:01,000\n  Keep dialogue  \n".utf8).write(to: subtitle)
        let entered = expectation(description: "Automatic job reached History")
        let history = try HeldBatchHistory(
            url: root.appendingPathComponent("job-history.json"), entered: entered)
        let queueURL = root.appendingPathComponent("job-queue.json")
        let assets = (0..<2).map { index in
            MediaAsset(
                sourceURL: root.appendingPathComponent("Movie \(index).mkv"), container: "matroska",
                duration: MediaTime(seconds: 10),
                tracks: [
                    .init(id: 0, kind: .video, codec: "h264", uid: UInt64(index + 1)),
                    .init(
                        id: 1, kind: .subtitle, codec: "subrip", codecID: "S_TEXT/UTF8",
                        uid: UInt64(index + 10)),
                ], globalTagCount: 1, trackTagCount: 0)
        }
        let model = AppModel(
            initialAssets: assets, historyRecorderFactory: { history },
            queueStoreFactory: { try JSONJobQueueStore(fileURL: queueURL) },
            queueEnvironmentReader: AuthoringQueueEnvironment())
        let controller = MainViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        model.didChange?()
        let content = controller.view
        let table = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let title = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Segment title"
            })
        title.stringValue = "Unfinished draft"
        let preview = try await model.previewSubtitleCleanup(at: subtitle)
        let edit = ReviewedBatchEdit.subtitleCleanup(.subRip(preview), restoringIDs: [])
        _ = try await model.enqueueReviewedEdit(
            edit, destinationURL: root.appendingPathComponent("First.srt"))
        let running = Task { try await model.runAutomaticQueueCycle() }
        await fulfillment(of: [entered], timeout: 10)
        do {
            XCTAssertTrue(model.isDrainingAutomaticQueue)
            XCTAssertNil(
                model.activeQueueJobID, "This is automatic work, not immediate Verify & Run")
            XCTAssertEqual(title.stringValue, "Unfinished draft")
            table.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
            for name in [
                "Clean MKV…", "Suggest Chapters…", "Tags…", "Edit Matching Tracks…",
                "Extract Subtitles…", "Trim Beginnings / Ends…",
            ] {
                XCTAssertTrue(try button(name, content).isEnabled, name)
            }
            let activity = controller.beginInterfaceActivity("Preparing a new review…")
            XCTAssertFalse(try button("Edit Matching Tracks…", content).isEnabled)
            controller.endInterfaceActivity(activity)
            XCTAssertTrue(try button("Edit Matching Tracks…", content).isEnabled)
            _ = try await model.enqueueReviewedEdit(
                edit, destinationURL: root.appendingPathComponent("Second.srt"))
            await model.addFiles([subtitle])
            XCTAssertTrue(model.isDrainingAutomaticQueue)
            XCTAssertEqual(table.selectedRowIndexes, IndexSet(integersIn: 0..<2))
            XCTAssertTrue(try button("Edit Matching Tracks…", content).isEnabled)
            XCTAssertFalse(try button("Verify & Run", content).isEnabled)
            XCTAssertTrue(
                try XCTUnwrap(
                    descendants(content).compactMap { $0 as? NSButton }.first {
                        $0.accessibilityLabel() == "Choose media files or folders"
                    }
                ).isEnabled)
        } catch {
            await history.release()
            _ = try? await running.value
            throw error
        }
        await history.release()
        let completed = try await running.value
        XCTAssertFalse(model.isDrainingAutomaticQueue)
        XCTAssertEqual(completed.jobs.map(\.state), [.succeeded, .succeeded])
        XCTAssertTrue(try button("Edit Matching Tracks…", content).isEnabled)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Second.srt").path))
    }

    @MainActor private func button(_ title: String, _ content: NSView) throws -> NSButton {
        try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSButton }.first { $0.title == title }, title)
    }
    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

private struct AuthoringQueueEnvironment: MediaQueueSchedulingEnvironmentReading {
    func read() -> MediaQueueSchedulingEnvironment {
        .init(isOnBattery: false, thermalPressure: .nominal)
    }
}

private actor HeldBatchHistory: JobHistoryRecording {
    let store: JSONJobHistoryStore
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var held = false
    init(url: URL, entered: XCTestExpectation) throws {
        store = try JSONJobHistoryStore(fileURL: url)
        self.entered = entered
    }
    func load() async throws -> [MediaJobRecord] { try await store.load() }
    func save(_ records: [MediaJobRecord]) async throws { try await store.save(records) }
    func create(_ record: MediaJobRecord) async throws {
        if !held {
            held = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }
        try await store.create(record)
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
    func transition(jobID: UUID, to state: MediaJobState, at timestamp: Date, message: String?)
        async throws -> MediaJobRecord
    {
        try await store.transition(jobID: jobID, to: state, at: timestamp, message: message)
    }
}
