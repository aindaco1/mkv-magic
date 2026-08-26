import AppKit

/// Shared native spacing values for MKV Magic windows and sheets.
///
/// `NSStackView.edgeInsets` are part of the stack's bounds. A child constrained to the
/// stack's full width therefore extends underneath those insets. Always use
/// `contentWidthConstraint(for:)` for full-width arranged subviews.
enum MKVMagicLayoutMetrics {
    static let compactControlGap: CGFloat = 8
    static let controlGap: CGFloat = 10
    static let sectionGap: CGFloat = 12
    static let largeSectionGap: CGFloat = 16

    static let windowInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
    static let compactWindowInsets = NSEdgeInsets(
        top: 20,
        left: 20,
        bottom: 18,
        right: 20
    )
    static let inspectorInsets = NSEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
    static let footerInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
}

extension NSStackView {
    /// Constrains a full-width arranged subview to the visible content width inside
    /// `edgeInsets`, instead of allowing it to overlap the stack's outer padding.
    func contentWidthConstraint(
        for arrangedSubview: NSView,
        additionalConstant: CGFloat = 0
    ) -> NSLayoutConstraint {
        let insetWidth = edgeInsets.left + edgeInsets.right
        return arrangedSubview.widthAnchor.constraint(
            equalTo: widthAnchor,
            constant: additionalConstant - insetWidth
        )
    }
}
