import AppKit
import MKVMagicExecution

@MainActor
final class VerifiedOutputProgressWindowController: NSWindowController {
    var onCancel: (() -> Void)?
    private let verifyingMessage: String
    private let committingMessage: String
    private let cancellingMessage: String
    private let totalUnitCount: Int
    private let progressUnitName: String
    private let statusLabel: NSTextField
    private let progressIndicator = NSProgressIndicator()
    private let progressSummaryLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    init(
        title: String,
        initialMessage: String,
        verifyingMessage: String,
        committingMessage: String,
        cancellingMessage: String,
        totalUnitCount: Int = VerifiedOutputExecutionStage.totalUnitCount,
        progressUnitName: String = "stages"
    ) {
        precondition(totalUnitCount > 0)
        self.verifyingMessage = verifyingMessage
        self.committingMessage = committingMessage
        self.cancellingMessage = cancellingMessage
        self.totalUnitCount = totalUnitCount
        self.progressUnitName = progressUnitName
        statusLabel = NSTextField(wrappingLabelWithString: initialMessage)
        let content = NSViewController()
        let window = NSPanel(contentViewController: content)
        window.title = title
        window.styleMask = [.titled]
        window.setContentSize(NSSize(width: 480, height: 202))
        super.init(window: window)

        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = Double(totalUnitCount)
        progressIndicator.doubleValue = 0
        progressIndicator.setAccessibilityLabel("Operation progress")
        progressIndicator.setAccessibilityHelp(
            "Determinate progress based on completed local stages, batch items, or an "
                + "MKVToolNix machine-reported percentage when that tool exposes one."
        )
        progressSummaryLabel.textColor = .secondaryLabelColor
        progressSummaryLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        progressSummaryLabel.setAccessibilityLabel("Progress summary")
        setCompletedUnitCount(0)
        statusLabel.setAccessibilityLabel("Execution status")
        statusLabel.setAccessibilityHelp(
            "Current local processing stage; the original remains unchanged before verified success."
        )
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityHelp(
            "Request cancellation and remove the temporary output; the original remains unchanged."
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancelButton])
        buttons.orientation = .horizontal
        // AppKit versions disagree slightly about the rounded button bezel's
        // trailing alignment inside a stack. Keep one extra native control gap
        // so the visible button remains inset on every supported macOS build.
        buttons.edgeInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: 0,
            right: MKVMagicLayoutMetrics.controlGap
        )
        let stack = NSStackView(
            views: [statusLabel, progressIndicator, progressSummaryLabel, buttons]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = MKVMagicLayoutMetrics.largeSectionGap
        stack.edgeInsets = MKVMagicLayoutMetrics.windowInsets
        stack.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
            stack.contentWidthConstraint(for: progressIndicator),
            stack.contentWidthConstraint(for: buttons),
        ])
        window.configureMKVMagicKeyboardNavigation(startingAt: cancelButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func losslessJoin() -> VerifiedOutputProgressWindowController {
        VerifiedOutputProgressWindowController(
            title: "Joining MKV Files",
            initialMessage: "Joining complete files…",
            verifyingMessage:
                "Verifying copied packet payloads, every join boundary, tracks, and chapters…",
            committingMessage: "Verification passed. Saving and auditing the final MKV…",
            cancellingMessage: "Cancelling and removing the temporary output…",
            totalUnitCount: VerifiedOutputExecutionStage.totalUnitCount
        )
    }

    static func trim(mode: TrimMode) -> VerifiedOutputProgressWindowController {
        VerifiedOutputProgressWindowController(
            title: mode == .fast ? "Fast Trimming MKV" : "Exact Trimming MKV",
            initialMessage:
                mode == .fast
                ? "Copying streams at the reviewed keyframe boundaries…"
                : "Encoding video once at the exact reviewed boundaries…",
            verifyingMessage:
                "Reopening the temporary MKV and verifying its range, tracks, and chapters…",
            committingMessage: "Verification passed. Saving and auditing the final MKV…",
            cancellingMessage: "Cancelling and removing the temporary output…",
            totalUnitCount: VerifiedOutputExecutionStage.totalUnitCount
        )
    }

    static func videoTranscode() -> VerifiedOutputProgressWindowController {
        VerifiedOutputProgressWindowController(
            title: "Converting Video",
            initialMessage: "Encoding the complete video once into a temporary MKV…",
            verifyingMessage:
                "Reopening the temporary MKV and verifying its format, tracks, and chapters…",
            committingMessage: "Verification passed. Saving and auditing the final MKV…",
            cancellingMessage: "Cancelling and removing the temporary output…",
            totalUnitCount: VerifiedOutputExecutionStage.totalUnitCount
        )
    }

    static func commonFormatJoin() -> VerifiedOutputProgressWindowController {
        VerifiedOutputProgressWindowController(
            title: "Joining MKV Files",
            initialMessage: "Normalizing only the incompatible lanes once…",
            verifyingMessage:
                "Verifying copied packet payloads, every join boundary, streams, and chapters…",
            committingMessage: "Verification passed. Saving and auditing the final MKV…",
            cancellingMessage:
                "Cancelling and removing the private stream bundle and temporary output…",
            totalUnitCount: CommonFormatJoinExecutionStage.totalUnitCount
        )
    }

    static func verifiedChange(
        title: String,
        initialMessage: String
    ) -> VerifiedOutputProgressWindowController {
        VerifiedOutputProgressWindowController(
            title: title,
            initialMessage: initialMessage,
            verifyingMessage: "Reopening and verifying the complete temporary output…",
            committingMessage: "Verification passed. Saving and auditing the final output…",
            cancellingMessage: "Cancelling and removing the temporary output…",
            totalUnitCount: VerifiedOutputExecutionStage.totalUnitCount
        )
    }

    static func batch(
        title: String,
        initialMessage: String,
        itemCount: Int
    ) -> VerifiedOutputProgressWindowController {
        VerifiedOutputProgressWindowController(
            title: title,
            initialMessage: initialMessage,
            verifyingMessage: "Finishing the batch…",
            committingMessage: "Finishing the batch…",
            cancellingMessage: "Cancelling after the current safe boundary…",
            totalUnitCount: itemCount,
            progressUnitName: "items"
        )
    }

    func beginSheet(for parentWindow: NSWindow) {
        guard let window else { return }
        parentWindow.beginSheet(window)
    }

    func update(stage: VerifiedOutputExecutionStage) {
        updateProgress(for: stage)
        switch stage {
        case .verifying:
            setStatus(verifyingMessage)
        case .committing:
            setStatus(committingMessage)
            cancelButton.isEnabled = false
            cancelButton.setAccessibilityHelp(
                "Cancellation is unavailable while the verified output is committed atomically."
            )
        }
    }

    func update(stage: CommonFormatJoinExecutionStage) {
        updateProgress(for: stage)
        switch stage {
        case .normalizing:
            setStatus("Normalizing only the incompatible lanes once…")
        case .assembling:
            setStatus(
                "Assembling normalized and packet-copy lanes into one temporary MKV…"
            )
        case .verifying:
            setStatus(verifyingMessage)
        case .committing:
            setStatus(committingMessage)
            cancelButton.isEnabled = false
            cancelButton.setAccessibilityHelp(
                "Cancellation is unavailable while the verified output is committed atomically."
            )
        }
    }

    func update(message: String) {
        setStatus(message)
    }

    func update(
        toolProgress: VerifiedOutputToolProgress,
        completedStageCount: Int = 0
    ) {
        let completed = min(max(0, completedStageCount), totalUnitCount - 1)
        progressIndicator.doubleValue =
            Double(completed) + toolProgress.fractionCompleted
        let phaseName: String
        let status: String
        switch toolProgress.phase {
        case .multiplexing:
            phaseName = "MKV assembly"
            status = "Assembling the temporary MKV… \(toolProgress.percentage)%"
        case .extractingTrack:
            phaseName = "track extraction"
            status = "Extracting the selected track… \(toolProgress.percentage)%"
        }
        setStatus(status)
        let summary =
            "\(toolProgress.percentage)% of current \(phaseName) • "
            + "\(completed) of \(totalUnitCount) \(progressUnitName) complete"
        progressSummaryLabel.stringValue = summary
        progressIndicator.setAccessibilityValue(summary)
    }

    func update(completedUnitCount: Int, message: String? = nil) {
        setCompletedUnitCount(completedUnitCount)
        if let message { setStatus(message) }
    }

    func finish() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
    }

    @objc private func cancel() {
        cancelButton.isEnabled = false
        setStatus(cancellingMessage)
        cancelButton.setAccessibilityHelp("Cancellation was requested; cleanup is in progress.")
        onCancel?()
    }

    private func setStatus(_ message: String) {
        AccessibleStatusPresentation.present(message, in: statusLabel)
    }

    private func updateProgress<Stage: BoundedExecutionStage>(for stage: Stage) {
        precondition(Stage.totalUnitCount == totalUnitCount)
        setCompletedUnitCount(stage.completedUnitCount)
    }

    private func setCompletedUnitCount(_ completedUnitCount: Int) {
        let completed = min(max(0, completedUnitCount), totalUnitCount)
        progressIndicator.doubleValue = Double(completed)
        let summary = "\(completed) of \(totalUnitCount) \(progressUnitName) complete"
        progressSummaryLabel.stringValue = summary
        progressIndicator.setAccessibilityValue(summary)
    }
}
