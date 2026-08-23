import AppKit
import MKVMagicCore
import MKVMagicPlanning
import UniformTypeIdentifiers

@MainActor
final class MainViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: AppModel
    private let tableView = NSTableView()
    private let inspectorText = NSTextView()
    private let segmentTitleField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let impactLabel = NSTextField(labelWithString: "No pending plan")
    private let previewButton = NSButton(title: "Preview Change", target: nil, action: nil)
    private let runButton = NSButton(title: "Verify & Run", target: nil, action: nil)

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        model.didChange = { [weak self] in self?.refresh() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = FileDropView()
        root.onFiles = { [weak self] urls in self?.inspect(urls) }
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        let sidebar = makeSidebar()
        let content = makeContent()
        let inspector = makeInspector()
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(content)
        split.addArrangedSubview(inspector)
        split.translatesAutoresizingMaskIntoConstraints = false

        let footer = makeFooter()
        root.addSubview(split)
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.topAnchor.constraint(equalTo: root.topAnchor),
            split.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 52),
            sidebar.widthAnchor.constraint(equalToConstant: 175),
            inspector.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            inspector.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
        ])
    }

    private func makeSidebar() -> NSView {
        let title = NSTextField(labelWithString: "MKV Magic")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        let stack = NSStackView(views: [
            title,
            sidebarLabel("Quick Actions", symbol: "wand.and.stars"),
            sidebarLabel("Workflows", symbol: "square.stack.3d.up"),
            sidebarLabel("Queue", symbol: "list.bullet.rectangle"),
            sidebarLabel("History", symbol: "clock.arrow.circlepath"),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 15
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        return container
    }

    private func sidebarLabel(_ title: String, symbol: String) -> NSView {
        let image = NSImageView(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        image.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        let label = NSTextField(labelWithString: title)
        let row = NSStackView(views: [image, label])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func makeContent() -> NSView {
        let heading = NSTextField(labelWithString: "Drop video files here")
        heading.font = .systemFont(ofSize: 24, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString:
                "Inspect tracks, choose a workflow, preview quality impact, then verify before committing."
        )
        help.textColor = .secondaryLabelColor

        let choose = NSButton(title: "Choose Files…", target: self, action: #selector(chooseFiles))
        choose.bezelStyle = .rounded

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("asset"))
        column.title = "Files"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 32
        tableView.allowsEmptySelection = true
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let stack = NSStackView(views: [heading, help, choose, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        choose.setContentHuggingPriority(.required, for: .horizontal)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
        return container
    }

    private func makeInspector() -> NSView {
        let heading = NSTextField(labelWithString: "Inspector")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        inspectorText.isEditable = false
        inspectorText.drawsBackground = false
        inspectorText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        inspectorText.string = "Select an inspected file to see its tracks."
        let scroll = NSScrollView()
        scroll.documentView = inspectorText
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        let titleLabel = NSTextField(labelWithString: "Segment title")
        segmentTitleField.placeholderString = "Leave empty to remove"
        previewButton.target = self
        previewButton.action = #selector(previewChange)
        previewButton.isEnabled = false

        let stack = NSStackView(views: [
            heading, scroll, titleLabel, segmentTitleField, previewButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        segmentTitleField.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            segmentTitleField.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return container
    }

    private func makeFooter() -> NSView {
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        impactLabel.font = .systemFont(ofSize: 13, weight: .medium)
        runButton.isEnabled = false
        runButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [statusLabel, spacer, impactLabel, runButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSVisualEffectView()
        container.material = .headerView
        container.blendingMode = .withinWindow
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    @objc private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .audiovisualContent, .video]
        guard panel.runModal() == .OK else { return }
        inspect(panel.urls)
    }

    private func inspect(_ urls: [URL]) {
        Task { await model.addFiles(urls) }
    }

    @objc private func previewChange() {
        guard let asset = selectedAsset else { return }
        let value = segmentTitleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let workflow = WorkflowDefinition(
            name: "Edit segment title",
            operations: [.editSegmentTitle(value.isEmpty ? nil : value)]
        )
        do {
            let plan = try WorkflowPlanner().plan(asset: asset, workflow: workflow)
            let mechanism = plan.stages.first?.mechanism.rawValue ?? "none"
            impactLabel.stringValue = "\(plan.impact.videoEncodeCount) video encodes • \(mechanism)"
            runButton.toolTip = "Execution arrives with the verified transaction milestone."
        } catch {
            impactLabel.stringValue = "Plan failed: \(error.localizedDescription)"
        }
    }

    private func refresh() {
        tableView.reloadData()
        switch model.state {
        case .ready:
            statusLabel.stringValue = model.assets.isEmpty ? "Ready" : "Inspection complete"
        case .inspecting(let filename):
            statusLabel.stringValue = "Inspecting \(filename)…"
        case .failed(let message):
            statusLabel.stringValue = message
        }
        if tableView.selectedRow >= model.assets.count {
            tableView.deselectAll(nil)
        }
        renderInspector()
    }

    private var selectedAsset: MediaAsset? {
        guard tableView.selectedRow >= 0, tableView.selectedRow < model.assets.count else {
            return nil
        }
        return model.assets[tableView.selectedRow]
    }

    private func renderInspector() {
        guard let asset = selectedAsset else {
            inspectorText.string = "Select an inspected file to see its tracks."
            segmentTitleField.stringValue = ""
            previewButton.isEnabled = false
            return
        }
        let duration = asset.duration.map { String(format: "%.3f s", $0.seconds) } ?? "Unknown"
        let tracks = asset.tracks.map { track in
            var details = "#\(track.id) \(track.kind.rawValue.capitalized) • \(track.codec)"
            if let language = track.language { details += " • \(language)" }
            if track.isDefault { details += " • default" }
            if track.isForced { details += " • forced" }
            return details
        }
        inspectorText.string =
            ([
                asset.sourceURL.lastPathComponent,
                "Container: \(asset.container)",
                "Duration: \(duration)",
                "Tracks: \(asset.tracks.count)",
                "",
            ] + tracks).joined(separator: "\n")
        segmentTitleField.stringValue = asset.metadata["title"] ?? ""
        previewButton.isEnabled = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        model.assets.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("AssetCell")
        let cell =
            tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = identifier
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = model.assets[row].sourceURL.lastPathComponent
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        impactLabel.stringValue = "No pending plan"
        renderInspector()
    }
}
