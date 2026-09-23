import AppKit
import MKVMagicCore
import MKVMagicExecution

enum BatchMediaOptionsKind { case metadata, trim }

@MainActor
final class BatchMediaOptionsWindowController: NSWindowController {
    private let content: BatchMediaOptionsViewController

    init(kind: BatchMediaOptionsKind) {
        content = BatchMediaOptionsViewController(kind: kind)
        let window = NSPanel(contentViewController: content)
        window.title = kind == .metadata ? "Edit Matching Tracks" : "Trim File Beginnings and Ends"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 620, height: kind == .metadata ? 680 : 380))
        window.minSize = NSSize(width: 540, height: 360)
        window.configureMKVMagicKeyboardNavigation(startingAt: content.initialResponder)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func beginSheet(for parent: NSWindow, completion: @escaping (BatchMediaEditOperation?) -> Void)
    {
        guard let window else {
            completion(nil)
            return
        }
        content.onFinish = { [weak window] operation in
            if let window { window.sheetParent?.endSheet(window) }
            completion(operation)
        }
        parent.beginSheet(window)
    }
}

@MainActor
private final class BatchMediaOptionsViewController: NSViewController, NSTextFieldDelegate {
    let kind: BatchMediaOptionsKind
    var onFinish: ((BatchMediaEditOperation?) -> Void)?
    private let trackKind = NSPopUpButton()
    private let nameMode = NSPopUpButton()
    private let nameField = NSTextField(string: "")
    private let languageMode = NSPopUpButton()
    private let languageField = NSTextField(string: "en")
    private var flags = [TrackMetadataFlag: NSPopUpButton]()
    private let beginningField = NSTextField(string: "0")
    private let endField = NSTextField(string: "0")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let reviewButton = NSButton(title: "Review Batch…", target: nil, action: nil)
    var initialResponder: NSView { kind == .metadata ? trackKind : beginningField }

    init(kind: BatchMediaOptionsKind) {
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        let heading = NSTextField(
            labelWithString: kind == .metadata ? "Edit matching tracks" : "Trim beginnings and ends"
        )
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString: kind == .metadata
                ? "Apply only the fields you choose to all tracks of one type. Review each file and its changes before queueing. Originals stay unchanged."
                : "Remove these amounts from every file. Fast trim does not encode: it aligns to video keyframes. Review the actual boundaries for every MKV; use individual Exact Trim when precise cuts are required."
        )
        explanation.textColor = AppPalette.secondaryText
        var rows = [[NSView]]()
        if kind == .metadata {
            configure(trackKind, label: "Track type", choices: ["Audio", "Subtitles", "Video"])
            configure(
                nameMode, label: "Track name action",
                choices: ["Unchanged", "Set name", "Clear name"])
            configure(
                languageMode, label: "Language action", choices: ["Unchanged", "Set language"])
            rows = [
                row("Track type", trackKind),
                row("Track name", nameMode), row("New name", nameField),
                row("Language", languageMode), row("Language tag", languageField),
            ]
            for flag in TrackMetadataFlag.allCases {
                let popup = NSPopUpButton()
                configure(popup, label: flag.title, choices: ["Unchanged", "Yes", "No"])
                flags[flag] = popup
                rows.append(row(flag.title, popup))
            }
        } else {
            rows = [row("Remove from beginning", beginningField), row("Remove from end", endField)]
            beginningField.placeholderString = "Seconds, or HH:MM:SS.mmm"
            endField.placeholderString = beginningField.placeholderString
        }
        for (field, label) in [
            (nameField, "New track name"), (languageField, "New language tag"),
            (beginningField, "Seconds to remove from beginning"),
            (endField, "Seconds to remove from end"),
        ] {
            field.delegate = self
            field.setAccessibilityLabel(label)
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        NativeFormLayout.configureLabeledGrid(grid)
        let scroll = NativeFormLayout.scrollingForm(grid)
        status.textColor = AppPalette.errorText
        status.setAccessibilityLabel("Batch settings validation")
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        reviewButton.target = self
        reviewButton.action = #selector(review)
        reviewButton.keyEquivalent = "\r"
        let footer = NativeFormLayout.footer(status: status, buttons: [cancel, reviewButton])
        let stack = NSStackView(views: [heading, explanation, scroll, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = MKVMagicLayoutMetrics.sectionGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        changed()
    }

    private func row(_ label: String, _ field: NSView) -> [NSView] {
        [NSTextField(labelWithString: label), field]
    }

    private func configure(_ popup: NSPopUpButton, label: String, choices: [String]) {
        popup.addItems(withTitles: choices)
        popup.target = self
        popup.action = #selector(changed)
        popup.setAccessibilityLabel(label)
    }

    private func operation() throws -> BatchMediaEditOperation {
        if kind == .trim {
            let amounts = try BatchTrimAmounts(
                beginning: BatchTrimAmounts.parseAmount(beginningField.stringValue),
                end: BatchTrimAmounts.parseAmount(endField.stringValue))
            _ = try amounts.retainedRange(duration: MediaTime(nanoseconds: Int64.max))
            return .trim(amounts)
        }
        let name: String? =
            nameMode.indexOfSelectedItem == 0
            ? nil
            : nameMode.indexOfSelectedItem == 2 ? "" : nameField.stringValue
        guard name?.contains("\0") != true, (name?.utf8.count ?? 0) <= 4_096 else {
            throw MKVPropertyEditError.invalidTrackName
        }
        let language =
            try languageMode.indexOfSelectedItem == 0
            ? nil
            : TrackLanguageTag.canonical(languageField.stringValue)
        let change = BulkTrackMetadataChange(
            kind: [.audio, .subtitle, .video][trackKind.indexOfSelectedItem], name: name,
            language: language,
            flags: flags.compactMapValues {
                $0.indexOfSelectedItem == 0 ? nil : $0.indexOfSelectedItem == 1
            })
        guard change.hasChanges else { throw MKVPropertyEditError.noChanges }
        return .metadata(change)
    }

    func controlTextDidChange(_ obj: Notification) { changed() }

    @objc private func changed() {
        nameField.isEnabled = nameMode.indexOfSelectedItem == 1
        languageField.isEnabled = languageMode.indexOfSelectedItem == 1
        do {
            _ = try operation()
            status.stringValue = ""
            reviewButton.isEnabled = true
        } catch {
            status.stringValue = UserFacingErrorPresentation.shortReason(error)
            reviewButton.isEnabled = false
        }
    }

    @objc private func review() {
        view.window?.makeFirstResponder(nil)
        do { onFinish?(try operation()) } catch { changed() }
    }
    @objc private func cancel() { onFinish?(nil) }
}
