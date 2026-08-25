import AppKit
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import MKVMagicSystem
import UniformTypeIdentifiers

@MainActor
private final class MediaAssetTableView: NSTableView {
    var onDeleteSelection: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onDeleteSelection?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class MediaAssetTableCellView: NSTableCellView {
    let removeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        textField = label
        addSubview(label)

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Remove file"
        )
        removeButton.imagePosition = .imageOnly
        removeButton.isBordered = false
        removeButton.bezelStyle = .inline
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 22),
            removeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class MainViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private struct PreparedSavedWorkflow {
        let recipe: SavedWorkflow
        let compiled: CompiledSavedWorkflow
        let externalSubtitlePayload: ExternalSubtitleMuxPayload?
        let sourceDisposition: MediaQueueSourceDisposition
        let retryingQueueJobID: UUID?
        let expectedSourceRevision: MediaFileRevision

        var queueInputCount: Int { externalSubtitlePayload == nil ? 1 : 2 }
    }

    private struct ReviewedExternalSubtitle {
        let payload: ExternalSubtitleMuxPayload
        let metadata: ExternalSubtitleTrackMetadata

        var preview: ExternalSubtitleFilePreview { payload.preview }

        var resolvedInput: SavedWorkflowExternalSubtitleInput {
            SavedWorkflowExternalSubtitleInput(
                sourceURL: preview.sourceURL,
                metadata: metadata,
                format: preview.format,
                reviewedCleanupChangeCount: payload.reviewedCleanupChangeCount
            )
        }
    }

    private struct DestinationSelection {
        let url: URL
        let sourceDisposition: MediaQueueSourceDisposition
    }

    private enum PendingChange {
        case segmentTitle(String?)
        case track(TrackMetadataEdit)
        case trackRemoval(TrackRemoval, isEnglishCleanup: Bool)
        case savedWorkflow(PreparedSavedWorkflow)
        case subtitleCleanup(SubtitleCleanupFilePreview, restoringCueIDs: Set<Int>)
        case advancedSubtitleCleanup(
            AdvancedSubtitleCleanupFilePreview,
            restoringEventIDs: Set<Int>
        )
        case externalSubtitle(ExternalSubtitleFilePreview, ExternalSubtitleTrackMetadata)
        case embeddedSubtitle(EmbeddedSubtitleCleanupPreview, restoringIDs: Set<Int>)
        case timedTextSubtitle(TimedTextSubtitleConversionPreview)
        case textSubtitleExtraction(MatroskaTextSubtitleExtractionPreview)
        case attachmentExtraction(MatroskaAttachmentExtractionPreview)
        case attachmentRemoval(MatroskaAttachmentRemovalPreview)
        case tagExport(MatroskaTagPreview)
        case tagRemoval(MatroskaTagPreview)
        case chapters(ChapterEditPreview, MatroskaChapterDocument)
        case remuxToMKV(MKVRemuxPreview)

        var progressPresentation: (title: String, message: String) {
            switch self {
            case .segmentTitle, .track:
                ("Editing MKV Metadata", "Editing a temporary verified copy without encoding…")
            case .trackRemoval:
                ("Removing MKV Tracks", "Remuxing retained tracks without encoding…")
            case .savedWorkflow(let prepared):
                (
                    "Running \(prepared.recipe.name)",
                    "Applying the reviewed workflow to one temporary output…"
                )
            case .subtitleCleanup, .advancedSubtitleCleanup:
                ("Cleaning Subtitle", "Writing and verifying the cleaned subtitle copy…")
            case .externalSubtitle:
                ("Adding Subtitle", "Adding the reviewed subtitle without encoding video…")
            case .embeddedSubtitle:
                ("Cleaning Embedded Subtitle", "Replacing the reviewed subtitle in one remux…")
            case .timedTextSubtitle:
                ("Converting Subtitle", "Writing and verifying the converted subtitle…")
            case .textSubtitleExtraction:
                ("Extracting Subtitle", "Extracting and verifying the exact subtitle track…")
            case .attachmentExtraction:
                ("Extracting Attachment", "Extracting and verifying the exact attachment…")
            case .attachmentRemoval:
                ("Removing Attachments", "Remuxing the retained MKV content without encoding…")
            case .tagExport:
                ("Exporting Tags", "Extracting and verifying the complete Matroska tag XML…")
            case .tagRemoval:
                ("Removing Tags", "Clearing tags on a temporary verified MKV copy…")
            case .chapters:
                ("Saving Chapters", "Replacing chapters on a temporary verified MKV copy…")
            case .remuxToMKV:
                ("Remuxing to MKV", "Copying compatible streams into one verified MKV…")
            }
        }
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
    private let tableView = MediaAssetTableView()
    private let inspectorText = NSTextView()
    private let segmentTitleField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let activityIndicator = ActivityIndicatorPresentation.make(
        label: "MKV Magic activity",
        help: "Shows when MKV Magic is inspecting, preparing, processing, or verifying local media."
    )
    private let impactLabel = NSTextField(labelWithString: "No pending plan")
    private let previewButton = NSButton(title: "Preview Change", target: nil, action: nil)
    private let editTrackButton = NSButton(title: "Edit a Track…", target: nil, action: nil)
    private let cleanMKVButton = NSButton(title: "Clean MKV…", target: nil, action: nil)
    private let removeTracksButton = NSButton(title: "Remove Tracks…", target: nil, action: nil)
    private let removeAttachmentsButton = NSButton(
        title: "Remove Attachments…", target: nil, action: nil)
    private let cleanSubtitleButton = NSButton(title: "Clean Subtitle…", target: nil, action: nil)
    private let extractSubtitleButton = NSButton(
        title: "Extract Subtitle…", target: nil, action: nil)
    private let convertTimedTextButton = NSButton(
        title: "Convert MP4 Subtitle…", target: nil, action: nil)
    private let addSubtitleButton = NSButton(title: "Add Subtitle…", target: nil, action: nil)
    private let chaptersButton = NSButton(title: "Chapters…", target: nil, action: nil)
    private let attachmentsButton = NSButton(title: "Attachments…", target: nil, action: nil)
    private let tagsButton = NSButton(title: "Tags…", target: nil, action: nil)
    private let trimButton = NSButton(title: "Trim…", target: nil, action: nil)
    private let remuxButton = NSButton(title: "Remux to MKV…", target: nil, action: nil)
    private let convertButton = NSButton(title: "Convert Video…", target: nil, action: nil)
    private let joinButton = NSButton(title: "Join Files…", target: nil, action: nil)
    private let queueButton = NSButton(title: "Add to Queue", target: nil, action: nil)
    private let runButton = NSButton(title: "Verify & Run", target: nil, action: nil)
    private let chooseFilesButton = NSButton(title: "Choose Files…", target: nil, action: nil)
    private var pendingChange: PendingChange?
    private var pendingAssetID: UUID?
    private var preferredSelectionURL: URL?
    private var lastAnnouncedModelFailure: String?
    private var historyWindowController: HistoryWindowController?
    private var queueWindowController: QueueWindowController?
    private var encodingBenchmarkWindowController: EncodingBenchmarkWindowController?
    private var trackEditorWindowController: TrackEditorWindowController?
    private var trackRemovalWindowController: TrackRemovalWindowController?
    private var workflowWindowController: WorkflowWindowController?
    private var workflowPlanReviewWindowController: WorkflowPlanReviewWindowController?
    private var subtitleCleanupWindowController: SubtitleCleanupWindowController?
    private var externalSubtitleMuxWindowController: ExternalSubtitleMuxWindowController?
    private var embeddedSubtitleTrackPickerWindowController:
        EmbeddedSubtitleTrackPickerWindowController?
    private var attachmentPickerWindowController: AttachmentPickerWindowController?
    private var attachmentRemovalWindowController: AttachmentRemovalWindowController?
    private var tagActionWindowController: TagActionWindowController?
    private var chapterStudioWindowController: ChapterStudioWindowController?
    private var trimWindowController: TrimWindowController?
    private var trimProgressWindowController: VerifiedOutputProgressWindowController?
    private var trimTask: Task<Void, Never>?
    private var isPreparingVideoProcessing = false
    private var losslessJoinWindowController: LosslessJoinWindowController?
    private var commonFormatJoinWindowController: CommonFormatJoinWindowController?
    private var losslessJoinProgressWindowController: VerifiedOutputProgressWindowController?
    private var losslessJoinTask: Task<Void, Never>?
    private var verifiedRunTask: Task<Void, Never>?
    private var verifiedRunProgressWindowController: VerifiedOutputProgressWindowController?
    private var interfaceActivityIDs = Set<UUID>()

    var preferredInitialFirstResponder: NSView { chooseFilesButton }

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        model.didChange = { [weak self] in self?.refresh() }
        model.queueDidChange = { [weak self] in self?.refreshOpenQueue() }
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
        joinButton.target = self
        joinButton.action = #selector(joinFiles)
        joinButton.image = NSImage(
            systemSymbolName: "rectangle.stack.badge.plus",
            accessibilityDescription: "Join Files"
        )
        joinButton.imagePosition = .imageLeading
        joinButton.alignment = .left
        joinButton.isBordered = false
        joinButton.font = .systemFont(ofSize: NSFont.systemFontSize)
        joinButton.isEnabled = false
        joinButton.setAccessibilityHelp(
            "Review how two or more inspected Matroska files will be joined."
        )
        let stack = NSStackView(views: [
            title,
            sidebarLabel("Quick Actions", symbol: "wand.and.stars"),
            sidebarButton(
                "Workflows",
                symbol: "square.stack.3d.up",
                action: #selector(showWorkflows)
            ),
            joinButton,
            sidebarLabel("Tools", symbol: "wrench.and.screwdriver"),
            sidebarButton(
                "Encoding Test…",
                symbol: "speedometer",
                action: #selector(showEncodingBenchmark)
            ),
            sidebarLabel("Queue", symbol: "list.bullet.rectangle"),
            sidebarButton(
                "Queue",
                symbol: "list.bullet.rectangle",
                action: #selector(showQueue)
            ),
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
        button.setAccessibilityHelp("Open \(title) in a separate window.")
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

        chooseFilesButton.target = self
        chooseFilesButton.action = #selector(chooseFiles)
        chooseFilesButton.bezelStyle = .rounded
        chooseFilesButton.setAccessibilityLabel("Choose media files or folders")
        chooseFilesButton.setAccessibilityHelp(
            "Open one or more media files or folders for local inspection."
        )

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("asset"))
        column.title = "Files"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 32
        tableView.allowsEmptySelection = true
        tableView.onDeleteSelection = { [weak self] in self?.removeSelectedAsset() }
        tableView.setAccessibilityLabel("Inspected media files")
        tableView.setAccessibilityHelp(
            "Choose a file to inspect its tracks and enable applicable actions. Use its remove button or press Delete to remove it from this list without deleting the source file."
        )
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let stack = NSStackView(views: [heading, help, chooseFilesButton, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        chooseFilesButton.setContentHuggingPriority(.required, for: .horizontal)

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
        inspectorText.setAccessibilityLabel("Selected media details")
        inspectorText.setAccessibilityHelp(
            "Read-only container, track, chapter, attachment, tag, and warning details."
        )
        let scroll = NSScrollView()
        scroll.documentView = inspectorText
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        let titleLabel = NSTextField(labelWithString: "Segment title")
        segmentTitleField.placeholderString = "Leave empty to remove"
        segmentTitleField.setAccessibilityLabel("Segment title")
        segmentTitleField.setAccessibilityHelp(
            "Edit the Matroska segment title, or leave it empty to remove the title."
        )
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
        removeAttachmentsButton.target = self
        removeAttachmentsButton.action = #selector(removeMatroskaAttachments)
        removeAttachmentsButton.isEnabled = false
        removeAttachmentsButton.setAccessibilityHelp(
            "Choose embedded Matroska attachments to omit from a new verified zero-encode MKV copy."
        )
        cleanSubtitleButton.target = self
        cleanSubtitleButton.action = #selector(cleanSubtitle)
        cleanSubtitleButton.isEnabled = false
        extractSubtitleButton.target = self
        extractSubtitleButton.action = #selector(extractMatroskaTextSubtitle)
        extractSubtitleButton.isEnabled = false
        extractSubtitleButton.setAccessibilityHelp(
            "Extract one embedded Matroska SRT, ASS, or SSA track into a separate exact verified subtitle without changing the MKV."
        )
        convertTimedTextButton.target = self
        convertTimedTextButton.action = #selector(convertTimedTextSubtitle)
        convertTimedTextButton.isEnabled = false
        convertTimedTextButton.setAccessibilityHelp(
            "Convert one selected MP4 TX3G text track into a separate verified UTF-8 ASS subtitle without changing the video."
        )
        addSubtitleButton.target = self
        addSubtitleButton.action = #selector(addExternalSubtitle)
        addSubtitleButton.isEnabled = false
        chaptersButton.target = self
        chaptersButton.action = #selector(editChapters)
        chaptersButton.isEnabled = false
        attachmentsButton.target = self
        attachmentsButton.action = #selector(extractMatroskaAttachment)
        attachmentsButton.isEnabled = false
        attachmentsButton.setAccessibilityHelp(
            "Extract one embedded Matroska attachment into a separate exact verified file without changing the MKV."
        )
        tagsButton.target = self
        tagsButton.action = #selector(manageMatroskaTags)
        tagsButton.isEnabled = false
        tagsButton.setAccessibilityHelp(
            "Export complete Matroska tags as exact XML or review clearing every tag from a new verified MKV copy."
        )
        trimButton.target = self
        trimButton.action = #selector(trimFile)
        trimButton.isEnabled = false
        remuxButton.target = self
        remuxButton.action = #selector(remuxToMKV)
        remuxButton.isEnabled = false
        remuxButton.setAccessibilityHelp(
            "Copy compatible MP4, MOV, M4V, or WebM streams into a verified MKV without encoding."
        )
        convertButton.target = self
        convertButton.action = #selector(convertVideo)
        convertButton.isEnabled = false
        let metadataButtons = NSStackView(views: [previewButton, editTrackButton])
        metadataButtons.orientation = .horizontal
        metadataButtons.spacing = 8
        let structuralButtons = NSStackView(views: [cleanMKVButton, removeTracksButton])
        structuralButtons.orientation = .horizontal
        structuralButtons.spacing = 8
        let subtitleButtons = NSStackView(views: [cleanSubtitleButton, addSubtitleButton])
        subtitleButtons.orientation = .horizontal
        subtitleButtons.spacing = 8
        let subtitleConversionButtons = NSStackView(views: [
            extractSubtitleButton, convertTimedTextButton,
        ])
        subtitleConversionButtons.orientation = .horizontal
        subtitleConversionButtons.spacing = 8
        let chapterButtons = NSStackView(views: [chaptersButton, trimButton])
        chapterButtons.orientation = .horizontal
        chapterButtons.spacing = 8
        let attachmentButtons = NSStackView(views: [attachmentsButton, removeAttachmentsButton])
        attachmentButtons.orientation = .horizontal
        attachmentButtons.spacing = 8
        let tagButtons = NSStackView(views: [tagsButton])
        tagButtons.orientation = .horizontal
        let videoButtons = NSStackView(views: [remuxButton, convertButton])
        videoButtons.orientation = .horizontal
        videoButtons.spacing = 8

        let stack = NSStackView(views: [
            heading, scroll, titleLabel, segmentTitleField, metadataButtons, structuralButtons,
            subtitleButtons, subtitleConversionButtons, chapterButtons, attachmentButtons,
            tagButtons, videoButtons,
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
        statusLabel.setAccessibilityLabel("Application status")
        impactLabel.setAccessibilityLabel("Plan impact")
        impactLabel.setAccessibilityHelp(
            "Summarizes whether the reviewed change copies, remuxes, or transcodes media."
        )
        impactLabel.font = .systemFont(ofSize: 13, weight: .medium)
        runButton.isEnabled = false
        runButton.keyEquivalent = "\r"
        runButton.target = self
        runButton.action = #selector(runChange)
        queueButton.isEnabled = false
        queueButton.target = self
        queueButton.action = #selector(addPendingWorkflowToQueue)
        queueButton.setAccessibilityHelp(
            "Save the reviewed workflow as waiting production-queue work."
        )
        runButton.setAccessibilityHelp(
            "Choose a destination, create one verified output, and preserve the original."
        )

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [
            activityIndicator, statusLabel, spacer, impactLabel, queueButton, runButton,
        ])
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

    @objc func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        inspect(panel.urls)
    }

    @objc func showMainWindow() {
        view.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showHistory() {
        let activityID = beginInterfaceActivity("Loading history…")
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let records = try await model.loadHistory()
                let controller = HistoryWindowController(
                    records: records,
                    onExport: { [model] destinationURL in
                        try await model.exportPrivacySafeSupportReport(
                            records: records,
                            to: destinationURL
                        )
                    }
                )
                historyWindowController = controller
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
                statusLabel.stringValue = records.isEmpty ? "No history yet" : "History loaded"
            } catch {
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not load History.",
                        recovery: "Media work is unchanged; close and reopen History to retry.",
                        error: error
                    ),
                    in: statusLabel
                )
            }
        }
    }

    @objc func showQueue() {
        if let controller = queueWindowController,
            controller.window?.isVisible == true
        {
            refreshOpenQueue()
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }
        let activityID = beginInterfaceActivity("Loading queue…")
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let snapshot = try await model.loadQueue()
                let controller = QueueWindowController(
                    snapshot: snapshot,
                    onSetPaused: { [model] paused in
                        try await model.setQueuePaused(paused)
                    },
                    onTransition: { [weak self, model] jobID, state, reason in
                        let snapshot = try await model.transitionQueueJob(
                            jobID,
                            to: state,
                            reason: reason
                        )
                        if state == .cancelling {
                            await model.cancelAutomaticQueueJob(jobID)
                        }
                        if QueueExecutionControl.shouldCancelActiveTask(
                            jobID: jobID,
                            transition: state,
                            activeJobID: model.activeQueueJobID
                        ) {
                            self?.verifiedRunTask?.cancel()
                        }
                        return snapshot
                    },
                    onReorder: { [model] orderedIDs in
                        try await model.reorderPendingQueueJobs(orderedIDs)
                    },
                    onReview: { [weak self] job in
                        self?.reviewQueueJob(job)
                    }
                )
                queueWindowController = controller
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
                statusLabel.stringValue =
                    snapshot.jobs.isEmpty ? "Queue is empty" : "Queue loaded"
            } catch {
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not load Queue.",
                        recovery: "Media work is unchanged; close and reopen Queue to retry.",
                        error: error
                    ),
                    in: statusLabel
                )
            }
        }
    }

    @objc func showEncodingBenchmark() {
        let activityID = beginInterfaceActivity(
            "Loading the saved local encoding recommendation…"
        )
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let report = try await model.loadEncodingBenchmarkReport()
                let controller = EncodingBenchmarkWindowController(
                    report: report,
                    onRun: { [model] in
                        try await model.runEncodingBenchmark()
                    }
                )
                encodingBenchmarkWindowController = controller
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
                statusLabel.stringValue =
                    report == nil
                    ? "Encoding test ready; it will not run without your approval."
                    : "Saved encoding recommendation loaded."
            } catch {
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not open Encoding Test.",
                        recovery: "No test was started; close and reopen Encoding Test to retry.",
                        error: error
                    ),
                    in: statusLabel
                )
            }
        }
    }

    private func refreshOpenQueue() {
        guard let controller = queueWindowController,
            controller.window?.isVisible == true
        else { return }
        Task { [weak self, model] in
            do {
                let snapshot = try await model.loadQueue()
                self?.queueWindowController?.update(snapshot: snapshot)
            } catch {
                // The queue window keeps its last valid snapshot and exposes the
                // next explicit mutation error without disturbing media work.
            }
        }
    }

    @objc func showWorkflows() {
        let activityID = beginInterfaceActivity("Loading workflows…")
        Task {
            defer { endInterfaceActivity(activityID) }
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
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not load workflows.",
                        recovery: "No workflow was changed; close and reopen Workflows to retry.",
                        error: error
                    ),
                    in: statusLabel
                )
            }
        }
    }

    @objc private func trimFile() {
        prepareVideoProcessing(operation: .trim)
    }

    @objc private func convertVideo() {
        prepareVideoProcessing(operation: .transcode)
    }

    @objc private func remuxToMKV() {
        guard let asset = selectedAsset else { return }
        clearPendingChange()
        do {
            let preview = try model.previewRemuxToMKV(source: asset)
            let chapterSummary =
                preview.plan.chapterCarrierTrackIDs.isEmpty
                ? "preserve chapters"
                : "convert the MP4 chapter carrier to Matroska chapters"
            impactLabel.stringValue =
                "No transcoding • Copy \(preview.plan.copiedTrackCount) track(s) • \(chapterSummary)"
            pendingChange = .remuxToMKV(preview)
            pendingAssetID = asset.id
            runButton.isEnabled = true
            runButton.toolTip =
                "Create one MKV, verify every copied packet and reviewed chapter, then commit it."
        } catch {
            AccessibleStatusPresentation.present(
                UserFacingErrorPresentation.message(
                    failure: "Could not prepare the zero-encode MKV remux.",
                    recovery:
                        "The original is unchanged; inspect the disabled action explanation or choose conversion for incompatible tracks.",
                    error: error
                ),
                in: impactLabel,
                returningFocusTo: remuxButton
            )
            clearPendingChange()
        }
    }

    private func prepareVideoProcessing(operation: ExactVideoOperation) {
        guard !isPreparingVideoProcessing, let asset = selectedAsset,
            operation == .trim
                ? TrimPresentationPolicy.canOfferTrim(for: asset)
                : TrimPresentationPolicy.canOfferConversion(for: asset),
            let duration = asset.duration, let parentWindow = view.window
        else { return }
        let times =
            operation == .trim
            ? TrimPresentationPolicy.thumbnailTimes(duration: duration) : []
        guard operation == .transcode || !times.isEmpty else { return }
        isPreparingVideoProcessing = true
        updateActivityIndicator()
        trimButton.isEnabled = false
        convertButton.isEnabled = false
        statusLabel.stringValue =
            operation == .transcode
            ? "Loading local encoder choices…"
            : "Loading local trim thumbnails and encoder choices…"
        Task {
            defer { updateActivityIndicator() }
            do {
                async let capabilityTask = model.probeEncodingCapabilities()
                let thumbnails =
                    operation == .trim
                    ? try await model.chapterThumbnails(in: asset, at: times) : []
                let capabilities = await capabilityTask
                guard selectedAsset?.id == asset.id, view.window === parentWindow else {
                    isPreparingVideoProcessing = false
                    refresh()
                    return
                }
                let controller = TrimWindowController(
                    source: asset,
                    thumbnails: thumbnails,
                    capabilities: capabilities,
                    operation: operation,
                    reviewProvider: { [weak model] request in
                        guard let model else { throw CancellationError() }
                        return try await model.previewTrim(
                            in: asset,
                            request: request,
                            capabilities: capabilities
                        )
                    }
                )
                isPreparingVideoProcessing = false
                trimWindowController = controller
                controller.beginSheet(for: parentWindow) { [weak self] preview in
                    guard let self else { return }
                    self.trimWindowController = nil
                    guard let preview else {
                        self.refresh()
                        return
                    }
                    guard self.selectedAsset?.id == asset.id else {
                        self.refresh()
                        return
                    }
                    self.chooseVideoProcessingDestination(
                        preview,
                        parentWindow: parentWindow
                    )
                }
                statusLabel.stringValue =
                    operation == .transcode
                    ? "Choose video and audio handling, then review one verified conversion."
                    : "Choose numeric trim boundaries and review the result."
            } catch {
                isPreparingVideoProcessing = false
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure:
                            operation == .transcode
                            ? "Could not open Convert Video." : "Could not open Trim.",
                        recovery:
                            "No output was created; check the selected video and try again.",
                        error: error
                    ),
                    in: statusLabel
                )
                refresh()
            }
        }
    }

    private func chooseVideoProcessingDestination(
        _ preview: TrimExecutionPreview,
        parentWindow: NSWindow
    ) {
        let panel = NSSavePanel()
        panel.title =
            preview.operation == .transcode
            ? "Save Verified Converted MKV" : "Save Verified Trimmed MKV"
        panel.prompt = preview.operation == .transcode ? "Convert & Save" : "Trim & Save"
        panel.message = OutputDestinationPolicy.savePanelMessage()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            preview.operation == .transcode
            ? OutputNamingPolicy.convertedFilename(for: preview.source.sourceURL)
            : OutputNamingPolicy.trimmedFilename(for: preview.source.sourceURL)
        panel.directoryURL = OutputDestinationPolicy.defaultDirectory(
            for: preview.source.sourceURL
        )
        panel.allowedContentTypes = [UTType(filenameExtension: "mkv") ?? .data]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard let self, response == .OK, let destinationURL = panel.url else {
                self?.refresh()
                return
            }
            self.runVideoProcessing(
                preview,
                destinationURL: destinationURL,
                parentWindow: parentWindow
            )
        }
    }

    private func runVideoProcessing(
        _ preview: TrimExecutionPreview,
        destinationURL: URL,
        parentWindow: NSWindow
    ) {
        let progress: VerifiedOutputProgressWindowController
        if preview.operation == .transcode {
            progress = .videoTranscode()
        } else {
            let mode: TrimMode =
                switch preview {
                case .fast: .fast
                case .exact: .exact
                }
            progress = .trim(mode: mode)
        }
        trimProgressWindowController = progress
        progress.beginSheet(for: parentWindow)
        let task = Task { [weak self, weak progress] in
            guard let self else { return }
            do {
                let output = try await model.executeTrim(
                    preview: preview,
                    destinationURL: destinationURL,
                    onStage: { stage in progress?.update(stage: stage) }
                )
                preferredSelectionURL = output.sourceURL
                progress?.finish()
                trimProgressWindowController = nil
                trimTask = nil
                refresh()
            } catch {
                progress?.finish()
                trimProgressWindowController = nil
                trimTask = nil
                refresh()
            }
        }
        trimTask = task
        progress.onCancel = { [weak self] in self?.trimTask?.cancel() }
    }

    @objc private func joinFiles() {
        guard let parentWindow = view.window else { return }
        let sources = model.assets.filter { MatroskaEditingPolicy.supports($0) }
        guard sources.count >= 2 else {
            statusLabel.stringValue = "Inspect at least two Matroska files to join."
            return
        }
        joinButton.isEnabled = false
        let activityID = beginInterfaceActivity(
            "Reading exact nested chapters for join setup…"
        )
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let options = try await model.loadLosslessJoinSourceOptions(sources)
                let capabilities = await model.probeEncodingCapabilities()
                guard view.window === parentWindow else { return }
                let controller = LosslessJoinWindowController(
                    options: options,
                    encodingCapabilities: capabilities
                )
                losslessJoinWindowController = controller
                controller.beginSheet(for: parentWindow) { [weak self] selection in
                    guard let self else { return }
                    self.losslessJoinWindowController = nil
                    guard let selection else {
                        self.refresh()
                        return
                    }
                    switch selection {
                    case .lossless(let candidate):
                        self.confirmLosslessJoin(candidate, parentWindow: parentWindow)
                    case .commonFormat(let candidate):
                        DispatchQueue.main.async { [weak self] in
                            self?.reviewCommonFormatJoin(
                                candidate,
                                parentWindow: parentWindow
                            )
                        }
                    }
                }
                statusLabel.stringValue = "Review source order, track lanes, and chapters."
            } catch {
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not open Join.",
                        recovery: "No output was created; review the selected files and try again.",
                        error: error
                    ),
                    in: statusLabel
                )
                refresh()
            }
        }
    }

    private func reviewCommonFormatJoin(
        _ candidate: CommonFormatJoinCandidate,
        parentWindow: NSWindow
    ) {
        do {
            let controller = try CommonFormatJoinWindowController(candidate: candidate)
            commonFormatJoinWindowController = controller
            controller.beginSheet(for: parentWindow) { [weak self] resolvedPlan in
                guard let self else { return }
                self.commonFormatJoinWindowController = nil
                guard let resolvedPlan else {
                    self.refresh()
                    return
                }
                self.confirmCommonFormatJoin(
                    candidate,
                    resolvedPlan: resolvedPlan,
                    parentWindow: parentWindow
                )
            }
        } catch {
            AccessibleStatusPresentation.present(
                UserFacingErrorPresentation.message(
                    failure: "Could not prepare common-format choices.",
                    recovery: "No plan was approved; close and reopen Join to retry.",
                    error: error
                ),
                in: statusLabel
            )
            refresh()
        }
    }

    private func confirmCommonFormatJoin(
        _ candidate: CommonFormatJoinCandidate,
        resolvedPlan: ResolvedJoinNormalizationPlan,
        parentWindow: NSWindow
    ) {
        let activityID = beginInterfaceActivity(
            "Confirming approved choices and unchanged sources…"
        )
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let preview = try await model.previewCommonFormatJoin(
                    candidate,
                    resolvedPlan: resolvedPlan
                )
                guard view.window === parentWindow else { return }
                chooseCommonFormatJoinDestination(preview, parentWindow: parentWindow)
            } catch {
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not confirm the common-format join.",
                        recovery:
                            "No output was created; reopen Join and review every choice again.",
                        error: error
                    ),
                    in: statusLabel
                )
                refresh()
            }
        }
    }

    private func chooseCommonFormatJoinDestination(
        _ preview: CommonFormatJoinPreview,
        parentWindow: NSWindow
    ) {
        guard let firstSource = preview.candidate.sources.first else { return }
        let panel = NSSavePanel()
        panel.title = "Save Verified Joined MKV"
        panel.prompt = "Normalize, Join & Save"
        panel.message = OutputDestinationPolicy.savePanelMessage(
            detail:
                "Incompatible lanes will be normalized once in private temporary storage; the final MKV is saved only after verification."
        )
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = OutputNamingPolicy.joinedFilename(for: firstSource.sourceURL)
        panel.directoryURL = OutputDestinationPolicy.defaultDirectory(
            for: firstSource.sourceURL
        )
        panel.allowedContentTypes = [UTType(filenameExtension: "mkv") ?? .data]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard let self, response == .OK, let destinationURL = panel.url else {
                self?.refresh()
                return
            }
            self.runCommonFormatJoin(
                preview,
                destinationURL: destinationURL,
                parentWindow: parentWindow
            )
        }
    }

    private func runCommonFormatJoin(
        _ preview: CommonFormatJoinPreview,
        destinationURL: URL,
        parentWindow: NSWindow
    ) {
        let progress = VerifiedOutputProgressWindowController.commonFormatJoin()
        losslessJoinProgressWindowController = progress
        progress.beginSheet(for: parentWindow)
        let task = Task { [weak self, weak progress] in
            guard let self else { return }
            do {
                let output = try await model.executeCommonFormatJoin(
                    preview: preview,
                    destinationURL: destinationURL,
                    onStage: { stage in progress?.update(stage: stage) }
                )
                preferredSelectionURL = output.sourceURL
                progress?.finish()
                losslessJoinProgressWindowController = nil
                losslessJoinTask = nil
                refresh()
            } catch {
                progress?.finish()
                losslessJoinProgressWindowController = nil
                losslessJoinTask = nil
                refresh()
            }
        }
        losslessJoinTask = task
        progress.onCancel = { [weak self] in self?.losslessJoinTask?.cancel() }
    }

    private func confirmLosslessJoin(
        _ candidate: LosslessJoinCandidate,
        parentWindow: NSWindow
    ) {
        let activityID = beginInterfaceActivity(
            "Confirming every reviewed source is unchanged…"
        )
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let preview = try await model.previewLosslessJoin(candidate)
                guard view.window === parentWindow else { return }
                chooseLosslessJoinDestination(preview, parentWindow: parentWindow)
            } catch {
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not confirm the lossless join.",
                        recovery:
                            "No output was created; reopen Join and review every source again.",
                        error: error
                    ),
                    in: statusLabel
                )
                refresh()
            }
        }
    }

    private func chooseLosslessJoinDestination(
        _ preview: LosslessJoinPreview,
        parentWindow: NSWindow
    ) {
        guard let firstSource = preview.sources.first else { return }
        let panel = NSSavePanel()
        panel.title = "Save Verified Joined MKV"
        panel.prompt = "Join & Save"
        panel.message = OutputDestinationPolicy.savePanelMessage()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = OutputNamingPolicy.joinedFilename(for: firstSource.sourceURL)
        panel.directoryURL = OutputDestinationPolicy.defaultDirectory(
            for: firstSource.sourceURL
        )
        panel.allowedContentTypes = [UTType(filenameExtension: "mkv") ?? .data]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard let self, response == .OK, let destinationURL = panel.url else {
                self?.refresh()
                return
            }
            self.runLosslessJoin(
                preview,
                destinationURL: destinationURL,
                parentWindow: parentWindow
            )
        }
    }

    private func runLosslessJoin(
        _ preview: LosslessJoinPreview,
        destinationURL: URL,
        parentWindow: NSWindow
    ) {
        let progress = VerifiedOutputProgressWindowController.losslessJoin()
        losslessJoinProgressWindowController = progress
        progress.beginSheet(for: parentWindow)
        let task = Task { [weak self, weak progress] in
            guard let self else { return }
            do {
                let output = try await model.executeLosslessJoin(
                    preview: preview,
                    destinationURL: destinationURL,
                    onStage: { stage in progress?.update(stage: stage) }
                )
                preferredSelectionURL = output.sourceURL
                progress?.finish()
                losslessJoinProgressWindowController = nil
                losslessJoinTask = nil
                refresh()
            } catch {
                progress?.finish()
                losslessJoinProgressWindowController = nil
                losslessJoinTask = nil
                refresh()
            }
        }
        losslessJoinTask = task
        progress.onCancel = { [weak self] in self?.losslessJoinTask?.cancel() }
    }

    private func previewSavedWorkflow(
        _ workflow: SavedWorkflow,
        sourceDisposition: MediaQueueSourceDisposition = .keepOriginal,
        retryingQueueJobID: UUID? = nil
    ) {
        guard let asset = selectedAsset, let parentWindow = view.window else {
            impactLabel.stringValue = "Select an inspected file first."
            clearPendingChange()
            return
        }
        clearPendingChange()
        guard
            workflow.steps.contains(where: {
                $0.isEnabled && $0.action == .addExternalSubtitle
            })
        else {
            presentSavedWorkflowReview(
                workflow,
                asset: asset,
                parentWindow: parentWindow,
                externalSubtitle: nil,
                sourceDisposition: sourceDisposition,
                retryingQueueJobID: retryingQueueJobID
            )
            return
        }
        let reviewsCleanup = workflow.steps.contains {
            $0.isEnabled && $0.action == .cleanExternalSubtitleText
        }
        prepareExternalSubtitle(
            asset: asset,
            parentWindow: parentWindow,
            reviewsCleanup: reviewsCleanup
        ) { [weak self] reviewed in
            guard let self else { return }
            guard let reviewed else {
                self.statusLabel.stringValue = "No external subtitle selected"
                self.clearPendingChange()
                return
            }
            self.presentSavedWorkflowReview(
                workflow,
                asset: asset,
                parentWindow: parentWindow,
                externalSubtitle: reviewed,
                sourceDisposition: sourceDisposition,
                retryingQueueJobID: retryingQueueJobID
            )
        }
    }

    private func presentSavedWorkflowReview(
        _ workflow: SavedWorkflow,
        asset: MediaAsset,
        parentWindow: NSWindow,
        externalSubtitle: ReviewedExternalSubtitle?,
        sourceDisposition: MediaQueueSourceDisposition,
        retryingQueueJobID: UUID?
    ) {
        let needsEncodingCapabilities = SavedWorkflowCompiler().needsEncodingCapabilities(
            for: workflow,
            asset: asset
        )
        guard needsEncodingCapabilities else {
            compileAndPresentSavedWorkflowReview(
                workflow,
                asset: asset,
                parentWindow: parentWindow,
                externalSubtitle: externalSubtitle,
                availableVideoPresets: [],
                availableAudioPresets: [],
                sourceDisposition: sourceDisposition,
                retryingQueueJobID: retryingQueueJobID
            )
            return
        }

        let activityID = beginInterfaceActivity(
            "Checking compatible video encoders on this Mac…"
        )
        Task { [weak self, weak parentWindow] in
            guard let self else { return }
            defer { endInterfaceActivity(activityID) }
            let capabilities = await model.probeEncodingCapabilities()
            guard let parentWindow, view.window === parentWindow,
                selectedAsset?.id == asset.id
            else {
                clearPendingChange()
                return
            }
            compileAndPresentSavedWorkflowReview(
                workflow,
                asset: asset,
                parentWindow: parentWindow,
                externalSubtitle: externalSubtitle,
                availableVideoPresets: capabilities.availableVideoPresets,
                availableAudioPresets: capabilities.availableAudioPresets,
                sourceDisposition: sourceDisposition,
                retryingQueueJobID: retryingQueueJobID
            )
        }
    }

    private func compileAndPresentSavedWorkflowReview(
        _ workflow: SavedWorkflow,
        asset: MediaAsset,
        parentWindow: NSWindow,
        externalSubtitle: ReviewedExternalSubtitle?,
        availableVideoPresets: [VideoPreset],
        availableAudioPresets: [AudioTranscodePreset],
        sourceDisposition: MediaQueueSourceDisposition,
        retryingQueueJobID: UUID?
    ) {
        guard let reviewedSourceRevision = model.reviewedSourceRevision(for: asset) else {
            statusLabel.stringValue = "The source changed after inspection"
            impactLabel.stringValue = "Inspect the file again before reviewing this workflow"
            clearPendingChange()
            return
        }
        do {
            let preview = try SavedWorkflowCompiler().preview(
                workflow,
                for: asset,
                inputs: SavedWorkflowResolvedInputs(
                    externalSubtitle: externalSubtitle?.resolvedInput,
                    availableVideoPresets: availableVideoPresets,
                    availableAudioPresets: availableAudioPresets
                )
            )
            let controller = WorkflowPlanReviewWindowController(
                preview: preview,
                sourceDisplayName: asset.sourceURL.lastPathComponent
            )
            workflowPlanReviewWindowController = controller
            statusLabel.stringValue = "Reviewing \(workflow.name)…"
            parentWindow.makeKeyAndOrderFront(nil)
            controller.beginSheet(for: parentWindow) { [weak self] accepted in
                guard let self else { return }
                self.workflowPlanReviewWindowController = nil
                guard accepted, let compiled = preview.compiledWorkflow else {
                    self.impactLabel.stringValue =
                        preview.compiledWorkflow == nil
                        ? "No changes needed for this file" : "Workflow preview cancelled"
                    self.statusLabel.stringValue =
                        preview.compiledWorkflow == nil
                        ? "The selected file already satisfies this workflow."
                        : "No workflow plan selected"
                    self.clearPendingChange()
                    return
                }
                guard self.selectedAsset?.id == asset.id else {
                    self.impactLabel.stringValue = "The selected file changed; preview again"
                    self.statusLabel.stringValue = "Workflow preview expired"
                    self.clearPendingChange()
                    return
                }
                self.installPendingWorkflow(
                    recipe: workflow,
                    compiled,
                    externalSubtitlePayload: externalSubtitle?.payload,
                    sourceDisposition: sourceDisposition,
                    retryingQueueJobID: retryingQueueJobID,
                    asset: asset,
                    reviewedSourceRevision: reviewedSourceRevision
                )
            }
        } catch {
            AccessibleStatusPresentation.present(
                UserFacingErrorPresentation.message(
                    failure: "Could not prepare this workflow.",
                    recovery:
                        "No output was created; review the selected file and workflow cards.",
                    error: error
                ),
                in: impactLabel,
                returningFocusTo: previewButton
            )
            statusLabel.stringValue = "Workflow preview needs attention"
            clearPendingChange()
        }
    }

    private func installPendingWorkflow(
        recipe: SavedWorkflow,
        _ compiled: CompiledSavedWorkflow,
        externalSubtitlePayload: ExternalSubtitleMuxPayload?,
        sourceDisposition: MediaQueueSourceDisposition,
        retryingQueueJobID: UUID?,
        asset: MediaAsset,
        reviewedSourceRevision: MediaFileRevision
    ) {
        guard model.reviewedSourceRevision(for: asset) == reviewedSourceRevision else {
            statusLabel.stringValue = "The source changed during workflow review"
            impactLabel.stringValue = "Inspect the file again and review the workflow"
            clearPendingChange()
            return
        }
        impactLabel.stringValue = WorkflowPlanReviewPresentation.impactSummary(for: compiled)
        statusLabel.stringValue = "Workflow plan ready for verification"
        pendingChange = .savedWorkflow(
            PreparedSavedWorkflow(
                recipe: recipe,
                compiled: compiled,
                externalSubtitlePayload: externalSubtitlePayload,
                sourceDisposition: sourceDisposition,
                retryingQueueJobID: retryingQueueJobID,
                expectedSourceRevision: reviewedSourceRevision
            )
        )
        pendingAssetID = asset.id
        runButton.isEnabled = true
        runButton.toolTip = compiled.summaries.joined(separator: "; ")
        updateQueueButton()
    }

    private func inspect(_ urls: [URL]) {
        Task { await model.addFiles(urls) }
    }

    @objc private func removeAssetFromList(_ sender: NSButton) {
        removeAsset(at: sender.tag)
    }

    private func removeSelectedAsset() {
        removeAsset(at: tableView.selectedRow)
    }

    private func removeAsset(at row: Int) {
        guard model.assets.indices.contains(row), !isMediaWorkBusy else { return }
        let asset = model.assets[row]
        let remaining = model.assets.enumerated().filter { $0.offset != row }.map(\.element)
        preferredSelectionURL =
            remaining.indices.contains(row)
            ? remaining[row].sourceURL : remaining.last?.sourceURL
        clearPendingChange()
        model.removeAssets(withIDs: [asset.id])
    }

    @discardableResult
    private func beginInterfaceActivity(_ message: String) -> UUID {
        let id = UUID()
        interfaceActivityIDs.insert(id)
        statusLabel.stringValue = message
        updateActivityIndicator()
        return id
    }

    private func endInterfaceActivity(_ id: UUID) {
        interfaceActivityIDs.remove(id)
        updateActivityIndicator()
    }

    private var isMediaWorkBusy: Bool {
        model.state.showsProgressIndicator
            || verifiedRunTask != nil
            || trimTask != nil
            || losslessJoinTask != nil
            || isPreparingVideoProcessing
    }

    private func updateActivityIndicator() {
        ActivityIndicatorPresentation.set(
            activityIndicator,
            active: isMediaWorkBusy || !interfaceActivityIDs.isEmpty
        )
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
            AccessibleStatusPresentation.present(
                UserFacingErrorPresentation.message(
                    failure: "Could not prepare the title edit.",
                    recovery: "The original is unchanged; revise the title and try again.",
                    error: error
                ),
                in: impactLabel,
                returningFocusTo: segmentTitleField
            )
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
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not prepare the track edit.",
                        recovery:
                            "The original is unchanged; revise the track fields and try again.",
                        error: error
                    ),
                    in: self.impactLabel,
                    returningFocusTo: self.editTrackButton
                )
                self.clearPendingChange()
            }
        }
    }

    @objc private func editChapters() {
        guard let asset = selectedAsset, MatroskaEditingPolicy.supports(asset),
            let parentWindow = view.window
        else { return }
        let activityID = beginInterfaceActivity(
            "Extracting nested chapters from \(asset.sourceURL.lastPathComponent)…"
        )
        chaptersButton.isEnabled = false
        Task {
            defer { endInterfaceActivity(activityID) }
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
                    },
                    thumbnailProvider: { [weak model] times in
                        guard let model else { return [] }
                        return try await model.chapterThumbnails(
                            in: preview.source,
                            at: times,
                            expectedSourceRevision: preview.sourceRevision
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
                chaptersButton.isEnabled = MatroskaEditingPolicy.supports(asset)
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not open Chapter Studio.",
                        recovery: "No chapters were changed; check the selected MKV and try again.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: chaptersButton
                )
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
        let activityID = beginInterfaceActivity(
            "Reading \(asset.sourceURL.lastPathComponent)…"
        )
        cleanSubtitleButton.isEnabled = false
        Task {
            defer { endInterfaceActivity(activityID) }
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
                cleanSubtitleButton.isEnabled = true
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not prepare the subtitle cleanup preview.",
                        recovery: "The subtitle is unchanged; check the file and try again.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: cleanSubtitleButton
                )
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
        controller.beginSheet(for: parentWindow) { [weak self] track in
            guard let self else { return }
            self.embeddedSubtitleTrackPickerWindowController = nil
            guard let trackUID = track?.uid else {
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

    @objc private func convertTimedTextSubtitle() {
        guard let asset = selectedAsset,
            let parentWindow = view.window
        else { return }
        let tracks = TimedTextSubtitleConversionPolicy.convertibleTracks(in: asset)
        guard !tracks.isEmpty else { return }
        clearPendingChange()
        if tracks.count == 1 {
            previewTimedTextSubtitleConversion(asset: asset, trackID: tracks[0].id)
            return
        }
        let controller = EmbeddedSubtitleTrackPickerWindowController(
            tracks: tracks,
            purpose: .timedTextConversion
        )
        embeddedSubtitleTrackPickerWindowController = controller
        controller.beginSheet(for: parentWindow) { [weak self] track in
            guard let self else { return }
            self.embeddedSubtitleTrackPickerWindowController = nil
            guard let track else {
                self.refresh()
                return
            }
            guard self.selectedAsset?.id == asset.id else {
                self.clearPendingChange()
                self.refresh()
                return
            }
            self.previewTimedTextSubtitleConversion(asset: asset, trackID: track.id)
        }
    }

    @objc private func extractMatroskaTextSubtitle() {
        guard let asset = selectedAsset,
            let parentWindow = view.window
        else { return }
        let tracks = EmbeddedTextSubtitlePolicy.extractableTracks(in: asset)
        guard !tracks.isEmpty else { return }
        clearPendingChange()
        if tracks.count == 1, let trackUID = tracks[0].uid {
            previewMatroskaTextSubtitleExtraction(asset: asset, trackUID: trackUID)
            return
        }
        let controller = EmbeddedSubtitleTrackPickerWindowController(
            tracks: tracks,
            purpose: .textExtraction
        )
        embeddedSubtitleTrackPickerWindowController = controller
        controller.beginSheet(for: parentWindow) { [weak self] track in
            guard let self else { return }
            self.embeddedSubtitleTrackPickerWindowController = nil
            guard let trackUID = track?.uid else {
                self.refresh()
                return
            }
            guard self.selectedAsset?.id == asset.id else {
                self.clearPendingChange()
                self.refresh()
                return
            }
            self.previewMatroskaTextSubtitleExtraction(asset: asset, trackUID: trackUID)
        }
    }

    private func previewMatroskaTextSubtitleExtraction(asset: MediaAsset, trackUID: UInt64) {
        let activityID = beginInterfaceActivity(
            "Extracting embedded subtitle privately for review…"
        )
        extractSubtitleButton.isEnabled = false
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let preview = try await model.previewMatroskaTextSubtitleExtraction(
                    in: asset,
                    trackUID: trackUID
                )
                guard selectedAsset?.id == asset.id else {
                    clearPendingChange()
                    refresh()
                    return
                }
                pendingChange = .textSubtitleExtraction(preview)
                pendingAssetID = asset.id
                let noun = preview.itemCount == 1 ? "item" : "items"
                impactLabel.stringValue =
                    "0 video/audio encodes • exact \(preview.format.displayName) sidecar • \(preview.itemCount) \(noun)"
                statusLabel.stringValue = "Subtitle extraction plan ready"
                runButton.isEnabled = true
                runButton.toolTip =
                    "Repeat the extraction, require the exact reviewed bytes and parsed subtitle, then commit and reopen a new sidecar."
            } catch {
                extractSubtitleButton.isEnabled =
                    !EmbeddedTextSubtitlePolicy.extractableTracks(in: asset).isEmpty
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not prepare the subtitle extraction.",
                        recovery: "The MKV is unchanged; inspect it again and retry.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: extractSubtitleButton
                )
                clearPendingChange()
            }
        }
    }

    @objc private func extractMatroskaAttachment() {
        guard let asset = selectedAsset,
            let parentWindow = view.window
        else { return }
        let attachments = MatroskaAttachmentExtractionPolicy.extractableAttachments(in: asset)
        guard !attachments.isEmpty else { return }
        clearPendingChange()
        if attachments.count == 1, let attachmentUID = attachments[0].uid {
            previewMatroskaAttachmentExtraction(asset: asset, attachmentUID: attachmentUID)
            return
        }
        let controller = AttachmentPickerWindowController(attachments: attachments)
        attachmentPickerWindowController = controller
        controller.beginSheet(for: parentWindow) { [weak self] attachment in
            guard let self else { return }
            self.attachmentPickerWindowController = nil
            guard let attachmentUID = attachment?.uid else {
                self.refresh()
                return
            }
            guard self.selectedAsset?.id == asset.id else {
                self.clearPendingChange()
                self.refresh()
                return
            }
            self.previewMatroskaAttachmentExtraction(
                asset: asset,
                attachmentUID: attachmentUID
            )
        }
    }

    private func previewMatroskaAttachmentExtraction(
        asset: MediaAsset,
        attachmentUID: UInt64
    ) {
        let activityID = beginInterfaceActivity(
            "Extracting attachment privately for review…"
        )
        attachmentsButton.isEnabled = false
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let preview = try await model.previewMatroskaAttachmentExtraction(
                    in: asset,
                    attachmentUID: attachmentUID
                )
                guard selectedAsset?.id == asset.id else {
                    clearPendingChange()
                    refresh()
                    return
                }
                pendingChange = .attachmentExtraction(preview)
                pendingAssetID = asset.id
                impactLabel.stringValue =
                    "0 video/audio encodes • exact attachment • \(formatBytes(preview.byteCount))"
                statusLabel.stringValue = "Attachment extraction plan ready"
                runButton.isEnabled = true
                runButton.toolTip =
                    "Repeat the extraction, require the exact reviewed bytes, then commit and reopen a new attachment file."
            } catch {
                attachmentsButton.isEnabled =
                    !MatroskaAttachmentExtractionPolicy.extractableAttachments(in: asset).isEmpty
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not prepare the attachment extraction.",
                        recovery: "The MKV is unchanged; inspect it again and retry.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: attachmentsButton
                )
                clearPendingChange()
            }
        }
    }

    @objc private func removeMatroskaAttachments() {
        guard let asset = selectedAsset,
            let parentWindow = view.window
        else { return }
        let attachments = MatroskaAttachmentRemovalPolicy.removableAttachments(in: asset)
        guard !attachments.isEmpty else { return }
        clearPendingChange()
        let controller = AttachmentRemovalWindowController(attachments: attachments)
        attachmentRemovalWindowController = controller
        controller.beginSheet(for: parentWindow) { [weak self] removal in
            guard let self else { return }
            self.attachmentRemovalWindowController = nil
            guard let removal else {
                self.refresh()
                return
            }
            guard self.selectedAsset?.id == asset.id else {
                self.clearPendingChange()
                self.refresh()
                return
            }
            self.previewMatroskaAttachmentRemoval(asset: asset, removal: removal)
        }
    }

    private func previewMatroskaAttachmentRemoval(
        asset: MediaAsset,
        removal: MatroskaAttachmentRemoval
    ) {
        let activityID = beginInterfaceActivity(
            "Re-inspecting attachment removal for review…"
        )
        removeAttachmentsButton.isEnabled = false
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let preview = try await model.previewMatroskaAttachmentRemoval(
                    in: asset,
                    removal: removal
                )
                guard selectedAsset?.id == asset.id else {
                    clearPendingChange()
                    refresh()
                    return
                }
                pendingChange = .attachmentRemoval(preview)
                pendingAssetID = asset.id
                let count = preview.removedAttachments.count
                let noun = count == 1 ? "attachment" : "attachments"
                impactLabel.stringValue =
                    "0 video/audio encodes • mkvmerge • remove \(count) \(noun)"
                statusLabel.stringValue = "Attachment removal plan ready"
                runButton.isEnabled = true
                runButton.toolTip =
                    "Copy every media track and only the retained attachments, verify the complete MKV, then commit and reopen it."
            } catch {
                removeAttachmentsButton.isEnabled =
                    !MatroskaAttachmentRemovalPolicy.removableAttachments(in: asset).isEmpty
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not prepare attachment removal.",
                        recovery: "The MKV is unchanged; inspect it again and retry.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: removeAttachmentsButton
                )
                clearPendingChange()
            }
        }
    }

    @objc private func manageMatroskaTags() {
        guard let asset = selectedAsset,
            let parentWindow = view.window,
            let counts = try? MatroskaTagPolicy.counts(in: asset)
        else { return }
        clearPendingChange()
        let controller = TagActionWindowController(counts: counts)
        tagActionWindowController = controller
        controller.beginSheet(for: parentWindow) { [weak self] action in
            guard let self else { return }
            self.tagActionWindowController = nil
            guard let action else {
                self.refresh()
                return
            }
            guard self.selectedAsset?.id == asset.id else {
                self.clearPendingChange()
                self.refresh()
                return
            }
            self.previewMatroskaTags(asset: asset, action: action)
        }
    }

    private func previewMatroskaTags(asset: MediaAsset, action: MatroskaTagAction) {
        let activityID = beginInterfaceActivity(
            "Extracting Matroska tags privately for review…"
        )
        tagsButton.isEnabled = false
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let preview = try await model.previewMatroskaTags(in: asset)
                guard selectedAsset?.id == asset.id else {
                    clearPendingChange()
                    refresh()
                    return
                }
                let count = preview.document.counts.total
                let noun = count == 1 ? "tag" : "tags"
                pendingAssetID = asset.id
                switch action {
                case .exportXML:
                    pendingChange = .tagExport(preview)
                    impactLabel.stringValue =
                        "0 video/audio encodes • exact XML • \(count) \(noun)"
                    statusLabel.stringValue = "Exact tag export plan ready"
                    runButton.toolTip =
                        "Repeat the complete tag extraction, require the exact reviewed XML, then commit and reopen the sidecar."
                case .removeAll:
                    pendingChange = .tagRemoval(preview)
                    impactLabel.stringValue =
                        "0 video/audio encodes • mkvpropedit • remove \(count) \(noun)"
                    statusLabel.stringValue = "Tag removal plan ready"
                    runButton.toolTip =
                        "Clear every reviewed tag on a clone, verify media and structure are unchanged, then commit and reopen the MKV."
                }
                runButton.isEnabled = true
            } catch {
                tagsButton.isEnabled = MatroskaTagPolicy.canOffer(for: asset)
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not prepare the Matroska tag action.",
                        recovery: "The MKV is unchanged; inspect it again and retry.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: tagsButton
                )
                clearPendingChange()
            }
        }
    }

    private func previewTimedTextSubtitleConversion(asset: MediaAsset, trackID: Int) {
        let activityID = beginInterfaceActivity(
            "Converting MP4 timed text privately for review…"
        )
        convertTimedTextButton.isEnabled = false
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let preview = try await model.previewTimedTextSubtitleConversion(
                    in: asset,
                    trackID: trackID
                )
                guard selectedAsset?.id == asset.id else {
                    clearPendingChange()
                    refresh()
                    return
                }
                pendingChange = .timedTextSubtitle(preview)
                pendingAssetID = asset.id
                let noun = preview.eventCount == 1 ? "event" : "events"
                impactLabel.stringValue =
                    "0 video/audio encodes • 1 TX3G track → UTF-8 ASS • \(preview.eventCount) \(noun)"
                statusLabel.stringValue = "MP4 subtitle conversion plan ready"
                runButton.isEnabled = true
                runButton.toolTip =
                    "Repeat the conversion, verify the exact ASS text, styles, and timing, then save a new subtitle while leaving the video unchanged."
            } catch {
                convertTimedTextButton.isEnabled =
                    TimedTextSubtitleConversionPolicy.canOffer(for: asset)
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not prepare the MP4 subtitle conversion.",
                        recovery: "The video is unchanged; inspect it again and retry.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: convertTimedTextButton
                )
                clearPendingChange()
            }
        }
    }

    private func previewEmbeddedSubtitleCleanup(
        asset: MediaAsset,
        trackUID: UInt64,
        parentWindow: NSWindow
    ) {
        let activityID = beginInterfaceActivity(
            "Extracting embedded subtitle for review…"
        )
        cleanSubtitleButton.isEnabled = false
        Task {
            defer { endInterfaceActivity(activityID) }
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
                cleanSubtitleButton.isEnabled = Self.canCleanSubtitle(asset)
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not prepare the embedded subtitle preview.",
                        recovery:
                            "The MKV is unchanged; choose the track again or inspect the file.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: cleanSubtitleButton
                )
                clearPendingChange()
            }
        }
    }

    @objc private func addExternalSubtitle() {
        guard let asset = selectedAsset, Self.canAddExternalSubtitle(to: asset),
            let parentWindow = view.window
        else { return }

        prepareExternalSubtitle(asset: asset, parentWindow: parentWindow) { [weak self] reviewed in
            guard let self, let reviewed else { return }
            self.pendingChange = .externalSubtitle(reviewed.preview, reviewed.metadata)
            self.pendingAssetID = asset.id
            self.impactLabel.stringValue =
                "0 video encodes • mkvmerge • 1 subtitle added last"
            self.statusLabel.stringValue = "Subtitle mux plan ready"
            self.runButton.isEnabled = true
            self.runButton.toolTip =
                "Copy all existing tracks, add the reviewed text subtitle last, verify the MKV, then commit it."
        }
    }

    private func prepareExternalSubtitle(
        asset: MediaAsset,
        parentWindow: NSWindow,
        reviewsCleanup: Bool = false,
        completion: @escaping (ReviewedExternalSubtitle?) -> Void
    ) {
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
        guard panel.runModal() == .OK, let subtitleURL = panel.url else {
            completion(nil)
            return
        }

        let activityID = beginInterfaceActivity(
            "Reading \(subtitleURL.lastPathComponent)…"
        )
        addSubtitleButton.isEnabled = false
        Task {
            defer { endInterfaceActivity(activityID) }
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
                    completion(nil)
                    return
                }
                guard selectedAsset?.id == asset.id else {
                    clearPendingChange()
                    refresh()
                    completion(nil)
                    return
                }
                if reviewsCleanup {
                    reviewExternalSubtitleCleanup(
                        preview: preview,
                        asset: asset,
                        parentWindow: parentWindow
                    ) { [weak self] payload in
                        guard let self else { return }
                        guard let payload else {
                            self.refresh()
                            completion(nil)
                            return
                        }
                        self.presentExternalSubtitleMetadata(
                            asset: asset,
                            payload: payload,
                            match: match,
                            parentWindow: parentWindow,
                            completion: completion
                        )
                    }
                } else {
                    presentExternalSubtitleMetadata(
                        asset: asset,
                        payload: .original(preview),
                        match: match,
                        parentWindow: parentWindow,
                        completion: completion
                    )
                }
            } catch {
                addSubtitleButton.isEnabled = Self.canAddExternalSubtitle(to: asset)
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not prepare the external subtitle preview.",
                        recovery: "No subtitle was added; check the subtitle file and try again.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: addSubtitleButton
                )
                clearPendingChange()
                completion(nil)
            }
        }
    }

    private func reviewExternalSubtitleCleanup(
        preview: ExternalSubtitleFilePreview,
        asset: MediaAsset,
        parentWindow: NSWindow,
        completion: @escaping (ExternalSubtitleMuxPayload?) -> Void
    ) {
        guard preview.cleanupChangeCount > 0 else {
            completion(.reviewedCleanup(preview, restoringIDs: []))
            return
        }
        let controller: SubtitleCleanupWindowController
        switch preview {
        case .subRip(let preview):
            controller = SubtitleCleanupWindowController(preview: preview)
        case .advanced(let preview):
            controller = SubtitleCleanupWindowController(preview: preview)
        }
        subtitleCleanupWindowController = controller
        controller.beginSheet(for: parentWindow) { [weak self] restoringIDs in
            guard let self else { return }
            self.subtitleCleanupWindowController = nil
            guard let restoringIDs else {
                completion(nil)
                return
            }
            guard self.selectedAsset?.id == asset.id else {
                self.clearPendingChange()
                completion(nil)
                return
            }
            let payload = ExternalSubtitleMuxPayload.reviewedCleanup(
                preview,
                restoringIDs: restoringIDs
            )
            do {
                try payload.validateForReview()
                completion(payload)
            } catch {
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not use the reviewed subtitle cleanup.",
                        recovery: "No subtitle was added; reopen the preview and review it again.",
                        error: error
                    ),
                    in: self.impactLabel
                )
                self.clearPendingChange()
                completion(nil)
            }
        }
    }

    private func presentExternalSubtitleMetadata(
        asset: MediaAsset,
        payload: ExternalSubtitleMuxPayload,
        match: ExternalSubtitleMatch,
        parentWindow: NSWindow,
        completion: @escaping (ReviewedExternalSubtitle?) -> Void
    ) {
        let controller = ExternalSubtitleMuxWindowController(
            media: asset,
            preview: payload.preview,
            match: match,
            reviewedCleanupChangeCount: payload.reviewedCleanupChangeCount
        )
        externalSubtitleMuxWindowController = controller
        controller.beginSheet(for: parentWindow) { [weak self] metadata in
            guard let self else { return }
            self.externalSubtitleMuxWindowController = nil
            self.addSubtitleButton.isEnabled = Self.canAddExternalSubtitle(to: asset)
            guard let metadata else {
                self.refresh()
                completion(nil)
                return
            }
            guard self.selectedAsset?.id == asset.id else {
                self.clearPendingChange()
                self.refresh()
                completion(nil)
                return
            }
            completion(ReviewedExternalSubtitle(payload: payload, metadata: metadata))
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
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not prepare track removal.",
                        recovery:
                            "The original is unchanged; revise the selected tracks and try again.",
                        error: error
                    ),
                    in: self.impactLabel,
                    returningFocusTo: isEnglishCleanup
                        ? self.cleanMKVButton : self.removeTracksButton
                )
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
        guard
            let destination = chooseDestination(
                for: pendingChange,
                asset: asset,
                prompt: "Save Verified Copy"
            )
        else { return }
        disableEditingControls()
        let presentation = pendingChange.progressPresentation
        let progress = VerifiedOutputProgressWindowController.verifiedChange(
            title: presentation.title,
            initialMessage: presentation.message
        )
        verifiedRunProgressWindowController = progress
        if let parentWindow = view.window {
            progress.beginSheet(for: parentWindow)
        }
        let task = Task { [weak self, weak progress] in
            guard let self else { return }
            defer {
                progress?.finish()
                self.verifiedRunProgressWindowController = nil
                self.verifiedRunTask = nil
                self.refresh()
            }
            do {
                let outputURL: URL
                switch pendingChange {
                case .segmentTitle(let title):
                    outputURL = try await model.editSegmentTitle(
                        in: asset,
                        title: title,
                        destinationURL: destination.url
                    ).sourceURL
                case .track(let edit):
                    outputURL = try await model.editTrackMetadata(
                        in: asset,
                        edit: edit,
                        destinationURL: destination.url
                    ).sourceURL
                case .trackRemoval(let removal, let isEnglishCleanup):
                    if isEnglishCleanup {
                        outputURL = try await model.cleanEnglishLibrary(
                            in: asset,
                            removal: removal,
                            destinationURL: destination.url
                        ).sourceURL
                    } else {
                        outputURL = try await model.removeTracks(
                            in: asset,
                            removal: removal,
                            destinationURL: destination.url
                        ).sourceURL
                    }
                case .savedWorkflow(let prepared):
                    outputURL = try await model.runSavedWorkflow(
                        prepared.compiled,
                        recipe: prepared.recipe,
                        externalSubtitlePayload: prepared.externalSubtitlePayload,
                        sourceDisposition: destination.sourceDisposition,
                        retryingQueueJobID: prepared.retryingQueueJobID,
                        expectedSourceRevision: prepared.expectedSourceRevision,
                        in: asset,
                        destinationURL: destination.url
                    ).sourceURL
                case .subtitleCleanup(let preview, let restoringCueIDs):
                    outputURL = try await model.cleanSubtitle(
                        preview: preview,
                        restoringCueIDs: restoringCueIDs,
                        destinationURL: destination.url
                    ).outputURL
                case .advancedSubtitleCleanup(let preview, let restoringEventIDs):
                    outputURL = try await model.cleanAdvancedSubtitle(
                        preview: preview,
                        restoringEventIDs: restoringEventIDs,
                        destinationURL: destination.url
                    ).outputURL
                case .externalSubtitle(let preview, let metadata):
                    outputURL = try await model.muxExternalSubtitle(
                        in: asset,
                        subtitlePreview: preview,
                        metadata: metadata,
                        destinationURL: destination.url
                    ).sourceURL
                case .embeddedSubtitle(let preview, let restoringIDs):
                    outputURL = try await model.cleanEmbeddedSubtitle(
                        preview: preview,
                        restoringIDs: restoringIDs,
                        destinationURL: destination.url
                    ).sourceURL
                case .timedTextSubtitle(let preview):
                    outputURL = try await model.executeTimedTextSubtitleConversion(
                        preview: preview,
                        destinationURL: destination.url
                    ).outputURL
                case .textSubtitleExtraction(let preview):
                    outputURL = try await model.executeMatroskaTextSubtitleExtraction(
                        preview: preview,
                        destinationURL: destination.url
                    ).outputURL
                case .attachmentExtraction(let preview):
                    outputURL = try await model.executeMatroskaAttachmentExtraction(
                        preview: preview,
                        destinationURL: destination.url
                    ).outputURL
                case .attachmentRemoval(let preview):
                    outputURL = try await model.executeMatroskaAttachmentRemoval(
                        preview: preview,
                        destinationURL: destination.url
                    ).sourceURL
                case .tagExport(let preview):
                    outputURL = try await model.executeMatroskaTagExport(
                        preview: preview,
                        destinationURL: destination.url
                    ).outputURL
                case .tagRemoval(let preview):
                    outputURL = try await model.executeMatroskaTagRemoval(
                        preview: preview,
                        destinationURL: destination.url
                    ).sourceURL
                case .chapters(let preview, let desired):
                    outputURL = try await model.editChapters(
                        preview: preview,
                        desired: desired,
                        destinationURL: destination.url
                    ).sourceURL
                case .remuxToMKV(let preview):
                    outputURL = try await model.executeRemuxToMKV(
                        preview: preview,
                        destinationURL: destination.url
                    ).sourceURL
                }
                preferredSelectionURL =
                    model.assets.contains { $0.sourceURL == outputURL }
                    ? outputURL : nil
                clearPendingChange()
            } catch {
                restoreEditingControls(for: asset)
            }
        }
        verifiedRunTask = task
        progress.onCancel = { [weak self] in self?.verifiedRunTask?.cancel() }
        updateActivityIndicator()
    }

    @objc private func addPendingWorkflowToQueue() {
        guard case .savedWorkflow(let prepared) = pendingChange,
            MediaQueueAutomaticWorkflowPolicy.supports(
                prepared.recipe,
                inputCount: prepared.queueInputCount
            ),
            let asset = selectedAsset,
            pendingAssetID == asset.id,
            let destination = chooseDestination(
                for: .savedWorkflow(prepared),
                asset: asset,
                prompt: "Add to Queue"
            )
        else {
            updateQueueButton()
            return
        }
        disableEditingControls()
        verifiedRunTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.verifiedRunTask = nil
                self.refresh()
            }
            do {
                _ = try await model.enqueueSavedWorkflow(
                    prepared.compiled,
                    recipe: prepared.recipe,
                    externalSubtitlePayload: prepared.externalSubtitlePayload,
                    sourceDisposition: destination.sourceDisposition,
                    retryingQueueJobID: prepared.retryingQueueJobID,
                    expectedSourceRevision: prepared.expectedSourceRevision,
                    in: asset,
                    destinationURL: destination.url
                )
                statusLabel.stringValue = "Added \(prepared.recipe.name) to the queue"
                clearPendingChange()
                refreshOpenQueue()
                await model.runAutomaticQueueCycleIfEligible()
            } catch {
                restoreEditingControls(for: asset)
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not add this workflow to the queue.",
                        recovery: "Nothing was queued; review the destination and try again.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: queueButton
                )
            }
        }
        updateActivityIndicator()
    }

    private func chooseDestination(
        for pendingChange: PendingChange,
        asset: MediaAsset,
        prompt: String
    ) -> DestinationSelection? {
        let panel = NSSavePanel()
        let isSubtitleCleanup: Bool
        switch pendingChange {
        case .subtitleCleanup, .advancedSubtitleCleanup:
            isSubtitleCleanup = true
        default:
            isSubtitleCleanup = false
        }
        let isTimedTextConversion: Bool
        if case .timedTextSubtitle = pendingChange {
            isTimedTextConversion = true
        } else {
            isTimedTextConversion = false
        }
        let isTextSubtitleExtraction: Bool
        if case .textSubtitleExtraction = pendingChange {
            isTextSubtitleExtraction = true
        } else {
            isTextSubtitleExtraction = false
        }
        let isAttachmentExtraction: Bool
        if case .attachmentExtraction = pendingChange {
            isAttachmentExtraction = true
        } else {
            isAttachmentExtraction = false
        }
        let isTagExport: Bool
        if case .tagExport = pendingChange {
            isTagExport = true
        } else {
            isTagExport = false
        }
        let isSubtitleMux: Bool
        if case .externalSubtitle = pendingChange {
            isSubtitleMux = true
        } else if case .savedWorkflow(let prepared) = pendingChange,
            prepared.compiled.externalSubtitleInput != nil
        {
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
        let requiresMKVOutput: Bool
        if case .attachmentRemoval = pendingChange {
            requiresMKVOutput = true
        } else if case .tagRemoval = pendingChange {
            requiresMKVOutput = true
        } else if case .remuxToMKV = pendingChange {
            requiresMKVOutput = true
        } else if case .savedWorkflow(let prepared) = pendingChange {
            requiresMKVOutput = prepared.compiled.requiresMKVOutputExtension
        } else {
            requiresMKVOutput = false
        }
        panel.title =
            isAttachmentExtraction
            ? "Save Verified Attachment Copy"
            : (isTagExport
                ? "Save Verified Tag XML"
                : (isSubtitleCleanup || isTimedTextConversion || isTextSubtitleExtraction
                    ? "Save Verified Subtitle Copy" : "Save Verified MKV Copy"))
        panel.prompt = prompt
        panel.message = OutputDestinationPolicy.savePanelMessage()
        panel.canCreateDirectories = true
        if case .savedWorkflow(let prepared) = pendingChange,
            let suggestedFilename = prepared.compiled.suggestedOutputFilename
        {
            panel.nameFieldStringValue = OutputNamingPolicy.savedWorkflowFilename(
                for: asset.sourceURL,
                suggestedFilename: suggestedFilename,
                requiresMKV: isSubtitleMux || requiresMKVOutput
            )
        } else if case .textSubtitleExtraction(let preview) = pendingChange {
            panel.nameFieldStringValue = OutputNamingPolicy.extractedSubtitleFilename(
                for: asset.sourceURL,
                track: preview.track,
                format: preview.format,
                trackCount: EmbeddedTextSubtitlePolicy.extractableTracks(in: asset).count
            )
        } else if case .attachmentExtraction(let preview) = pendingChange {
            panel.nameFieldStringValue = OutputNamingPolicy.extractedAttachmentFilename(
                for: preview.attachment
            )
        } else if isTagExport {
            panel.nameFieldStringValue = OutputNamingPolicy.extractedTagFilename(
                for: asset.sourceURL
            )
        } else if case .tagRemoval = pendingChange {
            panel.nameFieldStringValue = OutputNamingPolicy.tagsRemovedFilename(
                for: asset.sourceURL
            )
        } else if case .timedTextSubtitle(let preview) = pendingChange {
            panel.nameFieldStringValue = OutputNamingPolicy.convertedTimedTextFilename(
                for: asset.sourceURL,
                track: preview.track,
                trackCount: TimedTextSubtitleConversionPolicy.convertibleTracks(in: asset).count
            )
        } else if isSubtitleCleanup {
            panel.nameFieldStringValue = OutputNamingPolicy.cleanedSubtitleFilename(
                for: asset.sourceURL)
        } else if isSubtitleMux {
            panel.nameFieldStringValue = OutputNamingPolicy.subtitledFilename(for: asset.sourceURL)
        } else if isEmbeddedSubtitleCleanup {
            panel.nameFieldStringValue = OutputNamingPolicy.cleanedMKVFilename(for: asset.sourceURL)
        } else if requiresMKVOutput {
            panel.nameFieldStringValue = OutputNamingPolicy.remuxedFilename(for: asset.sourceURL)
        } else {
            panel.nameFieldStringValue = OutputNamingPolicy.suggestedFilename(for: asset.sourceURL)
        }
        panel.directoryURL = OutputDestinationPolicy.defaultDirectory(for: asset.sourceURL)
        let outputExtension: String
        if case .attachmentExtraction(let preview) = pendingChange {
            outputExtension =
                URL(
                    fileURLWithPath: OutputNamingPolicy.extractedAttachmentFilename(
                        for: preview.attachment
                    )
                ).pathExtension
        } else if case .textSubtitleExtraction(let preview) = pendingChange {
            outputExtension = preview.format.filenameExtension
        } else if isTagExport {
            outputExtension = "xml"
        } else if isTimedTextConversion {
            outputExtension = "ass"
        } else if isSubtitleCleanup {
            outputExtension = asset.sourceURL.pathExtension.lowercased()
        } else if isSubtitleMux || isEmbeddedSubtitleCleanup || requiresMKVOutput {
            outputExtension = "mkv"
        } else {
            outputExtension = asset.sourceURL.pathExtension
        }
        panel.allowedContentTypes = [UTType(filenameExtension: outputExtension) ?? .data]
        panel.allowsOtherFileTypes = isAttachmentExtraction
        panel.isExtensionHidden = false
        var sourceDispositionCheckbox: NSButton?
        if case .savedWorkflow(let prepared) = pendingChange {
            let accessory = SourceDispositionPresentation.makeAccessory(
                selected: prepared.sourceDisposition == .trashAfterVerifiedSuccess
            )
            panel.accessoryView = accessory.view
            sourceDispositionCheckbox = accessory.checkbox
        }
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return nil }
        return DestinationSelection(
            url: destinationURL,
            sourceDisposition: SourceDispositionPresentation.disposition(
                for: sourceDispositionCheckbox
            )
        )
    }

    private func disableEditingControls() {
        previewButton.isEnabled = false
        editTrackButton.isEnabled = false
        cleanMKVButton.isEnabled = false
        removeTracksButton.isEnabled = false
        removeAttachmentsButton.isEnabled = false
        cleanSubtitleButton.isEnabled = false
        extractSubtitleButton.isEnabled = false
        convertTimedTextButton.isEnabled = false
        addSubtitleButton.isEnabled = false
        chaptersButton.isEnabled = false
        attachmentsButton.isEnabled = false
        tagsButton.isEnabled = false
        trimButton.isEnabled = false
        remuxButton.isEnabled = false
        convertButton.isEnabled = false
        queueButton.isEnabled = false
        runButton.isEnabled = false
    }

    private func restoreEditingControls(for asset: MediaAsset) {
        previewButton.isEnabled = true
        editTrackButton.isEnabled = asset.tracks.contains {
            $0.kind != .attachment && $0.uid != nil
        }
        removeTracksButton.isEnabled = TrackRemovalPresentation.canOfferRemoval(
            for: asset.tracks)
        removeAttachmentsButton.isEnabled =
            !MatroskaAttachmentRemovalPolicy.removableAttachments(in: asset).isEmpty
        cleanMKVButton.isEnabled = Self.canOfferEnglishCleanup(for: asset)
        cleanSubtitleButton.isEnabled = Self.canCleanSubtitle(asset)
        extractSubtitleButton.isEnabled =
            !EmbeddedTextSubtitlePolicy.extractableTracks(in: asset).isEmpty
        convertTimedTextButton.isEnabled =
            TimedTextSubtitleConversionPolicy.canOffer(for: asset)
        addSubtitleButton.isEnabled = Self.canAddExternalSubtitle(to: asset)
        chaptersButton.isEnabled = MatroskaEditingPolicy.supports(asset)
        attachmentsButton.isEnabled =
            !MatroskaAttachmentExtractionPolicy.extractableAttachments(in: asset).isEmpty
        tagsButton.isEnabled = MatroskaTagPolicy.canOffer(for: asset)
        trimButton.isEnabled = TrimPresentationPolicy.canOfferTrim(for: asset)
        remuxButton.isEnabled = MKVRemuxPlanner().canOffer(for: asset)
        convertButton.isEnabled = TrimPresentationPolicy.canOfferTrim(for: asset)
        runButton.isEnabled = pendingChange != nil && pendingAssetID == asset.id
        updateQueueButton()
    }

    private func reviewQueueJob(_ job: MediaQueueJob) {
        guard let workflow = job.workflow.savedWorkflow else {
            statusLabel.stringValue = "This built-in queue job cannot be replanned yet."
            return
        }
        queueWindowController?.close()
        queueWindowController = nil
        let activityID = beginInterfaceActivity(
            "Restoring \(job.inputs.first?.displayName ?? "queued input")…"
        )
        Task {
            defer { endInterfaceActivity(activityID) }
            do {
                let sourceURL = try model.resolvePrimaryQueueInput(job)
                await model.addFiles([sourceURL])
                guard model.assets.contains(where: { $0.sourceURL == sourceURL }) else {
                    statusLabel.stringValue = "The queued input could not be inspected."
                    return
                }
                preferredSelectionURL = sourceURL
                refresh()
                previewSavedWorkflow(
                    workflow,
                    sourceDisposition: job.sourceDisposition,
                    retryingQueueJobID: job.id
                )
            } catch {
                AccessibleStatusPresentation.present(
                    UserFacingErrorPresentation.message(
                        failure: "Could not restore the queued input.",
                        recovery:
                            "The queued job remains saved; choose Review Again after checking the file.",
                        error: error
                    ),
                    in: statusLabel,
                    returningFocusTo: queueButton
                )
            }
        }
    }

    private func refresh() {
        tableView.reloadData()
        switch model.state {
        case .ready:
            lastAnnouncedModelFailure = nil
            statusLabel.stringValue = model.assets.isEmpty ? "Ready" : "Inspection complete"
        case .discovering:
            lastAnnouncedModelFailure = nil
            statusLabel.stringValue = "Finding media files…"
        case .inspecting(let filename):
            lastAnnouncedModelFailure = nil
            statusLabel.stringValue = "Inspecting \(filename)…"
        case .executing(let message):
            lastAnnouncedModelFailure = nil
            statusLabel.stringValue = message
        case .completed(let message):
            lastAnnouncedModelFailure = nil
            statusLabel.stringValue = message
        case .completedWithWarnings(let message):
            lastAnnouncedModelFailure = nil
            statusLabel.stringValue = message
        case .failed(let message):
            if lastAnnouncedModelFailure == message || statusLabel.stringValue == message {
                statusLabel.stringValue = message
            } else {
                AccessibleStatusPresentation.present(message, in: statusLabel)
            }
            lastAnnouncedModelFailure = message
        }
        if let progressMessage = model.state.progressMessage {
            verifiedRunProgressWindowController?.update(message: progressMessage)
        }
        updateActivityIndicator()
        chooseFilesButton.isEnabled = !model.state.showsProgressIndicator
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
        joinButton.isEnabled = model.assets.filter { MatroskaEditingPolicy.supports($0) }.count >= 2
        if isMediaWorkBusy {
            previewButton.isEnabled = false
            editTrackButton.isEnabled = false
            cleanMKVButton.isEnabled = false
            removeTracksButton.isEnabled = false
            removeAttachmentsButton.isEnabled = false
            cleanSubtitleButton.isEnabled = false
            extractSubtitleButton.isEnabled = false
            convertTimedTextButton.isEnabled = false
            addSubtitleButton.isEnabled = false
            chaptersButton.isEnabled = false
            attachmentsButton.isEnabled = false
            tagsButton.isEnabled = false
            trimButton.isEnabled = false
            remuxButton.isEnabled = false
            convertButton.isEnabled = false
            joinButton.isEnabled = false
            queueButton.isEnabled = false
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
            removeAttachmentsButton.isEnabled = false
            cleanSubtitleButton.isEnabled = false
            extractSubtitleButton.isEnabled = false
            convertTimedTextButton.isEnabled = false
            addSubtitleButton.isEnabled = false
            chaptersButton.isEnabled = false
            attachmentsButton.isEnabled = false
            tagsButton.isEnabled = false
            trimButton.isEnabled = false
            remuxButton.isEnabled = false
            convertButton.isEnabled = false
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
        removeAttachmentsButton.isEnabled =
            !MatroskaAttachmentRemovalPolicy.removableAttachments(in: asset).isEmpty
        removeAttachmentsButton.toolTip =
            removeAttachmentsButton.isEnabled
            ? "Choose one or more attachments to omit from a verified zero-encode MKV copy."
            : "Attachment removal requires a Matroska file whose attachments have stable unique IDs and UIDs."
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
        extractSubtitleButton.isEnabled =
            !EmbeddedTextSubtitlePolicy.extractableTracks(in: asset).isEmpty
        extractSubtitleButton.toolTip =
            extractSubtitleButton.isEnabled
            ? "Choose one embedded SRT, ASS, or SSA track and save an exact verified sidecar without changing the MKV."
            : "Subtitle extraction requires an inspected Matroska file with an embedded SRT, ASS, or SSA track."
        convertTimedTextButton.isEnabled =
            TimedTextSubtitleConversionPolicy.canOffer(for: asset)
        convertTimedTextButton.toolTip =
            convertTimedTextButton.isEnabled
            ? "Choose one MP4 TX3G text track and create a separate verified UTF-8 ASS subtitle without changing the video."
            : "MP4 subtitle conversion requires an inspected MP4, M4V, or MOV file with a TX3G text track."
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
        attachmentsButton.isEnabled =
            !MatroskaAttachmentExtractionPolicy.extractableAttachments(in: asset).isEmpty
        attachmentsButton.toolTip =
            attachmentsButton.isEnabled
            ? "Choose one bounded Matroska attachment and save an exact verified file without changing the MKV."
            : "Attachment extraction requires an inspected Matroska file with a stable, non-empty attachment up to 512 MB."
        tagsButton.isEnabled = MatroskaTagPolicy.canOffer(for: asset)
        tagsButton.toolTip =
            tagsButton.isEnabled
            ? "Export the complete tag XML or review clearing every global and track tag from a verified MKV copy."
            : "Tag actions require an inspected Matroska file with known nonzero global or track tag counts."
        trimButton.isEnabled =
            !isPreparingVideoProcessing && TrimPresentationPolicy.canOfferTrim(for: asset)
        trimButton.toolTip =
            trimButton.isEnabled
            ? "Choose numeric in/out points, preview keyframe adjustments, or encode video once for exact boundaries."
            : "Trim currently requires an inspected MKV with exactly one video track and a known duration."
        let remuxResolution = Result { try MKVRemuxPlanner().resolve(source: asset) }
        remuxButton.isEnabled = (try? remuxResolution.get()) != nil
        let remuxHelp =
            switch remuxResolution {
            case .success:
                "Copy compatible streams and chapters into a verified MKV without video or audio encoding."
            case .failure(let error):
                (error as? MKVRemuxPlanningError)?.userFacingReason
                    ?? "This file does not meet the verified zero-encode MKV contract."
            }
        remuxButton.toolTip = remuxHelp
        remuxButton.setAccessibilityHelp(remuxHelp)
        convertButton.isEnabled =
            !isPreparingVideoProcessing && TrimPresentationPolicy.canOfferConversion(for: asset)
        convertButton.toolTip =
            convertButton.isEnabled
            ? "Convert the complete MKV, MP4, M4V, MOV, or WebM video once to AV1, HEVC, H.264, or ProRes and create a verified MKV."
            : "Conversion needs one supported video input whose tracks, metadata, and chapters can be preserved safely."
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
            tableView.makeView(withIdentifier: identifier, owner: self)
            as? MediaAssetTableCellView
            ?? MediaAssetTableCellView()
        cell.identifier = identifier
        let asset = model.assets[row]
        cell.textField?.stringValue = asset.sourceURL.lastPathComponent
        cell.removeButton.tag = row
        cell.removeButton.target = self
        cell.removeButton.action = #selector(removeAssetFromList(_:))
        cell.removeButton.isEnabled = !isMediaWorkBusy
        cell.removeButton.setAccessibilityLabel(
            "Remove \(asset.sourceURL.lastPathComponent) from MKV Magic"
        )
        cell.removeButton.setAccessibilityHelp(
            "Remove this item from the list without deleting or changing the source file."
        )
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
        runButton.toolTip = nil
        updateQueueButton()
    }

    private func updateQueueButton() {
        guard case .savedWorkflow(let prepared) = pendingChange,
            MediaQueueAutomaticWorkflowPolicy.supports(
                prepared.recipe,
                inputCount: prepared.queueInputCount
            )
        else {
            queueButton.isEnabled = false
            if case .savedWorkflow? = pendingChange {
                queueButton.toolTip =
                    "This workflow needs another interactive review before it can be queued."
            } else {
                queueButton.toolTip = nil
            }
            return
        }
        queueButton.isEnabled = true
        queueButton.toolTip =
            "Save this reviewed plan as waiting work, then let pause, power, thermal, and resource limits decide when it starts."
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

@MainActor
enum SourceDispositionPresentation {
    static let checkboxTitle = "Move original video file to Trash after verified success"
    static let explanation =
        "Only after verified success. If Trash fails, the new output stays safe; MKV Magic checks the original before warning you."

    static func makeAccessory(selected: Bool) -> (view: NSView, checkbox: NSButton) {
        let checkbox = NSButton(checkboxWithTitle: checkboxTitle, target: nil, action: nil)
        checkbox.state = selected ? .on : .off
        let detail = NSTextField(wrappingLabelWithString: explanation)
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let stack = NSStackView(views: [checkbox, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 448, height: 70))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: container.bottomAnchor,
                constant: -2
            ),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return (container, checkbox)
    }

    static func disposition(for checkbox: NSButton?) -> MediaQueueSourceDisposition {
        checkbox?.state == .on ? .trashAfterVerifiedSuccess : .keepOriginal
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

enum OutputDestinationPolicy {
    static func defaultDirectory(for sourceURL: URL) -> URL {
        sourceURL.standardizedFileURL.deletingLastPathComponent()
    }

    static func savePanelMessage(detail: String? = nil) -> String {
        let location =
            "The original file’s folder is selected by default. Choose another folder here if you prefer."
        guard let detail, !detail.isEmpty else { return location }
        return "\(location) \(detail)"
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

    static func convertedTimedTextFilename(
        for sourceURL: URL,
        track: MediaTrack,
        trackCount: Int
    ) -> String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let trackSuffix = trackCount > 1 ? " Track \(track.id + 1)" : ""
        return "\(base) — TX3G\(trackSuffix).ass"
    }

    static func extractedSubtitleFilename(
        for sourceURL: URL,
        track: MediaTrack,
        format: ExternalTextSubtitleFormat,
        trackCount: Int
    ) -> String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let trackSuffix = trackCount > 1 ? " Track \(track.id + 1)" : ""
        return "\(base) — Subtitle\(trackSuffix).\(format.filenameExtension)"
    }

    static func extractedAttachmentFilename(for attachment: MediaAttachment) -> String {
        let invalid = CharacterSet.controlCharacters.union(
            CharacterSet(charactersIn: "/\\:")
        )
        let replaced = attachment.filename.unicodeScalars.map { scalar in
            invalid.contains(scalar) ? "-" : String(scalar)
        }.joined()
        let trimmed = replaced.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        )
        let fallback = "Attachment \(attachment.id).bin"
        let hasAlphanumeric = trimmed.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0)
        }
        let candidate = hasAlphanumeric ? trimmed : fallback
        return truncateAttachmentFilename(candidate, maximumUTF8Bytes: 200)
    }

    static func extractedTagFilename(for sourceURL: URL) -> String {
        "\(sourceURL.deletingPathExtension().lastPathComponent) — Tags.xml"
    }

    static func tagsRemovedFilename(for sourceURL: URL) -> String {
        "\(sourceURL.deletingPathExtension().lastPathComponent) — Tags Removed.mkv"
    }

    static func subtitledFilename(for sourceURL: URL) -> String {
        "\(sourceURL.deletingPathExtension().lastPathComponent) — Subtitled.mkv"
    }

    static func cleanedMKVFilename(for sourceURL: URL) -> String {
        "\(sourceURL.deletingPathExtension().lastPathComponent) — Cleaned.mkv"
    }

    static func joinedFilename(for firstSourceURL: URL) -> String {
        "\(firstSourceURL.deletingPathExtension().lastPathComponent) — Joined.mkv"
    }

    static func trimmedFilename(for sourceURL: URL) -> String {
        "\(sourceURL.deletingPathExtension().lastPathComponent) — Trimmed.mkv"
    }

    static func convertedFilename(for sourceURL: URL) -> String {
        "\(sourceURL.deletingPathExtension().lastPathComponent) — Converted.mkv"
    }

    static func remuxedFilename(for sourceURL: URL) -> String {
        "\(sourceURL.deletingPathExtension().lastPathComponent) — Remuxed.mkv"
    }

    static func savedWorkflowFilename(
        for sourceURL: URL,
        suggestedFilename reviewedSuggestion: String?,
        requiresMKV: Bool
    ) -> String {
        guard let reviewedSuggestion else { return suggestedFilename(for: sourceURL) }
        guard requiresMKV else { return reviewedSuggestion }
        return URL(fileURLWithPath: reviewedSuggestion)
            .deletingPathExtension().lastPathComponent + ".mkv"
    }

    private static func truncateAttachmentFilename(
        _ filename: String,
        maximumUTF8Bytes: Int
    ) -> String {
        guard filename.utf8.count > maximumUTF8Bytes else { return filename }
        let fileURL = URL(fileURLWithPath: filename)
        let rawExtension = fileURL.pathExtension
        let suffix = rawExtension.isEmpty ? "" : ".\(rawExtension)"
        let keptSuffix = suffix.utf8.count <= 48 ? suffix : ""
        let rawBase =
            keptSuffix.isEmpty
            ? filename : fileURL.deletingPathExtension().lastPathComponent
        let budget = maximumUTF8Bytes - keptSuffix.utf8.count
        var base = ""
        for character in rawBase {
            guard base.utf8.count + String(character).utf8.count <= budget else { break }
            base.append(character)
        }
        let usableBase = base.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        )
        return (usableBase.isEmpty ? "Attachment" : usableBase) + keptSuffix
    }
}
