import AppKit

@MainActor
enum AccessibleStatusPresentation {
    typealias NotificationPoster = (Any, NSAccessibility.Notification) -> Void

    static func present(
        _ message: String,
        in statusField: NSTextField,
        returningFocusTo recoveryControl: NSView? = nil,
        postNotification: NotificationPoster = { element, notification in
            NSAccessibility.post(element: element, notification: notification)
        }
    ) {
        statusField.stringValue = message
        guard !message.isEmpty else { return }

        if let recoveryControl,
            recoveryControl.isHidden == false,
            (recoveryControl as? NSControl)?.isEnabled != false,
            let window = recoveryControl.window
        {
            window.makeFirstResponder(recoveryControl)
        }
        postNotification(statusField, .valueChanged)
    }
}
