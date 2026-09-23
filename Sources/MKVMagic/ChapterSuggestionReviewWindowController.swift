import AppKit
import MKVMagicCore

struct ChapterSuggestionReviewGroup: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceName: String
    let suggestions: [ChapterSuggestion]

    init(id: UUID, sourceName: String, suggestions: [ChapterSuggestion]) {
        self.id = id
        self.sourceName = sourceName
        self.suggestions = suggestions
    }
}

struct ReviewedChapterSuggestionGroup: Equatable, Sendable {
    let id: UUID
    let suggestions: [ChapterSuggestion]
}

@MainActor
final class ChapterSuggestionReviewWindowController: NSWindowController {
    private let reviewViewController: ChapterSuggestionReviewViewController
    private let singleGroupID: UUID?
    private var completion: (([ReviewedChapterSuggestionGroup]) -> Void)?

    init(suggestions: [ChapterSuggestion]) {
        let id = UUID()
        singleGroupID = id
        reviewViewController = ChapterSuggestionReviewViewController(
            groups: [
                ChapterSuggestionReviewGroup(
                    id: id,
                    sourceName: "",
                    suggestions: suggestions
                )
            ],
            explanation:
                "These timestamps were detected locally. Uncheck false positives; you can rename or nest every added chapter afterward.",
            actionTitle: "Add Selected"
        )
        let window = Self.makeWindow(content: reviewViewController)
        window.minSize = NSSize(width: 680, height: 400)
        super.init(window: window)
        configureCallbacks()
    }

    init(groups: [ChapterSuggestionReviewGroup]) {
        singleGroupID = nil
        reviewViewController = ChapterSuggestionReviewViewController(
            groups: groups,
            explanation:
                "Every timestamp was detected locally. Uncheck false positives for any file before MKV Magic prepares separate verified chapter copies.",
            actionTitle: "Continue with Selected"
        )
        let window = Self.makeWindow(content: reviewViewController)
        super.init(window: window)
        configureCallbacks()
    }

    private static func makeWindow(
        content: ChapterSuggestionReviewViewController
    ) -> NSPanel {
        let window = NSPanel(contentViewController: content)
        window.title = "Review Chapter Suggestions"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 520))
        window.minSize = NSSize(width: 560, height: 400)
        window.configureMKVMagicKeyboardNavigation(
            startingAt: content.preferredInitialFirstResponder
        )
        return window
    }

    private func configureCallbacks() {
        reviewViewController.onCancel = { [weak self] in self?.finish(with: []) }
        reviewViewController.onAdd = { [weak self] groups in
            self?.finish(with: groups)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping ([ChapterSuggestion]) -> Void
    ) {
        guard let singleGroupID else {
            completion([])
            return
        }
        self.completion = { groups in
            completion(groups.first { $0.id == singleGroupID }?.suggestions ?? [])
        }
        beginSheet(for: parentWindow)
    }

    func beginBatchSheet(
        for parentWindow: NSWindow,
        completion: @escaping ([ReviewedChapterSuggestionGroup]) -> Void
    ) {
        guard singleGroupID == nil else {
            completion([])
            return
        }
        self.completion = completion
        beginSheet(for: parentWindow)
    }

    private func beginSheet(for parentWindow: NSWindow) {
        guard let window else {
            completion?([])
            return
        }
        parentWindow.beginSheet(window)
    }

    func cancel() {
        finish(with: [])
    }

    private func finish(with groups: [ReviewedChapterSuggestionGroup]) {
        guard let completion else { return }
        if let window {
            window.sheetParent?.endSheet(window)
        }
        self.completion = nil
        completion(groups)
    }
}

@MainActor
private final class ChapterSuggestionReviewViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate
{
    var onCancel: (() -> Void)?
    var onAdd: (([ReviewedChapterSuggestionGroup]) -> Void)?

    private struct Row {
        let groupID: UUID
        let sourceName: String
        let suggestion: ChapterSuggestion
    }

    private let groups: [ChapterSuggestionReviewGroup]
    private let explanationText: String
    private let rows: [Row]
    private var selectedRows: Set<Int>
    private let tableView = NSTableView()
    private let selectionLabel = NSTextField(labelWithString: "")
    private let addButton: NSButton

    var preferredInitialFirstResponder: NSView { tableView }

