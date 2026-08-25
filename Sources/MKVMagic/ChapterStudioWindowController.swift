import AppKit
import MKVMagicCore
import MKVMagicExecution
import UniformTypeIdentifiers

typealias ChapterSuggestionProvider =
    @MainActor (
        _ options: ChapterSuggestionOptions,
        _ existingChapterStarts: [MediaTime]
    ) async throws -> [ChapterSuggestion]

typealias ChapterThumbnailProvider =
    @MainActor (_ times: [MediaTime]) async throws -> [ChapterThumbnail]

@MainActor
final class ChapterStudioWindowController: NSWindowController {
    private let studioViewController: ChapterStudioViewController
    private var completion: ((MatroskaChapterDocument?) -> Void)?

    init(
        preview: ChapterEditPreview,
        suggestionProvider: ChapterSuggestionProvider? = nil,
        thumbnailProvider: ChapterThumbnailProvider? = nil
    ) {
        studioViewController = ChapterStudioViewController(
            preview: preview,
            suggestionProvider: suggestionProvider,
            thumbnailProvider: thumbnailProvider
        )
        let window = NSPanel(contentViewController: studioViewController)
        window.title = "Chapter Studio"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 680))
        window.minSize = NSSize(width: 820, height: 580)
        window.configureMKVMagicKeyboardNavigation(
            startingAt: studioViewController.preferredInitialFirstResponder
        )
        super.init(window: window)
        studioViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        studioViewController.onUseChanges = { [weak self] document in
            self?.finish(with: document)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (MatroskaChapterDocument?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with document: MatroskaChapterDocument?) {
        studioViewController.cancelAnalysis()
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(document)
        completion = nil
    }
}

@MainActor
private final class ChapterOutlineItem: NSObject {
    enum Kind {
        case edition(UUID)
        case chapter(UUID)
    }

    let kind: Kind
    let label: String
    let children: [ChapterOutlineItem]

    init(kind: Kind, label: String, children: [ChapterOutlineItem]) {
        self.kind = kind
        self.label = label
        self.children = children
    }

    var id: UUID {
        switch kind {
        case .edition(let id), .chapter(let id): id
        }
    }
}

