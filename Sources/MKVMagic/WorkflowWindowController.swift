import AppKit
import MKVMagicCore
import MKVMagicSystem
import UniformTypeIdentifiers

typealias WorkflowLibrarySaveHandler = @MainActor ([SavedWorkflow]) async throws -> Void

@MainActor
final class WorkflowWindowController: NSWindowController {
    init(
        workflows: [SavedWorkflow],
        hasSelectedAsset: Bool,
        onSave: @escaping WorkflowLibrarySaveHandler,
        onUse: @escaping (SavedWorkflow) -> Void
    ) {
        let viewController = WorkflowLibraryViewController(
            workflows: workflows,
            hasSelectedAsset: hasSelectedAsset,
            onSave: onSave,
            onUse: onUse
        )
        let window = NSWindow(contentViewController: viewController)
        window.title = "Workflows"
        window.setContentSize(NSSize(width: 780, height: 560))
        window.minSize = NSSize(width: 680, height: 480)
        window.styleMask.insert(.resizable)
        window.tabbingMode = .disallowed
        window.configureMKVMagicKeyboardNavigation(
            startingAt: viewController.preferredInitialFirstResponder
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class WorkflowLibraryViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate, NSTextFieldDelegate
{
    private var workflows: [SavedWorkflow]
    private let hasSelectedAsset: Bool
    private let onSave: WorkflowLibrarySaveHandler
    private let onUse: (SavedWorkflow) -> Void
    private let workflowTable = NSTableView()
    private let stepTable = NSTableView()
    private let nameField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let duplicateButton = NSButton(title: "Duplicate", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let importButton = NSButton(title: "Import…", target: nil, action: nil)
    private let exportButton = NSButton(title: "Export…", target: nil, action: nil)
    private let addStepButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let removeStepButton = NSButton(title: "Remove Step", target: nil, action: nil)
    private let moveUpButton = NSButton(title: "Move Up", target: nil, action: nil)
    private let moveDownButton = NSButton(title: "Move Down", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let useButton = NSButton(title: "Save & Preview", target: nil, action: nil)

    var preferredInitialFirstResponder: NSView { workflowTable }

    init(
        workflows: [SavedWorkflow],
        hasSelectedAsset: Bool,
        onSave: @escaping WorkflowLibrarySaveHandler,
        onUse: @escaping (SavedWorkflow) -> Void
    ) {
        self.workflows = workflows
        self.hasSelectedAsset = hasSelectedAsset
        self.onSave = onSave
        self.onUse = onUse
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        configureTables()

        let sidebar = makeSidebar()
        let editor = makeEditor()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        editor.translatesAutoresizingMaskIntoConstraints = false
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(editor)
        split.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            split.topAnchor.constraint(equalTo: view.topAnchor),
            split.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 235),
        ])

        workflowTable.reloadData()
        if !workflows.isEmpty {
            workflowTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        refreshEditor()
    }

    private func configureTables() {
        let workflowColumn = NSTableColumn(identifier: .init("workflow"))
        workflowColumn.title = "Saved Workflows"
        workflowTable.addTableColumn(workflowColumn)
        workflowTable.headerView = nil
        workflowTable.dataSource = self
        workflowTable.delegate = self
        workflowTable.rowHeight = 30
        workflowTable.allowsEmptySelection = true
        workflowTable.setAccessibilityLabel("Saved workflows")
        workflowTable.setAccessibilityHelp(
            "Choose a portable workflow to edit, duplicate, delete, export, or preview."
        )

        let stepColumn = NSTableColumn(identifier: .init("step"))
        stepColumn.title = "Steps"
        stepTable.addTableColumn(stepColumn)
        stepTable.headerView = nil
        stepTable.dataSource = self
        stepTable.delegate = self
        stepTable.rowHeight = 62
        stepTable.allowsEmptySelection = true
        stepTable.setAccessibilityLabel("Workflow steps")
        stepTable.setAccessibilityHelp(
            "Ordered steps run from top to bottom; select a step to remove or reorder it."
        )
    }

    private func makeSidebar() -> NSView {
        let heading = NSTextField(labelWithString: "Workflows")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString: "Portable recipes that compile against each inspected file."
        )
        help.textColor = .secondaryLabelColor
        let scroll = NSScrollView()
        scroll.documentView = workflowTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let add = NSButton(title: "+", target: self, action: #selector(addWorkflow))
        add.toolTip = "New workflow"
        add.setAccessibilityLabel("New workflow")
        add.setAccessibilityHelp("Create a new local workflow with the default cleanup steps.")
        duplicateButton.target = self
        duplicateButton.action = #selector(duplicateWorkflow)
        duplicateButton.setAccessibilityHelp("Create an unsaved copy of the selected workflow.")
        deleteButton.target = self
        deleteButton.action = #selector(deleteWorkflow)
        deleteButton.setAccessibilityHelp(
            "Ask before removing the selected workflow from this Mac.")
        let buttons = NSStackView(views: [add, duplicateButton, deleteButton])
        buttons.orientation = .horizontal
        buttons.spacing = 6

        let stack = NSStackView(views: [heading, help, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 250),
        ])
        return container
    }

    private func makeEditor() -> NSView {
        let heading = NSTextField(labelWithString: "Workflow Builder")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        let nameLabel = NSTextField(labelWithString: "Name")
        nameField.placeholderString = "Example: Prepare for Jellyfin"
        nameField.delegate = self
        nameField.setAccessibilityLabel("Workflow name")
        nameField.setAccessibilityHelp("Name this portable workflow before saving it.")
        let stepLabel = NSTextField(labelWithString: "Steps run from top to bottom")
        stepLabel.textColor = .secondaryLabelColor
        let scroll = NSScrollView()
        scroll.documentView = stepTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        configureAddStepMenu()
        removeStepButton.target = self
        removeStepButton.action = #selector(removeSelectedStep)
        removeStepButton.setAccessibilityHelp("Remove the selected step from this workflow.")
        moveUpButton.target = self
        moveUpButton.action = #selector(moveStepUp)
        moveUpButton.setAccessibilityHelp("Move the selected step one position earlier.")
        moveDownButton.target = self
        moveDownButton.action = #selector(moveStepDown)
        moveDownButton.setAccessibilityHelp("Move the selected step one position later.")
        let stepButtonSpacer = NSView()
        stepButtonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stepButtons = NSStackView(views: [
            addStepButton, removeStepButton, stepButtonSpacer, moveUpButton, moveDownButton,
        ])
        stepButtons.orientation = .horizontal
        stepButtons.alignment = .centerY
        stepButtons.spacing = 8

        importButton.target = self
        importButton.action = #selector(importWorkflow)
        importButton.setAccessibilityHelp("Choose one portable MKV Magic workflow to import.")
        exportButton.target = self
        exportButton.action = #selector(exportWorkflow)
        exportButton.setAccessibilityHelp("Export the selected workflow as a portable local file.")
        saveButton.target = self
        saveButton.action = #selector(saveLibrary)
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        saveButton.setAccessibilityHelp("Save all workflow changes privately on this Mac.")
        useButton.target = self
        useButton.action = #selector(saveAndUse)
        useButton.keyEquivalent = "\r"
        useButton.toolTip =
            hasSelectedAsset
            ? "Compile against the selected file and show its impact before running."
            : "Inspect and select a Matroska file before previewing this workflow."
        useButton.setAccessibilityHelp(useButton.toolTip)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [
            importButton, exportButton, spacer, saveButton, useButton,
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setAccessibilityLabel("Workflow status")
        let stack = NSStackView(views: [
            heading, nameLabel, nameField, stepLabel, scroll, stepButtons, statusLabel, actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        nameField.translatesAutoresizingMaskIntoConstraints = false
        stepButtons.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            nameField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 230),
            stepButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return container
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === workflowTable { return workflows.count }
        return selectedWorkflow?.steps.count ?? 0
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        if tableView === workflowTable {
            let label = NSTextField(labelWithString: workflows[row].name)
            label.lineBreakMode = .byTruncatingTail
            let cell = NSTableCellView()
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -7),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        guard let step = selectedWorkflow?.steps[row] else { return nil }
        let checkbox = NSButton(
            checkboxWithTitle: step.action.displayName,
            target: self,
            action: #selector(toggleStep(_:))
        )
        checkbox.state = step.isEnabled ? .on : .off
        checkbox.tag = row
        let detail = NSTextField(wrappingLabelWithString: step.action.explanation)
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 11)
        let stack = NSStackView(views: [checkbox, detail])
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        if notification.object as? NSTableView === workflowTable {
            refreshEditor()
        } else {
            refreshMoveButtons()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSTextField === nameField,
            let index = selectedWorkflowIndex
        else { return }
        workflows[index].name = nameField.stringValue
        workflowTable.reloadData()
        workflowTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        markUnsaved()
    }

    @objc private func addWorkflow() {
        workflows.append(WorkflowEditorPolicy.newWorkflow())
        workflowTable.reloadData()
        workflowTable.selectRowIndexes(
            IndexSet(integer: workflows.count - 1),
            byExtendingSelection: false
        )
        markUnsaved()
    }

    @objc private func duplicateWorkflow() {
        guard let workflow = selectedWorkflow else { return }
        workflows.append(WorkflowEditorPolicy.duplicate(workflow))
        workflowTable.reloadData()
        workflowTable.selectRowIndexes(
            IndexSet(integer: workflows.count - 1),
            byExtendingSelection: false
        )
        markUnsaved()
    }

    @objc private func deleteWorkflow() {
        guard let index = selectedWorkflowIndex else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(workflows[index].name)”?"
        alert.informativeText = "This removes the saved workflow from this Mac."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        workflows.remove(at: index)
        workflowTable.reloadData()
        if !workflows.isEmpty {
            workflowTable.selectRowIndexes(
                IndexSet(integer: min(index, workflows.count - 1)),
                byExtendingSelection: false
            )
        }
        refreshEditor()
        markUnsaved()
    }

    @objc private func toggleStep(_ sender: NSButton) {
        guard let workflowIndex = selectedWorkflowIndex,
            workflows[workflowIndex].steps.indices.contains(sender.tag)
        else { return }
        WorkflowEditorPolicy.setStepEnabled(
            sender.state == .on,
            at: sender.tag,
            in: &workflows[workflowIndex]
        )
        stepTable.reloadData()
        markUnsaved()
        refreshEditorButtons()
    }

    @objc private func addStep(_ sender: NSMenuItem) {
        guard let workflowIndex = selectedWorkflowIndex,
            let rawValue = sender.representedObject as? String,
            let action = SavedWorkflowAction(rawValue: rawValue),
            WorkflowEditorPolicy.add(action, to: &workflows[workflowIndex])
        else { return }
        stepTable.reloadData()
        let addedRow = workflows[workflowIndex].steps.count - 1
        stepTable.selectRowIndexes(IndexSet(integer: addedRow), byExtendingSelection: false)
        markUnsaved()
        refreshEditorButtons()
    }

    @objc private func removeSelectedStep() {
        guard let workflowIndex = selectedWorkflowIndex else { return }
        let removedRow = stepTable.selectedRow
        guard
            WorkflowEditorPolicy.removeStep(
                at: removedRow,
                from: &workflows[workflowIndex]
            )
        else { return }
        stepTable.reloadData()
        let remainingCount = workflows[workflowIndex].steps.count
        if remainingCount > 0 {
            stepTable.selectRowIndexes(
                IndexSet(integer: min(removedRow, remainingCount - 1)),
                byExtendingSelection: false
            )
        }
        markUnsaved()
        refreshEditorButtons()
    }

    @objc private func moveStepUp() { moveSelectedStep(by: -1) }
    @objc private func moveStepDown() { moveSelectedStep(by: 1) }

    private func moveSelectedStep(by offset: Int) {
        guard let workflowIndex = selectedWorkflowIndex,
            stepTable.selectedRow >= 0
        else { return }
        let source = stepTable.selectedRow
        let destination = source + offset
        guard workflows[workflowIndex].steps.indices.contains(destination) else { return }
        workflows[workflowIndex].steps.swapAt(source, destination)
        stepTable.reloadData()
        stepTable.selectRowIndexes(IndexSet(integer: destination), byExtendingSelection: false)
        markUnsaved()
    }

    @objc private func saveLibrary() { persistLibrary(thenUse: false) }
    @objc private func saveAndUse() { persistLibrary(thenUse: true) }

    private func persistLibrary(thenUse: Bool) {
        let workflowToUse: SavedWorkflow?
        if let workflow = selectedWorkflow {
            let trimmedName = workflow.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                AccessibleStatusPresentation.present(
                    "Give the workflow a name before saving.",
                    in: statusLabel,
                    returningFocusTo: nameField
                )
                return
            }
            guard !thenUse || workflow.steps.contains(where: \.isEnabled) else {
                AccessibleStatusPresentation.present(
                    "Enable at least one step before previewing.",
                    in: statusLabel,
                    returningFocusTo: stepTable
                )
                return
            }
            if let index = selectedWorkflowIndex { workflows[index].name = trimmedName }
            workflowToUse = selectedWorkflow
        } else {
            guard !thenUse else { return }
            workflowToUse = nil
        }
        setEditingEnabled(false)
        statusLabel.stringValue = "Saving…"
        Task {
            do {
                try await onSave(workflows)
                statusLabel.stringValue = "Saved privately on this Mac."
                setEditingEnabled(true)
                if thenUse, hasSelectedAsset, let workflowToUse {
                    onUse(workflowToUse)
                    view.window?.orderOut(nil)
                } else if thenUse {
                    statusLabel.stringValue = "Saved. Inspect a Matroska file to preview it."
                }
            } catch {
                setEditingEnabled(true)
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not save workflows.",
                        recovery: "Unsaved changes remain open; try Save again.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: thenUse ? useButton : saveButton
                )
            }
        }
    }

    @objc private func importWorkflow() {
        let panel = NSOpenPanel()
        panel.title = "Import MKV Magic Workflow"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [Self.workflowType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try JSONSavedWorkflowStore.loadPortableFile(at: url)
            if let existing = workflows.firstIndex(where: { $0.id == imported.id }) {
                workflows[existing] = imported
                workflowTable.reloadData()
                workflowTable.selectRowIndexes(
                    IndexSet(integer: existing), byExtendingSelection: false)
                statusLabel.stringValue = "Updated matching workflow. Save to keep it."
            } else {
                workflows.append(imported)
                workflowTable.reloadData()
                workflowTable.selectRowIndexes(
                    IndexSet(integer: workflows.count - 1), byExtendingSelection: false)
                statusLabel.stringValue = "Imported. Save to keep it."
            }
        } catch {
            AccessibleStatusPresentation.present(
                UserFacingErrorPresentation.message(
                    failure: "Could not import that workflow.",
                    recovery: "Nothing was added; choose another MKV Magic workflow file.",
                    error: error
                ),
                in: statusLabel,
                returningFocusTo: importButton
            )
        }
    }

    @objc private func exportWorkflow() {
        guard let workflow = selectedWorkflow else { return }
        let panel = NSSavePanel()
        panel.title = "Export MKV Magic Workflow"
        panel.prompt = "Export"
        panel.allowedContentTypes = [Self.workflowType]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = WorkflowEditorPolicy.exportFilename(for: workflow)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try JSONSavedWorkflowStore.writePortableFile(workflow, to: url)
            statusLabel.stringValue = "Exported \(url.lastPathComponent)."
        } catch {
            AccessibleStatusPresentation.present(
                UserFacingErrorPresentation.message(
                    failure: "Could not export the workflow.",
                    recovery: "The saved workflow is unchanged; choose another destination.",
                    error: error
                ),
                in: statusLabel,
                returningFocusTo: exportButton
            )
        }
    }

    private func refreshEditor() {
        nameField.stringValue = selectedWorkflow?.name ?? ""
        stepTable.reloadData()
        if selectedWorkflow?.steps.isEmpty == false {
            stepTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            stepTable.deselectAll(nil)
        }
        refreshEditorButtons()
    }

    private func refreshEditorButtons() {
        let hasWorkflow = selectedWorkflow != nil
        nameField.isEnabled = hasWorkflow
        duplicateButton.isEnabled = hasWorkflow
        deleteButton.isEnabled = hasWorkflow
        exportButton.isEnabled = hasWorkflow
        useButton.isEnabled =
            hasWorkflow && hasSelectedAsset
            && selectedWorkflow?.steps.contains(where: \.isEnabled) == true
        refreshAddStepMenu()
        refreshMoveButtons()
    }

    private func refreshMoveButtons() {
        let row = stepTable.selectedRow
        let count = selectedWorkflow?.steps.count ?? 0
        removeStepButton.isEnabled = row >= 0 && row < count
        moveUpButton.isEnabled = row > 0
        moveDownButton.isEnabled = row >= 0 && row < count - 1
    }

    private func setEditingEnabled(_ enabled: Bool) {
        workflowTable.isEnabled = enabled
        stepTable.isEnabled = enabled
        nameField.isEnabled = enabled && selectedWorkflow != nil
        addStepButton.isEnabled =
            enabled && selectedWorkflow != nil
        removeStepButton.isEnabled = enabled && stepTable.selectedRow >= 0
        moveUpButton.isEnabled = enabled && stepTable.selectedRow > 0
        moveDownButton.isEnabled =
            enabled && stepTable.selectedRow >= 0
            && stepTable.selectedRow < (selectedWorkflow?.steps.count ?? 0) - 1
        useButton.isEnabled =
            enabled && hasSelectedAsset
            && selectedWorkflow?.steps.contains(where: \.isEnabled) == true
    }

    private func configureAddStepMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Add Step…", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for action in WorkflowEditorPolicy.actionCatalog {
            let item = NSMenuItem(
                title: action.displayName,
                action: #selector(addStep(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = action.rawValue
            menu.addItem(item)
        }
        addStepButton.menu = menu
        addStepButton.setAccessibilityLabel("Add workflow step")
    }

