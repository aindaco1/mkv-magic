import AppKit
import MKVMagicCore
import MKVMagicExecution

@MainActor
final class ExternalSubtitleMuxWindowController: NSWindowController {
    private let muxViewController: ExternalSubtitleMuxViewController
    private var completion: ((ExternalSubtitleTrackMetadata?) -> Void)?

    convenience init(
        media: MediaAsset,
        preview: SubtitleCleanupFilePreview,
        match: ExternalSubtitleMatch
    ) {
        self.init(media: media, preview: .subRip(preview), match: match)
    }

    convenience init(
        media: MediaAsset,
        preview: AdvancedSubtitleCleanupFilePreview,
        match: ExternalSubtitleMatch
    ) {
        self.init(media: media, preview: .advanced(preview), match: match)
    }

    init(
        media: MediaAsset,
        preview: ExternalSubtitleFilePreview,
        match: ExternalSubtitleMatch,
        reviewedCleanupChangeCount: Int? = nil
    ) {
        muxViewController = ExternalSubtitleMuxViewController(
            media: media,
            preview: preview,
            match: match,
            reviewedCleanupChangeCount: reviewedCleanupChangeCount
        )
        let window = NSPanel(contentViewController: muxViewController)
        window.title = "Add External Subtitle"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 530))
        window.minSize = NSSize(width: 560, height: 500)
        window.tabbingMode = .disallowed
        window.initialFirstResponder = muxViewController.preferredInitialFirstResponder
        super.init(window: window)
        muxViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        muxViewController.onContinue = { [weak self] metadata in
            self?.finish(with: metadata)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (ExternalSubtitleTrackMetadata?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with metadata: ExternalSubtitleTrackMetadata?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(metadata)
        completion = nil
    }
}