@MainActor
final class ChapterStudioViewController: NSViewController, NSOutlineViewDataSource,
    NSOutlineViewDelegate, NSTextFieldDelegate
{
    var onCancel: (() -> Void)?
    var onUseChanges: ((MatroskaChapterDocument) -> Void)?

    private let preview: ChapterEditPreview
    private let suggestionProvider: ChapterSuggestionProvider?
    private let thumbnailProvider: ChapterThumbnailProvider?
    private var document: MatroskaChapterDocument
    private var roots = [ChapterOutlineItem]()
    private var selectedDisplayIndex = 0
    private var analysisTask: Task<Void, Never>?
    private var suggestionReviewController: ChapterSuggestionReviewWindowController?
    private var thumbnailTask: Task<Void, Never>?
    private var thumbnailWindowController: ChapterThumbnailWindowController?
    private var activityCount = 0

    private let outlineView = NSOutlineView()
    private let selectionHeading = NSTextField(labelWithString: "Select an edition or chapter")
    private let countLabel = NSTextField(labelWithString: "")
    private let displayPopup = NSPopUpButton()
    private let titleField = NSTextField()
    private let languageField = NSComboBox()
    private let countryField = NSTextField()
    private let startField = NSTextField()
    private let endField = NSTextField()
    private let hiddenCheck = NSButton(checkboxWithTitle: "Hidden", target: nil, action: nil)
    private let enabledCheck = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let defaultCheck = NSButton(
        checkboxWithTitle: "Default edition", target: nil, action: nil)
    private let orderedCheck = NSButton(
        checkboxWithTitle: "Ordered edition", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let activityIndicator = ActivityIndicatorPresentation.make(
        label: "Chapter Studio activity",
        help: "Shows while MKV Magic analyzes chapter suggestions or loads local thumbnails."
    )
    private let addChildButton = NSButton(title: "Add Child", target: nil, action: nil)
    private let duplicateButton = NSButton(title: "Duplicate", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let nestButton = NSButton(title: "Nest", target: nil, action: nil)
    private let unnestButton = NSButton(title: "Unnest", target: nil, action: nil)
    private let suggestButton = NSButton(title: "Suggest…", target: nil, action: nil)
    private let thumbnailsButton = NSButton(title: "Thumbnails…", target: nil, action: nil)
    private let addDisplayButton = NSButton(title: "+", target: nil, action: nil)
    private let removeDisplayButton = NSButton(title: "−", target: nil, action: nil)
    private let useChangesButton = NSButton(title: "Use Changes", target: nil, action: nil)

    var preferredInitialFirstResponder: NSView { outlineView }

    init(
        preview: ChapterEditPreview,
        suggestionProvider: ChapterSuggestionProvider?,
        thumbnailProvider: ChapterThumbnailProvider?
    ) {
        self.preview = preview
        self.suggestionProvider = suggestionProvider
        self.thumbnailProvider = thumbnailProvider
        document = preview.original
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Build nested Matroska chapters")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString:
                "Edit a lightweight chapter document, then create a new verified MKV copy. Audio, video, subtitles, tags, and attachments are not encoded or replaced."
        )
        help.textColor = .secondaryLabelColor

        let content = NSSplitView()
        content.isVertical = true
        content.dividerStyle = .thin
        content.addArrangedSubview(makeOutlinePane())
        content.addArrangedSubview(makeEditorPane())
        content.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.setAccessibilityLabel("Chapter Studio status")
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityHelp("Close without adding chapter changes to the plan.")
        useChangesButton.target = self
        useChangesButton.action = #selector(useChanges)
        useChangesButton.keyEquivalent = "\r"
        useChangesButton.setAccessibilityHelp(
            "Accept this nested chapter document for a new verified MKV copy."
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [
            activityIndicator, statusLabel, spacer, cancelButton, useChangesButton,
        ])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10

        let stack = NSStackView(views: [heading, help, content, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: 440),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        reloadOutline(
            selecting: document.editions.first?.chapters.first?.id
                ?? document.editions.first?.id
        )
    }

    private func makeOutlinePane() -> NSView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Chapter"))
        column.title = "Chapter"
        column.width = 500
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 16
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.allowsMultipleSelection = false
        outlineView.setAccessibilityLabel("Nested chapter hierarchy")
        outlineView.setAccessibilityHelp(
            "Select an edition or chapter to edit it, add children, or change nesting."
        )
        let scroll = NSScrollView()
        scroll.documentView = outlineView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let addEdition = NSButton(title: "Add Edition", target: self, action: #selector(addEdition))
        let addChapter = NSButton(title: "Add Chapter", target: self, action: #selector(addChapter))
        addChildButton.target = self
        addChildButton.action = #selector(addNestedChild)
        duplicateButton.target = self
        duplicateButton.action = #selector(duplicateSelection)
        removeButton.target = self
        removeButton.action = #selector(removeSelection)
        nestButton.target = self
        nestButton.action = #selector(nestSelection)
        unnestButton.target = self
        unnestButton.action = #selector(unnestSelection)
        let firstTools = NSStackView(views: [
            addEdition, addChapter, addChildButton, duplicateButton, removeButton,
        ])
        firstTools.orientation = .horizontal
        firstTools.spacing = 6

        let everyButton = NSButton(
            title: "Every…", target: self, action: #selector(createIntervals))
        everyButton.toolTip = "Replace the document with evenly spaced English chapters."
        suggestButton.target = self
        suggestButton.action = #selector(suggestChapters)
        suggestButton.toolTip =
            "Analyze scene changes, black frames, and silence locally, then review suggestions."
        suggestButton.isEnabled = suggestionProvider != nil
        thumbnailsButton.target = self
        thumbnailsButton.action = #selector(showThumbnails)
        thumbnailsButton.toolTip =
            "Preview local frames before, at, and after the selected chapter's numeric start time."
        let flattenButton = NSButton(
            title: "Flatten for Jellyfin", target: self, action: #selector(flattenForJellyfin))
        flattenButton.toolTip = "Explicitly replace nesting with one flat, chronological edition."
        let secondTools = NSStackView(views: [
            nestButton, unnestButton, everyButton, suggestButton, thumbnailsButton,
        ])
        secondTools.orientation = .horizontal
        secondTools.spacing = 6

        let importButton = NSButton(title: "Import…", target: self, action: #selector(importFile))
        let exportButton = NSButton(title: "Export…", target: self, action: #selector(exportFile))
        countLabel.textColor = .secondaryLabelColor
        let toolSpacer = NSView()
        toolSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let fileTools = NSStackView(views: [
            importButton, exportButton, flattenButton, toolSpacer, countLabel,
        ])
        fileTools.orientation = .horizontal
        fileTools.alignment = .centerY
        fileTools.spacing = 8
        for button in [
            addEdition, addChapter, addChildButton, duplicateButton, removeButton,
            nestButton, unnestButton, everyButton, suggestButton, thumbnailsButton, importButton,
            exportButton, flattenButton,
        ] {
            button.controlSize = .small
        }

        let stack = NSStackView(views: [scroll, firstTools, secondTools, fileTools])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        firstTools.translatesAutoresizingMaskIntoConstraints = false
        secondTools.translatesAutoresizingMaskIntoConstraints = false
        fileTools.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 390),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            firstTools.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secondTools.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fileTools.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return container
    }

    private func makeEditorPane() -> NSView {
        selectionHeading.font = .systemFont(ofSize: 16, weight: .semibold)
        let displayLabel = NSTextField(labelWithString: "Display name")
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged)
        addDisplayButton.target = self
        addDisplayButton.action = #selector(addDisplay)
        addDisplayButton.toolTip = "Add another localized chapter display name."
        removeDisplayButton.target = self
        removeDisplayButton.action = #selector(removeDisplay)
        removeDisplayButton.toolTip = "Remove the selected localized display name."
        let displayRow = NSStackView(views: [displayPopup, addDisplayButton, removeDisplayButton])
        displayRow.orientation = .horizontal
        displayRow.spacing = 6

        languageField.addItems(withObjectValues: [
            "en", "en-US", "es", "fr", "de", "it", "pt", "ja", "ko", "zh", "und",
        ])
        languageField.placeholderString = "en, en-US, es, und…"
        countryField.placeholderString = "Optional, e.g. US"
        titleField.placeholderString = "Chapter name"
        startField.placeholderString = "00:00:00.000000000"
        endField.placeholderString = "Optional"
        for field in [titleField, languageField, countryField, startField, endField] {
            field.delegate = self
            field.target = self
            field.action = #selector(commitFields)
        }
        hiddenCheck.target = self
        hiddenCheck.action = #selector(commitFlags)
        enabledCheck.target = self
        enabledCheck.action = #selector(commitFlags)
        defaultCheck.target = self
        defaultCheck.action = #selector(commitFlags)
        orderedCheck.target = self
        orderedCheck.action = #selector(commitFlags)

        let grid = NSGridView(views: [
            [displayLabel, displayRow],
            [fieldLabel("Title"), titleField],
            [fieldLabel("Language"), languageField],
            [fieldLabel("Country"), countryField],
            [fieldLabel("Start"), startField],
            [fieldLabel("End"), endField],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 240
        let flags = NSStackView(views: [hiddenCheck, enabledCheck, defaultCheck, orderedCheck])
        flags.orientation = .vertical
        flags.alignment = .leading
        flags.spacing = 8
        let note = NSTextField(
            wrappingLabelWithString:
                "Times accept HH:MM:SS with up to 9 fractional digits. Empty End lets the player infer the boundary from the next chapter."
        )
        note.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [selectionHeading, grid, flags, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 18, bottom: 0, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        setChapterControlsEnabled(false)
        setEditionControlsEnabled(false)
        return container
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? ChapterOutlineItem)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let item = item as? ChapterOutlineItem else { return false }
        return !item.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? ChapterOutlineItem)?.children[index] ?? roots[index]
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let item = item as? ChapterOutlineItem else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ChapterCell")
        let cell =
            outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = identifier
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = item.label
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        selectedDisplayIndex = 0
        populateEditor()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitFields()
    }

    @objc private func commitFields() {
        guard let selection = selectedItem,
            case .chapter(let chapterID) = selection.kind,
            let current = findChapter(chapterID),
            current.displays.indices.contains(selectedDisplayIndex)
        else { return }
        do {
            let start = try ChapterTimestamp.parse(startField.stringValue)
            let trimmedEnd = endField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = trimmedEnd.isEmpty ? nil : try ChapterTimestamp.parse(trimmedEnd)
            let title = titleField.stringValue
            let language = try ChapterLanguage.canonical(languageField.stringValue)
            let countryValue = countryField.stringValue.trimmingCharacters(
                in: .whitespacesAndNewlines)
            try applyMutation(selecting: chapterID) { candidate in
                mutateChapter(chapterID, in: &candidate) { chapter in
                    chapter.start = start
                    chapter.end = end
                    chapter.displays[selectedDisplayIndex] = ChapterDisplay(
                        title: title,
                        language: language,
                        country: countryValue.isEmpty ? nil : countryValue.uppercased()
                    )
                }
            }
        } catch {
            showDraftError("Could not update the chapter fields.", error: error)
            populateEditor()
        }
    }

    @objc private func commitFlags() {
        guard let selection = selectedItem else { return }
        do {
            switch selection.kind {
            case .edition(let editionID):
                try applyMutation(selecting: editionID) { candidate in
                    guard let index = candidate.editions.firstIndex(where: { $0.id == editionID })
                    else { return }
                    candidate.editions[index].isHidden = hiddenCheck.state == .on
                    candidate.editions[index].isOrdered = orderedCheck.state == .on
                    if defaultCheck.state == .on {
                        for otherIndex in candidate.editions.indices {
                            candidate.editions[otherIndex].isDefault = otherIndex == index
                        }
                    } else {
                        candidate.editions[index].isDefault = false
                    }
                }
            case .chapter(let chapterID):
                try applyMutation(selecting: chapterID) { candidate in
                    mutateChapter(chapterID, in: &candidate) { chapter in
                        chapter.isHidden = hiddenCheck.state == .on
                        chapter.isEnabled = enabledCheck.state == .on
                    }
                }
            }
        } catch {
            showDraftError("Could not update the chapter flags.", error: error)
            populateEditor()
        }
    }

    @objc private func addEdition() {
        let edition = MatroskaChapterEdition(
            isDefault: !document.editions.contains(where: \.isDefault),
            chapters: [
                MatroskaChapterAtom(
                    start: .zero,
                    displays: [ChapterDisplay(title: "Chapter \(document.chapterCount + 1)")]
                )
            ]
        )
        do {
            try applyMutation(selecting: edition.chapters[0].id) { $0.editions.append(edition) }
        } catch { showDraftError("Could not add an edition.", error: error) }
    }

    @objc private func addChapter() {
        let editionID: UUID?
        let afterChapterID: UUID?
        switch selectedItem?.kind {
        case .edition(let id):
            editionID = id
            afterChapterID = nil
        case .chapter(let id):
            editionID = editionContaining(chapterID: id)?.id
            afterChapterID = id
        case nil:
            editionID = document.editions.first?.id
            afterChapterID = nil
        }
        let newEdition =
            editionID == nil
            ? MatroskaChapterEdition(isDefault: true, chapters: []) : nil
        guard let targetEditionID = editionID ?? newEdition?.id else { return }
        let siblings =
            document.editions.first(where: { $0.id == targetEditionID })?.chapters ?? []
        let reference = afterChapterID.flatMap(findChapter)
        let lastSibling = siblings.last
        let proposedStart =
            reference?.end ?? reference?.start ?? lastSibling?.end
            ?? lastSibling?.start ?? .zero
        let chapter = MatroskaChapterAtom(
            start: proposedStart,
            displays: [ChapterDisplay(title: "Chapter \(document.chapterCount + 1)")]
        )
        do {
            try applyMutation(selecting: chapter.id) { candidate in
                if let newEdition {
                    candidate.editions.append(newEdition)
                }
                guard let index = candidate.editions.firstIndex(where: { $0.id == targetEditionID })
                else { return }
                if let afterChapterID,
                    insertChapter(
                        chapter, after: afterChapterID, in: &candidate.editions[index].chapters)
                {
                    return
                }
                candidate.editions[index].chapters.append(chapter)
            }
        } catch { showDraftError("Could not add a chapter.", error: error) }
    }

    @objc private func addNestedChild() {
        guard let selection = selectedItem, case .chapter(let parentID) = selection.kind,
            let parent = findChapter(parentID)
        else { return }
        let child = MatroskaChapterAtom(
            start: parent.children.last?.end ?? parent.children.last?.start ?? parent.start,
            end: parent.end,
            displays: [ChapterDisplay(title: "Chapter \(document.chapterCount + 1)")]
        )
        do {
            try applyMutation(selecting: child.id) { candidate in
                mutateChapter(parentID, in: &candidate) { $0.children.append(child) }
            }
        } catch { showDraftError("Could not add a nested chapter.", error: error) }
    }

    @objc private func duplicateSelection() {
        guard let selection = selectedItem else { return }
        do {
            switch selection.kind {
            case .edition(let editionID):
                guard let original = document.editions.first(where: { $0.id == editionID }) else {
                    return
                }
                let duplicate = MatroskaChapterEdition(
                    isHidden: original.isHidden,
                    isDefault: false,
                    isOrdered: original.isOrdered,
                    chapters: original.chapters.map { $0.regeneratingUIDs() }
                )
                try applyMutation(selecting: duplicate.id) { candidate in
                    guard let index = candidate.editions.firstIndex(where: { $0.id == editionID })
                    else { return }
                    candidate.editions.insert(duplicate, at: index + 1)
                }
            case .chapter(let chapterID):
                guard let original = findChapter(chapterID),
                    let location = locateChapter(chapterID)
                else { return }
                let duplicate = original.regeneratingUIDs()
                try applyMutation(selecting: duplicate.id) { candidate in
                    mutateSiblings(
                        in: &candidate.editions[location.editionIndex].chapters,
                        parentPath: Array(location.path.dropLast())
                    ) { siblings in
                        siblings.insert(duplicate, at: location.path.last! + 1)
                    }
                }
            }
        } catch { showDraftError("Could not duplicate that item.", error: error) }
    }

    @objc private func removeSelection() {
        guard let selection = selectedItem else { return }
        do {
            switch selection.kind {
            case .edition(let id):
                try applyMutation(selecting: nil) { candidate in
                    candidate.editions.removeAll { $0.id == id }
                }
            case .chapter(let id):
                guard let location = locateChapter(id) else { return }
                let fallback = editionContaining(chapterID: id)?.id
                try applyMutation(selecting: fallback) { candidate in
                    mutateSiblings(
                        in: &candidate.editions[location.editionIndex].chapters,
                        parentPath: Array(location.path.dropLast())
                    ) { siblings in
                        siblings.remove(at: location.path.last!)
                    }
                }
            }
        } catch { showDraftError("Could not remove that item.", error: error) }
    }

    @objc private func nestSelection() {
        guard let selection = selectedItem, case .chapter(let id) = selection.kind,
            let location = locateChapter(id), let index = location.path.last, index > 0
        else {
            showError("Choose a chapter that has a previous sibling to nest under.")
            return
        }
        do {
            try applyMutation(selecting: id) { candidate in
                mutateSiblings(
                    in: &candidate.editions[location.editionIndex].chapters,
                    parentPath: Array(location.path.dropLast())
                ) { siblings in
                    let moved = siblings.remove(at: index)
                    siblings[index - 1].children.append(moved)
                }
            }
        } catch { showDraftError("Could not nest that chapter.", error: error) }
    }

    @objc private func unnestSelection() {
        guard let selection = selectedItem, case .chapter(let id) = selection.kind,
            let location = locateChapter(id), location.path.count >= 2,
            let childIndex = location.path.last,
            let parentIndex = location.path.dropLast().last
        else {
            showError("Choose a nested chapter to move out one level.")
            return
        }
        let grandparentPath = Array(location.path.dropLast(2))
        do {
            try applyMutation(selecting: id) { candidate in
                mutateSiblings(
                    in: &candidate.editions[location.editionIndex].chapters,
                    parentPath: grandparentPath
                ) { siblings in
                    let moved = siblings[parentIndex].children.remove(at: childIndex)
                    siblings.insert(moved, at: parentIndex + 1)
                }
            }
        } catch { showDraftError("Could not move that chapter out one level.", error: error) }
    }

    @objc private func addDisplay() {
        guard let selection = selectedItem, case .chapter(let id) = selection.kind else { return }
        let newIndex = (findChapter(id)?.displays.count ?? 0)
        do {
            try applyMutation(selecting: id) { candidate in
                mutateChapter(id, in: &candidate) { chapter in
                    chapter.displays.append(ChapterDisplay(title: "Translation", language: "en"))
                }
            }
            selectedDisplayIndex = newIndex
            populateEditor()
        } catch { showDraftError("Could not add a chapter title translation.", error: error) }
    }

    @objc private func removeDisplay() {
        guard let selection = selectedItem, case .chapter(let id) = selection.kind,
            let chapter = findChapter(id), chapter.displays.count > 1,
            chapter.displays.indices.contains(selectedDisplayIndex)
        else { return }
        let removing = selectedDisplayIndex
        do {
            try applyMutation(selecting: id) { candidate in
                mutateChapter(id, in: &candidate) { $0.displays.remove(at: removing) }
            }
            selectedDisplayIndex = max(0, removing - 1)
            populateEditor()
        } catch { showDraftError("Could not remove that chapter title translation.", error: error) }
    }

    @objc private func displayChanged() {
        selectedDisplayIndex = max(0, displayPopup.indexOfSelectedItem)
        populateEditor()
    }

    @objc private func createIntervals() {
        guard let window = view.window, let duration = preview.source.duration, duration > .zero
        else {
            showError("A known positive media duration is required.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Create evenly spaced chapters?"
        alert.informativeText =
            "This replaces the current in-memory chapter document. The source MKV remains unchanged until you verify and run."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let intervalField = NSTextField(string: "300")
        intervalField.placeholderString = "Seconds"
        intervalField.setAccessibilityLabel("Chapter interval in seconds")
        alert.accessoryView = intervalField
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn,
                let seconds = Double(intervalField.stringValue), seconds.isFinite,
                let interval = MediaTime(seconds: seconds)
            else { return }
            do {
                let suggested = try MatroskaChapterDocument.fixedInterval(
                    duration: duration,
                    interval: interval
                )
                self.document = suggested
                self.reloadOutline(selecting: suggested.editions.first?.chapters.first?.id)
                self.showInfo("Created \(suggested.chapterCount) chapters.")
            } catch {
                self.showDraftError("Could not create evenly spaced chapters.", error: error)
            }
        }
    }

    @objc private func suggestChapters() {
        guard let window = view.window, suggestionProvider != nil,
            preview.source.duration.map({ $0 > .zero }) == true
        else {
            showError("A known positive media duration and bundled FFmpeg are required.")
            return
        }
        let hasVideo = preview.source.tracks.contains { $0.kind == .video }
        let hasAudio = preview.source.tracks.contains { $0.kind == .audio }
        guard hasVideo || hasAudio else {
            showError("No video or audio track is available for local analysis.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Suggest chapter boundaries?"
        alert.informativeText =
            "MKV Magic analyzes the file locally with bundled FFmpeg. Review every timestamp before it is added; the source is never changed."
        alert.addButton(withTitle: "Analyze")
        alert.addButton(withTitle: "Cancel")
        let sceneCheck = NSButton(
            checkboxWithTitle: "Scene changes", target: nil, action: nil)
        sceneCheck.state = hasVideo ? .on : .off
        sceneCheck.isEnabled = hasVideo
        let blackCheck = NSButton(
            checkboxWithTitle: "Black frames", target: nil, action: nil)
        blackCheck.state = hasVideo ? .on : .off
        blackCheck.isEnabled = hasVideo
        let silenceCheck = NSButton(
            checkboxWithTitle: "Silence", target: nil, action: nil)
        silenceCheck.state = hasAudio ? .on : .off
        silenceCheck.isEnabled = hasAudio
        let spacingField = NSTextField(string: "60")
        spacingField.alignment = .right
        spacingField.setAccessibilityLabel("Minimum seconds between suggestions")
        let secondsLabel = NSTextField(labelWithString: "seconds apart")
        let spacingRow = NSStackView(views: [
            NSTextField(labelWithString: "Keep suggestions at least"), spacingField, secondsLabel,
        ])
        spacingRow.orientation = .horizontal
        spacingRow.alignment = .centerY
        spacingRow.spacing = 6
        spacingField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let choices = NSStackView(views: [sceneCheck, blackCheck, silenceCheck, spacingRow])
        choices.orientation = .vertical
        choices.alignment = .leading
        choices.spacing = 8
        choices.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 6, right: 0)
        alert.accessoryView = choices
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            guard let seconds = Double(spacingField.stringValue), seconds.isFinite, seconds >= 0,
                let spacing = MediaTime(seconds: seconds)
            else {
                self.showError("Minimum spacing must be a nonnegative number of seconds.")
                return
            }
            var options = ChapterSuggestionOptions()
            options.detectsSceneChanges = sceneCheck.state == .on
            options.detectsBlackFrames = blackCheck.state == .on
            options.detectsSilence = silenceCheck.state == .on
            options.minimumSpacing = spacing
            do {
                _ = try options.validated()
                self.runSuggestionAnalysis(options: options)
            } catch {
                self.showError(
                    failure: "Could not use those chapter suggestion settings.",
                    recovery: "No analysis was started; revise the settings and try again.",
                    error: error
                )
            }
        }
    }

    private func runSuggestionAnalysis(options: ChapterSuggestionOptions) {
        guard let suggestionProvider, let duration = preview.source.duration else { return }
        analysisTask?.cancel()
        suggestButton.isEnabled = false
        beginChapterActivity()
        showInfo("Analyzing locally with FFmpeg…")
        let startsAtLaunch = allChapterStarts()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            defer { endChapterActivity() }
            do {
                let analyzed = try await suggestionProvider(options, startsAtLaunch)
                try Task.checkCancellation()
                let detections = analyzed.flatMap { suggestion in
                    suggestion.signals.map {
                        ChapterSuggestionDetection(time: suggestion.time, signal: $0)
                    }
                }
                let currentSuggestions = try ChapterSuggestionConsolidator.consolidate(
                    detections,
                    duration: duration,
                    existingChapterStarts: self.allChapterStarts(),
                    options: options
                )
                self.analysisTask = nil
                self.suggestButton.isEnabled = self.suggestionProvider != nil
                guard !currentSuggestions.isEmpty else {
                    self.showInfo("No new boundaries matched these settings.")
                    return
                }
                self.presentSuggestionReview(currentSuggestions)
            } catch is CancellationError {
                self.analysisTask = nil
                self.suggestButton.isEnabled = self.suggestionProvider != nil
            } catch {
                self.analysisTask = nil
                self.suggestButton.isEnabled = self.suggestionProvider != nil
                self.showError(
                    failure: "Could not finish chapter analysis.",
                    recovery: "The chapter draft is unchanged; adjust the settings and try again.",
                    error: error
                )
            }
        }
    }

    private func presentSuggestionReview(_ suggestions: [ChapterSuggestion]) {
        guard let window = view.window else { return }
        let controller = ChapterSuggestionReviewWindowController(suggestions: suggestions)
        suggestionReviewController = controller
        controller.beginSheet(for: window) { [weak self] selected in
            guard let self else { return }
            self.suggestionReviewController = nil
            guard !selected.isEmpty else {
                self.showInfo("No suggested chapters were selected.")
                return
            }
            self.applySuggestions(selected)
        }
    }

    private func applySuggestions(_ suggestions: [ChapterSuggestion]) {
        let targetEditionID: UUID?
        switch selectedItem?.kind {
        case .edition(let id):
            targetEditionID = id
        case .chapter(let id):
            targetEditionID = editionContaining(chapterID: id)?.id
        case nil:
            targetEditionID = document.editions.first?.id
        }
        do {
            let result = try ChapterSuggestionApplicator.apply(
                suggestions,
                to: document,
                editionID: targetEditionID,
                mediaDuration: preview.source.duration
            )
            guard result.addedCount > 0 else {
                showError("The selected boundaries overlap existing chapter ranges.")
                return
            }
            document = result.document
            reloadOutline(selecting: result.firstAddedChapterID)
            let skipped =
                result.skippedCount == 0 ? "" : " • \(result.skippedCount) overlapping skipped"
            showInfo(
                "Added \(result.addedCount) reviewed chapter\(result.addedCount == 1 ? "" : "s")\(skipped)."
            )
        } catch {
            showDraftError("Could not add the reviewed chapter suggestions.", error: error)
        }
    }

    @objc private func showThumbnails() {
        guard let thumbnailProvider, let window = view.window,
            let selection = selectedItem, case .chapter(let chapterID) = selection.kind,
            let chapter = findChapter(chapterID),
            let duration = preview.source.duration, duration > .zero
        else {
            showError("Choose a chapter in a video with a known positive duration.")
            return
        }
        let originalStart = chapter.start
        let times = thumbnailTimes(around: originalStart, duration: duration)
        guard !times.isEmpty else {
            showError("No safe thumbnail times are available for this chapter.")
            return
        }

        thumbnailTask?.cancel()
        thumbnailsButton.isEnabled = false
        beginChapterActivity()
        showInfo("Loading local thumbnails…")
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            defer { endChapterActivity() }
            do {
                let thumbnails = try await thumbnailProvider(times)
                try Task.checkCancellation()
                self.thumbnailTask = nil
                self.updateActionAvailability()
                guard let currentSelection = self.selectedItem,
                    case .chapter(chapterID) = currentSelection.kind,
                    self.findChapter(chapterID)?.start == originalStart
                else {
                    self.showInfo("Selection changed; discarded the thumbnail preview.")
                    return
                }
                guard
                    let controller = ChapterThumbnailWindowController(
                        thumbnails: thumbnails,
                        currentTime: originalStart
                    )
                else {
                    self.showError("FFmpeg returned an unreadable thumbnail preview.")
                    return
                }
                self.thumbnailWindowController = controller
                controller.beginSheet(for: window) { [weak self] selectedTime in
                    guard let self else { return }
                    self.thumbnailWindowController = nil
                    guard let selectedTime else { return }
                    guard self.findChapter(chapterID)?.start == originalStart else {
                        self.showInfo("The chapter changed; no thumbnail time was applied.")
                        return
                    }
                    do {
                        try self.applyMutation(selecting: chapterID) { candidate in
                            self.mutateChapter(chapterID, in: &candidate) {
                                $0.start = selectedTime
                            }
                        }
                        self.showInfo(
                            "Set chapter start to \(ChapterTimestamp.format(selectedTime, digits: 3))."
                        )
                    } catch {
                        self.showDraftError(
                            "Could not apply the selected thumbnail time.",
                            error: error
                        )
                    }
                }
            } catch is CancellationError {
                self.thumbnailTask = nil
                self.updateActionAvailability()
            } catch {
                self.thumbnailTask = nil
                self.updateActionAvailability()
                self.showError(
                    failure: "Could not create the thumbnail preview.",
                    recovery: "The chapter draft is unchanged; check the video and try again.",
                    error: error
                )
            }
        }
    }

    private func thumbnailTimes(around start: MediaTime, duration: MediaTime) -> [MediaTime] {
        let offset: Int64 = 5_000_000_000
        let beforeResult = start.nanoseconds.subtractingReportingOverflow(offset)
        let before = MediaTime(
            nanoseconds: beforeResult.overflow ? 0 : max(0, beforeResult.partialValue))
        let lastNanosecond = max(0, duration.nanoseconds - 1)
        let afterResult = start.nanoseconds.addingReportingOverflow(offset)
        let after = MediaTime(
            nanoseconds: afterResult.overflow
                ? lastNanosecond : min(lastNanosecond, afterResult.partialValue))
        return Array(Set([before, start, after])).filter { $0 >= .zero && $0 < duration }.sorted()
    }

    @objc private func flattenForJellyfin() {
        guard let window = view.window else { return }
        let flattened = document.flattenedForJellyfin()
        guard flattened != document else {
            showInfo("The document is already flat for Jellyfin.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Replace nesting with one flat edition?"
        alert.informativeText =
            "Only leaf chapters are retained, sorted by time, and assigned new UIDs. This changes the in-memory plan only."
        alert.addButton(withTitle: "Flatten")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.document = flattened
            self.reloadOutline(selecting: flattened.editions.first?.chapters.first?.id)
            self.showInfo("Created a flat Jellyfin-compatible chapter edition.")
        }
    }

    @objc private func importFile() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Chapters"
        panel.prompt = "Import"
        panel.message = "Choose Matroska chapter XML or simple CHAPTER01 text."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.xml,
            UTType(filenameExtension: "txt") ?? .plainText,
        ]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                guard
                    let values = try? url.resourceValues(forKeys: [
                        .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
                    ]),
                    values.isRegularFile == true,
                    values.isSymbolicLink != true,
                    let fileSize = values.fileSize,
                    fileSize >= 0,
                    fileSize <= MatroskaChapterXMLCodec.maximumInputBytes
                else {
                    throw MatroskaChapterCodecError.oversizedInput
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let imported =
                    if url.pathExtension.lowercased() == "xml" {
                        try MatroskaChapterXMLCodec().parse(data)
                    } else {
                        try SimpleChapterTextCodec().parse(data)
                    }
                self.document = try imported.validated(mediaDuration: self.preview.source.duration)
                self.reloadOutline(selecting: imported.editions.first?.chapters.first?.id)
                self.showInfo("Imported \(imported.chapterCount) chapters.")
            } catch {
                self.showError(
                    failure: "Could not import those chapters.",
                    recovery: "The current draft is unchanged; choose another XML or text file.",
                    error: error
                )
            }
        }
    }

    @objc private func exportFile() {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.title = "Export Chapters"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "chapters.xml"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [
            UTType.xml,
            UTType(filenameExtension: "txt") ?? .plainText,
        ]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                let data =
                    if url.pathExtension.lowercased() == "txt" {
                        try SimpleChapterTextCodec().serialize(self.document)
                    } else {
                        try MatroskaChapterXMLCodec().serialize(self.document)
                    }
                try data.write(to: url, options: .atomic)
                self.showInfo("Exported \(url.lastPathComponent).")
            } catch {
                self.showError(
                    failure: "Could not export the chapters.",
                    recovery: "The chapter draft is unchanged; choose another destination.",
                    error: error
                )
            }
        }
    }

    @objc private func useChanges() {
        do {
            let desired = try document.validated(mediaDuration: preview.source.duration)
            let codec = MatroskaChapterXMLCodec()
            guard try codec.serialize(desired) != codec.serialize(preview.original) else {
                showInfo("Change at least one chapter value first.")
                return
            }
            clearStatus()
            onUseChanges?(desired)
        } catch {
            showError(
                failure: "Could not use these chapter changes.",
                recovery: "The source MKV is unchanged; correct the chapter draft and try again.",
                error: error
            )
        }
    }

    @objc private func cancel() {
        cancelAnalysis()
        onCancel?()
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        suggestionReviewController?.cancel()
        suggestionReviewController = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        thumbnailWindowController?.cancel()
        thumbnailWindowController = nil
    }

    private var selectedItem: ChapterOutlineItem? {
        guard outlineView.selectedRow >= 0 else { return nil }
        return outlineView.item(atRow: outlineView.selectedRow) as? ChapterOutlineItem
    }

    private func populateEditor() {
        guard let selection = selectedItem else {
            selectionHeading.stringValue = "Select an edition or chapter"
            setChapterControlsEnabled(false)
            setEditionControlsEnabled(false)
            updateActionAvailability()
            return
        }
        clearStatus()
        switch selection.kind {
        case .edition(let id):
            guard let edition = document.editions.first(where: { $0.id == id }) else { return }
            selectionHeading.stringValue = "Edition"
            setChapterControlsEnabled(false)
            setEditionControlsEnabled(true)
            hiddenCheck.state = edition.isHidden ? .on : .off
            defaultCheck.state = edition.isDefault ? .on : .off
            orderedCheck.state = edition.isOrdered ? .on : .off
        case .chapter(let id):
            guard let chapter = findChapter(id) else { return }
            selectionHeading.stringValue = chapter.primaryTitle
            setChapterControlsEnabled(true)
            setEditionControlsEnabled(false)
            selectedDisplayIndex = min(selectedDisplayIndex, max(0, chapter.displays.count - 1))
            displayPopup.removeAllItems()
            displayPopup.addItems(
                withTitles: chapter.displays.enumerated().map { offset, display in
                    "\(offset + 1). \(display.language) — \(display.title)"
                })
            displayPopup.selectItem(at: selectedDisplayIndex)
            let display = chapter.displays[selectedDisplayIndex]
            titleField.stringValue = display.title
            languageField.stringValue = display.language
            countryField.stringValue = display.country ?? ""
            startField.stringValue = ChapterTimestamp.format(chapter.start)
            endField.stringValue = chapter.end.map { ChapterTimestamp.format($0) } ?? ""
            hiddenCheck.state = chapter.isHidden ? .on : .off
            enabledCheck.state = chapter.isEnabled ? .on : .off
            removeDisplayButton.isEnabled = chapter.displays.count > 1
        }
        updateActionAvailability()
    }

    private func setChapterControlsEnabled(_ enabled: Bool) {
        for control in [
            displayPopup, titleField, languageField, countryField, startField, endField,
            hiddenCheck, enabledCheck, addDisplayButton, removeDisplayButton,
        ] {
            control.isEnabled = enabled
        }
    }

    private func setEditionControlsEnabled(_ enabled: Bool) {
        defaultCheck.isEnabled = enabled
        orderedCheck.isEnabled = enabled
        if enabled { hiddenCheck.isEnabled = true }
    }

    private func updateActionAvailability() {
        let isChapter: Bool
        if case .chapter = selectedItem?.kind { isChapter = true } else { isChapter = false }
        addChildButton.isEnabled = isChapter
        duplicateButton.isEnabled = selectedItem != nil
        removeButton.isEnabled = selectedItem != nil
        nestButton.isEnabled = isChapter
        unnestButton.isEnabled = isChapter
        thumbnailsButton.isEnabled =
            isChapter && thumbnailProvider != nil && thumbnailTask == nil
            && preview.source.tracks.contains { $0.kind == .video }
            && preview.source.duration.map { $0 > .zero } == true
        useChangesButton.isEnabled = true
    }

    private func reloadOutline(selecting selectedID: UUID?) {
        roots = document.editions.enumerated().map { offset, edition in
            ChapterOutlineItem(
                kind: .edition(edition.id),
                label: editionLabel(edition, offset: offset),
                children: edition.chapters.map(makeOutlineItem)
            )
        }
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
        countLabel.stringValue =
            "\(document.editions.count) edition\(document.editions.count == 1 ? "" : "s") • "
            + "\(document.chapterCount) chapter\(document.chapterCount == 1 ? "" : "s")"
        if let selectedID, let item = findOutlineItem(selectedID, in: roots) {
            let row = outlineView.row(forItem: item)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
            }
        } else {
            outlineView.deselectAll(nil)
        }
        populateEditor()
    }

    private func editionLabel(_ edition: MatroskaChapterEdition, offset: Int) -> String {
        var roles = [String]()
        if edition.isDefault { roles.append("default") }
        if edition.isOrdered { roles.append("ordered") }
        if edition.isHidden { roles.append("hidden") }
        let suffix = roles.isEmpty ? "" : " — \(roles.joined(separator: ", "))"
        return "Edition \(offset + 1) • \(edition.chapters.count) top-level\(suffix)"
    }

    private func makeOutlineItem(_ chapter: MatroskaChapterAtom) -> ChapterOutlineItem {
        ChapterOutlineItem(
            kind: .chapter(chapter.id),
            label: "\(ChapterTimestamp.format(chapter.start, digits: 3))  \(chapter.primaryTitle)",
            children: chapter.children.map(makeOutlineItem)
        )
    }

    private func findOutlineItem(_ id: UUID, in items: [ChapterOutlineItem])
        -> ChapterOutlineItem?
    {
        for item in items {
            if item.id == id { return item }
            if let found = findOutlineItem(id, in: item.children) { return found }
        }
        return nil
    }

    private func applyMutation(
        selecting selectedID: UUID?,
        _ mutation: (inout MatroskaChapterDocument) -> Void
    ) throws {
        var candidate = document
        mutation(&candidate)
        document = try candidate.validated(mediaDuration: preview.source.duration)
        clearStatus()
        reloadOutline(selecting: selectedID)
    }

    private func showError(_ message: String) {
        statusLabel.textColor = .systemRed
        AccessibleStatusPresentation.present(
            message,
            in: statusLabel,
            returningFocusTo: outlineView
        )
    }

    private func showError(failure: String, recovery: String, error: Error) {
        showError(
            UserFacingErrorPresentation.message(
                failure: failure,
                recovery: recovery,
                error: error
            )
        )
    }

    private func showDraftError(_ failure: String, error: Error) {
        showError(
            failure: failure,
            recovery: "The last valid chapter draft remains shown; revise it and try again.",
            error: error
        )
    }

    private func showInfo(_ message: String) {
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = message
    }

    private func beginChapterActivity() {
        activityCount += 1
        ActivityIndicatorPresentation.set(activityIndicator, active: true)
    }

    private func endChapterActivity() {
        activityCount = max(0, activityCount - 1)
        ActivityIndicatorPresentation.set(activityIndicator, active: activityCount > 0)
    }

    private func clearStatus() {
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = ""
    }

    private func fieldLabel(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.alignment = .right
        return label
    }

    private func findChapter(_ id: UUID) -> MatroskaChapterAtom? {
        for edition in document.editions {
            if let chapter = findChapter(id, in: edition.chapters) { return chapter }
        }
        return nil
    }

    private func allChapterStarts() -> [MediaTime] {
        allChapterStarts(in: document)
    }

    private func allChapterStarts(in document: MatroskaChapterDocument) -> [MediaTime] {
        document.editions.flatMap { allChapterStarts(in: $0.chapters) }
    }

    private func allChapterStarts(in chapters: [MatroskaChapterAtom]) -> [MediaTime] {
        chapters.flatMap { [$0.start] + allChapterStarts(in: $0.children) }
    }

    private func findChapter(_ id: UUID, in chapters: [MatroskaChapterAtom])
        -> MatroskaChapterAtom?
    {
        for chapter in chapters {
            if chapter.id == id { return chapter }
            if let child = findChapter(id, in: chapter.children) { return child }
        }
        return nil
    }

    private func editionContaining(chapterID: UUID) -> MatroskaChapterEdition? {
        document.editions.first { findChapter(chapterID, in: $0.chapters) != nil }
    }

    private func mutateChapter(
        _ id: UUID,
        in candidate: inout MatroskaChapterDocument,
        mutation: (inout MatroskaChapterAtom) -> Void
    ) {
        for index in candidate.editions.indices {
            if mutateChapter(id, in: &candidate.editions[index].chapters, mutation: mutation) {
                return
            }
        }
    }

    private func mutateChapter(
        _ id: UUID,
        in chapters: inout [MatroskaChapterAtom],
        mutation: (inout MatroskaChapterAtom) -> Void
    ) -> Bool {
        for index in chapters.indices {
            if chapters[index].id == id {
                mutation(&chapters[index])
                return true
            }
            if mutateChapter(id, in: &chapters[index].children, mutation: mutation) { return true }
        }
        return false
    }

    private func insertChapter(
        _ chapter: MatroskaChapterAtom,
        after id: UUID,
        in chapters: inout [MatroskaChapterAtom]
    ) -> Bool {
        for index in chapters.indices {
            if chapters[index].id == id {
                chapters.insert(chapter, at: index + 1)
                return true
            }
            if insertChapter(chapter, after: id, in: &chapters[index].children) { return true }
        }
        return false
    }

    private struct ChapterLocation {
        let editionIndex: Int
        let path: [Int]
    }

    private func locateChapter(_ id: UUID) -> ChapterLocation? {
        for editionIndex in document.editions.indices {
            if let path = locateChapter(id, in: document.editions[editionIndex].chapters) {
                return ChapterLocation(editionIndex: editionIndex, path: path)
            }
        }
        return nil
    }

    private func locateChapter(_ id: UUID, in chapters: [MatroskaChapterAtom]) -> [Int]? {
        for index in chapters.indices {
            if chapters[index].id == id { return [index] }
            if let child = locateChapter(id, in: chapters[index].children) {
                return [index] + child
            }
        }
        return nil
    }

    private func mutateSiblings(
        in chapters: inout [MatroskaChapterAtom],
        parentPath: [Int],
        mutation: (inout [MatroskaChapterAtom]) -> Void
    ) {
        guard let index = parentPath.first else {
            mutation(&chapters)
            return
        }
        mutateSiblings(
            in: &chapters[index].children,
            parentPath: Array(parentPath.dropFirst()),
            mutation: mutation
        )
    }
}
