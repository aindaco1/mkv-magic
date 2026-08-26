import AppKit
import MKVMagicCore

enum BatchReviewItemStatus: String, Sendable {
    case ready = "Ready"
    case noChanges = "No changes"
    case blocked = "Blocked"
}

struct BatchReviewItemPresentation: Identifiable, Sendable {
    let id: UUID
    let inputName: String
    let outputName: String
    let status: BatchReviewItemStatus
    let detail: String
}

struct BatchReviewDecision: Sendable {
    /// `nil` means each output stays beside its source.
    let commonDestinationDirectory: URL?
    let sourceDisposition: MediaQueueSourceDisposition
    let directoryAccess: OutputDirectorySecurityScope?
}

@MainActor
final class BatchReviewWindowController: NSWindowController {
    private let content: BatchReviewViewController

    init(
        title: String,
        explanation: String,
        items: [BatchReviewItemPresentation],
        actionTitle: String,
        offersSourceDisposition: Bool,
        initialDestinationDirectory: URL? = nil,
        initialDirectoryAccess: OutputDirectorySecurityScope? = nil
    ) {
        content = BatchReviewViewController(
            title: title,
            explanation: explanation,
            items: items,
            actionTitle: actionTitle,
            offersSourceDisposition: offersSourceDisposition,
            initialDestinationDirectory: initialDestinationDirectory,
            initialDirectoryAccess: initialDirectoryAccess
        )
        let window = NSWindow(contentViewController: content)
        window.title = title
        window.setContentSize(NSSize(width: 880, height: 560))
        window.minSize = NSSize(width: 720, height: 460)
        window.tabbingMode = .disallowed
        window.configureMKVMagicKeyboardNavigation(
            startingAt: content.preferredInitialFirstResponder
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping @MainActor (BatchReviewDecision?) -> Void
    ) {
        guard let window else {
            completion(nil)
            return
        }
        content.onFinish = { [weak self, weak parentWindow] decision in
            guard let self else { return }
            if let parentWindow, let window = self.window {
                parentWindow.endSheet(window)
            }
            completion(decision)
        }
        parentWindow.beginSheet(window)
    }
}

@MainActor
private final class BatchReviewViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate
{
    private let heading: String
    private let explanation: String
    private let items: [BatchReviewItemPresentation]
    private let offersSourceDisposition: Bool
    private let tableView = NSTableView()
    private let destinationLabel = NSTextField(labelWithString: "Beside each source (default)")
    private let chooseFolderButton = NSButton(
        title: "Choose Output Folder…",
        target: nil,
        action: nil
    )
    private let trashCheckbox = NSButton(
        checkboxWithTitle: "Move each original to Trash only after its output verifies",
        target: nil,
        action: nil
    )
    private let actionButton: NSButton
    private var commonDestinationDirectory: URL?
    private var directoryAccess: OutputDirectorySecurityScope?

    var onFinish: (@MainActor (BatchReviewDecision?) -> Void)?
    var preferredInitialFirstResponder: NSView { tableView }

