import AppKit
import MKVMagicCore
import MKVMagicExecution

private struct SubtitleCleanupReviewChange {
    let id: Int
    let title: String
    let detail: String
    let start: SubRipTimestamp
    let end: SubRipTimestamp
    let selectedByDefault: Bool
}

private enum SubtitleCleanupReviewPreview {
    case subRip(SubtitleCleanupFilePreview)
    case advanced(AdvancedSubtitleCleanupFilePreview)
    case embeddedSubRip(EmbeddedSubRipCleanupPreview)
    case embeddedAdvanced(EmbeddedAdvancedSubtitleCleanupPreview)

    var changes: [SubtitleCleanupReviewChange] {
        switch self {
        case .subRip(let preview):
            preview.cleanup.changes.map { change in
                SubtitleCleanupReviewChange(
                    id: change.id,
                    title: SubtitleCleanupPresentation.title(change),
                    detail: SubtitleCleanupPresentation.detail(change),
                    start: change.before.start,
                    end: change.before.end,
                    selectedByDefault: SubtitleCleanupPresentation.selectedByDefault(
                        reasons: change.reasons
                    )
                )
            }
        case .advanced(let preview):
            preview.cleanup.changes.map { change in
                SubtitleCleanupReviewChange(
                    id: change.id,
                    title: SubtitleCleanupPresentation.title(change),
                    detail: SubtitleCleanupPresentation.detail(change),
                    start: change.before.start,
                    end: change.before.end,
                    selectedByDefault: SubtitleCleanupPresentation.selectedByDefault(
                        reasons: change.reasons
                    )
                )
            }
        case .embeddedSubRip(let preview):
            preview.cleanup.changes.map { change in
                SubtitleCleanupReviewChange(
                    id: change.id,
                    title: SubtitleCleanupPresentation.title(change),
                    detail: SubtitleCleanupPresentation.detail(change),
                    start: change.before.start,
                    end: change.before.end,
                    selectedByDefault: SubtitleCleanupPresentation.selectedByDefault(
                        reasons: change.reasons
                    )
                )
            }
        case .embeddedAdvanced(let preview):
            preview.cleanup.changes.map { change in
                SubtitleCleanupReviewChange(
                    id: change.id,
                    title: SubtitleCleanupPresentation.title(change),
                    detail: SubtitleCleanupPresentation.detail(change),
                    start: change.before.start,
                    end: change.before.end,
                    selectedByDefault: SubtitleCleanupPresentation.selectedByDefault(
                        reasons: change.reasons
                    )
                )
            }
        }
    }

    var itemCount: Int {
        switch self {
        case .subRip(let preview): preview.cleanup.original.cues.count
        case .advanced(let preview): preview.cleanup.original.events.count
        case .embeddedSubRip(let preview): preview.cleanup.original.cues.count
        case .embeddedAdvanced(let preview): preview.cleanup.original.events.count
        }
    }

    var defaultAppliedChangeIDs: Set<Int> {
        Set(changes.filter(\.selectedByDefault).map(\.id))
    }

    var itemName: String {
        switch self {
        case .subRip, .embeddedSubRip: "cues"
        case .advanced, .embeddedAdvanced: "events"
        }
    }

    var itemSingular: String {
        switch self {
        case .subRip, .embeddedSubRip: "cue"
        case .advanced, .embeddedAdvanced: "event"
        }
    }

    var explanation: String {
        switch self {
        case .subRip:
            "Deterministic ad, whitespace, and high-confidence local English OCR fixes are selected. Possible spelling corrections start unselected. Uncheck any selected change to restore that cue. Cue timing is never changed."
        case .advanced:
            "Deterministic ad, whitespace, and high-confidence local English OCR fixes are selected. Possible spelling corrections start unselected. Uncheck any selected change to restore that event. Styles, override tags, layout fields, and timing are never changed."
        case .embeddedSubRip:
            "Review the extracted text before MKV Magic replaces this one embedded SRT track in a new MKV. Existing track order, metadata, chapters, attachments, tags, video, and audio are preserved without encoding."
        case .embeddedAdvanced:
            "Review the extracted dialogue before MKV Magic replaces this one embedded styled track in a new MKV. Styles, override tags, track order, metadata, timing, chapters, attachments, video, and audio are preserved without encoding."
        }
    }

