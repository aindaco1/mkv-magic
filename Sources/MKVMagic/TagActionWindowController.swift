import AppKit
import MKVMagicCore

enum MatroskaTagAction: Equatable {
    case exportXML
    case removeAll
}

@MainActor
final class TagActionWindowController: NSWindowController {
    private var completion: ((MatroskaTagAction?) -> Void)?

    init(counts: MatroskaTagCounts) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Matroska Tags"
        window.isReleasedWhenClosed = false
        window.setAccessibilityLabel("Matroska tag actions")
        super.init(window: window)

        let heading = NSTextField(labelWithString: "Choose what to do with these tags")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)

        let globalNoun = counts.global == 1 ? "tag" : "tags"
        let trackNoun = counts.track == 1 ? "tag" : "tags"
        let summary = NSTextField(
            wrappingLabelWithString:
                "This MKV contains \(counts.global) global \(globalNoun) and \(counts.track) track \(trackNoun)."
        )
        summary.setAccessibilityLabel(
            "\(counts.global) global tags and \(counts.track) track tags"
        )

        let explanation = NSTextField(
            wrappingLabelWithString:
                "Export creates an exact XML sidecar and leaves the MKV untouched. Removal creates a new verified MKV copy with every global and track tag cleared; tracks, title, chapters, and attachments stay in place."
        )
        explanation.textColor = .secondaryLabelColor

        let exportButton = NSButton(
            title: "Export XML…",
            target: self,
            action: #selector(exportXML)
        )
        exportButton.keyEquivalent = "\r"
        exportButton.setAccessibilityHelp(
            "Review an exact bounded XML export without changing the MKV."
        )
        let removeButton = NSButton(
            title: "Review Removal…",
            target: self,
            action: #selector(removeAll)
        )
        removeButton.setAccessibilityHelp(
            "Review clearing every global and track tag from a new verified MKV copy."
        )
        let cancelButton = NSButton(
            title: "Cancel",
            target: self,
            action: #selector(cancel)
        )
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [cancelButton, removeButton, exportButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSView()
        buttonRow.addSubview(buttons)

        let stack = NSStackView(views: [heading, summary, explanation, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        buttons.alignment = .centerY
        buttons.setContentHuggingPriority(.required, for: .horizontal)

        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            summary.widthAnchor.constraint(equalTo: stack.widthAnchor),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: buttonRow.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: buttonRow.topAnchor),
            buttons.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor),
        ])
        window.tabbingMode = .disallowed
        window.configureMKVMagicKeyboardNavigation(startingAt: exportButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parent: NSWindow,
        completion: @escaping (MatroskaTagAction?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            completion(nil)
            return
        }
        parent.beginSheet(window)
    }

    @objc private func exportXML() { finish(.exportXML) }
    @objc private func removeAll() { finish(.removeAll) }
    @objc private func cancel() { finish(nil) }

    private func finish(_ action: MatroskaTagAction?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        let completion = completion
        self.completion = nil
        completion?(action)
    }
}
