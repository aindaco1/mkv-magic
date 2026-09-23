import AppKit
import MKVMagicCore
import XCTest

@testable import MKVMagic

final class BatchActionUXTests: XCTestCase {
    @MainActor
    func testCancellingBatchPreparationCreatesNoQueueJobs() async throws {
        let video = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Feature.mp4"), container: "mov",
            duration: MediaTime(seconds: 10), tracks: [.init(id: 0, kind: .video, codec: "h264")])
        let sidecar = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Feature.en.srt"), container: "srt")
        let model = AppModel(initialAssets: [video, sidecar])
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false)
        // This fixture has no NSWindowController to disable AppKit's legacy
        // release-on-close ownership; Swift ARC owns the test window instead.
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var result: String?
        let coordinator = BatchRemuxCoordinator(model: model, parent: window) { result = $0 }
        coordinator.begin(assets: [video, sidecar])
        let progress = try XCTUnwrap(window.attachedSheet?.contentView)
        try button("Cancel", progress).performClick(nil)
        for _ in 0..<100 where result == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(result, "Remux batch cancelled; nothing queued.")
        XCTAssertNil(window.attachedSheet)
    }

    @MainActor
    func testMixedSelectionKeepsApplicableBatchActionsAvailable() throws {
        let assets = [
            MediaAsset(
                sourceURL: URL(fileURLWithPath: "/Media/Feature.mp4"), container: "mov,mp4",
                duration: MediaTime(seconds: 10),
                tracks: [.init(id: 0, kind: .video, codec: "h264")]),
            MediaAsset(sourceURL: URL(fileURLWithPath: "/Media/Feature.en.srt"), container: "srt"),
            MediaAsset(
                sourceURL: URL(fileURLWithPath: "/Media/Other.mkv"), container: "matroska",
                tracks: [.init(id: 0, kind: .video, codec: "h264", uid: 1)], globalTagCount: 1,
                trackTagCount: 0),
        ]
        let model = AppModel(initialAssets: assets)
        let controller = MainViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        model.didChange?()
        let content = controller.view
        let table = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet(integersIn: 0..<assets.count), byExtendingSelection: false)
        XCTAssertTrue(try button("Remux Batch to MKV…", content).isEnabled)
        XCTAssertTrue(try button("Clean MKV…", content).isEnabled)
        XCTAssertTrue(try button("Clean Subtitle…", content).isEnabled)
        XCTAssertTrue(try button("Suggest Chapters…", content).isEnabled)
        XCTAssertTrue(try button("Tags…", content).isEnabled)
    }

    @MainActor
    func testSharedReviewCanExcludeItemsWithoutLosingChoicesOnRefresh() throws {
        let ready = BatchReviewItemPresentation(
            id: UUID(), inputName: "Feature.mp4", outputName: "Feature.mkv",
            status: .ready, detail: "Long warning that must be selectable and readable.",
            isEditable: true)
        let blocked = BatchReviewItemPresentation(
            id: UUID(), inputName: "Other.mp4", outputName: "Other.mkv",
            status: .blocked, detail: "Needs review")
        let directory = URL(fileURLWithPath: "/Batch")
        let access = try XCTUnwrap(
            OutputDirectorySecurityScope(
                directoryURL: directory,
                startAccessing: { _ in true }, stopAccessing: { _ in }))
        let controller = BatchReviewWindowController(
            title: "Review Batch", explanation: "Review every file.",
            items: [ready, blocked], actionTitle: "Queue Included", offersSourceDisposition: false,
            initialDestinationDirectory: directory, initialDirectoryAccess: access)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let table = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTableView }.first)
        let column = try XCTUnwrap(table.tableColumns.first { $0.identifier.rawValue == "include" })
        let include = try XCTUnwrap(
            table.delegate?.tableView?(table, viewFor: column, row: 0) as? NSButton)
        let blockedInclude = try XCTUnwrap(
            table.delegate?.tableView?(table, viewFor: column, row: 1) as? NSButton)
        XCTAssertEqual(include.state, .on)
        XCTAssertFalse(blockedInclude.isEnabled)
        include.performClick(nil)
        XCTAssertFalse(try button("Queue Included", content).isEnabled)
        controller.update(ready)
        XCTAssertFalse(
            try button("Queue Included", content).isEnabled, "Refreshing must not undo an exclusion"
        )
        controller.update(
            BatchReviewItemPresentation(
                id: blocked.id, inputName: blocked.inputName,
                outputName: blocked.outputName, status: .ready, detail: "Reviewed"))
        XCTAssertTrue(try button("Queue Included", content).isEnabled)
        var edited: UUID?
        controller.onEditItem = { edited = $0 }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try button("Edit Selected…", content).performClick(nil)
        XCTAssertEqual(edited, ready.id)
        let details = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextView }
                .first { $0.accessibilityLabel() == "Selected batch item details" })
        XCTAssertTrue(details.isSelectable)
        XCTAssertTrue(details.string.contains(ready.detail))
        XCTAssertEqual(details.textColor, .textColor)
    }

    func testBatchDestinationUsesEachSourceFolderAndReservesCollisions() throws {
        let one = UUID(), two = UUID()
        func access(_ path: String) throws -> OutputDirectorySecurityScope {
            try XCTUnwrap(
                OutputDirectorySecurityScope(
                    directoryURL: URL(fileURLWithPath: path, isDirectory: true),
                    startAccessing: { _ in true }, stopAccessing: { _ in }))
        }
        let first = try access("/Batch/First"), second = try access("/Batch/Second")
        let decision = BatchReviewDecision(
            commonDestinationDirectory: first.directoryURL,
            sourceDisposition: .keepOriginal, directoryAccess: first, includedItemIDs: [one],
            perItemDirectories: [one: first, two: second])
        XCTAssertTrue(decision.includes(one))
        XCTAssertFalse(decision.includes(two))
        let output = try decision.destination(for: one, filename: "Feature.mkv")
        XCTAssertEqual(output.deletingLastPathComponent(), first.directoryURL)
        XCTAssertEqual(
            try decision.destination(for: two, filename: "Feature.mkv").deletingLastPathComponent(),
            second.directoryURL)
        XCTAssertNotEqual(
            try decision.destination(
                for: one, filename: "Feature.mkv", reservedPaths: [output.path]), output)
        XCTAssertThrowsError(try decision.destination(for: one, filename: "../unsafe.mkv"))
    }

    @MainActor
    func testRemuxChoicesReadActiveFieldEditorAndKeepFlagsAndExclusions() throws {
        let id = UUID(), omitted = UUID()
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Feature.English.mp4"), container: "mov,mp4")
        let choices = [
            BatchRemuxTrackChoice(
                id: id, filename: "Feature.es.srt", metadata: .init(language: "es", isForced: true),
                included: true, explanation: "Review timing."),
            BatchRemuxTrackChoice(
                id: omitted, filename: "Feature.en.sdh.srt",
                metadata: .init(language: "en", isHearingImpaired: true), included: false,
                explanation: "Optional."),
        ]
        let controller = BatchRemuxOptionsWindowController(
            media: media, choices: choices, audioLanguages: [1: "en"])
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let editor = try XCTUnwrap(window.contentViewController as? BatchRemuxOptionsViewController)
        var result: BatchRemuxOptions?
        editor.onFinish = { result = $0 }
        let language = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextField }
                .first { $0.accessibilityLabel() == "Feature.es.srt language" })
        XCTAssertTrue(window.makeFirstResponder(language))
        let fieldEditor = try XCTUnwrap(language.currentEditor() as? NSTextView)
        fieldEditor.insertText(
            "fr", replacementRange: NSRange(location: 0, length: fieldEditor.string.utf16.count))
        try button("Use These Choices", content).performClick(nil)
        XCTAssertEqual(result?.subtitles[id]?.language, "fr")
        XCTAssertEqual(result?.subtitles[id]?.isForced, true)
        XCTAssertNil(result?.subtitles[omitted])
        XCTAssertEqual(result?.audioLanguages, [1: "en"])
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()
        for title in ["Cancel", "Use These Choices"] {
            let action = try button(title, content)
            let frame = content.convert(action.bounds, from: action)
            XCTAssertGreaterThanOrEqual(frame.minY, 0)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.width)
        }
        let scroll = try XCTUnwrap(descendants(content).compactMap { $0 as? NSScrollView }.first)
        XCTAssertGreaterThan(scroll.frame.height, 200)
        let document = try XCTUnwrap(scroll.documentView)
        let lastField = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextField }
                .first { $0.accessibilityLabel() == "Feature.en.sdh.srt track name" })
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            lastField.scrollToVisible(lastField.bounds)
            content.layoutSubtreeIfNeeded()
            let target = document.convert(lastField.bounds, from: lastField)
            XCTAssertTrue(
                scroll.documentVisibleRect.intersects(target), "Last subtitle must remain reachable"
            )
        }
        language.scrollToVisible(language.bounds)
        if let path = ProcessInfo.processInfo.environment["MKV_MAGIC_BATCH_OPTIONS_CAPTURE"],
            path.hasPrefix("/")
        {
            window.appearance = NSAppearance(named: .aqua)
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.white.cgColor
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
            window.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: path))
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor
    private func button(_ title: String, _ view: NSView) throws -> NSButton {
        try XCTUnwrap(descendants(view).compactMap { $0 as? NSButton }.first { $0.title == title })
    }
}