    private func refreshAddStepMenu() {
        let available = Set(
            selectedWorkflow.map { WorkflowEditorPolicy.availableActions(for: $0) } ?? []
        )
        for item in addStepButton.itemArray {
            guard let rawValue = item.representedObject as? String,
                let action = SavedWorkflowAction(rawValue: rawValue)
            else { continue }
            item.isEnabled = available.contains(action)
        }
        addStepButton.isEnabled = selectedWorkflow != nil
        addStepButton.toolTip =
            available.isEmpty
            ? "All available steps are already in this workflow."
            : "Add another portable step to this workflow."
        addStepButton.setAccessibilityHelp(addStepButton.toolTip)
    }

    private func markUnsaved() {
        statusLabel.stringValue = "Unsaved changes"
    }

    private var selectedWorkflowIndex: Int? {
        let row = workflowTable.selectedRow
        return workflows.indices.contains(row) ? row : nil
    }

    private var selectedWorkflow: SavedWorkflow? {
        selectedWorkflowIndex.map { workflows[$0] }
    }

    private static var workflowType: UTType {
        UTType(filenameExtension: "mkvmagic-workflow") ?? .json
    }
}

enum WorkflowEditorPolicy {
    static let actionCatalog: [SavedWorkflowAction] = [
        .removeNonEnglishSubtitles,
        .removeRedundantEnglishSDH,
        .removeSegmentTitle,
        .normalizeFilename,
        .addExternalSubtitle,
        .cleanExternalSubtitleText,
        .convertVideoIfNotAV1OrHEVC,
        .convertVideoRecommended,
        .convertVideoAV1,
        .convertVideoHEVC,
        .convertVideoH264,
        .convertVideoProRes,
        .transcodeAllAudioAAC,
        .transcodeAllAudioOpus,
        .transcodeAllAudioAC3,
        .transcodeAllAudioEAC3,
        .transcodeAllAudioFLAC,
    ]