    init(
        title: String,
        explanation: String,
        items: [BatchReviewItemPresentation],
        actionTitle: String,
        offersSourceDisposition: Bool,
        initialDestinationDirectory: URL?,
        initialDirectoryAccess: OutputDirectorySecurityScope?
    ) {
        heading = title
        self.explanation = explanation
        self.items = items
        self.offersSourceDisposition = offersSourceDisposition
        commonDestinationDirectory = initialDestinationDirectory?.standardizedFileURL
        directoryAccess = initialDirectoryAccess
        actionButton = NSButton(title: actionTitle, target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let title = NSTextField(labelWithString: heading)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: explanation)
        help.textColor = .secondaryLabelColor

        for (identifier, label, width) in [
            ("input", "Input", 155.0),
            ("output", "Output", 165.0),
            ("status", "Status", 115.0),
            ("detail", "What will happen", 215.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = label
            column.width = width
            column.minWidth = width
            tableView.addTableColumn(column)
        }
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 30
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.setAccessibilityLabel("Batch workflow review")
        tableView.setAccessibilityHelp(
            "Lists every selected file, proposed output, and whether it is ready, already clean, or blocked."
        )
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFolder)
        chooseFolderButton.setAccessibilityHelp(
            "Choose one folder for every ready output. The default keeps each output beside its source."
        )
        destinationLabel.textColor = .secondaryLabelColor
        destinationLabel.lineBreakMode = .byTruncatingMiddle
        destinationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let destinationSpacer = NSView()
        destinationSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let destinationRow = NSStackView(views: [
            chooseFolderButton, destinationLabel, destinationSpacer,
        ])
        destinationRow.orientation = .horizontal
        destinationRow.alignment = .centerY
        destinationRow.spacing = MKVMagicLayoutMetrics.controlGap

        trashCheckbox.state = .off
        trashCheckbox.isHidden = !offersSourceDisposition
        trashCheckbox.setAccessibilityHelp(
            "This remains off by default and is evaluated independently after each verified success."
        )

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        actionButton.target = self
        actionButton.action = #selector(accept)
        actionButton.keyEquivalent = "\r"
        actionButton.isEnabled = items.contains { $0.status == .ready }
        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [actionSpacer, cancelButton, actionButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = MKVMagicLayoutMetrics.controlGap

        let summary = NSTextField(
            labelWithString: BatchReviewPresentation.summary(items: items)
        )
        summary.font = .systemFont(ofSize: 13, weight: .medium)

        let stack = NSStackView(views: [
            title, help, summary, scroll, destinationRow, trashCheckbox, actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = MKVMagicLayoutMetrics.sectionGap
        stack.edgeInsets = MKVMagicLayoutMetrics.windowInsets
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.contentWidthConstraint(for: help),
            stack.contentWidthConstraint(for: summary),
            stack.contentWidthConstraint(for: scroll),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            stack.contentWidthConstraint(for: destinationRow),
            stack.contentWidthConstraint(for: trashCheckbox),
            stack.contentWidthConstraint(for: actions),
        ])
        view = root
        if let commonDestinationDirectory {
            destinationLabel.stringValue = commonDestinationDirectory.path(percentEncoded: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn else { return nil }
        let identifier = tableColumn.identifier
        let cell =
            tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: identifier)
        let item = items[row]
        let value =
            switch identifier.rawValue {
            case "input": item.inputName
            case "output": item.outputName
            case "status": item.status.rawValue
            case "detail": item.detail
            default: ""
            }
        cell.textField?.stringValue = value
        cell.toolTip = value
        return cell
    }

    @objc private func chooseFolder() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Batch Output Folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let directory = panel.url else { return }
            self.commonDestinationDirectory = directory.standardizedFileURL
            self.directoryAccess = OutputDirectorySecurityScope(directoryURL: directory)
            self.destinationLabel.stringValue = directory.path(percentEncoded: false)
        }
    }

    @objc private func cancel() {
        onFinish?(nil)
    }

    @objc private func accept() {
        onFinish?(
            BatchReviewDecision(
                commonDestinationDirectory: commonDestinationDirectory,
                sourceDisposition: offersSourceDisposition && trashCheckbox.state == .on
                    ? .trashAfterVerifiedSuccess : .keepOriginal,
                directoryAccess: directoryAccess
            )
        )
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode =
            identifier.rawValue == "input" || identifier.rawValue == "output"
            ? .byTruncatingMiddle : .byTruncatingTail
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

enum BatchReviewPresentation {
    static func summary(items: [BatchReviewItemPresentation]) -> String {
        let ready = items.count { $0.status == .ready }
        let noChanges = items.count { $0.status == .noChanges }
        let blocked = items.count { $0.status == .blocked }
        return "\(ready) ready • \(noChanges) no changes • \(blocked) blocked"
    }
}
