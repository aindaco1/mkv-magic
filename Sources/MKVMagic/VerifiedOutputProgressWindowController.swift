import AppKit
import MKVMagicExecution

@MainActor
final class VerifiedOutputProgressWindowController: NSWindowController {
    var onCancel: (() -> Void)?
    private let verifyingMessage: String
    private let committingMessage: String
    private let cancellingMessage: String
    private let statusLabel: NSTextField
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    init(
        title: String,
        initialMessage: String,
        verifyingMessage: String,
        committingMessage: String,
        cancellingMessage: String
    ) {
        self.verifyingMessage = verifyingMessage
        self.committingMessage = committingMessage
        self.cancellingMessage = cancellingMessage
        statusLabel = NSTextField(wrappingLabelWithString: initialMessage)
        let content = NSViewController()
        let window = NSPanel(contentViewController: content)
        window.title = title
        window.styleMask = [.titled]
        window.setContentSize(NSSize(width: 480, height: 180))
        super.init(window: window)

        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        progress.setAccessibilityLabel("Verified output progress")
        progress.setAccessibilityHelp(
            "Indeterminate progress while MKV Magic creates, verifies, and commits one output."
        )
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
        let stack = NSStackView(views: [statusLabel, progress, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = MKVMagicLayoutMetrics.largeSectionGap
        stack.edgeInsets = MKVMagicLayoutMetrics.windowInsets
        stack.translatesAutoresizingMaskIntoConstraints = false
        progress.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
            stack.contentWidthConstraint(for: progress),
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
            cancellingMessage: "Cancelling and removing the temporary output…"
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
            cancellingMessage: "Cancelling and removing the temporary output…"
        )
    }

    static func videoTranscode() -> VerifiedOutputProgressWindowController {
        VerifiedOutputProgressWindowController(
            title: "Converting Video",
            initialMessage: "Encoding the complete video once into a temporary MKV…",
            verifyingMessage:
                "Reopening the temporary MKV and verifying its format, tracks, and chapters…",
            committingMessage: "Verification passed. Saving and auditing the final MKV…",
            cancellingMessage: "Cancelling and removing the temporary output…"
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
                "Cancelling and removing the private stream bundle and temporary output…"
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
            cancellingMessage: "Cancelling and removing the temporary output…"
        )
    }

    func beginSheet(for parentWindow: NSWindow) {
        guard let window else { return }
        parentWindow.beginSheet(window)
    }

    func update(stage: VerifiedOutputExecutionStage) {
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
}
