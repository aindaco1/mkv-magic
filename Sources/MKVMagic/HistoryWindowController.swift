import AppKit
import MKVMagicCore

@MainActor
final class HistoryWindowController: NSWindowController {
    init(records: [MediaJobRecord]) {
        let content = HistoryViewController(records: records)
        let window = NSWindow(contentViewController: content)
        window.title = "MKV Magic History"
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 620, height: 420)
        window.tabbingMode = .disallowed
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
    private let tableView = NSTableView()
    private let detailText = NSTextView()

    init(records: [MediaJobRecord]) {
        self.records = HistoryPresentation.sorted(records)
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
        let detailScroll = NSScrollView()
        detailScroll.documentView = detailText
        detailScroll.hasVerticalScroller = true
        detailScroll.borderType = .bezelBorder

        let stack = NSStackView(views: [heading, help, tableScroll, detailScroll])
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
            tableScroll.heightAnchor.constraint(equalToConstant: 190),
            detailScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
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