    init(
        groups: [ChapterSuggestionReviewGroup],
        explanation: String,
        actionTitle: String
    ) {
        self.groups = groups
        explanationText = explanation
        rows = groups.flatMap { group in
            group.suggestions.map {
                Row(groupID: group.id, sourceName: group.sourceName, suggestion: $0)
            }
        }
        selectedRows = Set(rows.indices)
        addButton = NSButton(title: actionTitle, target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Review before adding")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString: explanationText
        )
        explanation.textColor = AppPalette.secondaryText

        let useColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Use"))
        useColumn.title = "Use"
        useColumn.width = 56
        useColumn.minWidth = 48
        useColumn.maxWidth = 72
        tableView.addTableColumn(useColumn)
        if groups.count > 1 {
            let sourceColumn = NSTableColumn(
                identifier: NSUserInterfaceItemIdentifier("Source"))
            sourceColumn.title = "File"
            sourceColumn.width = 190
            sourceColumn.minWidth = 120
            tableView.addTableColumn(sourceColumn)
        }
        let timeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Time"))
        timeColumn.title = "Time"
        timeColumn.width = 150
        timeColumn.minWidth = 120
        tableView.addTableColumn(timeColumn)
        let signalColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Signal"))
        signalColumn.title = "Detected boundary"
        signalColumn.width = 400
        signalColumn.minWidth = 240
        tableView.addTableColumn(signalColumn)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.setAccessibilityLabel("Detected chapter boundaries")
        tableView.setAccessibilityHelp(
            "Review each locally detected timestamp and uncheck false positives."
        )
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = groups.count > 1
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        let selectAll = NSButton(
            title: "Select All", target: self, action: #selector(selectAllRows))
        let selectNone = NSButton(
            title: "Select None", target: self, action: #selector(selectNoRows))
        selectionLabel.textColor = AppPalette.secondaryText
        selectionLabel.setAccessibilityLabel("Selected chapter suggestion count")
        let selectionSpacer = NSView()
        selectionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let selectionTools = NSStackView(views: [
            selectAll, selectNone, selectionSpacer, selectionLabel,
        ])
        selectionTools.orientation = .horizontal
        selectionTools.alignment = .centerY
        selectionTools.spacing = 8

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityHelp("Close without adding detected chapter boundaries.")
        addButton.target = self
        addButton.action = #selector(addSelected)
        addButton.keyEquivalent = "\r"
        addButton.setAccessibilityHelp(
            "Add every checked timestamp as an editable chapter."
        )
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [footerSpacer, cancelButton, addButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10

        let stack = NSStackView(views: [heading, explanation, scroll, selectionTools, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        selectionTools.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.contentWidthConstraint(for: scroll),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            stack.contentWidthConstraint(for: selectionTools),
            stack.contentWidthConstraint(for: footer),
        ])
        view = root
        updateSelectionState()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard rows.indices.contains(row), let identifier = tableColumn?.identifier else {
            return nil
        }
        let item = rows[row]
        let suggestion = item.suggestion
        switch identifier.rawValue {
        case "Use":
            let checkbox =
                tableView.makeView(withIdentifier: identifier, owner: self) as? NSButton
                ?? NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRow(_:)))
            checkbox.identifier = identifier
            checkbox.target = self
            checkbox.action = #selector(toggleRow(_:))
            checkbox.tag = row
            checkbox.state = selectedRows.contains(row) ? .on : .off
            checkbox.setAccessibilityLabel(
                "Use suggestion at \(ChapterTimestamp.format(suggestion.time, digits: 3))")
            return checkbox
        case "Time":
            return labelCell(
                identifier: identifier,
                value: ChapterTimestamp.format(suggestion.time, digits: 3)
            )
        case "Source":
            return labelCell(identifier: identifier, value: item.sourceName)
        default:
            return labelCell(identifier: identifier, value: suggestion.signalDescription)
        }
    }

    @objc private func toggleRow(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }
        if sender.state == .on {
            selectedRows.insert(sender.tag)
        } else {
            selectedRows.remove(sender.tag)
        }
        updateSelectionState()
    }

    @objc private func selectAllRows() {
        selectedRows = Set(rows.indices)
        tableView.reloadData()
        updateSelectionState()
    }

    @objc private func selectNoRows() {
        selectedRows.removeAll()
        tableView.reloadData()
        updateSelectionState()
    }

    @objc private func addSelected() {
        let selected = selectedRows.sorted().map { rows[$0] }
        onAdd?(
            groups.compactMap { group in
                let suggestions = selected.filter { $0.groupID == group.id }.map(\.suggestion)
                guard !suggestions.isEmpty else { return nil }
                return ReviewedChapterSuggestionGroup(id: group.id, suggestions: suggestions)
            }
        )
    }

    @objc private func cancel() {
        onCancel?()
    }

    private func updateSelectionState() {
        selectionLabel.stringValue =
            "\(selectedRows.count) of \(rows.count) selected"
        addButton.isEnabled = !selectedRows.isEmpty
    }

    private func labelCell(identifier: NSUserInterfaceItemIdentifier, value: String) -> NSView {
        let label =
            tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? NSTextField(labelWithString: "")
        label.identifier = identifier
        label.stringValue = value
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
