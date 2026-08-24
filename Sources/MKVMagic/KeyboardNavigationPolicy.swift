import AppKit

@MainActor
extension NSWindow {
    func configureMKVMagicKeyboardNavigation(startingAt firstResponder: NSView) {
        autorecalculatesKeyViewLoop = true
        initialFirstResponder = firstResponder
    }
}
