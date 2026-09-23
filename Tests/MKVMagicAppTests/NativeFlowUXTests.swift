import AppKit
import MKVMagicCore
import MKVMagicExecution
import XCTest

@testable import MKVMagic

/// Exercise real AppKit layout and field-editor events, not just presentation models.
final class NativeFlowUXTests: XCTestCase {
    @MainActor
    func testInspectorUsesTheSameStatisticsTagCountsAsTagActions() throws {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Statistics.mkv"), container: "matroska",
            tracks: [
                .init(
                    id: 0, kind: .video, codec: "h264", uid: 1,
                    tags: ["_STATISTICS_WRITING_APP": "mkvmerge"])
            ],
            globalTagCount: 1, trackTagCount: 0)
        let model = AppModel(initialAssets: [asset])
        let controller = MainViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        model.didChange?()
        let text = try XCTUnwrap(
            descendants(controller.view).compactMap { $0 as? NSTextView }
                .first { $0.accessibilityLabel() == "Selected media details" })
        let counts = try MatroskaTagPolicy.counts(in: asset)
        XCTAssertTrue(text.string.contains("TAGS  \(counts.global) global • \(counts.track) track"))
        XCTAssertEqual(counts.track, 1)
        XCTAssertTrue(try button("Tags…", in: controller.view).isEnabled)
    }

    @MainActor
    func testMainStatusRefreshDoesNotEraseActionFailureOrRecoveryGuidance() throws {
        let model = AppModel()
        let controller = MainViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        model.didChange?()
        let status = try XCTUnwrap(
            descendants(controller.view).compactMap { $0 as? NSTextField }
                .first { $0.accessibilityLabel() == "Application status" })
        let failure = "Could not open Trim. No output was created; check the video and try again."
        AccessibleStatusPresentation.present(failure, in: status)
        model.didChange?()
        XCTAssertEqual(status.stringValue, failure)
        model.didChange?()
        XCTAssertEqual(status.stringValue, failure)
    }

    @MainActor
    func testFinishedInterfaceActivityRetiresOnlyItsOwnProgressMessage() throws {
        let model = AppModel()
        let controller = MainViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        model.didChange?()
        let status = try XCTUnwrap(
            descendants(controller.view).compactMap { $0 as? NSTextField }
                .first { $0.accessibilityLabel() == "Application status" })
        let first = controller.beginInterfaceActivity("Extracting chapters…")
        let second = controller.beginInterfaceActivity("Reading tags…")
        controller.endInterfaceActivity(first)
        XCTAssertEqual(status.stringValue, "Reading tags…")
        controller.endInterfaceActivity(second)
        XCTAssertEqual(status.stringValue, "Ready")

        let failing = controller.beginInterfaceActivity("Preparing review…")
        AccessibleStatusPresentation.present("Could not prepare review. Try again.", in: status)
        controller.endInterfaceActivity(failing)
        model.didChange?()
        XCTAssertEqual(status.stringValue, "Could not prepare review. Try again.")
        status.stringValue = "Choose numeric trim boundaries and review the result."
        controller.restoreModelStatusAfterReview()
        XCTAssertEqual(status.stringValue, "Ready", "Cancelled reviews must retire their guidance")
    }

    @MainActor
    func testCleanMKVIsAvailableWithoutSubtitleRemovalAndForMatroskaBatch() throws {
        let assets = (0..<2).map { index in
            MediaAsset(
                sourceURL: URL(fileURLWithPath: "/Media/Clean-Candidate-\(index).mkv"),
                container: "matroska",
                tracks: [
                    .init(id: 0, kind: .video, codec: "h264", uid: 10),
                    .init(id: 1, kind: .audio, codec: "aac", uid: 20, language: "en"),
                ],
                metadata: ["title": "Remove Me"],
                globalTagCount: 1,
                trackTagCount: 0
            )
        }
        XCTAssertTrue(EnglishLibraryCleanupPolicy.trackSuggestions(for: assets[0]).isEmpty)

        let model = AppModel(initialAssets: assets)
        let controller = MainViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        let content = controller.view
        model.didChange?()
        let clean = try button("Clean MKV…", in: content)
        XCTAssertTrue(clean.isEnabled, "Metadata-only cleanup must remain reviewable")
        XCTAssertTrue(clean.toolTip?.contains("tags") == true)

        let table = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        XCTAssertTrue(clean.isEnabled, "Clean MKV must support a selection of MKV files")
        XCTAssertTrue(clean.toolTip?.contains("each selected MKV") == true)
    }

    @MainActor
    func testMainRefreshPreservesTypedTitleAndReviewedPlanUntilSelectionChanges() throws {
        let assets = ["Original", "Other"].map { title in
            MediaAsset(
                sourceURL: URL(fileURLWithPath: "/Media/\(title).mkv"),
                container: "matroska", tracks: [.init(id: 0, kind: .video, codec: "h264", uid: 1)],
                metadata: ["title": title])
        }
        let model = AppModel(initialAssets: assets)
        let controller = MainViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        model.didChange?()
        let content = controller.view
        try button("More Tools", in: content).performClick(nil)
        let title = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextField }.first {
                $0.isEditable && $0.accessibilityLabel() == "Segment title"
            })
        try type("Unsaved title", into: title, window: window)
        model.didChange?()
        XCTAssertEqual(title.stringValue, "Unsaved title")
        try button("Preview Change", in: content).performClick(nil)
        let run = try button("Verify & Run", in: content)
        XCTAssertTrue(run.isEnabled)
        model.didChange?()
        XCTAssertTrue(run.isEnabled, "Status refresh must not discard a reviewed plan")
        let table = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertEqual(title.stringValue, "Other")
        XCTAssertFalse(run.isEnabled, "A plan may not carry over to another source")
    }

    @MainActor
    func testSegmentTitleReadinessTracksTypingAndInvalidatesAnOutdatedPreview() throws {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Title.mkv"), container: "matroska",
            tracks: [.init(id: 0, kind: .video, codec: "h264", uid: 1)],
            metadata: ["title": "Original"])
        let model = AppModel(initialAssets: [asset])
        let controller = MainViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        model.didChange?()
        try button("More Tools", in: controller.view).performClick(nil)
        let title = try XCTUnwrap(
            descendants(controller.view).compactMap { $0 as? NSTextField }
                .first { $0.isEditable && $0.accessibilityLabel() == "Segment title" })
        let preview = try button("Preview Change", in: controller.view)
        let run = try button("Verify & Run", in: controller.view)
        XCTAssertFalse(preview.isEnabled)
        XCTAssertTrue(preview.toolTip?.contains("Change the segment title") == true)
        try type("New title", into: title, window: window)
        XCTAssertTrue(preview.isEnabled)
        preview.performClick(nil)
        XCTAssertTrue(run.isEnabled)
        try type("Another title", into: title, window: window)
        XCTAssertFalse(run.isEnabled, "The user must review the newly typed title")
        try type("Original", into: title, window: window)
        XCTAssertFalse(preview.isEnabled)
        try type("", into: title, window: window)
        XCTAssertTrue(preview.isEnabled, "Clearing an existing title is a valid change")
    }

    @MainActor
    func testInspectorEmptyStateAndExpandableToolsFitSmallWindows() throws {
        let model = AppModel()
        let controller = MainViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        window.setContentSize(NSSize(width: 820, height: 520))
        let scroll = try XCTUnwrap(
            descendants(controller.view).compactMap { $0 as? NSScrollView }
                .first { $0.accessibilityLabel() == "File actions" })
        XCTAssertTrue(scroll.isHidden, "Do not show a wall of disabled tools before intake")

        let selectedModel = AppModel(initialAssets: [
            MediaAsset(
                sourceURL: URL(fileURLWithPath: "/Media/Title.mkv"), container: "matroska",
                tracks: [.init(id: 0, kind: .video, codec: "h264", uid: 1)])
        ])
        let selected = MainViewController(model: selectedModel)
        let selectedWindow = NSWindow(contentViewController: selected)
        defer { selectedWindow.close() }
        selectedWindow.setContentSize(NSSize(width: 820, height: 520))
        selectedModel.didChange?()
        let details = try XCTUnwrap(
            descendants(selected.view).compactMap { $0 as? NSScrollView }
                .first { $0.accessibilityLabel() == "File actions" })
        let more = try button("More Tools", in: selected.view)
        let advanced = try button("Edit a Track…", in: selected.view)
        XCTAssertEqual(more.accessibilityLabel(), "More Tools")
        let collapsedIcon = try XCTUnwrap(more.image?.tiffRepresentation)
        XCTAssertFalse(details.isHidden)
        XCTAssertTrue(advanced.isHiddenOrHasHiddenAncestor)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            selectedWindow.appearance = NSAppearance(named: appearance)
            more.performClick(nil)
            selected.view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(more.frame.width, 80, "The disclosure must show its text label")
            XCTAssertFalse(advanced.isHiddenOrHasHiddenAncestor)
            XCTAssertNotEqual(more.image?.tiffRepresentation, collapsedIcon)
            XCTAssertEqual(more.accessibilityLabel(), "More Tools")
            XCTAssertTrue(details.hasVerticalScroller)
            let frame = details.convert(details.bounds, to: selected.view)
            XCTAssertGreaterThanOrEqual(frame.minY, 52)
            XCTAssertLessThanOrEqual(frame.maxY, selected.view.bounds.height)
            XCTAssertLessThanOrEqual(selected.view.bounds.width, 821)
            XCTAssertLessThanOrEqual(selected.view.bounds.height, 521)
            more.performClick(nil)
            XCTAssertTrue(advanced.isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(more.image?.tiffRepresentation, collapsedIcon)
        }
    }

    @MainActor
    func testMainRefreshPreservesSingleAndMultipleSelectionsByIdentity() throws {
        let assets = (0..<3).map { index in
            MediaAsset(
                sourceURL: URL(fileURLWithPath: "/Media/Part-\(index).mkv"),
                container: "matroska", tracks: [.init(id: 0, kind: .video, codec: "h264", uid: 1)])
        }
        let model = AppModel(initialAssets: assets)
        let controller = MainViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        let table = try XCTUnwrap(
            descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        model.didChange?()
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 1))
        table.selectRowIndexes(IndexSet([1, 2]), byExtendingSelection: false)
        model.didChange?()
        XCTAssertEqual(table.selectedRowIndexes, IndexSet([1, 2]))
        model.removeAssets(withIDs: [assets[0].id])
        XCTAssertEqual(
            table.selectedRowIndexes, IndexSet([0, 1]), "Keep selected identities when rows shift")
    }

    @MainActor
    func testSubtitleRemuxLabelsAndFieldsFitAtMinimumSize() throws {
        let controller = subtitleController()
        try checkMinimumForm(
            controller, labels: ["Video", "Subtitle language", "Subtitle track name"])
    }

    @MainActor
    func testExtractionPickersFitLongNamesAtMinimumSize() throws {
        try checkMinimumForm(
            AttachmentPickerWindowController(attachments: attachments), labels: ["Attachment"])
        for purpose: SubtitleTrackPickerPurpose in [
            .embeddedCleanup, .textExtraction, .timedTextConversion,
        ] {
            let tracks = [
                MediaTrack(
                    id: 2, kind: .subtitle,
                    codec: purpose == .timedTextConversion ? "mov_text" : "subrip",
                    uid: 3, language: "en",
                    title: String(repeating: "Long subtitle name ", count: 20))
            ]
            try checkMinimumForm(
                EmbeddedSubtitleTrackPickerWindowController(tracks: tracks, purpose: purpose),
                labels: ["Subtitle"])
        }
    }

    @MainActor
    func testSubtitleRemuxRecoversFromInvalidAudioAndSubtitleLanguagesWhileTyping() throws {
        let controller = subtitleController()
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let editor = try XCTUnwrap(
            window.contentViewController as? ExternalSubtitleMuxViewController)
        let review = try button("Review Remux", in: content)
        let fields = descendants(content).compactMap { $0 as? NSComboBox }
        let audio = try XCTUnwrap(
            fields.first { $0.accessibilityLabel() == "Audio track 1 language tag" })
        let subtitle = try XCTUnwrap(
            fields.first { $0.accessibilityLabel() == "Subtitle language tag" })
        let status = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Subtitle track status"
            })
        var accepted: ExternalSubtitleMuxOptions?
        editor.onContinue = { accepted = $0 }
        for field in [audio, subtitle] {
            try type("not_a_language", into: field, window: window)
            XCTAssertFalse(review.isEnabled)
            XCTAssertFalse(status.stringValue.isEmpty)
            try type("es", into: field, window: window)
            XCTAssertTrue(review.isEnabled)
            XCTAssertFalse(status.stringValue.contains("Could not"))
        }
        try type("fr", into: subtitle, window: window)
        review.performClick(nil)
        XCTAssertEqual(accepted?.subtitleMetadata.language, "fr")
        XCTAssertEqual(accepted?.sourceTrackLanguageOverrides, [1: "es"])
    }

    @MainActor
    func testSubtitleNameValidationDoesNotHideActionsAndRecovers() throws {
        let controller = subtitleController()
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let name = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Subtitle track name"
            })
        let review = try button("Review Remux", in: content)
        try type(String(repeating: "x", count: 4097), into: name, window: window)
        XCTAssertFalse(review.isEnabled)
        let status = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Subtitle track status"
            })
        XCTAssertTrue(status.stringValue.hasPrefix("Subtitle track name:"))
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(status.frame.width, content.frame.width - 60)
        let statusFrame = status.convert(status.bounds, to: content)
        let reviewFrame = review.convert(review.bounds, to: content)
        XCTAssertTrue(statusFrame.intersection(reviewFrame).isNull)
        XCTAssertGreaterThanOrEqual(reviewFrame.minY, 0)
        try type("English SDH", into: name, window: window)
        XCTAssertTrue(review.isEnabled)
        XCTAssertEqual(status.stringValue, "")
    }

    @MainActor
    func testCancellingReviewedSubtitleOptionsCompletesOnceWithoutAccepting() throws {
        let controller = subtitleController()
        let parent = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer {
            parent.close()
            controller.window?.close()
        }
        var completions = 0
        controller.beginOptionsSheet(for: parent) { options in
            completions += 1
            XCTAssertNil(options)
        }
        let cancel = try button("Cancel", in: XCTUnwrap(controller.window?.contentView))
        cancel.performClick(nil)
        cancel.performClick(nil)
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testChapterSuggestionSpacingRecoversWhileTypingAndRequiresADetector() throws {
        let controller = ChapterSuggestionOptionsWindowController(
            capabilities: .init(hasVideo: true, hasAudio: true))
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let spacing = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Minimum seconds between suggestions"
            })
        let analyze = try button("Analyze", in: content)
        for invalid in ["bad", "-1", "nan", "1e99"] {
            try type(invalid, into: spacing, window: window)
            XCTAssertFalse(analyze.isEnabled, invalid)
        }
        try type("12.5", into: spacing, window: window)
        XCTAssertTrue(analyze.isEnabled)
        let status = try XCTUnwrap(
            descendants(content).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Chapter suggestion settings error"
            })
        XCTAssertTrue(status.isHidden || status.stringValue.isEmpty)
        for title in ["Scene changes", "Black frames", "Silence"] {
            try button(title, in: content).performClick(nil)
        }
        XCTAssertFalse(analyze.isEnabled)
        try button("Silence", in: content).performClick(nil)
        XCTAssertTrue(analyze.isEnabled)
    }

    @MainActor
    func testTrackRemovalReadinessAndLongScrollableRows() throws {
        let tracks = (0..<30).map { index in
            MediaTrack(
                id: index, kind: index == 0 ? .video : .audio, codec: "aac", uid: UInt64(index + 1),
                title: String(repeating: "Long track name ", count: 20))
        }
        let controller = TrackRemovalWindowController(
            asset: .init(
                sourceURL: URL(fileURLWithPath: "/Media/Test.mkv"), container: "matroska",
                tracks: tracks))
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let preview = try button("Preview Removal", in: content)
        XCTAssertFalse(preview.isEnabled)
        let rows = descendants(content).compactMap { $0 as? NSButton }.filter {
            $0.accessibilityHelp()?.contains("Remove this track") == true
        }
        try checkScrollableRows(rows, window: window)
        rows[0].performClick(nil)
        XCTAssertTrue(preview.isEnabled)
        for row in rows.dropFirst() { row.performClick(nil) }
        XCTAssertFalse(preview.isEnabled, "Keep at least one playable track")
        rows[0].performClick(nil)
        XCTAssertTrue(preview.isEnabled)
        var removal: TrackRemoval?
        (window.contentViewController as? TrackRemovalViewController)?.onPreview = { removal = $0 }
        preview.performClick(nil)
        XCTAssertEqual(removal?.trackUIDs.count, 29)
    }

    @MainActor
    func testAttachmentRemovalReadinessAndLongScrollableRows() throws {
        let controller = AttachmentRemovalWindowController(attachments: attachments)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let review = try button("Review Removal", in: content)
        XCTAssertFalse(review.isEnabled)
        let rows = descendants(content).compactMap { $0 as? NSButton }.filter {
            $0.accessibilityHelp()?.contains("Remove this attachment") == true
        }
        try checkScrollableRows(rows, window: window)
        rows[0].performClick(nil)
        XCTAssertTrue(review.isEnabled)
        rows[0].performClick(nil)
        XCTAssertFalse(review.isEnabled)
    }

    private var attachments: [MediaAttachment] {
        (0..<30).map { index in
            MediaAttachment(
                id: index, filename: String(repeating: "Very long attachment name ", count: 15),
                mimeType: "application/octet-stream", size: 1024, uid: UInt64(index + 1))
        }
    }

    @MainActor
    private func subtitleController() -> ExternalSubtitleMuxWindowController {
        let cue = SubRipCue(
            id: 0, start: .init(milliseconds: 0), end: .init(milliseconds: 1000), lines: ["Hello"])
        let preview = SubtitleCleanupFilePreview(
            sourceURL: URL(
                fileURLWithPath: "/Media/" + String(repeating: "Long title ", count: 20) + ".en.srt"
            ),
            sourceSHA256: Data(repeating: 0, count: 32), encoding: .utf8, diagnostics: [],
            cleanup: SubtitleCleanupPolicy().preview(SubRipDocument(cues: [cue])),
            normalizationNeeded: false)
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.en.mp4"),
            container: "mov", duration: MediaTime(seconds: 2),
            tracks: [
                .init(id: 0, kind: .video, codec: "h264"), .init(id: 1, kind: .audio, codec: "aac"),
            ])
        let match = ExternalSubtitleMatcher().match(
            media: media, subtitleURL: preview.sourceURL,
            subtitle: preview.cleanup.original)
        return ExternalSubtitleMuxWindowController(
            media: media, preview: .subRip(preview),
            match: match, sourceTrackLanguageDefaults: [1: "en"])
    }

    @MainActor
    private func checkMinimumForm(_ controller: NSWindowController, labels: [String]) throws {
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            window.setContentSize(window.minSize)
            content.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(content.frame.width, window.minSize.width + 1)
            XCTAssertLessThanOrEqual(content.frame.height, window.minSize.height + 1)
            for grid in descendants(content).compactMap({ $0 as? NSGridView })
            where grid.numberOfColumns == 2 {
                let value = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 0).contentView)
                XCTAssertGreaterThan(
                    value.frame.width, 250,
                    "Values must not be squeezed by an expanding label column")
            }
            for title in labels {
                let label = try XCTUnwrap(
                    descendants(content).compactMap { $0 as? NSTextField }.first {
                        !$0.isEditable && $0.stringValue == title
                    })
                XCTAssertGreaterThanOrEqual(
                    label.frame.width + 1, label.intrinsicContentSize.width, title)
            }
            try capture(window, suffix: appearance.rawValue)
            for field in descendants(content).filter({
                $0 is NSComboBox || $0 is NSPopUpButton || ($0 as? NSTextField)?.isEditable == true
            }) {
                XCTAssertLessThanOrEqual(field.frame.height, 32, "Stretched form field")
            }
        }
    }

    @MainActor
    private func checkScrollableRows(_ rows: [NSButton], window: NSWindow) throws {
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(content).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertEqual(rows.count, 30)
        XCTAssertTrue(document.isFlipped, "First choice should start at the top")
        XCTAssertLessThanOrEqual(content.frame.width, window.minSize.width + 1)
        XCTAssertLessThanOrEqual(content.frame.height, window.minSize.height + 1)
        XCTAssertGreaterThan(document.frame.height, scroll.contentView.bounds.height)
        for row in rows {
            let frame = row.convert(row.bounds, to: document)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, document.bounds.width + 1)
            XCTAssertGreaterThanOrEqual(row.frame.height, 14)
        }
        try capture(window)
    }

    @MainActor
    private func capture(_ window: NSWindow, suffix: String = "") throws {
        guard let path = ProcessInfo.processInfo.environment["MKV_MAGIC_UX_CAPTURE_DIRECTORY"],
            path.hasPrefix("/")
        else { return }
        let content = try XCTUnwrap(window.contentView)
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        content.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(
            to: URL(fileURLWithPath: path).appendingPathComponent(window.title + suffix + ".png"))
    }

    @MainActor
    private func type(_ value: String, into field: NSTextField, window: NSWindow) throws {
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText(
            value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor
    private func button(_ title: String, in view: NSView) throws -> NSButton {
        try XCTUnwrap(descendants(view).compactMap { $0 as? NSButton }.first { $0.title == title })
    }
}
