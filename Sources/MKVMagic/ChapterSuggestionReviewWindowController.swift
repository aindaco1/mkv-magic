import AppKit
import MKVMagicCore

@MainActor
final class ChapterSuggestionReviewWindowController: NSWindowController {
    private let reviewViewController: ChapterSuggestionReviewViewController
    private var completion: (([ChapterSuggestion]) -> Void)?

    init(suggestions: [ChapterSuggestion]) {
        reviewViewController = ChapterSuggestionReviewViewController(suggestions: suggestions)
        let window = NSPanel(contentViewController: reviewViewController)
        window.title = "Review Chapter Suggestions"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 520))
        window.minSize = NSSize(width: 560, height: 400)
        window.configureMKVMagicKeyboardNavigation(
            startingAt: reviewViewController.preferredInitialFirstResponder
        )
        super.init(window: window)
        reviewViewController.onCancel = { [weak self] in self?.finish(with: []) }
        reviewViewController.onAdd = { [weak self] suggestions in
            self?.finish(with: suggestions)
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
        self.completion = completion
        guard let window else {
            completion([])
            return
        }
        parentWindow.beginSheet(window)
    }

    func cancel() {
        finish(with: [])
    }

    private func finish(with suggestions: [ChapterSuggestion]) {
        guard let completion else { return }
        if let window {
            window.sheetParent?.endSheet(window)
        }
        self.completion = nil
        completion(suggestions)
    }
}

@MainActor
private final class ChapterSuggestionReviewViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate
{
    var onCancel: (() -> Void)?
    var onAdd: (([ChapterSuggestion]) -> Void)?

    private let suggestions: [ChapterSuggestion]
    private var selectedRows: Set<Int>
    private let tableView = NSTableView()
    private let selectionLabel = NSTextField(labelWithString: "")
    private let addButton = NSButton(title: "Add Selected", target: nil, action: nil)

    var preferredInitialFirstResponder: NSView { tableView }

    init(suggestions: [ChapterSuggestion]) {
        self.suggestions = suggestions
        selectedRows = Set(suggestions.indices)
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
            wrappingLabelWithString:
                "These timestamps were detected locally. Uncheck false positives; you can rename or nest every added chapter afterward."
        )
        explanation.textColor = .secondaryLabelColor

        let useColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Use"))
        useColumn.title = "Use"
        useColumn.width = 56
        useColumn.minWidth = 48
        useColumn.maxWidth = 72
        let timeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Time"))
        timeColumn.title = "Time"
        timeColumn.width = 150
        timeColumn.minWidth = 120
        let signalColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Signal"))
        signalColumn.title = "Detected boundary"
        signalColumn.width = 400
        signalColumn.minWidth = 240
        tableView.addTableColumn(useColumn)
        tableView.addTableColumn(timeColumn)
        tableView.addTableColumn(signalColumn)
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
        scroll.borderType = .bezelBorder

        let selectAll = NSButton(
            title: "Select All", target: self, action: #selector(selectAllRows))
        let selectNone = NSButton(
            title: "Select None", target: self, action: #selector(selectNoRows))
        selectionLabel.textColor = .secondaryLabelColor
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
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            selectionTools.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        updateSelectionState()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        suggestions.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard suggestions.indices.contains(row), let identifier = tableColumn?.identifier else {
            return nil
        }
        let suggestion = suggestions[row]
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
        default:
            return labelCell(identifier: identifier, value: suggestion.signalDescription)
        }
    }

    @objc private func toggleRow(_ sender: NSButton) {
        guard suggestions.indices.contains(sender.tag) else { return }
        if sender.state == .on {
            selectedRows.insert(sender.tag)
        } else {
            selectedRows.remove(sender.tag)
        }
        updateSelectionState()
    }

    @objc private func selectAllRows() {
        selectedRows = Set(suggestions.indices)
        tableView.reloadData()
        updateSelectionState()
    }

    @objc private func selectNoRows() {
        selectedRows.removeAll()
        tableView.reloadData()
        updateSelectionState()
    }

    @objc private func addSelected() {
        onAdd?(selectedRows.sorted().map { suggestions[$0] })
    }

    @objc private func cancel() {
        onCancel?()
    }

    private func updateSelectionState() {
        selectionLabel.stringValue =
            "\(selectedRows.count) of \(suggestions.count) selected"
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
