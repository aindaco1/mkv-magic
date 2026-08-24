import AppKit
import MKVMagicCore
import UniformTypeIdentifiers

@MainActor
final class HistoryWindowController: NSWindowController {
    init(
        records: [MediaJobRecord],
        onExport: (@MainActor @Sendable (URL) async throws -> Void)? = nil
    ) {
        let content = HistoryViewController(records: records, onExport: onExport)
        let window = NSWindow(contentViewController: content)
        window.title = "MKV Magic History"
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 620, height: 420)
        window.tabbingMode = .disallowed
        window.configureMKVMagicKeyboardNavigation(
            startingAt: content.preferredInitialFirstResponder
        )
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class HistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let records: [MediaJobRecord]
    private let onExport: (@MainActor @Sendable (URL) async throws -> Void)?
    private let tableView = NSTableView()
    private let detailText = NSTextView()
    private let exportButton = NSButton(
        title: "Export Privacy-Safe Report…",
        target: nil,
        action: nil
    )
    private let exportStatus = NSTextField(labelWithString: "")

    var preferredInitialFirstResponder: NSView { tableView }

    init(
        records: [MediaJobRecord],
        onExport: (@MainActor @Sendable (URL) async throws -> Void)?
    ) {
        self.records = HistoryPresentation.sorted(records)
        self.onExport = onExport
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "History")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let help = NSTextField(
            labelWithString: "Verified jobs and their sanitized execution progress."
        )
        help.textColor = .secondaryLabelColor
        let exportHelp = NSTextField(
            wrappingLabelWithString:
                "The optional report contains coarse media facts, encode counts, lifecycle states, "
                + "and app/tool versions. It excludes filenames, paths, titles, subtitle text, "
                + "custom workflow names, raw tool output, and exact timestamps."
        )
        exportHelp.textColor = .secondaryLabelColor

        for (identifier, title, width) in [
            ("workflow", "Workflow", 170.0),
            ("input", "Input", 190.0),
            ("state", "Status", 90.0),
            ("updated", "Updated", 170.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.allowsEmptySelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.setAccessibilityLabel("Verified job history")
        tableView.setAccessibilityHelp(
            "Choose a job to read its sanitized execution progress."
        )
        let tableScroll = NSScrollView()
        tableScroll.documentView = tableView
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder

        detailText.isEditable = false
        detailText.isSelectable = true
        detailText.drawsBackground = false
        detailText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailText.textContainerInset = NSSize(width: 8, height: 8)
        detailText.string = HistoryPresentation.emptyDetail
        detailText.setAccessibilityLabel("Selected job progress")
        detailText.setAccessibilityHelp(
            "Read-only ordered stages and sanitized messages for the selected job."
        )
        let detailScroll = NSScrollView()
        detailScroll.documentView = detailText
        detailScroll.hasVerticalScroller = true
        detailScroll.borderType = .bezelBorder

        exportButton.target = self
        exportButton.action = #selector(exportPrivacySafeReport)
        exportButton.isEnabled = onExport != nil
        exportButton.setAccessibilityLabel("Export Privacy-Safe Report")
        exportButton.setAccessibilityHelp(
            "Choose a local destination for a bounded report without media names or paths."
        )
        exportStatus.textColor = .secondaryLabelColor
        exportStatus.lineBreakMode = .byTruncatingMiddle
        exportStatus.setAccessibilityLabel("Report export status")
        let exportRow = NSStackView(views: [exportButton, exportStatus])
        exportRow.orientation = .horizontal
        exportRow.spacing = 10
        exportRow.alignment = .centerY

        let stack = NSStackView(views: [
            heading, help, tableScroll, detailScroll, exportHelp, exportRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            tableScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tableScroll.heightAnchor.constraint(equalToConstant: 160),
            detailScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            exportHelp.widthAnchor.constraint(equalTo: stack.widthAnchor),
            exportRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root

        if !records.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            renderSelectedRecord()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        records.count
    }

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
        cell.textField?.stringValue = HistoryPresentation.columnValue(
            identifier: identifier.rawValue,
            record: records[row]
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        renderSelectedRecord()
    }

    @objc private func exportPrivacySafeReport() {
        guard let window = view.window, let onExport else { return }
        let panel = NSSavePanel()
        panel.title = "Export Privacy-Safe Support Report"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "MKV-Magic-Support-Report.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.message =
            "Review and share this local report only if you choose. It contains no media names or paths."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let destinationURL = panel.url else { return }
            self.exportButton.isEnabled = false
            self.exportStatus.stringValue = "Building report…"
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await onExport(destinationURL)
                    self.exportStatus.stringValue = "Privacy-safe report exported."
                } catch {
                    self.exportButton.isEnabled = true
                    AccessibleStatusPresentation.present(
                        UserFacingErrorPresentation.message(
                            failure: "Could not export the report.",
                            recovery: "History is unchanged; choose another destination.",
                            error: error
                        ),
                        in: self.exportStatus,
                        returningFocusTo: self.exportButton
                    )
                }
                self.exportButton.isEnabled = true
            }
        }
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

    private func renderSelectedRecord() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < records.count else {
            detailText.string = HistoryPresentation.emptyDetail
            return
        }
        detailText.string = HistoryPresentation.detail(for: records[tableView.selectedRow])
    }
}

enum HistoryPresentation {
    static let emptyDetail = "No jobs yet. Verified runs will appear here."

    static func sorted(_ records: [MediaJobRecord]) -> [MediaJobRecord] {
        records.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.updatedAt > $1.updatedAt
        }
    }

    static func columnValue(identifier: String, record: MediaJobRecord) -> String {
        switch identifier {
        case "workflow": record.workflowName
        case "input": record.inputs.first?.displayName ?? "Unknown input"
        case "state": stateLabel(record.state)
        case "updated": format(record.updatedAt)
        default: ""
        }
    }

    static func detail(for record: MediaJobRecord) -> String {
        var lines = [
            record.workflowName,
            "Input: \(record.inputs.map(\.displayName).joined(separator: ", "))",
            "Output: \(record.outputDisplayName ?? "Not created")",
            "Created: \(format(record.createdAt))",
            "Status: \(stateLabel(record.state))",
            "",
            "Progress",
        ]
        for event in record.events {
            var line = "\(stateLabel(event.state)) — \(format(event.timestamp))"
            if let message = event.message, !message.isEmpty { line += "\n  \(message)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func stateLabel(_ state: MediaJobState) -> String {
        switch state {
        case .queued: "Queued"
        case .inspecting: "Inspected"
        case .planned: "Planned"
        case .ready: "Ready"
        case .running: "Running"
        case .verifying: "Verifying"
        case .committing: "Committing"
        case .succeeded: "Succeeded"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }

    private static func format(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}
