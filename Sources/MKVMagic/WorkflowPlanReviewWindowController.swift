import AppKit
import MKVMagicCore
import MKVMagicPlanning

@MainActor
final class WorkflowPlanReviewWindowController: NSWindowController {
    private let preview: SavedWorkflowCompilationPreview
    private var completion: ((Bool) -> Void)?

    init(preview: SavedWorkflowCompilationPreview, sourceDisplayName: String) {
        self.preview = preview
        let content = NSViewController()
        let panel = NSPanel(contentViewController: content)
        panel.title = "Workflow Preview"
        panel.styleMask = [.titled, .resizable]
        panel.setContentSize(NSSize(width: 620, height: 500))
        panel.minSize = NSSize(width: 540, height: 420)
        super.init(window: panel)

        let heading = NSTextField(
            labelWithString: preview.compiledWorkflow == nil
                ? "This file already matches" : "Review what will change"
        )
        heading.font = .systemFont(ofSize: 20, weight: .semibold)

        let context = NSTextField(
            wrappingLabelWithString:
                "\(preview.workflowName) • \(sourceDisplayName)"
        )
        context.textColor = .secondaryLabelColor
        context.lineBreakMode = .byTruncatingMiddle
        context.setAccessibilityLabel("Workflow and source")

        let impact = NSTextField(
            wrappingLabelWithString: WorkflowPlanReviewPresentation.impactSummary(for: preview)
        )
        impact.font = .systemFont(ofSize: 13, weight: .medium)
        impact.setAccessibilityLabel("Encoding impact")

        let outcomeStack = WorkflowOutcomeStackView()
        outcomeStack.orientation = .vertical
        outcomeStack.alignment = .leading
        outcomeStack.spacing = 12
        outcomeStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        for outcome in preview.stepOutcomes {
            outcomeStack.addArrangedSubview(Self.outcomeRow(outcome))
        }

        let scroll = NSScrollView()
        scroll.documentView = outcomeStack
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setAccessibilityLabel("Workflow step outcomes")
        scroll.setAccessibilityHelp(
            "Lists each enabled, already satisfied, or disabled workflow card."
        )

        let safety = NSTextField(
            wrappingLabelWithString: preview.compiledWorkflow == nil
                ? "No output will be created."
                : "MKV Magic will create and verify one new MKV. The source file will not be changed."
        )
        safety.textColor = .secondaryLabelColor
        safety.setAccessibilityLabel("Source safety")

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        let primary = NSButton(
            title: preview.compiledWorkflow == nil ? "Done" : "Use This Plan",
            target: self,
            action: #selector(accept)
        )
        primary.keyEquivalent = "\r"
        primary.setAccessibilityHelp(
            preview.compiledWorkflow == nil
                ? "Close this review without creating an output."
                : "Accept this exact plan and enable Verify and Run."
        )
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityHelp("Close this review without accepting the plan.")
        if preview.compiledWorkflow == nil { cancel.isHidden = true }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, primary])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let stack = NSStackView(views: [heading, context, impact, scroll, safety, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        outcomeStack.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 230),
            outcomeStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        panel.configureMKVMagicKeyboardNavigation(startingAt: primary)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(for parentWindow: NSWindow, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        guard let window else { return }
        parentWindow.beginSheet(window)
    }

    private static func outcomeRow(_ outcome: SavedWorkflowStepOutcome) -> NSView {
        let symbol =
            NSImage(
                systemSymbolName: WorkflowPlanReviewPresentation.symbolName(for: outcome),
                accessibilityDescription: WorkflowPlanReviewPresentation.statusLabel(for: outcome)
            ) ?? NSImage()
        let image = NSImageView(image: symbol)
        image.contentTintColor = WorkflowPlanReviewPresentation.color(for: outcome)
        image.symbolConfiguration = .init(pointSize: 15, weight: .semibold)

        let title = NSTextField(labelWithString: outcome.action.displayName)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        let detail = NSTextField(wrappingLabelWithString: outcome.detail)
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 12)
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = NSStackView(views: [image, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        return row
    }

    @objc private func cancel() { finish(accepted: false) }

    @objc private func accept() { finish(accepted: preview.compiledWorkflow != nil) }

    private func finish(accepted: Bool) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        let completion = completion
        self.completion = nil
        completion?(accepted)
    }
}

private final class WorkflowOutcomeStackView: NSStackView {
    override var isFlipped: Bool { true }
}

enum WorkflowPlanReviewPresentation {
    static func impactSummary(for preview: SavedWorkflowCompilationPreview) -> String {
        guard let compiled = preview.compiledWorkflow else {
            return "No applicable changes • No output"
        }
        return impactSummary(for: compiled)
    }

    static func impactSummary(for compiled: CompiledSavedWorkflow) -> String {
        if compiled.createsUnchangedCopy {
            return "No transcoding • byte-identical file copy"
        }
        let mechanisms = compiled.plan.stages.compactMap { stage -> String? in
            switch stage.mechanism {
            case .mkvMerge: "one MKV remux"
            case .mkvPropEdit: "one metadata pass"
            case .ffmpegStreamCopy: "one FFmpeg stream-copy pass"
            case .ffmpegEncode: "one FFmpeg encode pass"
            case .verify, .commit: nil
            }
        }
        let impact = compiled.plan.impact
        let encoding: String
        switch (impact.videoEncodeCount, impact.audioEncodeCount) {
        case (0, 0): encoding = "No transcoding"
        case (0, let audio): encoding = "\(audio) audio encode" + (audio == 1 ? "" : "s")
        case (let video, 0): encoding = "\(video) video encode" + (video == 1 ? "" : "s")
        case (let video, let audio):
            encoding = "\(video) video + \(audio) audio encodes"
        }
        return ([encoding] + mechanisms).joined(separator: " • ")
    }

    static func statusLabel(for outcome: SavedWorkflowStepOutcome) -> String {
        switch outcome.disposition {
        case .applied: "Will apply"
        case .skipped: "Already satisfied"
        case .disabled: "Disabled"
        }
    }

    static func symbolName(for outcome: SavedWorkflowStepOutcome) -> String {
        switch outcome.disposition {
        case .applied: "checkmark.circle.fill"
        case .skipped: "arrow.right.circle"
        case .disabled: "minus.circle"
        }
    }

    static func color(for outcome: SavedWorkflowStepOutcome) -> NSColor {
        switch outcome.disposition {
        case .applied: .systemGreen
        case .skipped: .systemOrange
        case .disabled: .secondaryLabelColor
        }
    }
}