    static func newWorkflow() -> SavedWorkflow {
        SavedWorkflow(
            name: "New Workflow",
            steps: [
                SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                SavedWorkflowStep(action: .removeRedundantEnglishSDH),
                SavedWorkflowStep(isEnabled: false, action: .removeSegmentTitle),
            ]
        )
    }

    static func duplicate(_ workflow: SavedWorkflow) -> SavedWorkflow {
        SavedWorkflow(
            name: workflow.name + " Copy",
            steps: workflow.steps.map {
                SavedWorkflowStep(isEnabled: $0.isEnabled, action: $0.action)
            }
        )
    }

    static func availableActions(for workflow: SavedWorkflow) -> [SavedWorkflowAction] {
        let existing = Set(workflow.steps.map(\.action))
        return actionCatalog.filter { action in
            guard !existing.contains(action) else { return false }
            if action.isVideoConversion,
                workflow.steps.contains(where: { $0.action.isVideoConversion })
            {
                return false
            }
            if action.isAudioConversion {
                return !workflow.steps.contains(where: { $0.action.isAudioConversion })
                    && (!action.requiresVideoConversion
                        || workflow.steps.contains(where: { $0.action.isVideoConversion }))
            }
            return action != .cleanExternalSubtitleText || existing.contains(.addExternalSubtitle)
        }
    }

