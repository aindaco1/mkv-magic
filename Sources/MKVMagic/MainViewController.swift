import AppKit
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import UniformTypeIdentifiers

@MainActor
final class MainViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum PendingChange {
        case segmentTitle(String?)
        case track(TrackMetadataEdit)
        case trackRemoval(TrackRemoval, isEnglishCleanup: Bool)
        case savedWorkflow(CompiledSavedWorkflow)
        case subtitleCleanup(SubtitleCleanupFilePreview, restoringCueIDs: Set<Int>)
        case advancedSubtitleCleanup(
            AdvancedSubtitleCleanupFilePreview,
            restoringEventIDs: Set<Int>
        )
        case externalSubtitle(ExternalSubtitleFilePreview, ExternalSubtitleTrackMetadata)
        case embeddedSubtitle(EmbeddedSubtitleCleanupPreview, restoringIDs: Set<Int>)
        case chapters(ChapterEditPreview, MatroskaChapterDocument)
    }

    private enum SubtitleCleanupCandidate {
        case subRip(SubtitleCleanupFilePreview)
        case advanced(AdvancedSubtitleCleanupFilePreview)

        var normalizationNeeded: Bool {
            switch self {
            case .subRip(let preview): preview.normalizationNeeded
            case .advanced(let preview): preview.normalizationNeeded
            }
        }

        var changeCount: Int {
            switch self {
            case .subRip(let preview): preview.cleanup.changes.count
            case .advanced(let preview): preview.cleanup.changes.count
            }
        }

        var formatLabel: String {
            switch self {
            case .subRip: "SRT"
            case .advanced(let preview): preview.sourceURL.pathExtension.uppercased()
            }
        }

        @MainActor
        func makeReviewController() -> SubtitleCleanupWindowController {
            switch self {
            case .subRip(let preview): SubtitleCleanupWindowController(preview: preview)
            case .advanced(let preview): SubtitleCleanupWindowController(preview: preview)
            }
        }

        func hasRemainingText(restoringIDs: Set<Int>) -> Bool {
            switch self {
            case .subRip(let preview):
                !preview.cleanup.document(restoringCueIDs: restoringIDs).cues.isEmpty
            case .advanced(let preview):
                !preview.cleanup.document(restoringEventIDs: restoringIDs).events.isEmpty
            }
        }

        func pendingChange(restoringIDs: Set<Int>) -> PendingChange {
            switch self {
            case .subRip(let preview):
                .subtitleCleanup(preview, restoringCueIDs: restoringIDs)
            case .advanced(let preview):
                .advancedSubtitleCleanup(preview, restoringEventIDs: restoringIDs)
            }
        }
    }

    private let model: AppModel
    private let tableView = NSTableView()
    private let inspectorText = NSTextView()
    private let segmentTitleField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let impactLabel = NSTextField(labelWithString: "No pending plan")
    private let previewButton = NSButton(title: "Preview Change", target: nil, action: nil)
    private let editTrackButton = NSButton(title: "Edit a Track…", target: nil, action: nil)
    private let cleanMKVButton = NSButton(title: "Clean MKV…", target: nil, action: nil)
    private let removeTracksButton = NSButton(title: "Remove Tracks…", target: nil, action: nil)
    private let cleanSubtitleButton = NSButton(title: "Clean Subtitle…", target: nil, action: nil)
    private let addSubtitleButton = NSButton(title: "Add Subtitle…", target: nil, action: nil)
    private let chaptersButton = NSButton(title: "Chapters…", target: nil, action: nil)
    private let runButton = NSButton(title: "Verify & Run", target: nil, action: nil)
    private var pendingChange: PendingChange?
    private var pendingAssetID: UUID?
    private var preferredSelectionURL: URL?
    private var historyWindowController: HistoryWindowController?
    private var trackEditorWindowController: TrackEditorWindowController?
    private var trackRemovalWindowController: TrackRemovalWindowController?
    private var workflowWindowController: WorkflowWindowController?
    private var subtitleCleanupWindowController: SubtitleCleanupWindowController?
    private var externalSubtitleMuxWindowController: ExternalSubtitleMuxWindowController?
    private var embeddedSubtitleTrackPickerWindowController:
        EmbeddedSubtitleTrackPickerWindowController?
    private var chapterStudioWindowController: ChapterStudioWindowController?

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
            sidebarButton(
                "Workflows",
                symbol: "square.stack.3d.up",
                action: #selector(showWorkflows)
            ),
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
        cleanMKVButton.target = self
        cleanMKVButton.action = #selector(cleanMKV)
        cleanMKVButton.isEnabled = false
        removeTracksButton.target = self
        removeTracksButton.action = #selector(removeTracks)
        removeTracksButton.isEnabled = false
        cleanSubtitleButton.target = self
        cleanSubtitleButton.action = #selector(cleanSubtitle)
        cleanSubtitleButton.isEnabled = false
        addSubtitleButton.target = self
        addSubtitleButton.action = #selector(addExternalSubtitle)
        addSubtitleButton.isEnabled = false
        chaptersButton.target = self
        chaptersButton.action = #selector(editChapters)
        chaptersButton.isEnabled = false
        let metadataButtons = NSStackView(views: [previewButton, editTrackButton])
        metadataButtons.orientation = .horizontal
        metadataButtons.spacing = 8
        let structuralButtons = NSStackView(views: [cleanMKVButton, removeTracksButton])
        structuralButtons.orientation = .horizontal
        structuralButtons.spacing = 8
        let subtitleButtons = NSStackView(views: [cleanSubtitleButton, addSubtitleButton])
        subtitleButtons.orientation = .horizontal
        subtitleButtons.spacing = 8
        let chapterButtons = NSStackView(views: [chaptersButton])
        chapterButtons.orientation = .horizontal

        let stack = NSStackView(views: [
            heading, scroll, titleLabel, segmentTitleField, metadataButtons, structuralButtons,
            subtitleButtons, chapterButtons,
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

    @objc private func showWorkflows() {
        statusLabel.stringValue = "Loading workflows…"
        Task {
            do {
                let workflows = try await model.loadWorkflows()
                let controller = WorkflowWindowController(
                    workflows: workflows,
                    hasSelectedAsset: selectedAsset != nil,
                    onSave: { [model] workflows in
                        try await model.saveWorkflows(workflows)
                    },
                    onUse: { [weak self] workflow in
                        self?.previewSavedWorkflow(workflow)
                    }
                )
                workflowWindowController = controller
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
                statusLabel.stringValue =
                    workflows.isEmpty
                    ? "Create your first portable workflow"
                    : "Workflows loaded"
            } catch {
                statusLabel.stringValue = "Could not load workflows: \(error.localizedDescription)"
            }
        }
    }

    private func previewSavedWorkflow(_ workflow: SavedWorkflow) {
        guard let asset = selectedAsset else {
            impactLabel.stringValue = "Select an inspected file first."
            clearPendingChange()
            return
        }
        do {
            let compiled = try SavedWorkflowCompiler().compile(workflow, for: asset)
            let stageSummary = compiled.plan.stages
                .filter { $0.mechanism != .verify && $0.mechanism != .commit }
                .map(\.mechanism.rawValue)
                .joined(separator: " + ")
            impactLabel.stringValue =
                "\(compiled.plan.impact.videoEncodeCount) video encodes • \(stageSummary)"
            pendingChange = .savedWorkflow(compiled)
            pendingAssetID = asset.id
            runButton.isEnabled = true
            runButton.toolTip = compiled.summaries.joined(separator: "; ")
            view.window?.makeKeyAndOrderFront(nil)
        } catch SavedWorkflowCompilationError.noApplicableChanges {
            impactLabel.stringValue = "No changes needed for this file"
            clearPendingChange()
        } catch {
            impactLabel.stringValue = "Workflow cannot run: \(error.localizedDescription)"
            clearPendingChange()
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
            pendingChange = .segmentTitle(title)
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
                self.pendingChange = .track(edit)
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

    @objc private func editChapters() {
        guard let asset = selectedAsset, MatroskaEditingPolicy.supports(asset),
            let parentWindow = view.window
        else { return }
        statusLabel.stringValue =
            "Extracting nested chapters from \(asset.sourceURL.lastPathComponent)…"
        chaptersButton.isEnabled = false
        Task {
            do {
                let preview = try await model.previewChapters(in: asset)
                guard selectedAsset?.id == asset.id else {
                    clearPendingChange()
                    refresh()
                    return
                }
                let controller = ChapterStudioWindowController(
                    preview: preview,
                    suggestionProvider: { [weak model] options, existingStarts in
                        guard let model else { return [] }
                        return try await model.suggestChapters(
                            in: preview.source,
                            existingChapterStarts: existingStarts,
                            options: options
                        )
                    }
                )
                chapterStudioWindowController = controller
                controller.beginSheet(for: parentWindow) { [weak self] desired in
                    guard let self else { return }
                    self.chapterStudioWindowController = nil
                    self.chaptersButton.isEnabled = MatroskaEditingPolicy.supports(asset)
                    guard let desired else {
                        self.refresh()
                        return
                    }
                    guard self.selectedAsset?.id == asset.id else {
                        self.clearPendingChange()
                        self.refresh()
                        return
                    }
                    self.pendingChange = .chapters(preview, desired)
                    self.pendingAssetID = asset.id
                    self.impactLabel.stringValue =
                        "0 video encodes • mkvpropedit • \(desired.chapterCount) nested entries"
                    self.statusLabel.stringValue = "Chapter edit plan ready"
                    self.runButton.isEnabled = true
                    self.runButton.toolTip =
                        "Replace chapters on a temporary clone, re-extract the exact hierarchy, verify preserved media, then commit."
                }
            } catch {
                statusLabel.stringValue = "Could not open chapters: \(error.localizedDescription)"
                chaptersButton.isEnabled = MatroskaEditingPolicy.supports(asset)
                clearPendingChange()
            }
        }
    }

    @objc private func removeTracks() {
        guard let asset = selectedAsset, let parentWindow = view.window else { return }
        presentTrackRemoval(
            asset: asset,
            parentWindow: parentWindow,
            mode: .manual,
            workflowName: "Remove tracks",
            isEnglishCleanup: false
        )
    }

    @objc private func cleanMKV() {
        guard let asset = selectedAsset, let parentWindow = view.window else { return }
        presentTrackRemoval(
            asset: asset,
            parentWindow: parentWindow,
            mode: .englishLibraryCleanup,
            workflowName: "English Library Cleanup",
            isEnglishCleanup: true
        )
    }

    @objc private func cleanSubtitle() {
        guard let asset = selectedAsset, Self.canCleanSubtitle(asset),
            let parentWindow = view.window
        else { return }
        guard Self.isStandaloneTextSubtitle(asset) else {
            presentEmbeddedSubtitleCleanup(asset: asset, parentWindow: parentWindow)
            return
        }
        statusLabel.stringValue = "Reading \(asset.sourceURL.lastPathComponent)…"
        cleanSubtitleButton.isEnabled = false
        Task {
            do {
                let candidate: SubtitleCleanupCandidate
                switch asset.sourceURL.pathExtension.lowercased() {
                case "srt":
                    candidate = .subRip(
                        try await model.previewSubtitleCleanup(at: asset.sourceURL)
                    )
                case "ass", "ssa":
                    candidate = .advanced(
                        try await model.previewAdvancedSubtitleCleanup(at: asset.sourceURL)
                    )
                default:
                    return
                }
                guard candidate.normalizationNeeded || candidate.changeCount > 0 else {
                    statusLabel.stringValue =
                        "This \(candidate.formatLabel) subtitle is already normalized and clean"
                    impactLabel.stringValue = "No changes needed"
                    cleanSubtitleButton.isEnabled = true
                    clearPendingChange()
                    return
                }
                let controller = candidate.makeReviewController()
                subtitleCleanupWindowController = controller
                controller.beginSheet(for: parentWindow) { [weak self] restoredIDs in
                    guard let self else { return }
                    self.subtitleCleanupWindowController = nil
                    self.cleanSubtitleButton.isEnabled = true
                    guard let restoredIDs else {
                        self.refresh()
                        return
                    }
                    guard self.selectedAsset?.id == asset.id else {
                        self.clearPendingChange()
                        self.refresh()
                        return
                    }
                    guard candidate.hasRemainingText(restoringIDs: restoredIDs) else {
                        self.impactLabel.stringValue = "Restore at least one subtitle event"
                        self.clearPendingChange()
                        return
                    }
                    let appliedCount = candidate.changeCount - restoredIDs.count
                    guard candidate.normalizationNeeded || appliedCount > 0 else {
                        self.impactLabel.stringValue = "No cleanup changes selected"
                        self.clearPendingChange()
                        return
                    }
                    self.impactLabel.stringValue =
                        "0 video encodes • UTF-8 \(candidate.formatLabel) • \(appliedCount) reviewed changes"
                    self.pendingChange = candidate.pendingChange(
                        restoringIDs: restoredIDs
                    )
                    self.pendingAssetID = asset.id
                    self.statusLabel.stringValue = "Cleanup preview ready"
                    self.runButton.isEnabled = true
                    self.runButton.toolTip =
                        "Write a normalized subtitle copy, verify text, timing, and style structure, then commit it."
                }
            } catch {
                statusLabel.stringValue =
                    "Could not preview subtitle: \(error.localizedDescription)"
                cleanSubtitleButton.isEnabled = true
                clearPendingChange()
            }
        }
    }

    private func presentEmbeddedSubtitleCleanup(asset: MediaAsset, parentWindow: NSWindow) {
        let tracks = EmbeddedTextSubtitlePolicy.editableTracks(in: asset)
        guard !tracks.isEmpty else { return }
        if tracks.count == 1, let trackUID = tracks[0].uid {
            previewEmbeddedSubtitleCleanup(
                asset: asset,
                trackUID: trackUID,
                parentWindow: parentWindow
            )
            return
        }
        let controller = EmbeddedSubtitleTrackPickerWindowController(tracks: tracks)
        embeddedSubtitleTrackPickerWindowController = controller
        controller.beginSheet(for: parentWindow) { [weak self] trackUID in
            guard let self else { return }
            self.embeddedSubtitleTrackPickerWindowController = nil
            guard let trackUID else {
                self.refresh()
                return
            }
            guard self.selectedAsset?.id == asset.id else {
                self.clearPendingChange()
                self.refresh()
                return
            }
            self.previewEmbeddedSubtitleCleanup(
                asset: asset,
                trackUID: trackUID,
                parentWindow: parentWindow
            )
        }
    }

    private func previewEmbeddedSubtitleCleanup(
        asset: MediaAsset,
        trackUID: UInt64,
        parentWindow: NSWindow
    ) {
        statusLabel.stringValue = "Extracting embedded subtitle for review…"
        cleanSubtitleButton.isEnabled = false
        Task {
            do {
                let preview = try await model.previewEmbeddedSubtitleCleanup(
                    in: asset,
                    trackUID: trackUID
                )
                guard selectedAsset?.id == asset.id else {
                    clearPendingChange()
                    refresh()
                    return
                }
                guard preview.cleanupChangeCount > 0 else {
                    statusLabel.stringValue =
                        "This embedded \(preview.format.displayName) subtitle is already clean"
                    impactLabel.stringValue = "No changes needed"
                    cleanSubtitleButton.isEnabled = true
                    clearPendingChange()
                    return
                }
                let controller = SubtitleCleanupWindowController(preview: preview)
                subtitleCleanupWindowController = controller
                controller.beginSheet(for: parentWindow) { [weak self] restoredIDs in
                    guard let self else { return }
                    self.subtitleCleanupWindowController = nil
                    self.cleanSubtitleButton.isEnabled = true
                    guard let restoredIDs else {
                        self.refresh()
                        return
                    }
                    guard self.selectedAsset?.id == asset.id else {
                        self.clearPendingChange()
                        self.refresh()
                        return
                    }
                    guard
                        Self.embeddedPreviewHasRemainingText(
                            preview,
                            restoringIDs: restoredIDs
                        )
                    else {
                        self.impactLabel.stringValue = "Restore at least one subtitle event"
                        self.clearPendingChange()
                        return
                    }
                    let appliedCount = preview.cleanupChangeCount - restoredIDs.count
                    guard appliedCount > 0 else {
                        self.impactLabel.stringValue = "No cleanup changes selected"
                        self.clearPendingChange()
                        return
                    }
                    self.pendingChange = .embeddedSubtitle(
                        preview,
                        restoringIDs: restoredIDs
                    )
                    self.pendingAssetID = asset.id
                    self.impactLabel.stringValue =
                        "0 video encodes • 1 embedded \(preview.format.displayName) track replaced in place • \(appliedCount) reviewed changes"
                    self.statusLabel.stringValue = "Embedded subtitle cleanup plan ready"
                    self.runButton.isEnabled = true
                    self.runButton.toolTip =
                        "Remux once, restore the original track UID and position, verify the MKV and extracted subtitle, then commit it."
                }
            } catch {
                statusLabel.stringValue =
                    "Could not preview embedded subtitle: \(error.localizedDescription)"
                cleanSubtitleButton.isEnabled = Self.canCleanSubtitle(asset)
                clearPendingChange()
            }
        }
    }

    @objc private func addExternalSubtitle() {
        guard let asset = selectedAsset, Self.canAddExternalSubtitle(to: asset),
            let parentWindow = view.window
        else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose a Text Subtitle"
        panel.prompt = "Review Subtitle"
        panel.message =
            "Choose one external SRT, ASS, or SSA subtitle to add as the last track in a new verified MKV copy."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["srt", "ass", "ssa"].map {
            UTType(filenameExtension: $0) ?? .plainText
        }
        guard panel.runModal() == .OK, let subtitleURL = panel.url else { return }

        statusLabel.stringValue = "Reading \(subtitleURL.lastPathComponent)…"
        addSubtitleButton.isEnabled = false
        Task {
            do {
                let preview: ExternalSubtitleFilePreview
                let match: ExternalSubtitleMatch
                switch subtitleURL.pathExtension.lowercased() {
                case "srt":
                    let subRip = try await model.previewSubtitleCleanup(at: subtitleURL)
                    preview = .subRip(subRip)
                    match = ExternalSubtitleMatcher().match(
                        media: asset,
                        subtitleURL: subtitleURL,
                        subtitle: subRip.cleanup.original
                    )
                case "ass", "ssa":
                    let advanced = try await model.previewAdvancedSubtitleCleanup(at: subtitleURL)
                    preview = .advanced(advanced)
                    match = ExternalSubtitleMatcher().match(
                        media: asset,
                        subtitleURL: subtitleURL,
                        subtitle: advanced.cleanup.original
                    )
                default:
                    return
                }
                guard selectedAsset?.id == asset.id else {
                    clearPendingChange()
                    refresh()
                    return
                }
                let controller = ExternalSubtitleMuxWindowController(
                    media: asset,
                    preview: preview,
                    match: match
                )
                externalSubtitleMuxWindowController = controller
                controller.beginSheet(for: parentWindow) { [weak self] metadata in
                    guard let self else { return }
                    self.externalSubtitleMuxWindowController = nil
                    self.addSubtitleButton.isEnabled = Self.canAddExternalSubtitle(to: asset)
                    guard let metadata else {
                        self.refresh()
                        return
                    }
                    guard self.selectedAsset?.id == asset.id else {
                        self.clearPendingChange()
                        self.refresh()
                        return
                    }
                    self.pendingChange = .externalSubtitle(preview, metadata)
                    self.pendingAssetID = asset.id
                    self.impactLabel.stringValue =
                        "0 video encodes • mkvmerge • 1 subtitle added last"
                    self.statusLabel.stringValue = "Subtitle mux plan ready"
                    self.runButton.isEnabled = true
                    self.runButton.toolTip =
                        "Copy all existing tracks, add the reviewed text subtitle last, verify the MKV, then commit it."
                }
            } catch {
                statusLabel.stringValue =
                    "Could not preview subtitle: \(error.localizedDescription)"
                addSubtitleButton.isEnabled = Self.canAddExternalSubtitle(to: asset)
                clearPendingChange()
            }
        }
    }

    private func presentTrackRemoval(
        asset: MediaAsset,
        parentWindow: NSWindow,
        mode: TrackRemovalSheetMode,
        workflowName: String,
        isEnglishCleanup: Bool
    ) {
        let controller = TrackRemovalWindowController(asset: asset, mode: mode)
        trackRemovalWindowController = controller
        controller.beginSheet(for: parentWindow) { [weak self] removal in
            guard let self else { return }
            self.trackRemovalWindowController = nil
            guard let removal else { return }
            let workflow = WorkflowDefinition(
                name: workflowName,
                operations: [.removeTracksByUID(removal)]
            )
            do {
                let plan = try WorkflowPlanner().plan(asset: asset, workflow: workflow)
                let mechanism = plan.stages.first?.mechanism.rawValue ?? "none"
                self.impactLabel.stringValue =
                    "\(plan.impact.videoEncodeCount) video encodes • \(mechanism)"
                self.pendingChange = .trackRemoval(
                    removal,
                    isEnglishCleanup: isEnglishCleanup
                )
                self.pendingAssetID = asset.id
                self.runButton.isEnabled = true
                self.runButton.toolTip =
                    "Remux retained tracks, verify the new MKV, then commit it."
            } catch {
                self.impactLabel.stringValue = "Plan failed: \(error.localizedDescription)"
                self.clearPendingChange()
            }
        }
    }

    @objc private func runChange() {
        guard let pendingChange,
            let asset = selectedAsset,
            pendingAssetID == asset.id
        else {
            clearPendingChange()
            return
        }
        let panel = NSSavePanel()
        let isSubtitleCleanup: Bool
        switch pendingChange {
        case .subtitleCleanup, .advancedSubtitleCleanup:
            isSubtitleCleanup = true
        default:
            isSubtitleCleanup = false
        }
        let isSubtitleMux: Bool
        if case .externalSubtitle = pendingChange {
            isSubtitleMux = true
        } else {
            isSubtitleMux = false
        }
        let isEmbeddedSubtitleCleanup: Bool
        if case .embeddedSubtitle = pendingChange {
            isEmbeddedSubtitleCleanup = true
        } else {
            isEmbeddedSubtitleCleanup = false
        }
        panel.title = isSubtitleCleanup ? "Save Verified Subtitle Copy" : "Save Verified MKV Copy"
        panel.prompt = "Save Verified Copy"
        panel.canCreateDirectories = true
        if isSubtitleCleanup {
            panel.nameFieldStringValue = OutputNamingPolicy.cleanedSubtitleFilename(
                for: asset.sourceURL)
        } else if isSubtitleMux {
            panel.nameFieldStringValue = OutputNamingPolicy.subtitledFilename(for: asset.sourceURL)
        } else if isEmbeddedSubtitleCleanup {
            panel.nameFieldStringValue = OutputNamingPolicy.cleanedMKVFilename(for: asset.sourceURL)
        } else {
            panel.nameFieldStringValue = OutputNamingPolicy.suggestedFilename(for: asset.sourceURL)
        }
        panel.directoryURL = asset.sourceURL.deletingLastPathComponent()
        let outputExtension =
            isSubtitleCleanup
            ? asset.sourceURL.pathExtension.lowercased()
            : ((isSubtitleMux || isEmbeddedSubtitleCleanup)
                ? "mkv" : asset.sourceURL.pathExtension)
        panel.allowedContentTypes = [UTType(filenameExtension: outputExtension) ?? .data]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        previewButton.isEnabled = false
        editTrackButton.isEnabled = false
        cleanMKVButton.isEnabled = false
        removeTracksButton.isEnabled = false
        cleanSubtitleButton.isEnabled = false
        addSubtitleButton.isEnabled = false
        chaptersButton.isEnabled = false
        runButton.isEnabled = false
        Task {
            do {
                let outputURL: URL
                switch pendingChange {
                case .segmentTitle(let title):
                    outputURL = try await model.editSegmentTitle(
                        in: asset,
                        title: title,
                        destinationURL: destinationURL
                    ).sourceURL
                case .track(let edit):
                    outputURL = try await model.editTrackMetadata(
                        in: asset,
                        edit: edit,
                        destinationURL: destinationURL
                    ).sourceURL
                case .trackRemoval(let removal, let isEnglishCleanup):
                    if isEnglishCleanup {
                        outputURL = try await model.cleanEnglishLibrary(
                            in: asset,
                            removal: removal,
                            destinationURL: destinationURL
                        ).sourceURL
                    } else {
                        outputURL = try await model.removeTracks(
                            in: asset,
                            removal: removal,
                            destinationURL: destinationURL
                        ).sourceURL
                    }
                case .savedWorkflow(let workflow):
                    outputURL = try await model.runSavedWorkflow(
                        workflow,
                        in: asset,
                        destinationURL: destinationURL
                    ).sourceURL
                case .subtitleCleanup(let preview, let restoringCueIDs):
                    outputURL = try await model.cleanSubtitle(
                        preview: preview,
                        restoringCueIDs: restoringCueIDs,
                        destinationURL: destinationURL
                    ).outputURL
                case .advancedSubtitleCleanup(let preview, let restoringEventIDs):
                    outputURL = try await model.cleanAdvancedSubtitle(
                        preview: preview,
                        restoringEventIDs: restoringEventIDs,
                        destinationURL: destinationURL
                    ).outputURL
                case .externalSubtitle(let preview, let metadata):
                    outputURL = try await model.muxExternalSubtitle(
                        in: asset,
                        subtitlePreview: preview,
                        metadata: metadata,
                        destinationURL: destinationURL
                    ).sourceURL
                case .embeddedSubtitle(let preview, let restoringIDs):
                    outputURL = try await model.cleanEmbeddedSubtitle(
                        preview: preview,
                        restoringIDs: restoringIDs,
                        destinationURL: destinationURL
                    ).sourceURL
                case .chapters(let preview, let desired):
                    outputURL = try await model.editChapters(
                        preview: preview,
                        desired: desired,
                        destinationURL: destinationURL
                    ).sourceURL
                }
                preferredSelectionURL =
                    model.assets.contains { $0.sourceURL == outputURL }
                    ? outputURL : nil
                clearPendingChange()
                refresh()
            } catch {
                previewButton.isEnabled = true
                editTrackButton.isEnabled = asset.tracks.contains {
                    $0.kind != .attachment && $0.uid != nil
                }
                removeTracksButton.isEnabled = TrackRemovalPresentation.canOfferRemoval(
                    for: asset.tracks)
                cleanMKVButton.isEnabled = Self.canOfferEnglishCleanup(for: asset)
                cleanSubtitleButton.isEnabled = Self.canCleanSubtitle(asset)
                addSubtitleButton.isEnabled = Self.canAddExternalSubtitle(to: asset)
                chaptersButton.isEnabled = MatroskaEditingPolicy.supports(asset)
                runButton.isEnabled =
                    self.pendingChange != nil
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
            cleanMKVButton.isEnabled = false
            removeTracksButton.isEnabled = false
            cleanSubtitleButton.isEnabled = false
            addSubtitleButton.isEnabled = false
            chaptersButton.isEnabled = false
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
            cleanMKVButton.isEnabled = false
            removeTracksButton.isEnabled = false
            cleanSubtitleButton.isEnabled = false
            addSubtitleButton.isEnabled = false
            chaptersButton.isEnabled = false
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
        removeTracksButton.isEnabled =
            MatroskaEditingPolicy.supports(asset)
            && TrackRemovalPresentation.canOfferRemoval(for: asset.tracks)
        removeTracksButton.toolTip =
            removeTracksButton.isEnabled
            ? "Choose tracks to omit from a verified zero-encode MKV copy."
            : "Removal requires at least two tracks with stable Matroska UIDs."
        cleanMKVButton.isEnabled = Self.canOfferEnglishCleanup(for: asset)
        cleanMKVButton.toolTip =
            cleanMKVButton.isEnabled
            ? "Review deterministic English-library subtitle cleanup suggestions."
            : "No deterministic English-library subtitle removals are suggested."
        cleanSubtitleButton.isEnabled = Self.canCleanSubtitle(asset)
        cleanSubtitleButton.toolTip =
            Self.isStandaloneTextSubtitle(asset)
            ? "Normalize and review deterministic SRT/ASS/SSA text cleanup without changing timing or styles."
            : (cleanSubtitleButton.isEnabled
                ? "Extract, review, and replace one embedded SRT/ASS/SSA track in a verified zero-encode MKV copy."
                : "Text cleanup requires a standalone subtitle or an MKV with an editable SRT, ASS, or SSA track.")
        addSubtitleButton.isEnabled = Self.canAddExternalSubtitle(to: asset)
        addSubtitleButton.toolTip =
            addSubtitleButton.isEnabled
            ? "Review and add one external SRT, ASS, or SSA track last in a verified MKV copy."
            : "External subtitle muxing currently requires an inspected Matroska video."
        chaptersButton.isEnabled = MatroskaEditingPolicy.supports(asset)
        chaptersButton.toolTip =
            chaptersButton.isEnabled
            ? "Create and edit exact nested Matroska chapters without encoding."
            : "Chapter Studio currently requires an inspected Matroska file."
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
        pendingChange = nil
        pendingAssetID = nil
        runButton.isEnabled = false
    }

    private static func canOfferEnglishCleanup(for asset: MediaAsset) -> Bool {
        MatroskaEditingPolicy.supports(asset)
            && TrackRemovalPresentation.canOfferRemoval(for: asset.tracks)
            && !EnglishLibraryCleanupPolicy.trackSuggestions(for: asset).isEmpty
    }

    private static func canCleanSubtitle(_ asset: MediaAsset) -> Bool {
        isStandaloneTextSubtitle(asset)
            || (MatroskaEditingPolicy.supports(asset)
                && !EmbeddedTextSubtitlePolicy.editableTracks(in: asset).isEmpty)
    }

    private static func isStandaloneTextSubtitle(_ asset: MediaAsset) -> Bool {
        ["srt", "ass", "ssa"].contains(asset.sourceURL.pathExtension.lowercased())
    }

    private static func embeddedPreviewHasRemainingText(
        _ preview: EmbeddedSubtitleCleanupPreview,
        restoringIDs: Set<Int>
    ) -> Bool {
        switch preview {
        case .subRip(let preview):
            !preview.cleanup.document(restoringCueIDs: restoringIDs).cues.isEmpty
        case .advanced(let preview):
            !preview.cleanup.document(restoringEventIDs: restoringIDs).events.isEmpty
        }
    }

    private static func canAddExternalSubtitle(to asset: MediaAsset) -> Bool {
        MatroskaEditingPolicy.supports(asset)
            && asset.tracks.contains { $0.kind == .video }
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

    static func cleanedSubtitleFilename(for sourceURL: URL) -> String {
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let outputExtension =
            ["srt", "ass", "ssa"].contains(sourceExtension)
            ? sourceExtension : "srt"
        return "\(sourceURL.deletingPathExtension().lastPathComponent) — Clean.\(outputExtension)"
    }

    static func subtitledFilename(for sourceURL: URL) -> String {
        "\(sourceURL.deletingPathExtension().lastPathComponent) — Subtitled.mkv"
    }

    static func cleanedMKVFilename(for sourceURL: URL) -> String {
        "\(sourceURL.deletingPathExtension().lastPathComponent) — Cleaned.mkv"
    }
}
