import AppKit
import MKVMagicCore

@MainActor
final class QueueWindowController: NSWindowController {
    private let queueViewController: QueueViewController

    init(
        snapshot: MediaQueueSnapshot,
        onSetPaused: @escaping @MainActor @Sendable (Bool) async throws -> MediaQueueSnapshot,
        onTransition:
            @escaping @MainActor @Sendable (
                UUID, MediaQueueJobState, MediaQueueEventReason?
            ) async throws -> MediaQueueSnapshot,
        onReorder: @escaping @MainActor @Sendable ([UUID]) async throws -> MediaQueueSnapshot,
        onReview: @escaping @MainActor @Sendable (MediaQueueJob) -> Void
    ) {
        let content = QueueViewController(
            snapshot: snapshot,
            onSetPaused: onSetPaused,
            onTransition: onTransition,
            onReorder: onReorder,
            onReview: onReview
        )
        queueViewController = content
        let window = NSWindow(contentViewController: content)
        window.title = "MKV Magic Queue"
        window.setContentSize(NSSize(width: 840, height: 520))
        window.minSize = NSSize(width: 700, height: 420)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(snapshot: MediaQueueSnapshot) {
        queueViewController.update(snapshot: snapshot)
    }
}

@MainActor
final class QueueViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var snapshot: MediaQueueSnapshot
    private let onSetPaused: @MainActor @Sendable (Bool) async throws -> MediaQueueSnapshot
    private let onTransition:
        @MainActor @Sendable (
            UUID, MediaQueueJobState, MediaQueueEventReason?
        ) async throws -> MediaQueueSnapshot
    private let onReorder: @MainActor @Sendable ([UUID]) async throws -> MediaQueueSnapshot
    private let onReview: @MainActor @Sendable (MediaQueueJob) -> Void

