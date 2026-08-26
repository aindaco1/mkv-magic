import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    init(preferences: OutputDestinationPreferences) {
        let content = SettingsViewController(preferences: preferences)
        let window = NSWindow(contentViewController: content)
        window.title = "MKV Magic Settings"
        window.setContentSize(NSSize(width: 600, height: 300))
        window.minSize = NSSize(width: 520, height: 270)
        window.tabbingMode = .disallowed
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
private final class SettingsViewController: NSViewController {
    private let preferences: OutputDestinationPreferences
    private let modePopup = NSPopUpButton()
    private let folderLabel = NSTextField(labelWithString: "No folder chosen")
    private let chooseFolderButton = NSButton(
        title: "Choose Folder…",
        target: nil,
        action: nil
    )
    private var previousMode: OutputDestinationMode

    var preferredInitialFirstResponder: NSView { modePopup }

    init(preferences: OutputDestinationPreferences) {
        self.preferences = preferences
        previousMode = preferences.mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Output location")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString:
                "Choose whether MKV Magic saves verified outputs automatically or asks each time. Originals are never overwritten. If a suggested output already exists, MKV Magic adds a number to the new filename."
        )
        explanation.textColor = .secondaryLabelColor

        modePopup.addItems(withTitles: OutputDestinationMode.allCases.map(\.title))
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        modePopup.setAccessibilityLabel("Default output location behavior")
        modePopup.setAccessibilityHelp(
            "Save beside each source, save to one chosen folder, or ask for every output."
        )

        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFolder)
        chooseFolderButton.setAccessibilityHelp(
            "Choose and remember one folder for future verified outputs."
        )
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let folderSpacer = NSView()
        folderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let folderRow = NSStackView(views: [chooseFolderButton, folderLabel, folderSpacer])
        folderRow.orientation = .horizontal
        folderRow.alignment = .centerY
        folderRow.spacing = MKVMagicLayoutMetrics.controlGap

        let stack = NSStackView(views: [heading, explanation, modePopup, folderRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = MKVMagicLayoutMetrics.sectionGap
        stack.edgeInsets = MKVMagicLayoutMetrics.windowInsets
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
            stack.contentWidthConstraint(for: explanation),
            stack.contentWidthConstraint(for: folderRow),
        ])
        view = root
        refresh()
    }

    @objc private func modeChanged() {
        guard modePopup.indexOfSelectedItem >= 0 else { return }
        let selected = OutputDestinationMode.allCases[modePopup.indexOfSelectedItem]
        if selected == .chosenFolder, !preferences.hasChosenFolder {
            modePopup.selectItem(
                at: OutputDestinationMode.allCases.firstIndex(of: previousMode) ?? 0)
            chooseFolder()
            return
        }
        preferences.mode = selected
        previousMode = selected
        refresh()
    }

    @objc private func chooseFolder() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Default Output Folder"
        panel.prompt = "Use This Folder"
        panel.message =
            "MKV Magic will remember access to this folder and save future verified outputs there without another save prompt."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let directoryURL = panel.url else {
                self?.refresh()
                return
            }
            do {
                try self.preferences.chooseFolder(directoryURL)
                self.previousMode = .chosenFolder
            } catch {
                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: window)
            }
            self.refresh()
        }
    }

    private func refresh() {
        let mode = preferences.mode
        modePopup.selectItem(at: OutputDestinationMode.allCases.firstIndex(of: mode) ?? 0)
        chooseFolderButton.isEnabled = mode == .chosenFolder
        folderLabel.stringValue = preferences.chosenFolderDisplayName ?? "No folder chosen"
        folderLabel.isHidden = mode != .chosenFolder
        previousMode = mode
    }
}
