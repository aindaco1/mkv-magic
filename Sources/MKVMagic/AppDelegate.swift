import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model: AppModel
    private let updateController: UpdateChecking
    private var windowController: NSWindowController?
    private var automaticQueueTask: Task<Void, Never>?

    init(
        model: AppModel = AppModel(),
        updateController: UpdateChecking = AppUpdateController()
    ) {
        self.model = model
        self.updateController = updateController
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let content = MainViewController(model: model)
        NSApp.mainMenu = makeMainMenu(openTarget: content)
        let window = NSWindow(contentViewController: content)
        window.title = "MKV Magic"
        window.setContentSize(NSSize(width: 1080, height: 680))
        window.minSize = NSSize(width: 820, height: 520)
        window.center()
        window.tabbingMode = .disallowed
        window.initialFirstResponder = content.preferredInitialFirstResponder
        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        automaticQueueTask = Task { await model.runAutomaticQueueCycleIfEligible() }
    }

    func waitForInitialQueueCycle() async {
        await automaticQueueTask?.value
    }

    func applicationWillTerminate(_ notification: Notification) {
        automaticQueueTask?.cancel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { await model.addFiles(urls) }
    }

    @objc private func checkForUpdates() {
        updateController.checkForUpdates()
    }

    private func makeMainMenu(openTarget: MainViewController) -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About MKV Magic",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let update = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        update.target = self
        appMenu.addItem(update)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide MKV Magic", action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        appMenu.addItem(
            withTitle: "Quit MKV Magic", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let open = NSMenuItem(
            title: "Open…",
            action: #selector(MainViewController.chooseFiles),
            keyEquivalent: "o"
        )
        open.target = openTarget
        fileMenu.addItem(open)
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        return main
    }
}