    var normalization: String {
        switch self {
        case .subRip(let preview): SubtitleCleanupPresentation.normalization(preview)
        case .advanced(let preview): SubtitleCleanupPresentation.normalization(preview)
        case .embeddedSubRip(let preview):
            SubtitleCleanupPresentation.embeddedNormalization(
                format: .subRip,
                track: preview.track,
                appliesEnglishOCRRules: preview.appliesEnglishOCRRules,
                diagnosticCount: preview.diagnostics.count
            )
        case .embeddedAdvanced(let preview):
            SubtitleCleanupPresentation.embeddedNormalization(
                format: preview.format,
                track: preview.track,
                appliesEnglishOCRRules: preview.appliesEnglishOCRRules,
                diagnosticCount: preview.diagnostics.count
            )
        }
    }

    func canConfirm(appliedChangeIDs: Set<Int>) -> Bool {
        switch self {
        case .subRip(let preview):
            return SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: appliedChangeIDs
            )
        case .advanced(let preview):
            return SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: appliedChangeIDs
            )
        case .embeddedSubRip(let preview):
            let allChangeIDs = Set(preview.cleanup.changes.map(\.id))
            return !preview.cleanup.document(
                restoringCueIDs: allChangeIDs.subtracting(appliedChangeIDs)
            ).cues.isEmpty
        case .embeddedAdvanced(let preview):
            let allChangeIDs = Set(preview.cleanup.changes.map(\.id))
            return !preview.cleanup.document(
                restoringEventIDs: allChangeIDs.subtracting(appliedChangeIDs)
            ).events.isEmpty
        }
    }
}

@MainActor
final class SubtitleCleanupWindowController: NSWindowController {
    private let cleanupViewController: SubtitleCleanupViewController

    convenience init(preview: SubtitleCleanupFilePreview) {
        self.init(review: .subRip(preview), title: "Clean SRT Subtitle")
    }

    convenience init(preview: AdvancedSubtitleCleanupFilePreview) {
        self.init(review: .advanced(preview), title: "Clean ASS/SSA Subtitle")
    }

    convenience init(preview: EmbeddedSubtitleCleanupPreview) {
        switch preview {
        case .subRip(let preview):
            self.init(review: .embeddedSubRip(preview), title: "Clean Embedded SRT Subtitle")
        case .advanced(let preview):
            self.init(
                review: .embeddedAdvanced(preview),
                title: "Clean Embedded \(preview.format.displayName) Subtitle"
            )
        }
    }

    private init(review: SubtitleCleanupReviewPreview, title: String) {
        cleanupViewController = SubtitleCleanupViewController(review: review)
        let window = NSWindow(contentViewController: cleanupViewController)
        window.title = title
        window.setContentSize(NSSize(width: 740, height: 560))
        window.minSize = NSSize(width: 640, height: 480)
        window.styleMask.insert(.resizable)
        window.tabbingMode = .disallowed
        window.initialFirstResponder = cleanupViewController.preferredInitialFirstResponder
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (Set<Int>?) -> Void
    ) {
        guard let window else {
            completion(nil)
            return
        }
        cleanupViewController.onComplete = { [weak self, weak parentWindow] restoredCueIDs in
            guard let self else { return }
            if let parentWindow, let sheet = self.window, parentWindow.attachedSheet === sheet {
                parentWindow.endSheet(sheet)
            }
            completion(restoredCueIDs)
        }
        parentWindow.beginSheet(window)
    }
}

@MainActor
final class SubtitleCleanupViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate
{
    var onComplete: ((Set<Int>?) -> Void)?
    private let review: SubtitleCleanupReviewPreview
    private let tableView = NSTableView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let validationLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(
        title: "Continue",
        target: nil,
        action: nil
    )
    private var appliedChangeIDs = Set<Int>()

    var preferredInitialFirstResponder: NSView { tableView }

    fileprivate init(review: SubtitleCleanupReviewPreview) {
        self.review = review
        appliedChangeIDs = review.defaultAppliedChangeIDs
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        let heading = NSTextField(labelWithString: "Review subtitle cleanup")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString: review.explanation
        )
        explanation.textColor = .secondaryLabelColor
        summaryLabel.stringValue = SubtitleCleanupPresentation.selectionSummary(
            appliedCount: appliedChangeIDs.count,
            totalCount: review.changes.count,
            itemCount: review.itemCount,
            itemName: review.itemName
        )

