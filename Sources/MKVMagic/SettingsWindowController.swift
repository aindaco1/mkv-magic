import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    init(
        preferences: OutputDestinationPreferences,
        appearancePreferences: AppearancePreferences = AppearancePreferences()
    ) {
        let content = SettingsViewController(
            preferences: preferences, appearancePreferences: appearancePreferences)
        let window = NSWindow(contentViewController: content)
        window.title = "MKV Magic Settings"
        window.setContentSize(NSSize(width: 600, height: 420))
        window.minSize = NSSize(width: 520, height: 400)
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
    private let appearancePreferences: AppearancePreferences
    private let appearancePopup = NSPopUpButton()
    private let modePopup = NSPopUpButton()
    private let folderLabel = NSTextField(labelWithString: "No folder chosen")
    private let chooseFolderButton = NSButton(
        title: "Choose Folder…",
        target: nil,
        action: nil
    )
    private var previousMode: OutputDestinationMode

    var preferredInitialFirstResponder: NSView { appearancePopup }

    init(preferences: OutputDestinationPreferences, appearancePreferences: AppearancePreferences) {
        self.preferences = preferences
        self.appearancePreferences = appearancePreferences
        previousMode = preferences.mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let appearanceHeading = NSTextField(labelWithString: "Appearance")
        appearanceHeading.font = .systemFont(ofSize: 22, weight: .semibold)
        appearancePopup.addItems(withTitles: AppAppearanceMode.allCases.map(\.title))
        appearancePopup.selectItem(
            at: AppAppearanceMode.allCases.firstIndex(of: appearancePreferences.mode) ?? 0)
        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged)
        appearancePopup.setAccessibilityLabel("Appearance")
        let appearanceHelp = NSTextField(
            wrappingLabelWithString:
                "System follows your Mac’s Light, Dark, or Auto setting. Changes apply immediately to every window."
        )
        appearanceHelp.textColor = AppPalette.secondaryText
        appearancePopup.setAccessibilityHelp(appearanceHelp.stringValue)
        let heading = NSTextField(labelWithString: "Output location")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString:
                "This setting applies to every media output and export. Automatic saves use an unused filename without a save dialog. macOS may ask you to allow folder access once. Reports and workflows without a source remember an export folder. Originals are never overwritten."
        )
        explanation.textColor = AppPalette.secondaryText

        modePopup.addItems(withTitles: OutputDestinationMode.allCases.map(\.title))
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        modePopup.setAccessibilityLabel("Default output location behavior")
        modePopup.setAccessibilityHelp(
            "Save beside a source when its folder is authorized, save to one chosen folder, or ask for every output."
        )

        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFolder)
        chooseFolderButton.setAccessibilityHelp(
            "Choose and remember one folder for all outputs and exports."
        )
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = AppPalette.secondaryText
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let folderSpacer = NSView()
        folderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let folderRow = NSStackView(views: [chooseFolderButton, folderLabel, folderSpacer])
        folderRow.orientation = .horizontal
        folderRow.alignment = .centerY
        folderRow.spacing = MKVMagicLayoutMetrics.controlGap

        let stack = NSStackView(views: [
            appearanceHeading, appearancePopup, appearanceHelp,
            heading, explanation, modePopup, folderRow,
        ])
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
            stack.contentWidthConstraint(for: appearanceHelp),
            stack.contentWidthConstraint(for: folderRow),
        ])
        view = root
        refresh()
    }

    @objc private func appearanceChanged() {
        guard AppAppearanceMode.allCases.indices.contains(appearancePopup.indexOfSelectedItem)
        else {
            return
        }
        appearancePreferences.mode = AppAppearanceMode.allCases[appearancePopup.indexOfSelectedItem]
        appearancePreferences.apply()
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
