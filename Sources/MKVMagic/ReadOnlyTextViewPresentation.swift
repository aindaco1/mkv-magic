import AppKit

@MainActor
enum ReadOnlyTextViewPresentation {
    static func configure(
        _ textView: NSTextView,
        drawsBackground: Bool,
        inset: NSSize = NSSize(width: 8, height: 8),
        font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    ) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = drawsBackground
        textView.backgroundColor = drawsBackground ? .textBackgroundColor : .clear
        textView.textColor = .textColor
        textView.font = font
        textView.textContainerInset = inset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    static func scrollView(
        containing textView: NSTextView,
        borderType: NSBorderType
    ) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = borderType
        textView.frame = scroll.contentView.bounds
        scroll.documentView = textView
        return scroll
    }

    static func present(_ value: String, in textView: NSTextView) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: textView.font
                ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: value, attributes: attributes)
        )
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
}
