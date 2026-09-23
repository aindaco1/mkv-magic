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
    var sourceURL: URL? = nil
    var isEditable = false
}

struct BatchReviewDecision: Sendable {
    let commonDestinationDirectory: URL
    let sourceDisposition: MediaQueueSourceDisposition
    let directoryAccess: OutputDirectorySecurityScope
    var includedItemIDs: Set<UUID>? = nil
    var perItemDirectories: [UUID: OutputDirectorySecurityScope] = [:]

    func includes(_ id: UUID) -> Bool { includedItemIDs?.contains(id) ?? true }

    func destination(for id: UUID, filename: String, reservedPaths: Set<String> = []) throws -> URL
    {
        try OutputDestinationPolicy.availableOutputURL(
            filename: filename,
            directoryURL: perItemDirectories[id]?.directoryURL ?? commonDestinationDirectory,
            fileExists: { reservedPaths.contains($0) || FileManager.default.fileExists(atPath: $0) }
        )
    }
}

@MainActor
final class BatchReviewWindowController: NSWindowController {
    private let content: BatchReviewViewController
    var onEditItem: ((UUID) -> Void)? {
        get { content.onEditItem }
        set { content.onEditItem = newValue }
    }

    func update(_ item: BatchReviewItemPresentation) { content.update(item) }

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
        window.setContentSize(NSSize(width: 920, height: 680))
        window.minSize = NSSize(width: 780, height: 620)
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
    private var items: [BatchReviewItemPresentation]
    private var includedIDs: Set<UUID>
    private let summary = NSTextField(labelWithString: "")
    private let editButton = NSButton(title: "Edit Selected…", target: nil, action: nil)
    private let besideSource = NSButton(
        checkboxWithTitle: "Save beside each source", target: nil, action: nil)
    var onEditItem: ((UUID) -> Void)? {
        didSet {
            editButton.isHidden = onEditItem == nil
            if isViewLoaded { updateDetails() }
        }
    }
    private let offersSourceDisposition: Bool
    private let tableView = NSTableView()
    private let details = NSTextView()
    private let destinationLabel = NSTextField(
        labelWithString: "Choose one output folder to continue"
    )
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
        self.includedIDs = Set(items.filter { $0.status == .ready }.map(\.id))
        self.offersSourceDisposition = offersSourceDisposition
        let supportsSourceFolders = items.filter { $0.status == .ready }.allSatisfy {
            $0.sourceURL != nil
        }
        besideSource.isHidden = !supportsSourceFolders
        besideSource.state =
            supportsSourceFolders && initialDestinationDirectory == nil
                && OutputDestinationPreferences().mode == .besideSource ? .on : .off
        if let initialDestinationDirectory, let initialDirectoryAccess,
            initialDirectoryAccess.directoryURL
                == initialDestinationDirectory.standardizedFileURL
        {
            commonDestinationDirectory = initialDirectoryAccess.directoryURL
            directoryAccess = initialDirectoryAccess
        } else {
            commonDestinationDirectory = nil
            directoryAccess = nil
        }
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
        help.textColor = AppPalette.secondaryText