    @discardableResult
    static func add(_ action: SavedWorkflowAction, to workflow: inout SavedWorkflow) -> Bool {
        guard availableActions(for: workflow).contains(action) else { return false }
        workflow.steps.append(SavedWorkflowStep(action: action))
        if action.requiresVideoConversion {
            for videoIndex in workflow.steps.indices
            where workflow.steps[videoIndex].action.isVideoConversion {
                workflow.steps[videoIndex].isEnabled = true
            }
        }
        return true
    }

    @discardableResult
    static func removeStep(at index: Int, from workflow: inout SavedWorkflow) -> Bool {
        guard workflow.steps.indices.contains(index) else { return false }
        let removedAction = workflow.steps[index].action
        workflow.steps.remove(at: index)
        if removedAction == .addExternalSubtitle {
            workflow.steps.removeAll { $0.action == .cleanExternalSubtitleText }
        } else if removedAction.isVideoConversion {
            workflow.steps.removeAll { $0.action.requiresVideoConversion }
        }
        return true
    }

    @discardableResult
    static func setStepEnabled(
        _ isEnabled: Bool,
        at index: Int,
        in workflow: inout SavedWorkflow
    ) -> Bool {
        guard workflow.steps.indices.contains(index) else { return false }
        let action = workflow.steps[index].action
        workflow.steps[index].isEnabled = isEnabled
        if action == .addExternalSubtitle, !isEnabled {
            for cleanupIndex in workflow.steps.indices
            where workflow.steps[cleanupIndex].action == .cleanExternalSubtitleText {
                workflow.steps[cleanupIndex].isEnabled = false
            }
        } else if action == .cleanExternalSubtitleText, isEnabled {
            for addIndex in workflow.steps.indices
            where workflow.steps[addIndex].action == .addExternalSubtitle {
                workflow.steps[addIndex].isEnabled = true
            }
        } else if action.isVideoConversion, !isEnabled {
            for audioIndex in workflow.steps.indices
            where workflow.steps[audioIndex].action.requiresVideoConversion {
                workflow.steps[audioIndex].isEnabled = false
            }
        } else if action.requiresVideoConversion, isEnabled {
            for videoIndex in workflow.steps.indices
            where workflow.steps[videoIndex].action.isVideoConversion {
                workflow.steps[videoIndex].isEnabled = true
            }
        }
        return true
    }

    static func exportFilename(for workflow: SavedWorkflow) -> String {
        let safe = workflow.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (safe.isEmpty ? "MKV Magic Workflow" : safe) + ".mkvmagic-workflow"
    }
}