@MainActor
final class ExternalSubtitleMuxViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onContinue: ((ExternalSubtitleTrackMetadata) -> Void)?

    private let media: MediaAsset
    private let preview: ExternalSubtitleFilePreview
    private let match: ExternalSubtitleMatch
    private let reviewedCleanupChangeCount: Int?
    private let languageField = NSComboBox()
    private let nameField = NSTextField()
    private let defaultCheck = NSButton(
        checkboxWithTitle: "Default subtitle", target: nil, action: nil)
    private let forcedCheck = NSButton(
        checkboxWithTitle: "Forced display", target: nil, action: nil)
    private let hearingCheck = NSButton(
        checkboxWithTitle: "Hearing impaired / SDH", target: nil, action: nil)
    private let validationLabel = NSTextField(wrappingLabelWithString: "")

    var preferredInitialFirstResponder: NSView { languageField }

    init(
        media: MediaAsset,
        preview: ExternalSubtitleFilePreview,
        match: ExternalSubtitleMatch,
        reviewedCleanupChangeCount: Int? = nil
    ) {
        self.media = media
        self.preview = preview
        self.match = match
        self.reviewedCleanupChangeCount = reviewedCleanupChangeCount
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Confirm subtitle and track details")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString:
                "MKV Magic will copy every existing stream and add this \(preview.format.displayName) subtitle as the last track. Video and audio are not encoded."
                + cleanupExplanation
        )
        explanation.textColor = .secondaryLabelColor

        let files = NSGridView(views: [
            [fieldLabel("Video"), valueLabel(media.sourceURL.lastPathComponent)],
            [fieldLabel("Subtitle"), valueLabel(preview.sourceURL.lastPathComponent)],
            [fieldLabel("Match"), valueLabel(ExternalSubtitleMuxPresentation.matchSummary(match))],
        ])
        files.rowSpacing = 8
        files.columnSpacing = 12
        files.column(at: 0).xPlacement = .trailing
        files.column(at: 1).width = 440

        languageField.addItems(withObjectValues: [
            "en", "en-US", "es", "fr", "de", "it", "pt", "ja", "ko", "zh", "und",
        ])
        languageField.placeholderString = "en, en-US, es, und…"
        languageField.stringValue = match.suggestedMetadata.language
        languageField.setAccessibilityLabel("Subtitle language tag")
        languageField.setAccessibilityHelp(
            "Confirm a language tag such as en, en-US, or und for undetermined."
        )
        nameField.placeholderString = "Optional display name"
        nameField.stringValue = match.suggestedMetadata.name ?? ""
        nameField.setAccessibilityLabel("Subtitle track name")
        nameField.setAccessibilityHelp("Set an optional subtitle name shown by media players.")
        defaultCheck.state = match.suggestedMetadata.isDefault ? .on : .off
        forcedCheck.state = match.suggestedMetadata.isForced ? .on : .off
        hearingCheck.state = match.suggestedMetadata.isHearingImpaired ? .on : .off

        let fields = NSGridView(views: [
            [fieldLabel("Language tag"), languageField],
            [fieldLabel("Track name"), nameField],
        ])
        fields.rowSpacing = 10
        fields.columnSpacing = 12
        fields.column(at: 0).xPlacement = .trailing
        fields.column(at: 1).width = 440

        let flags = NSStackView(views: [defaultCheck, forcedCheck, hearingCheck])
        flags.orientation = .vertical
        flags.alignment = .leading
        flags.spacing = 7

        let warnings = ExternalSubtitleMuxPresentation.warnings(
            preview: preview,
            match: match,
            cleanupWasReviewed: reviewedCleanupChangeCount != nil
        )
        let warningLabel = NSTextField(
            wrappingLabelWithString: warnings.isEmpty
                ? "The \(preview.format.displayName) subtitle is structurally normalized to UTF-8 in a private temporary copy. The selected subtitle remains unchanged."
                : warnings.map { "⚠︎ \($0)" }.joined(separator: "\n")
        )
        warningLabel.textColor = warnings.isEmpty ? .secondaryLabelColor : .systemOrange
        warningLabel.font = .systemFont(ofSize: 11)
        warningLabel.maximumNumberOfLines = 0
        warningLabel.setAccessibilityLabel("Subtitle match and cleanup warning")

        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        validationLabel.maximumNumberOfLines = 2
        validationLabel.setAccessibilityLabel("Subtitle track status")
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityHelp("Close without adding this subtitle to the plan.")
        let continueButton = NSButton(
            title: "Add to Plan", target: self, action: #selector(confirm))
        continueButton.keyEquivalent = "\r"
        continueButton.setAccessibilityHelp(
            "Accept these subtitle options and add one remux step to the reviewed plan."
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [validationLabel, spacer, cancelButton, continueButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 9

        let divider = separator()
        let stack = NSStackView(views: [
            heading, explanation, files, divider, fields, flags, warningLabel, actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        files.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        fields.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            files.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fields.widthAnchor.constraint(equalTo: stack.widthAnchor),
            warningLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
    }

    private var cleanupExplanation: String {
        guard let reviewedCleanupChangeCount else { return "" }
        let noun = reviewedCleanupChangeCount == 1 ? "change" : "changes"
        return reviewedCleanupChangeCount == 0
            ? " Cleanup was reviewed; no text changes were selected."
            : " \(reviewedCleanupChangeCount) reviewed cleanup \(noun) will be applied inside this same remux."
    }

    @objc private func cancel() { onCancel?() }

    @objc private func confirm() {
        do {
            let metadata = try ExternalSubtitleMuxPresentation.metadata(
                language: languageField.stringValue,
                name: nameField.stringValue,
                isDefault: defaultCheck.state == .on,
                isForced: forcedCheck.state == .on,
                isHearingImpaired: hearingCheck.state == .on
            )
            validationLabel.stringValue = ""
            onContinue?(metadata)
        } catch {
            validationLabel.stringValue = UserFacingErrorPresentation.message(
                failure: "Could not prepare the subtitle track.",
                recovery:
                    "No subtitle was added; review the language and track options and try again.",
                error: error
            )
        }
    }

    private func fieldLabel(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.alignment = .right
        return label
    }

    private func valueLabel(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = value
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}

enum ExternalSubtitleMuxPresentation {
    static func metadata(
        language: String,
        name: String,
        isDefault: Bool,
        isForced: Bool,
        isHearingImpaired: Bool
    ) throws -> ExternalSubtitleTrackMetadata {
        let canonicalLanguage = try TrackLanguageTag.canonical(language)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.contains("\0"), trimmedName.utf8.count <= 4_096 else {
            throw ExternalSubtitleMuxError.invalidTrackName
        }
        return ExternalSubtitleTrackMetadata(
            language: canonicalLanguage,
            name: trimmedName.isEmpty ? nil : trimmedName,
            isDefault: isDefault,
            isForced: isForced,
            isHearingImpaired: isHearingImpaired
        )
    }

    static func matchSummary(_ match: ExternalSubtitleMatch) -> String {
        let reasons = match.reasons.compactMap(reasonLabel).sorted()
        let detail =
            reasons.isEmpty ? "manual confirmation required" : reasons.joined(separator: ", ")
        return "\(match.confidence.rawValue.capitalized) confidence • \(detail)"
    }

    static func warnings(
        preview: SubtitleCleanupFilePreview,
        match: ExternalSubtitleMatch
    ) -> [String] {
        warnings(preview: .subRip(preview), match: match)
    }

    static func warnings(
        preview: AdvancedSubtitleCleanupFilePreview,
        match: ExternalSubtitleMatch
    ) -> [String] {
        warnings(preview: .advanced(preview), match: match)
    }

    static func warnings(
        preview: ExternalSubtitleFilePreview,
        match: ExternalSubtitleMatch,
        cleanupWasReviewed: Bool = false
    ) -> [String] {
        var values = [String]()
        if match.confidence == .low {
            values.append(
                "The filename is a weak match. Confirm that this subtitle belongs to the selected video."
            )
        }
        if match.isDurationCompatible == false,
            let difference = match.durationDifferenceMilliseconds
        {
            values.append(
                "Subtitle end time differs from the video by \(durationDifference(difference))."
            )
        }
        if preview.cleanupChangeCount > 0, !cleanupWasReviewed {
            values.append(
                "\(preview.cleanupChangeCount) cleanup suggestion(s) will not be applied. Use Clean Subtitle first if you want them."
            )
        }
        return values
    }

    private static func reasonLabel(_ reason: ExternalSubtitleMatchReason) -> String? {
        switch reason {
        case .exactBasename: "same filename"
        case .normalizedTitleAndYear: "same title/year"
        case .episodeIdentifier: "same episode"
        case .durationCompatible: "compatible timing"
        case .languageInFilename: "language inferred"
        case .forcedInFilename: "forced inferred"
        case .hearingImpairedInFilename: "SDH inferred"
        }
    }

    private static func durationDifference(_ milliseconds: Int64) -> String {
        let seconds = abs(Double(milliseconds) / 1_000)
        let direction = milliseconds < 0 ? "shorter" : "longer"
        if seconds >= 60 {
            return String(format: "%.1f minutes \(direction)", seconds / 60)
        }
        return String(format: "%.1f seconds \(direction)", seconds)
    }
}