    private let tableView = NSTableView()
    private let pauseButton = NSButton(title: "Pause Automatic Starts", target: nil, action: nil)
    private let primaryButton = NSButton(title: "Hold", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let moveUpButton = NSButton(title: "Move Up", target: nil, action: nil)
    private let moveDownButton = NSButton(title: "Move Down", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    init(
        snapshot: MediaQueueSnapshot,
        onSetPaused: @escaping @MainActor @Sendable (Bool) async throws -> MediaQueueSnapshot,
        onTransition:
            @escaping @MainActor @Sendable (
                UUID, MediaQueueJobState, MediaQueueEventReason?
            ) async throws -> MediaQueueSnapshot,
        onReorder: @escaping @MainActor @Sendable ([UUID]) async throws -> MediaQueueSnapshot,
        onReview: @escaping @MainActor @Sendable (MediaQueueJob) -> Void
    ) {
        self.snapshot = snapshot
        self.onSetPaused = onSetPaused
        self.onTransition = onTransition
        self.onReorder = onReorder
        self.onReview = onReview
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Production Queue")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString:
                "Add to Queue saves a reviewed workflow for automatic starts. Pause blocks new automatic starts; Verify & Run remains an explicit immediate start. Work already running continues to its next safe boundary. Interrupted or failed jobs must be reviewed again before retry."
        )
        help.textColor = .secondaryLabelColor

        for (identifier, title, width) in [
            ("order", "#", 36.0),
            ("workflow", "Workflow", 165.0),
            ("input", "Input", 150.0),
            ("resource", "Work", 95.0),
            ("state", "Status", 95.0),
            ("attempts", "Tries", 44.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        primaryButton.target = self
        primaryButton.action = #selector(performPrimaryAction)
        cancelButton.target = self
        cancelButton.action = #selector(cancelSelectedJob)
        moveUpButton.target = self
        moveUpButton.action = #selector(moveSelectedUp)
        moveDownButton.target = self
        moveDownButton.action = #selector(moveSelectedDown)
        for button in [pauseButton, primaryButton, cancelButton, moveUpButton, moveDownButton] {
            button.bezelStyle = .rounded
        }
        statusLabel.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let controls = NSStackView(views: [
            pauseButton, moveUpButton, moveDownButton, spacer, primaryButton, cancelButton,
        ])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8

        let stack = NSStackView(views: [heading, help, scroll, statusLabel, controls])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            controls.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        refreshSelection()
    }

    func update(snapshot: MediaQueueSnapshot) {
        let selectedID = selectedJob?.id
        self.snapshot = snapshot
        tableView.reloadData()
        if let selectedID,
            let row = snapshot.jobs.firstIndex(where: { $0.id == selectedID })
        {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        refreshSelection()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { snapshot.jobs.count }

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
        cell.textField?.stringValue = QueuePresentation.columnValue(
            identifier: identifier.rawValue,
            row: row,
            job: snapshot.jobs[row]
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshSelection()
    }

    @objc private func togglePause() {
        performMutation { [onSetPaused, snapshot] in
            try await onSetPaused(!snapshot.isPaused)
        }
    }

    @objc private func performPrimaryAction() {
        guard let job = selectedJob else { return }
        switch job.state {
        case .waiting:
            transition(job, to: .held)
        case .held:
            transition(job, to: .waiting)
        case .failed, .needsReview:
            onReview(job)
        default:
            break
        }
    }

    @objc private func cancelSelectedJob() {
        guard let job = selectedJob else { return }
        switch job.state {
        case .running:
            transition(job, to: .cancelling)
        case .waiting, .held, .failed, .needsReview:
            transition(job, to: .cancelled)
        default:
            break
        }
    }

    @objc private func moveSelectedUp() { moveSelected(by: -1) }
    @objc private func moveSelectedDown() { moveSelected(by: 1) }

    private func transition(_ job: MediaQueueJob, to state: MediaQueueJobState) {
        performMutation { [onTransition] in
            try await onTransition(job.id, state, .userAction)
        }
    }

    private func moveSelected(by offset: Int) {
        guard let job = selectedJob, job.state.isPending else { return }
        var pendingIDs = snapshot.jobs.filter { $0.state.isPending }.map(\.id)
        guard let index = pendingIDs.firstIndex(of: job.id) else { return }
        let destination = index + offset
        guard pendingIDs.indices.contains(destination) else { return }
        pendingIDs.swapAt(index, destination)
        performMutation(selecting: job.id) { [onReorder] in
            try await onReorder(pendingIDs)
        }
    }

    private func performMutation(
        selecting jobID: UUID? = nil,
        _ operation: @escaping @MainActor () async throws -> MediaQueueSnapshot
    ) {
        setControlsEnabled(false)
        statusLabel.stringValue = "Updating queue…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let statusMessage: String
            do {
                self.snapshot = try await operation()
                self.tableView.reloadData()
                if let jobID,
                    let row = self.snapshot.jobs.firstIndex(where: { $0.id == jobID })
                {
                    self.tableView.selectRowIndexes(
                        IndexSet(integer: row),
                        byExtendingSelection: false
                    )
                }
                statusMessage = QueuePresentation.summary(self.snapshot)
            } catch {
                statusMessage = "Queue update failed: \(error.localizedDescription)"
            }
            self.refreshSelection()
            self.statusLabel.stringValue = statusMessage
        }
    }

    private func refreshSelection() {
        pauseButton.title =
            snapshot.isPaused ? "Resume Automatic Starts" : "Pause Automatic Starts"
        pauseButton.isEnabled = true
        statusLabel.stringValue = QueuePresentation.summary(snapshot)
        guard let job = selectedJob else {
            primaryButton.isEnabled = false
            cancelButton.isEnabled = false
            moveUpButton.isEnabled = false
            moveDownButton.isEnabled = false
            return
        }
        switch job.state {
        case .waiting:
            primaryButton.title = "Hold"
            primaryButton.isEnabled = true
        case .held:
            primaryButton.title = "Resume"
            primaryButton.isEnabled = true
        case .failed, .needsReview:
            primaryButton.title = "Review Again…"
            primaryButton.isEnabled = true
        default:
            primaryButton.title = "Hold"
            primaryButton.isEnabled = false
        }
        cancelButton.isEnabled = [.waiting, .held, .running, .failed, .needsReview].contains(
            job.state
        )
        let pending = snapshot.jobs.filter { $0.state.isPending }
        let pendingIndex = pending.firstIndex(where: { $0.id == job.id })
        moveUpButton.isEnabled = pendingIndex.map { $0 > 0 } ?? false
        moveDownButton.isEnabled = pendingIndex.map { $0 + 1 < pending.count } ?? false
    }

    private func setControlsEnabled(_ enabled: Bool) {
        for button in [pauseButton, primaryButton, cancelButton, moveUpButton, moveDownButton] {
            button.isEnabled = enabled
        }
    }

    private var selectedJob: MediaQueueJob? {
        guard tableView.selectedRow >= 0, tableView.selectedRow < snapshot.jobs.count else {
            return nil
        }
        return snapshot.jobs[tableView.selectedRow]
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

enum QueuePresentation {
    static func columnValue(identifier: String, row: Int, job: MediaQueueJob) -> String {
        switch identifier {
        case "order": String(row + 1)
        case "workflow": job.workflow.name
        case "input": job.inputs.first?.displayName ?? "Unknown input"
        case "resource": resourceLabel(job.resourceClass)
        case "state": stateLabel(job)
        case "attempts": String(job.attemptCount)
        default: ""
        }
    }

    static func summary(_ snapshot: MediaQueueSnapshot) -> String {
        guard !snapshot.jobs.isEmpty else {
            return "No queued jobs. Review a saved workflow, then choose Add to Queue."
        }
        let active = snapshot.jobs.filter { $0.state == .running || $0.state == .cancelling }.count
        let pending = snapshot.jobs.filter { $0.state.isPending }.count
        let review = snapshot.jobs.filter { $0.state == .failed || $0.state == .needsReview }.count
        let trashFollowUp = snapshot.jobs.filter {
            $0.sourceDisposition == .trashAfterVerifiedSuccess
                && $0.state == .succeeded
                && $0.sourceDispositionResult?.outcome != .applied
        }.count
        let pause = snapshot.isPaused ? " • new starts paused" : ""
        let trashLabel = trashFollowUp == 1 ? "Trash follow-up" : "Trash follow-ups"
        let trash = trashFollowUp > 0 ? " • \(trashFollowUp) \(trashLabel)" : ""
        return "\(active) active • \(pending) pending • \(review) need review\(trash)\(pause)"
    }

    static func stateLabel(_ job: MediaQueueJob) -> String {
        guard job.state == .succeeded,
            job.sourceDisposition == .trashAfterVerifiedSuccess
        else { return stateLabel(job.state) }
        return switch job.sourceDispositionResult?.outcome {
        case .applied: "Trashed"
        case .failed: "Trash failed"
        case .uncertain: "Check Trash"
        case nil: "Trash pending"
        }
    }

    static func stateLabel(_ state: MediaQueueJobState) -> String {
        switch state {
        case .waiting: "Waiting"
        case .held: "Held"
        case .running: "Running"
        case .cancelling: "Cancelling"
        case .needsReview: "Needs Review"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    static func resourceLabel(_ resource: MediaQueueResourceClass) -> String {
        switch resource {
        case .lightweight: "No encode"
        case .audioHeavy: "Audio encode"
        case .videoHeavy: "Video encode"
        }
    }
}

enum QueueExecutionControl {
    static func shouldCancelActiveTask(
        jobID: UUID,
        transition: MediaQueueJobState,
        activeJobID: UUID?
    ) -> Bool {
        transition == .cancelling && activeJobID == jobID
    }
}
