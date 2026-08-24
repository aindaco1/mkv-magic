import AppKit
import MKVMagicCore

@MainActor
final class AttachmentPickerWindowController: NSWindowController {
    private let pickerViewController: AttachmentPickerViewController
    private var completion: ((MediaAttachment?) -> Void)?

    init(attachments: [MediaAttachment]) {
        pickerViewController = AttachmentPickerViewController(attachments: attachments)
        let window = NSPanel(contentViewController: pickerViewController)
        window.title = "Choose Attachment to Extract"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 280))
        window.minSize = NSSize(width: 540, height: 260)
        window.tabbingMode = .disallowed
        window.configureMKVMagicKeyboardNavigation(
            startingAt: pickerViewController.preferredInitialFirstResponder
        )
        super.init(window: window)
        pickerViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        pickerViewController.onContinue = { [weak self] attachment in
            self?.finish(with: attachment)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (MediaAttachment?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with attachment: MediaAttachment?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(attachment)
        completion = nil
    }
}

@MainActor
final class AttachmentPickerViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onContinue: ((MediaAttachment) -> Void)?
    private let attachments: [MediaAttachment]
    private let attachmentPopup = NSPopUpButton()
    private let validationLabel = NSTextField(labelWithString: "")

    var preferredInitialFirstResponder: NSView { attachmentPopup }

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
        let heading = NSTextField(labelWithString: "Choose an attachment to extract")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString:
                "MKV Magic copies one embedded font, image, or other attachment into a separate file. The MKV remains unchanged."
        )
        explanation.textColor = .secondaryLabelColor
        attachmentPopup.addItems(withTitles: attachments.map(Self.title))
        attachmentPopup.setAccessibilityLabel("Matroska attachment")
        attachmentPopup.setAccessibilityHelp(
            "Choose one bounded attachment with a stable Matroska identity to extract exactly."
        )
        let selector = NSGridView(views: [
            [NSTextField(labelWithString: "Attachment"), attachmentPopup]
        ])
        selector.rowSpacing = 8
        selector.columnSpacing = 12
        selector.column(at: 0).xPlacement = .trailing
        selector.column(at: 1).width = 430

        let note = NSTextField(
            wrappingLabelWithString:
                "Review extracts privately. Save repeats the extraction and commits only the exact reviewed bytes after reopening the result."
        )
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        validationLabel.setAccessibilityLabel("Attachment selection status")
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityHelp("Close without extracting or saving an attachment.")
        let review = NSButton(
            title: "Review Extraction", target: self, action: #selector(reviewAction))
        review.keyEquivalent = "\r"
        review.isEnabled = !attachments.isEmpty
        review.setAccessibilityHelp(
            "Extract the selected attachment privately and prepare an exact verified save plan."
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [validationLabel, spacer, cancel, review])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let stack = NSStackView(views: [heading, explanation, selector, note, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        selector.translatesAutoresizingMaskIntoConstraints = false
        note.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            selector.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
    }

    @objc private func cancelAction() { onCancel?() }

    @objc private func reviewAction() {
        guard attachments.indices.contains(attachmentPopup.indexOfSelectedItem) else {
            validationLabel.stringValue = "Choose an attachment to extract."
            return
        }
        validationLabel.stringValue = ""
        onContinue?(attachments[attachmentPopup.indexOfSelectedItem])
    }

    static func title(_ attachment: MediaAttachment) -> String {
        let sanitizedFilename = attachment.filename.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? "�" : String(scalar)
        }.joined()
        let filename =
            sanitizedFilename.count > 160
            ? String(sanitizedFilename.prefix(159)) + "…" : sanitizedFilename
        let rawMIMEType = attachment.mimeType ?? "unknown type"
        let mimeType =
            rawMIMEType.count > 80
            ? String(rawMIMEType.prefix(79)) + "…" : rawMIMEType
        let size = attachment.size.map(ByteCountFormatter.string) ?? "Unknown size"
        return [
            "#\(attachment.id)",
            filename,
            mimeType,
            size,
        ].joined(separator: " • ")
    }
}

extension ByteCountFormatter {
    fileprivate static func string(_ byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: byteCount)
    }
}
