import AppKit

/// Layout shared by the small native editors. Validation remains with each flow.
@MainActor
enum NativeFormLayout {
    static func scrollingForm(_ form: NSView) -> NSScrollView {
        let document = NativeFormChoicesDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        form.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(form)
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            form.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            form.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            form.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -4),
        ])
        return scroll
    }

    static func configureLabeledGrid(_ grid: NSGridView) {
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        // Let values use the remaining width instead of stretching the label
        // column and squeezing a long filename down to a few characters.
        grid.column(at: 0).width =
            (0..<grid.numberOfRows).compactMap {
                grid.cell(atColumnIndex: 0, rowIndex: $0).contentView?.intrinsicContentSize.width
            }.max() ?? 0
        for row in 0..<grid.numberOfRows {
            grid.cell(atColumnIndex: 0, rowIndex: row).contentView?
                .setContentCompressionResistancePriority(.required, for: .horizontal)
            let value = grid.cell(atColumnIndex: 1, rowIndex: row).contentView
            value?.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            value?.setContentHuggingPriority(.required, for: .vertical)
            (value as? NSPopUpButton)?.lineBreakMode = .byTruncatingMiddle
        }
    }

    static func footer(status: NSTextField, buttons: [NSButton]) -> NSStackView {
        status.cell?.wraps = true
        status.cell?.isScrollable = false
        status.setContentHuggingPriority(.required, for: .vertical)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [spacer] + buttons)
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = MKVMagicLayoutMetrics.controlGap
        let footer = NSStackView(views: [status, actions])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = MKVMagicLayoutMetrics.compactControlGap
        NSLayoutConstraint.activate([
            footer.contentWidthConstraint(for: status),
            footer.contentWidthConstraint(for: actions),
        ])
        return footer
    }

    static func scrollingChoices(_ choices: [NSButton]) -> NSScrollView {
        let rows = NSStackView(views: choices)
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = MKVMagicLayoutMetrics.controlGap
        rows.translatesAutoresizingMaskIntoConstraints = false
        let document = NativeFormChoicesDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rows)
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        for choice in choices {
            choice.lineBreakMode = .byTruncatingMiddle
            choice.toolTip = choice.title
            choice.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            choice.setContentHuggingPriority(.required, for: .vertical)
            choice.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            rows.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            rows.topAnchor.constraint(equalTo: document.topAnchor, constant: 10),
            rows.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -10),
        ])
        return scroll
    }
}

private final class NativeFormChoicesDocumentView: NSView {
    override var isFlipped: Bool { true }
}
