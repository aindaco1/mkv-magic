import AppKit

@MainActor
final class HelpWindowController: NSWindowController {
    init() {
        let content = HelpViewController()
        let window = NSWindow(contentViewController: content)
        window.title = "MKV Magic Help"
        window.setContentSize(NSSize(width: 620, height: 520))
        window.minSize = NSSize(width: 520, height: 420)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.configureMKVMagicKeyboardNavigation(
            startingAt: content.preferredInitialFirstResponder
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class HelpViewController: NSViewController {
    private let topics = NSTextView()

    var preferredInitialFirstResponder: NSView { topics }

    override func loadView() {
        let heading = NSTextField(labelWithString: "MKV Magic Help")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let introduction = NSTextField(
            wrappingLabelWithString:
                "Prepare Matroska and other video files locally, with review before every output."
        )
        introduction.textColor = .secondaryLabelColor

        topics.isEditable = false
        topics.isRichText = false
        topics.isSelectable = true
        topics.drawsBackground = false
        topics.font = .systemFont(ofSize: 13)
        topics.string = Self.helpText
        topics.textContainerInset = NSSize(width: 4, height: 4)
        topics.setAccessibilityLabel("MKV Magic help topics")
        topics.setAccessibilityHelp(
            "Getting started, output safety, encoding, workflows, and keyboard shortcuts."
        )
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = topics

        let close = NSButton(
            title: "Close",
            target: self,
            action: #selector(closeHelp)
        )
        close.keyEquivalent = "\u{1b}"
        close.setAccessibilityLabel("Close MKV Magic Help")
        close.setAccessibilityHelp("Closes this local help window.")

        let actions = NSStackView(views: [NSView(), close])
        actions.orientation = .horizontal
        let stack = NSStackView(views: [heading, introduction, scroll, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        view = root
    }

    @objc private func closeHelp() {
        view.window?.performClose(nil)
    }

    private static let helpText = """
        GETTING STARTED
        1. Open media with Command-O, the Choose Files or Folder button, or drag and drop.
        2. Select a file and choose a task such as metadata, tracks, subtitles, chapters, trim, or join.
        3. Review the planned stages, encoding impact, destination, and source-safety note.
        4. Save or queue the reviewed job. MKV is the default output container.

        OUTPUT SAFETY
        MKV Magic creates and verifies a separate output before it reports success. By default, it saves automatically beside the source without opening a save panel. In MKV Magic > Settings, you can instead remember one output folder or ask where to save every time. Existing files are never overwritten; automatic outputs receive a number when needed. Originals remain unchanged by default. Moving originals to Trash is explicit, optional, and happens only after verified success.

        WHEN MKV MAGIC ENCODES
        Metadata edits use MKVToolNix without encoding. Track removal, subtitle muxing, and compatible joins remux or copy streams. If a workflow truly needs video encoding, its video work is fused into one final pass. AV1 is preferred when its encoder is locally verified; compatible HEVC or H.264 choices remain available.

        SAVED WORKFLOWS AND QUEUE
        Workflows store portable intent rather than private media paths. Preview a workflow against inspected media before saving or queuing it. The Queue and History windows preserve reviewable local state and privacy-safe status details.

        KEYBOARD
        Command-O: open media
        Command-0: main window
        Command-1: workflows
        Command-2: queue
        Command-3: history
        Command-4: encoding test
        Command-Comma: output-location settings
        Command-S: save in the workflow editor
        Delete or Forward Delete: remove every selected file from the main list without deleting the source files
        Escape: cancel or close reviews where it is safe to do so

        PRIVACY
        Media processing, inspection, workflow planning, history, and support reports stay local. MKV Magic has no accounts, analytics, uploads, telemetry, or LLM dependency. Update checks occur only when you choose Check for Updates.

        LICENSES AND NOTICES
        Choose Help > Third-Party Software to read the notices and full license texts shipped inside your installed copy of MKV Magic.

        TROUBLESHOOTING
        If a file is unavailable, select the real local file instead of a link and read the disabled control's prerequisite. If an output is refused, keep the original, choose a new destination, reinspect the source, and review the plan again. Queue jobs that are interrupted, stale, or changed require review instead of silent retry. History can export a bounded privacy-safe report when you choose.
        """
}
