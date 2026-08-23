import AppKit
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import UniformTypeIdentifiers

@MainActor
final class MainViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum PendingMetadataChange {
        case segmentTitle(String?)
        case track(TrackMetadataEdit)
    }

    private let model: AppModel
    private let tableView = NSTableView()
    private let inspectorText = NSTextView()
    private let segmentTitleField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let impactLabel = NSTextField(labelWithString: "No pending plan")
    private let previewButton = NSButton(title: "Preview Change", target: nil, action: nil)
    private let editTrackButton = NSButton(title: "Edit a Track…", target: nil, action: nil)
    private let runButton = NSButton(title: "Verify & Run", target: nil, action: nil)
    private var pendingMetadataChange: PendingMetadataChange?
    private var pendingAssetID: UUID?
    private var preferredSelectionURL: URL?
    private var historyWindowController: HistoryWindowController?
    private var trackEditorWindowController: TrackEditorWindowController?

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
        view = root

        let sidebar = makeSidebar()
        let content = makeContent()
        let inspector = makeInspector()
        for pane in [sidebar, content, inspector] {
            pane.translatesAutoresizingMaskIntoConstraints = false
        }
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(content)
        split.addArrangedSubview(inspector)
        split.translatesAutoresizingMaskIntoConstraints = false

        let footer = makeFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
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
            sidebarButton(
                "History",
                symbol: "clock.arrow.circlepath",
                action: #selector(showHistory)
            ),
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

    private func sidebarButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.isBordered = false
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        return button
    }

    private func makeContent() -> NSView {
        let heading = NSTextField(labelWithString: "Drop media files or folders here")
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
        tableView.allowsEmptySelection = false
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
        inspectorText.isHorizontallyResizable = false
        inspectorText.textContainer?.widthTracksTextView = true
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
        editTrackButton.target = self
        editTrackButton.action = #selector(editTrack)
        editTrackButton.isEnabled = false
        let metadataButtons = NSStackView(views: [previewButton, editTrackButton])
        metadataButtons.orientation = .horizontal
        metadataButtons.spacing = 8

        let stack = NSStackView(views: [
            heading, scroll, titleLabel, segmentTitleField, metadataButtons,
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
        runButton.target = self
        runButton.action = #selector(runChange)

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
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        inspect(panel.urls)
    }

    @objc private func showHistory() {
        statusLabel.stringValue = "Loading history…"
        Task {
            do {
                let records = try await model.loadHistory()
                let controller = HistoryWindowController(records: records)
                historyWindowController = controller
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
                statusLabel.stringValue = records.isEmpty ? "No history yet" : "History loaded"
            } catch {
                statusLabel.stringValue = "Could not load history: \(error.localizedDescription)"
            }
        }
    }

    private func inspect(_ urls: [URL]) {
        Task { await model.addFiles(urls) }
    }

    @objc private func previewChange() {
        guard let asset = selectedAsset else { return }
        guard MatroskaEditingPolicy.supports(asset) else {
            impactLabel.stringValue = "Segment-title editing requires Matroska."
            clearPendingChange()
            return
        }
        let value = segmentTitleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = value.isEmpty ? nil : value
        if title == asset.metadata["title"] {
            impactLabel.stringValue = "No title change"
            clearPendingChange()
            return
        }
        let workflow = WorkflowDefinition(
            name: "Edit segment title",
            operations: [.editSegmentTitle(title)]
        )
        do {
            let plan = try WorkflowPlanner().plan(asset: asset, workflow: workflow)
            let mechanism = plan.stages.first?.mechanism.rawValue ?? "none"
            impactLabel.stringValue = "\(plan.impact.videoEncodeCount) video encodes • \(mechanism)"
            pendingMetadataChange = .segmentTitle(title)
            pendingAssetID = asset.id
            runButton.isEnabled = true
            runButton.toolTip =
                "Create a new MKV from a temporary clone, verify it, then commit it."
        } catch {
            impactLabel.stringValue = "Plan failed: \(error.localizedDescription)"
            clearPendingChange()
        }
    }

    @objc private func editTrack() {
        guard let asset = selectedAsset, let parentWindow = view.window else { return }
        let controller = TrackEditorWindowController(asset: asset)
        trackEditorWindowController = controller
        controller.beginSheet(for: parentWindow) { [weak self] edit in
            guard let self else { return }
            self.trackEditorWindowController = nil
            guard let edit else { return }
            let workflow = WorkflowDefinition(
                name: "Edit track metadata",
                operations: [.editTrackMetadata(edit)]
            )
            do {
                let plan = try WorkflowPlanner().plan(asset: asset, workflow: workflow)
                let mechanism = plan.stages.first?.mechanism.rawValue ?? "none"
                self.impactLabel.stringValue =
                    "\(plan.impact.videoEncodeCount) video encodes • \(mechanism)"
                self.pendingMetadataChange = .track(edit)
                self.pendingAssetID = asset.id
                self.runButton.isEnabled = true
                self.runButton.toolTip =
                    "Create a new MKV from a temporary clone, verify it, then commit it."
            } catch {
                self.impactLabel.stringValue = "Plan failed: \(error.localizedDescription)"
                self.clearPendingChange()
            }
        }
    }

    @objc private func runChange() {
        guard let pendingMetadataChange,
            let asset = selectedAsset,
            pendingAssetID == asset.id
        else {
            clearPendingChange()
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save Verified MKV Copy"
        panel.prompt = "Save Verified Copy"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = OutputNamingPolicy.suggestedFilename(for: asset.sourceURL)
        panel.directoryURL = asset.sourceURL.deletingLastPathComponent()
        panel.allowedContentTypes = [
            UTType(filenameExtension: asset.sourceURL.pathExtension) ?? .data
        ]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        previewButton.isEnabled = false
        editTrackButton.isEnabled = false
        runButton.isEnabled = false
        Task {
            do {
                let output: MediaAsset
                switch pendingMetadataChange {
                case .segmentTitle(let title):
                    output = try await model.editSegmentTitle(
                        in: asset,
                        title: title,
                        destinationURL: destinationURL
                    )
                case .track(let edit):
                    output = try await model.editTrackMetadata(
                        in: asset,
                        edit: edit,
                        destinationURL: destinationURL
                    )
                }
                preferredSelectionURL = output.sourceURL
                clearPendingChange()
                refresh()
            } catch {
                previewButton.isEnabled = true
                editTrackButton.isEnabled = asset.tracks.contains {
                    $0.kind != .attachment && $0.uid != nil
                }
                runButton.isEnabled =
                    self.pendingMetadataChange != nil
                    && pendingAssetID == asset.id
            }
        }
    }

    private func refresh() {
        tableView.reloadData()
        switch model.state {
        case .ready:
            statusLabel.stringValue = model.assets.isEmpty ? "Ready" : "Inspection complete"
        case .discovering:
            statusLabel.stringValue = "Finding media files…"
        case .inspecting(let filename):
            statusLabel.stringValue = "Inspecting \(filename)…"
        case .executing(let message):
            statusLabel.stringValue = message
        case .completed(let message):
            statusLabel.stringValue = message
        case .completedWithWarnings(let message):
            statusLabel.stringValue = message
        case .failed(let message):
            statusLabel.stringValue = message
        }
        if tableView.selectedRow >= model.assets.count {
            tableView.deselectAll(nil)
        }
        if let preferredSelectionURL,
            let row = model.assets.firstIndex(where: { $0.sourceURL == preferredSelectionURL })
        {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            self.preferredSelectionURL = nil
        } else if let row = AssetSelectionPolicy.rowToSelect(
            currentRow: tableView.selectedRow, assetCount: model.assets.count)
        {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        renderInspector()
        if case .executing = model.state {
            previewButton.isEnabled = false
            editTrackButton.isEnabled = false
            runButton.isEnabled = false
        }
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
            editTrackButton.isEnabled = false
            return
        }
        var lines = [
            asset.sourceURL.lastPathComponent,
            "",
            "FILE",
            "Container  \(asset.formatLongName ?? asset.container)",
            "Duration   \(formatDuration(asset.duration))",
            "Size       \(formatBytes(asset.fileSize))",
            "Bitrate    \(formatBitrate(asset.bitrate))",
        ]
        if let application = asset.writingApplication ?? asset.muxingApplication {
            lines.append("Written by  \(application)")
        }
        let playableTracks = InspectorPresentationPolicy.playableTracks(in: asset.tracks)
        lines.append(contentsOf: ["", "TRACKS (\(playableTracks.count))"])
        lines.append(contentsOf: playableTracks.map(formatTrack))

        let chapterCount = asset.chapterEntryCount ?? asset.chapters.count
        lines.append(contentsOf: ["", "CHAPTERS  \(chapterCount)"])
        if chapterCount > 0 {
            lines.append(
                contentsOf: asset.chapters.prefix(8).map {
                    "  \(formatDuration($0.start))  \($0.title)"
                })
            if asset.chapters.count > 8 { lines.append("  …and \(asset.chapters.count - 8) more") }
        }

        lines.append(contentsOf: ["", "ATTACHMENTS  \(asset.attachments.count)"])
        lines.append(
            contentsOf: asset.attachments.map {
                "  \($0.filename) • \($0.mimeType ?? "unknown") • \(formatBytes($0.size))"
            })
        if let globalTags = asset.globalTagCount, let trackTags = asset.trackTagCount {
            lines.append(contentsOf: ["", "TAGS  \(globalTags) global • \(trackTags) track"])
        }
        if !asset.warnings.isEmpty {
            lines.append(contentsOf: ["", "WARNINGS"] + asset.warnings.map { "  ⚠︎ \($0)" })
        }
        inspectorText.string = lines.joined(separator: "\n")
        segmentTitleField.stringValue = asset.metadata["title"] ?? ""
        previewButton.isEnabled = MatroskaEditingPolicy.supports(asset)
        previewButton.toolTip =
            previewButton.isEnabled ? nil : "Segment-title editing currently requires Matroska."
        editTrackButton.isEnabled =
            MatroskaEditingPolicy.supports(asset)
            && asset.tracks.contains { $0.kind != .attachment && $0.uid != nil }
        editTrackButton.toolTip =
            editTrackButton.isEnabled
            ? "Edit track names, languages, roles, and playback flags without encoding."
            : "Track editing requires a Matroska track with a stable UID."
    }

    private func formatTrack(_ track: MediaTrack) -> String {
        var facts = [track.codec.uppercased()]
        if let profile = track.profile { facts.append(profile) }
        if let dimensions = track.dimensions {
            facts.append("\(dimensions.width)×\(dimensions.height)")
        }
        if let bitDepth = InspectorPresentationPolicy.displayedBitDepth(for: track) {
            facts.append("\(bitDepth)-bit")
        }
        if let frameRate = track.frameRate, frameRate != "0/0" { facts.append(frameRate + " fps") }
        if let channels = track.channels {
            facts.append(track.channelLayout ?? "\(channels) ch")
        }
        if let sampleRate = track.sampleRate {
            facts.append(String(format: "%.1f kHz", Double(sampleRate) / 1_000))
        }
        if let language = track.language { facts.append(language) }
        if let title = track.title, !title.isEmpty { facts.append(title) }
        facts.append(contentsOf: track.hdrFormats)

        var flags = [String]()
        if track.isDefault { flags.append("default") }
        if track.isForced { flags.append("forced") }
        if !track.isEnabled { flags.append("disabled") }
        if track.isCommentary { flags.append("commentary") }
        if track.isHearingImpaired { flags.append("SDH") }
        if track.isVisualImpaired { flags.append("descriptive") }
        if !flags.isEmpty { facts.append(flags.joined(separator: ", ")) }
        return "  #\(track.id) \(track.kind.rawValue.capitalized)\n    "
            + facts.joined(separator: " • ")
    }

    private func formatDuration(_ duration: MediaTime?) -> String {
        guard let duration else { return "Unknown" }
        let total = max(0, Int(duration.seconds.rounded()))
        return String(format: "%d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
    }

    private func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatBitrate(_ bitrate: Int64?) -> String {
        guard let bitrate else { return "Unknown" }
        return String(format: "%.2f Mb/s", Double(bitrate) / 1_000_000)
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
        clearPendingChange()
        renderInspector()
    }

    private func clearPendingChange() {
        pendingMetadataChange = nil
        pendingAssetID = nil
        runButton.isEnabled = false
    }
}

enum AssetSelectionPolicy {
    static func rowToSelect(currentRow: Int, assetCount: Int) -> Int? {
        currentRow < 0 && assetCount > 0 ? 0 : nil
    }
}

enum InspectorPresentationPolicy {
    static func playableTracks(in tracks: [MediaTrack]) -> [MediaTrack] {
        tracks.filter { $0.kind != .attachment }
    }

    static func displayedBitDepth(for track: MediaTrack) -> Int? {
        track.kind == .video ? track.bitDepth : nil
    }
}

enum OutputNamingPolicy {
    static func suggestedFilename(for sourceURL: URL) -> String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mkv" : sourceURL.pathExtension
        return "\(base) — Edited.\(fileExtension)"
    }
}
