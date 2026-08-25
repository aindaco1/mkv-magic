import AppKit

@MainActor
enum ActivityIndicatorPresentation {
    static func make(
        label: String,
        help: String
    ) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        indicator.isDisplayedWhenStopped = false
        indicator.isHidden = true
        indicator.setAccessibilityLabel(label)
        indicator.setAccessibilityHelp(help)
        return indicator
    }

    static func set(_ indicator: NSProgressIndicator, active: Bool) {
        if active {
            indicator.isHidden = false
            indicator.startAnimation(nil)
        } else {
            indicator.stopAnimation(nil)
            indicator.isHidden = true
        }
    }
}