        let column = NSTableColumn(identifier: .init("change"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 86
        tableView.allowsEmptySelection = true
        tableView.setAccessibilityLabel("Subtitle cleanup suggestions")
        tableView.setAccessibilityHelp(
            "Review each suggested text change and uncheck any change you do not want."
        )
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let normalization = NSTextField(
            wrappingLabelWithString: review.normalization
        )
        summaryLabel.setAccessibilityLabel("Subtitle cleanup selection summary")
        normalization.textColor = .secondaryLabelColor
        normalization.font = .systemFont(ofSize: 11)
        normalization.setAccessibilityLabel("Subtitle normalization details")
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        validationLabel.setAccessibilityLabel("Subtitle cleanup status")
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityHelp("Close without saving or muxing cleaned subtitles.")
        saveButton.target = self
        saveButton.action = #selector(confirm)
        saveButton.keyEquivalent = "\r"
        saveButton.setAccessibilityHelp(
            "Accept the selected text changes and continue to the verified output step."
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [validationLabel, spacer, cancel, saveButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let stack = NSStackView(views: [
            heading, explanation, summaryLabel, scroll, normalization, actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        updateSelectionState()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        review.changes.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let change = review.changes[row]
        let checkbox = NSButton(
            checkboxWithTitle: change.title,
            target: self,
            action: #selector(toggleChange(_:))
        )
        checkbox.state = appliedChangeIDs.contains(change.id) ? .on : .off
        checkbox.tag = row
        let timing = NSTextField(
            labelWithString:
                "\(SubtitleCleanupPresentation.time(change.start)) → "
                + SubtitleCleanupPresentation.time(change.end)
        )
        timing.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        timing.textColor = .secondaryLabelColor
        let detail = NSTextField(
            wrappingLabelWithString: change.detail
        )
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        let stack = NSStackView(views: [checkbox, timing, detail])
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

    @objc private func toggleChange(_ sender: NSButton) {
        guard review.changes.indices.contains(sender.tag) else { return }
        let id = review.changes[sender.tag].id
        if sender.state == .on {
            appliedChangeIDs.insert(id)
        } else {
            appliedChangeIDs.remove(id)
        }
        updateSelectionState()
    }

    @objc private func cancel() { onComplete?(nil) }

    @objc private func confirm() {
        guard
            review.canConfirm(appliedChangeIDs: appliedChangeIDs)
        else { return }
        let allChangeIDs = Set(review.changes.map(\.id))
        onComplete?(allChangeIDs.subtracting(appliedChangeIDs))
    }

    private func updateSelectionState() {
        summaryLabel.stringValue = SubtitleCleanupPresentation.selectionSummary(
            appliedCount: appliedChangeIDs.count,
            totalCount: review.changes.count,
            itemCount: review.itemCount,
            itemName: review.itemName
        )
        saveButton.isEnabled = review.canConfirm(appliedChangeIDs: appliedChangeIDs)
        validationLabel.stringValue =
            saveButton.isEnabled
            ? "" : "Restore at least one \(review.itemSingular) before continuing."
    }
}

enum SubtitleCleanupPresentation {
    static func summary(_ preview: SubtitleCleanupFilePreview) -> String {
        let appliedCount = preview.cleanup.changes.filter {
            selectedByDefault(reasons: $0.reasons)
        }.count
        return selectionSummary(
            appliedCount: appliedCount,
            totalCount: preview.cleanup.changes.count,
            cueCount: preview.cleanup.original.cues.count
        )
    }

    static func selectionSummary(appliedCount: Int, totalCount: Int, cueCount: Int) -> String {
        selectionSummary(
            appliedCount: appliedCount,
            totalCount: totalCount,
            itemCount: cueCount,
            itemName: "cues"
        )
    }

    static func selectionSummary(
        appliedCount: Int,
        totalCount: Int,
        itemCount: Int,
        itemName: String
    ) -> String {
        "\(itemCount) \(itemName) • \(appliedCount) of \(totalCount) suggested changes selected"
    }

    static func normalization(_ preview: SubtitleCleanupFilePreview) -> String {
        var details = ["Output: UTF-8 without BOM, LF line endings, sequential cue numbers"]
        details.append(
            preview.appliesEnglishOCRRules
                ? "Local English OCR review enabled"
                : "English OCR review skipped: filename identifies another language"
        )
        if preview.encoding != .utf8 {
            details.append("Input encoding: \(preview.encoding.rawValue)")
        }
        if !preview.diagnostics.isEmpty {
            details.append("Structural normalization: \(preview.diagnostics.count) item(s)")
        }
        return details.joined(separator: " • ")
    }

    static func normalization(_ preview: AdvancedSubtitleCleanupFilePreview) -> String {
        var details = [
            "Output: UTF-8 without BOM and LF line endings; script sections and styles preserved"
        ]
        details.append(
            preview.appliesEnglishOCRRules
                ? "Local English OCR review enabled"
                : "English OCR review skipped: filename identifies another language"
        )
        if preview.encoding != .utf8 {
            details.append("Input encoding: \(preview.encoding.rawValue)")
        }
        if !preview.diagnostics.isEmpty {
            details.append("Structural normalization: \(preview.diagnostics.count) item(s)")
        }
        return details.joined(separator: " • ")
    }

    static func embeddedNormalization(
        format: ExternalTextSubtitleFormat,
        track: MediaTrack,
        appliesEnglishOCRRules: Bool,
        diagnosticCount: Int
    ) -> String {
        var details = [
            "Track #\(track.id + 1): \(format.displayName) • output: verified MKV replacement at the same position"
        ]
        details.append(
            appliesEnglishOCRRules
                ? "Local English OCR review enabled from track language"
                : "English OCR review skipped: track language identifies another language"
        )
        if diagnosticCount > 0 {
            details.append("Structural normalization: \(diagnosticCount) item(s)")
        }
        return details.joined(separator: " • ")
    }

    static func title(_ change: SubtitleCleanupChange) -> String {
        if change.reasons.contains(.ytsAdvertisement) { return "Remove known YTS/YIFY ad block" }
        if change.reasons.contains(.spellingSuggestion) {
            return "Review possible English OCR spelling correction"
        }
        if change.reasons.contains(.ocrHighConfidence) {
            return "Fix high-confidence English OCR error"
        }
        return "Trim accidental edge whitespace"
    }

    static func detail(_ change: SubtitleCleanupChange) -> String {
        let before = change.before.lines.joined(separator: " / ")
        guard let after = change.after else { return "Remove: \(before)" }
        return "Before: \(before)   →   After: \(after.lines.joined(separator: " / "))"
    }

    static func title(_ change: AdvancedSubStationAlphaCleanupChange) -> String {
        if change.reasons.contains(.ytsAdvertisement) { return "Remove known YTS/YIFY ad event" }
        if change.reasons.contains(.spellingSuggestion) {
            return "Review possible English OCR spelling correction"
        }
        if change.reasons.contains(.ocrHighConfidence) {
            return "Fix high-confidence English OCR error"
        }
        return "Trim dialogue edge whitespace"
    }

    static func detail(_ change: AdvancedSubStationAlphaCleanupChange) -> String {
        guard let after = change.after else { return "Remove: \(change.before.text)" }
        return "Before: \(change.before.text)   →   After: \(after.text)"
    }

    static func time(_ timestamp: SubRipTimestamp) -> String {
        let milliseconds = max(0, timestamp.milliseconds)
        return String(
            format: "%02lld:%02lld:%02lld,%03lld",
            milliseconds / 3_600_000,
            (milliseconds / 60_000) % 60,
            (milliseconds / 1_000) % 60,
            milliseconds % 1_000
        )
    }

    static func selectedByDefault(reasons: Set<SubtitleCleanupReason>) -> Bool {
        !reasons.contains(.spellingSuggestion)
    }

    static func canConfirm(
        preview: SubtitleCleanupFilePreview,
        appliedChangeIDs: Set<Int>
    ) -> Bool {
        let allChangeIDs = Set(preview.cleanup.changes.map(\.id))
        let restoredCueIDs = allChangeIDs.subtracting(appliedChangeIDs)
        return !preview.cleanup.document(restoringCueIDs: restoredCueIDs).cues.isEmpty
    }

    static func canConfirm(
        preview: AdvancedSubtitleCleanupFilePreview,
        appliedChangeIDs: Set<Int>
    ) -> Bool {
        let allChangeIDs = Set(preview.cleanup.changes.map(\.id))
        let restoredEventIDs = allChangeIDs.subtracting(appliedChangeIDs)
        return !preview.cleanup.document(restoringEventIDs: restoredEventIDs).events.isEmpty
    }
}
