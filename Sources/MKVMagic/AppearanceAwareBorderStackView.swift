import AppKit

@MainActor
final class AppearanceAwareBorderStackView: NSStackView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureBorder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshSemanticBorderColor()
    }

    private func configureBorder() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        refreshSemanticBorderColor()
    }

    private func refreshSemanticBorderColor() {
        var resolvedColor: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = NSColor.separatorColor.cgColor
        }
        layer?.borderColor = resolvedColor
    }
}
