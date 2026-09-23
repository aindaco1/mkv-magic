import AppKit
import MKVMagicCore

struct ChapterSuggestionCapabilities: Equatable, Sendable {
    let hasVideo: Bool
    let hasAudio: Bool
    let fileCount: Int

    init(hasVideo: Bool, hasAudio: Bool, fileCount: Int = 1) {
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.fileCount = max(1, fileCount)
    }
}

@MainActor
final class ChapterSuggestionOptionsWindowController: NSWindowController {
    private let content: ChapterSuggestionOptionsViewController
    private var completion: ((ChapterSuggestionOptions?) -> Void)?

    init(capabilities: ChapterSuggestionCapabilities) {
        content = ChapterSuggestionOptionsViewController(capabilities: capabilities)
        let window = NSPanel(contentViewController: content)
        window.title = "Suggest Chapters"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 370))
        window.minSize = NSSize(width: 500, height: 350)
        window.configureMKVMagicKeyboardNavigation(
            startingAt: content.preferredInitialFirstResponder
        )
        super.init(window: window)
        content.onCancel = { [weak self] in self?.finish(with: nil) }
        content.onAnalyze = { [weak self] options in self?.finish(with: options) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (ChapterSuggestionOptions?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    func cancel() {
        finish(with: nil)
    }

    private func finish(with options: ChapterSuggestionOptions?) {
        guard let completion else { return }
        if let window {
            window.sheetParent?.endSheet(window)
        }
        self.completion = nil
        completion(options)
    }
}

@MainActor
private final class ChapterSuggestionOptionsViewController: NSViewController, NSTextFieldDelegate {
    var onCancel: (() -> Void)?
    var onAnalyze: ((ChapterSuggestionOptions) -> Void)?

    private let capabilities: ChapterSuggestionCapabilities
    private let sceneCheck = NSButton(
        checkboxWithTitle: "Scene changes", target: nil, action: nil)
    private let blackCheck = NSButton(
        checkboxWithTitle: "Black frames", target: nil, action: nil)
    private let silenceCheck = NSButton(
        checkboxWithTitle: "Silence", target: nil, action: nil)
    private let spacingField = NSTextField(string: "60")
    private let validationLabel = NSTextField(wrappingLabelWithString: "")
    private let analyzeButton = NSButton(title: "Analyze", target: nil, action: nil)

    var preferredInitialFirstResponder: NSView {
        if sceneCheck.isEnabled { return sceneCheck }
        if blackCheck.isEnabled { return blackCheck }
        return silenceCheck
    }

    init(capabilities: ChapterSuggestionCapabilities) {
        self.capabilities = capabilities
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Suggest chapter boundaries")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)

        let subject =
            capabilities.fileCount == 1
            ? "the selected file" : "each of the \(capabilities.fileCount) selected files"
        let explanation = NSTextField(
            wrappingLabelWithString:
                "MKV Magic analyzes \(subject) locally with bundled FFmpeg. Every timestamp is reviewed before it is added, and every original remains unchanged."
        )
        explanation.textColor = AppPalette.secondaryText
        explanation.maximumNumberOfLines = 0

        configureDetector(sceneCheck, available: capabilities.hasVideo)
        configureDetector(blackCheck, available: capabilities.hasVideo)
        configureDetector(silenceCheck, available: capabilities.hasAudio)

        let detectorHeading = NSTextField(labelWithString: "Look for")
        detectorHeading.font = .systemFont(ofSize: 13, weight: .semibold)
        let detectors = NSStackView(views: [
            detectorHeading, sceneCheck, blackCheck, silenceCheck,
        ])
        detectors.orientation = .vertical
        detectors.alignment = .leading
        detectors.spacing = MKVMagicLayoutMetrics.controlGap

        spacingField.alignment = .right
        spacingField.delegate = self
        spacingField.setAccessibilityLabel("Minimum seconds between suggestions")
        spacingField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let spacingRow = NSStackView(views: [
            NSTextField(labelWithString: "Keep suggestions at least"),
            spacingField,
            NSTextField(labelWithString: "seconds apart"),
        ])
        spacingRow.orientation = .horizontal
        spacingRow.alignment = .centerY
        spacingRow.spacing = MKVMagicLayoutMetrics.controlGap

        validationLabel.textColor = AppPalette.errorText
        validationLabel.maximumNumberOfLines = 2
        validationLabel.setAccessibilityLabel("Chapter suggestion settings error")
        validationLabel.isHidden = true

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        analyzeButton.target = self
        analyzeButton.action = #selector(analyze)
        analyzeButton.keyEquivalent = "\r"
        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [actionSpacer, cancelButton, analyzeButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = MKVMagicLayoutMetrics.controlGap

        let stack = NSStackView(views: [
            heading, explanation, detectors, spacingRow, validationLabel, actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = MKVMagicLayoutMetrics.sectionGap
        stack.edgeInsets = MKVMagicLayoutMetrics.windowInsets
        stack.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
            stack.contentWidthConstraint(for: explanation),
            stack.contentWidthConstraint(for: validationLabel),
            stack.contentWidthConstraint(for: actions),
        ])
        view = root
        updateAnalyzeAvailability()
    }

    private func configureDetector(_ button: NSButton, available: Bool) {
        button.target = self
        button.action = #selector(detectorChanged)
        button.state = available ? .on : .off
        button.isEnabled = available
        if !available {
            button.toolTip =
                button === silenceCheck
                ? "No selected file has an audio track."
                : "No selected file has a video track."
        }
    }

    @objc private func detectorChanged() {
        updateAnalyzeAvailability()
    }

    func controlTextDidChange(_ notification: Notification) {
        updateAnalyzeAvailability()
    }

    @objc private func analyze() {
        guard view.window?.makeFirstResponder(nil) != false else { return }
        do {
            onAnalyze?(try currentOptions())
        } catch {
            showValidation(UserFacingErrorPresentation.shortReason(error))
            view.window?.makeFirstResponder(spacingField)
        }
    }

    private func currentOptions() throws -> ChapterSuggestionOptions {
        guard let seconds = Double(spacingField.stringValue), seconds.isFinite, seconds >= 0,
            let spacing = MediaTime(seconds: seconds)
        else {
            throw ChapterSpacingInputError.invalidSpacing
        }
        var options = ChapterSuggestionOptions()
        options.detectsSceneChanges = sceneCheck.state == .on
        options.detectsBlackFrames = blackCheck.state == .on
        options.detectsSilence = silenceCheck.state == .on
        options.minimumSpacing = spacing
        return try options.validated()
    }

    @objc private func cancel() {
        onCancel?()
    }

    private func updateAnalyzeAvailability() {
        do {
            _ = try currentOptions()
            analyzeButton.isEnabled = true
            validationLabel.stringValue = ""
            validationLabel.isHidden = true
        } catch {
            analyzeButton.isEnabled = false
            showValidation(UserFacingErrorPresentation.shortReason(error))
        }
    }

    private func showValidation(_ message: String) {
        validationLabel.stringValue = message
        validationLabel.isHidden = false
    }
}

private enum ChapterSpacingInputError: LocalizedError {
    case invalidSpacing

    var errorDescription: String? {
        "Minimum spacing must be a nonnegative number of seconds."
    }
}