        for (identifier, label, width) in [
            ("include", "Include", 65.0),
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
        ReadOnlyTextViewPresentation.configure(
            details, drawsBackground: true,
            font: .systemFont(ofSize: 13))
        details.setAccessibilityLabel("Selected batch item details")
        ReadOnlyTextViewPresentation.present(
            "Select a row to read its full plan and warnings.", in: details)
        let detailScroll = ReadOnlyTextViewPresentation.scrollView(
            containing: details, borderType: .bezelBorder)

        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFolder)
        chooseFolderButton.setAccessibilityHelp(
            "Choose one writable folder for every ready output."
        )
        besideSource.target = self
        besideSource.action = #selector(destinationModeChanged)
        destinationLabel.textColor = AppPalette.secondaryText
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
        actionButton.isEnabled =
            items.contains { $0.status == .ready }
            && commonDestinationDirectory != nil
            && directoryAccess != nil
        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        editButton.target = self
        editButton.action = #selector(editSelected)
        editButton.isHidden = onEditItem == nil
        editButton.isEnabled = false
        let actions = NSStackView(views: [editButton, actionSpacer, cancelButton, actionButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = MKVMagicLayoutMetrics.controlGap

        summary.stringValue = BatchReviewPresentation.summary(items: items)
        summary.font = .systemFont(ofSize: 13, weight: .medium)

        let stack = NSStackView(views: [
            title, help, summary, scroll, detailScroll, besideSource, destinationRow, trashCheckbox,
            actions,
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
            stack.contentWidthConstraint(for: detailScroll),
            detailScroll.heightAnchor.constraint(equalToConstant: 80),
            stack.contentWidthConstraint(for: destinationRow),
            stack.contentWidthConstraint(for: trashCheckbox),
            stack.contentWidthConstraint(for: actions),
        ])
        view = root
        if let commonDestinationDirectory {
            destinationLabel.stringValue = commonDestinationDirectory.path(percentEncoded: false)
        }
        updateSummary()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn else { return nil }
        let identifier = tableColumn.identifier
        if identifier.rawValue == "include" {
            let checkbox = NSButton(
                checkboxWithTitle: "", target: self, action: #selector(toggleIncluded(_:)))
            checkbox.tag = row
            checkbox.state = includedIDs.contains(items[row].id) ? .on : .off
            checkbox.isEnabled = items[row].status == .ready
            checkbox.setAccessibilityLabel("Include \(items[row].inputName)")
            return checkbox
        }
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
            guard let access = OutputDirectorySecurityScope(directoryURL: directory) else {
                let alert = NSAlert()
                alert.messageText = "MKV Magic could not access that output folder."
                alert.informativeText =
                    "Choose a writable folder through the folder picker and try again."
                alert.beginSheetModal(for: window)
                return
            }
            self.commonDestinationDirectory = directory.standardizedFileURL
            self.directoryAccess = access
            self.besideSource.state = .off
            self.destinationLabel.stringValue = directory.path(percentEncoded: false)
            self.updateSummary()
        }
    }

    @objc private func cancel() {
        onFinish?(nil)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDetails()
    }

    private func updateDetails() {
        let row = tableView.selectedRow
        editButton.isEnabled =
            onEditItem != nil && items.indices.contains(row) && items[row].isEditable
        let text =
            items.indices.contains(row)
            ? "\(items[row].inputName)\n\(items[row].status.rawValue) • \(items[row].detail)"
            : "Select a row to read its full plan and warnings."
        ReadOnlyTextViewPresentation.present(text, in: details)
    }

    @objc private func editSelected() {
        guard items.indices.contains(tableView.selectedRow), items[tableView.selectedRow].isEditable
        else { return }
        onEditItem?(items[tableView.selectedRow].id)
    }

    @objc private func toggleIncluded(_ sender: NSButton) {
        guard items.indices.contains(sender.tag), items[sender.tag].status == .ready else { return }
        let id = items[sender.tag].id
        if sender.state == .on { includedIDs.insert(id) } else { includedIDs.remove(id) }
        updateSummary()
    }

    func update(_ item: BatchReviewItemPresentation) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let wasReady = items[index].status == .ready
        items[index] = item
        if item.status != .ready {
            includedIDs.remove(item.id)
        } else if !wasReady {
            includedIDs.insert(item.id)
        }
        tableView.reloadData()
        updateDetails()
        updateSummary()
    }

    private func updateSummary() {
        summary.stringValue =
            "\(includedIDs.count) included • " + BatchReviewPresentation.summary(items: items)
        actionButton.isEnabled =
            !includedIDs.isEmpty
            && (besideSource.state == .on
                || (commonDestinationDirectory != nil && directoryAccess != nil))
        if besideSource.state == .on {
            destinationLabel.stringValue =
                "Each source folder • permission requested only if needed"
        }
    }

    @objc private func destinationModeChanged() {
        if besideSource.state == .off {
            destinationLabel.stringValue =
                commonDestinationDirectory?.path ?? "Choose one output folder to continue"
        }
        updateSummary()
    }

    @objc private func accept() {
        guard !includedIDs.isEmpty else { return }
        var itemDirectories = [UUID: OutputDirectorySecurityScope]()
        if besideSource.state == .on {
            let preferences = OutputDestinationPreferences()
            var grantedFolders = [String: OutputDirectorySecurityScope]()
            do {
                for item in items where includedIDs.contains(item.id) {
                    guard let source = item.sourceURL else {
                        throw OutputDestinationPreferenceError.unavailableChosenFolder
                    }
                    let parent = source.standardizedFileURL.deletingLastPathComponent()
                    let capability = preferences.authorizedFolder(matching: parent) ?? parent
                    guard
                        let access = try grantedFolders[parent.path]
                            ?? OutputDirectorySecurityScope(directoryURL: capability)
                            ?? OutputDirectoryAuthorization.authorize(
                                destinationURL: parent.appendingPathComponent(item.outputName))
                    else { return }
                    try preferences.rememberAuthorizedFolder(access.directoryURL)
                    grantedFolders[parent.path] = access
                    itemDirectories[item.id] = access
                }
            } catch {
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.shortReason(error), in: destinationLabel)
                return
            }
        }
        guard let access = itemDirectories.values.first ?? directoryAccess,
            let directory = itemDirectories.isEmpty
                ? commonDestinationDirectory : access.directoryURL
        else { return }
        onFinish?(
            BatchReviewDecision(
                commonDestinationDirectory: directory,
                sourceDisposition: offersSourceDisposition && trashCheckbox.state == .on
                    ? .trashAfterVerifiedSuccess : .keepOriginal,
                directoryAccess: access,
                includedItemIDs: includedIDs,
                perItemDirectories: itemDirectories
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
