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
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancelButton])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [statusLabel, progress, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        progress.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
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

    func beginSheet(for parentWindow: NSWindow) {
        guard let window else { return }
        parentWindow.beginSheet(window)
    }

    func update(stage: VerifiedOutputExecutionStage) {
        switch stage {
        case .verifying:
            statusLabel.stringValue = verifyingMessage
        case .committing:
            statusLabel.stringValue = committingMessage
            cancelButton.isEnabled = false
        }
    }

    func update(stage: CommonFormatJoinExecutionStage) {
        switch stage {
        case .normalizing:
            statusLabel.stringValue = "Normalizing only the incompatible lanes once…"
        case .assembling:
            statusLabel.stringValue =
                "Assembling normalized and packet-copy lanes into one temporary MKV…"
        case .verifying:
            statusLabel.stringValue = verifyingMessage
        case .committing:
            statusLabel.stringValue = committingMessage
            cancelButton.isEnabled = false
        }
    }

    func finish() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
    }

    @objc private func cancel() {
        cancelButton.isEnabled = false
        statusLabel.stringValue = cancellingMessage
        onCancel?()
    }
}
