import AppKit
import MKVMagicCore

private final class AttachmentRemovalRowsView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class AttachmentRemovalWindowController: NSWindowController {
    private let removalViewController: AttachmentRemovalViewController
    private var completion: ((MatroskaAttachmentRemoval?) -> Void)?

    init(attachments: [MediaAttachment]) {
        removalViewController = AttachmentRemovalViewController(attachments: attachments)
        let window = NSPanel(contentViewController: removalViewController)
        window.title = "Remove Attachments"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 660, height: 460))
        window.minSize = NSSize(width: 560, height: 400)
        window.tabbingMode = .disallowed
        window.configureMKVMagicKeyboardNavigation(
            startingAt: removalViewController.preferredInitialFirstResponder
        )
        super.init(window: window)
        removalViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        removalViewController.onContinue = { [weak self] removal in
            self?.finish(with: removal)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (MatroskaAttachmentRemoval?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            self.completion = nil
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with removal: MatroskaAttachmentRemoval?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(removal)
        completion = nil
    }
}

@MainActor
final class AttachmentRemovalViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onContinue: ((MatroskaAttachmentRemoval) -> Void)?
    private let attachments: [MediaAttachment]
    private var checkboxes = [NSButton]()
    private let statusLabel = NSTextField(labelWithString: "")
    private let reviewButton = NSButton(
        title: "Review Removal",
        target: nil,
        action: nil
    )

    var preferredInitialFirstResponder: NSView {
        checkboxes.first ?? reviewButton
    }

    init(attachments: [MediaAttachment]) {
        self.attachments = attachments
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Choose attachments to remove")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString:
                "Checked attachments will be omitted from a new MKV. Media tracks, tags, and nested chapters are copied without encoding; the original stays untouched."
        )
        explanation.textColor = .secondaryLabelColor

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 9
        checkboxes = attachments.map { attachment in
            let checkbox = NSButton(
                checkboxWithTitle: AttachmentPickerViewController.title(attachment),
                target: self,
                action: #selector(selectionChanged)
            )
            checkbox.setAccessibilityHelp(
                "Remove this attachment from the verified MKV copy."
            )
            checkbox.lineBreakMode = .byTruncatingMiddle
            rows.addArrangedSubview(checkbox)
            return checkbox
        }
        let document = AttachmentRemovalRowsView()
        document.translatesAutoresizingMaskIntoConstraints = false
        rows.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rows)
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            rows.trailingAnchor.constraint(
                lessThanOrEqualTo: document.trailingAnchor, constant: -12),
            rows.topAnchor.constraint(equalTo: document.topAnchor, constant: 10),
            rows.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -10),
        ])

        let note = NSTextField(
            wrappingLabelWithString:
                "MKV Magic re-inspects the source, resolves your choices by stable attachment UID, then verifies every retained media and metadata fact before saving."
        )
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.setAccessibilityLabel("Attachment removal status")
        let cancelButton = NSButton(
            title: "Cancel",
            target: self,
            action: #selector(cancel)
        )
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityHelp("Close without removing any attachments.")
        reviewButton.target = self
        reviewButton.action = #selector(review)
        reviewButton.keyEquivalent = "\r"
        reviewButton.setAccessibilityHelp(
            "Review the selected omissions before creating a verified MKV copy."
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [statusLabel, spacer, cancelButton, reviewButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let stack = NSStackView(views: [heading, explanation, scroll, note, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        note.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 210),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
        ])
        view = root
    }

    @objc private func selectionChanged() {
        statusLabel.stringValue = ""
    }

    @objc private func cancel() {
        onCancel?()
    }

    @objc private func review() {
        do {
            let selectedIndexes = Set(
                checkboxes.indices.filter { checkboxes[$0].state == .on }
            )
            let removal = try AttachmentRemovalPresentation.removal(
                attachments: attachments,
                selectedIndexes: selectedIndexes
            )
            statusLabel.stringValue = ""
            onContinue?(removal)
        } catch {
            AccessibleStatusPresentation.present(
                UserFacingErrorPresentation.message(
                    failure: "Could not prepare attachment removal.",
                    recovery: "No attachments were removed; revise the selection and try again.",
                    error: error
                ),
                in: statusLabel,
                returningFocusTo: preferredInitialFirstResponder
            )
        }
    }
}

enum AttachmentRemovalPresentationError: Error, Equatable {
    case emptySelection
    case unsafeAttachment
}

extension AttachmentRemovalPresentationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptySelection: "Check at least one attachment to remove."
        case .unsafeAttachment: "One selected attachment cannot be addressed safely."
        }
    }
}

enum AttachmentRemovalPresentation {
    static func removal(
        attachments: [MediaAttachment],
        selectedIndexes: Set<Int>
    ) throws -> MatroskaAttachmentRemoval {
        guard !selectedIndexes.isEmpty else {
            throw AttachmentRemovalPresentationError.emptySelection
        }
        let selected = attachments.indices.compactMap { index in
            selectedIndexes.contains(index) ? attachments[index] : nil
        }
        let selectedUIDs = selected.compactMap(\.uid)
        guard selected.count == selectedIndexes.count,
            selectedUIDs.count == selected.count,
            Set(selectedUIDs).count == selectedUIDs.count
        else {
            throw AttachmentRemovalPresentationError.unsafeAttachment
        }
        return MatroskaAttachmentRemoval(attachmentUIDs: Set(selectedUIDs))
    }
}
