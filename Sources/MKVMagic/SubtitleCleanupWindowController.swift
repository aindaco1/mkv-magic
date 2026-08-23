import AppKit
import MKVMagicCore
import MKVMagicExecution

@MainActor
final class SubtitleCleanupWindowController: NSWindowController {
    private let cleanupViewController: SubtitleCleanupViewController

    init(preview: SubtitleCleanupFilePreview) {
        cleanupViewController = SubtitleCleanupViewController(preview: preview)
        let window = NSWindow(contentViewController: cleanupViewController)
        window.title = "Clean SRT Subtitle"
        window.setContentSize(NSSize(width: 740, height: 560))
        window.minSize = NSSize(width: 640, height: 480)
        window.styleMask.insert(.resizable)
        window.tabbingMode = .disallowed
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (Set<Int>?) -> Void
    ) {
        guard let window else {
            completion(nil)
            return
        }
        cleanupViewController.onComplete = { [weak self, weak parentWindow] restoredCueIDs in
            guard let self else { return }
            if let parentWindow, let sheet = self.window, parentWindow.attachedSheet === sheet {
                parentWindow.endSheet(sheet)
            }
            completion(restoredCueIDs)
        }
        parentWindow.beginSheet(window)
    }
}

@MainActor
final class SubtitleCleanupViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate
{
    var onComplete: ((Set<Int>?) -> Void)?
    private let preview: SubtitleCleanupFilePreview
    private let tableView = NSTableView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let validationLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(
        title: "Continue",
        target: nil,
        action: nil
    )
    private var appliedChangeIDs = Set<Int>()

    init(preview: SubtitleCleanupFilePreview) {
        self.preview = preview
        appliedChangeIDs = Set(preview.cleanup.changes.map(\.id))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        let heading = NSTextField(labelWithString: "Review subtitle cleanup")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString:
                "Only deterministic whole-block ad matches and accidental edge whitespace are selected. Uncheck any change to restore that cue. Cue timing is never changed."
        )
        explanation.textColor = .secondaryLabelColor
        summaryLabel.stringValue = SubtitleCleanupPresentation.summary(preview)

        let column = NSTableColumn(identifier: .init("change"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 86
        tableView.allowsEmptySelection = true
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let normalization = NSTextField(
            wrappingLabelWithString: SubtitleCleanupPresentation.normalization(preview)
        )
        normalization.textColor = .secondaryLabelColor
        normalization.font = .systemFont(ofSize: 11)
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        saveButton.target = self
        saveButton.action = #selector(confirm)
        saveButton.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [validationLabel, spacer, cancel, saveButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let stack = NSStackView(views: [
            heading, explanation, summaryLabel, scroll, normalization, actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        updateSelectionState()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        preview.cleanup.changes.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let change = preview.cleanup.changes[row]
        let checkbox = NSButton(
            checkboxWithTitle: SubtitleCleanupPresentation.title(change),
            target: self,
            action: #selector(toggleChange(_:))
        )
        checkbox.state = appliedChangeIDs.contains(change.id) ? .on : .off
        checkbox.tag = row
        let timing = NSTextField(
            labelWithString:
                "\(SubtitleCleanupPresentation.time(change.before.start)) → "
                + SubtitleCleanupPresentation.time(change.before.end)
        )
        timing.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        timing.textColor = .secondaryLabelColor
        let detail = NSTextField(
            wrappingLabelWithString: SubtitleCleanupPresentation.detail(change)
        )
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        let stack = NSStackView(views: [checkbox, timing, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        let cell = NSTableCellView()
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func toggleChange(_ sender: NSButton) {
        guard preview.cleanup.changes.indices.contains(sender.tag) else { return }
        let id = preview.cleanup.changes[sender.tag].id
        if sender.state == .on {
            appliedChangeIDs.insert(id)
        } else {
            appliedChangeIDs.remove(id)
        }
        updateSelectionState()
    }

    @objc private func cancel() { onComplete?(nil) }

    @objc private func confirm() {
        guard
            SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: appliedChangeIDs
            )
        else { return }
        let allChangeIDs = Set(preview.cleanup.changes.map(\.id))
        onComplete?(allChangeIDs.subtracting(appliedChangeIDs))
    }

    private func updateSelectionState() {
        summaryLabel.stringValue = SubtitleCleanupPresentation.selectionSummary(
            appliedCount: appliedChangeIDs.count,
            totalCount: preview.cleanup.changes.count,
            cueCount: preview.cleanup.original.cues.count
        )
        saveButton.isEnabled = SubtitleCleanupPresentation.canConfirm(
            preview: preview,
            appliedChangeIDs: appliedChangeIDs
        )
        validationLabel.stringValue =
            saveButton.isEnabled ? "" : "Restore at least one cue before continuing."
    }
}

enum SubtitleCleanupPresentation {
    static func summary(_ preview: SubtitleCleanupFilePreview) -> String {
        selectionSummary(
            appliedCount: preview.cleanup.changes.count,
            totalCount: preview.cleanup.changes.count,
            cueCount: preview.cleanup.original.cues.count
        )
    }

    static func selectionSummary(appliedCount: Int, totalCount: Int, cueCount: Int) -> String {
        "\(cueCount) cues • \(appliedCount) of \(totalCount) suggested changes selected"
    }

    static func normalization(_ preview: SubtitleCleanupFilePreview) -> String {
        var details = ["Output: UTF-8 without BOM, LF line endings, sequential cue numbers"]
        if preview.encoding != .utf8 {
            details.append("Input encoding: \(preview.encoding.rawValue)")
        }
        if !preview.diagnostics.isEmpty {
            details.append("Structural normalization: \(preview.diagnostics.count) item(s)")
        }
        return details.joined(separator: " • ")
    }

    static func title(_ change: SubtitleCleanupChange) -> String {
        if change.reasons.contains(.ytsAdvertisement) { return "Remove known YTS/YIFY ad block" }
        return "Trim accidental edge whitespace"
    }

    static func detail(_ change: SubtitleCleanupChange) -> String {
        let before = change.before.lines.joined(separator: " / ")
        guard let after = change.after else { return "Remove: \(before)" }
        return "Before: \(before)   →   After: \(after.lines.joined(separator: " / "))"
    }

    static func time(_ timestamp: SubRipTimestamp) -> String {
        let milliseconds = max(0, timestamp.milliseconds)
        return String(
            format: "%02lld:%02lld:%02lld,%03lld",
            milliseconds / 3_600_000,
            (milliseconds / 60_000) % 60,
            (milliseconds / 1_000) % 60,
            milliseconds % 1_000
        )
    }

    static func canConfirm(
        preview: SubtitleCleanupFilePreview,
        appliedChangeIDs: Set<Int>
    ) -> Bool {
        let allChangeIDs = Set(preview.cleanup.changes.map(\.id))
        let restoredCueIDs = allChangeIDs.subtracting(appliedChangeIDs)
        return !preview.cleanup.document(restoringCueIDs: restoredCueIDs).cues.isEmpty
    }
}
