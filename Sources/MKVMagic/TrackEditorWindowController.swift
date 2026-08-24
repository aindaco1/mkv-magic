import AppKit
import MKVMagicCore
import MKVMagicExecution

@MainActor
final class TrackEditorWindowController: NSWindowController {
    private let editorViewController: TrackEditorViewController
    private var completion: ((TrackMetadataEdit?) -> Void)?

    init(asset: MediaAsset) {
        editorViewController = TrackEditorViewController(asset: asset)
        let window = NSPanel(contentViewController: editorViewController)
        window.title = "Edit Track Metadata"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 510))
        window.minSize = NSSize(width: 520, height: 480)
        super.init(window: window)
        editorViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        editorViewController.onPreview = { [weak self] edit in self?.finish(with: edit) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(for parentWindow: NSWindow, completion: @escaping (TrackMetadataEdit?) -> Void)
    {
        self.completion = completion
        guard let window else {
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with edit: TrackMetadataEdit?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(edit)
        completion = nil
    }
}

@MainActor
final class TrackEditorViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onPreview: ((TrackMetadataEdit) -> Void)?

    private let tracks: [MediaTrack]
    private let trackPopup = NSPopUpButton()
    private let nameField = NSTextField()
    private let languageField = NSComboBox()
    private let defaultCheck = NSButton(checkboxWithTitle: "Default", target: nil, action: nil)
    private let forcedCheck = NSButton(checkboxWithTitle: "Forced", target: nil, action: nil)
    private let enabledCheck = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let commentaryCheck = NSButton(
        checkboxWithTitle: "Commentary", target: nil, action: nil)
    private let hearingCheck = NSButton(
        checkboxWithTitle: "Hearing impaired / SDH", target: nil, action: nil)
    private let visualCheck = NSButton(
        checkboxWithTitle: "Audio description", target: nil, action: nil)
    private let originalCheck = NSButton(
        checkboxWithTitle: "Original language", target: nil, action: nil)
    private let textDescriptionCheck = NSButton(
        checkboxWithTitle: "Text descriptions", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    init(asset: MediaAsset) {
        tracks = asset.tracks.filter { $0.kind != .attachment && $0.uid != nil }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Edit one track")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString:
                "This changes Matroska headers only. Audio, video, subtitles, chapters, and attachments are copied exactly."
        )
        help.textColor = .secondaryLabelColor

        trackPopup.addItems(withTitles: tracks.map(TrackEditorPresentation.label))
        trackPopup.target = self
        trackPopup.action = #selector(selectedTrackChanged)
        nameField.placeholderString = "Optional display name"
        languageField.addItems(withObjectValues: [
            "en", "en-US", "es", "fr", "de", "it", "pt", "ja", "ko", "zh", "und",
        ])
        languageField.placeholderString = "en, en-US, es, und…"

        let fields = NSGridView(views: [
            [fieldLabel("Track"), trackPopup],
            [fieldLabel("Name"), nameField],
            [fieldLabel("Language tag"), languageField],
        ])
        fields.rowSpacing = 10
        fields.columnSpacing = 12
        fields.column(at: 0).xPlacement = .trailing
        fields.column(at: 1).width = 360

        let flagsHeading = NSTextField(labelWithString: "Playback roles and flags")
        flagsHeading.font = .systemFont(ofSize: 13, weight: .semibold)
        let flagGrid = NSGridView(views: [
            [defaultCheck, forcedCheck],
            [enabledCheck, commentaryCheck],
            [hearingCheck, visualCheck],
            [originalCheck, textDescriptionCheck],
        ])
        flagGrid.rowSpacing = 8
        flagGrid.columnSpacing = 22
        flagGrid.column(at: 0).width = 210
        flagGrid.column(at: 1).width = 210

        statusLabel.textColor = .systemRed
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        let previewButton = NSButton(
            title: "Preview Changes", target: self, action: #selector(preview))
        previewButton.keyEquivalent = "\r"
        previewButton.bezelStyle = .rounded
        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [statusLabel, buttonSpacer, cancelButton, previewButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        let stack = NSStackView(views: [heading, help, fields, flagsHeading, flagGrid, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        fields.translatesAutoresizingMaskIntoConstraints = false
        flagGrid.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            fields.widthAnchor.constraint(equalTo: stack.widthAnchor),
            flagGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        populateFields()
    }

    @objc private func selectedTrackChanged() {
        populateFields()
    }

    @objc private func cancel() {
        onCancel?()
    }

    @objc private func preview() {
        guard let track = selectedTrack else {
            statusLabel.stringValue = "No track with a stable Matroska UID is available."
            return
        }
        do {
            let language = try TrackLanguageTag.canonical(languageField.stringValue)
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let edit = TrackMetadataEdit(
                trackUID: try requiredUID(track),
                name: name.isEmpty ? nil : name,
                language: language,
                isDefault: defaultCheck.state == .on,
                isForced: forcedCheck.state == .on,
                isEnabled: enabledCheck.state == .on,
                isCommentary: commentaryCheck.state == .on,
                isHearingImpaired: hearingCheck.state == .on,
                isVisualImpaired: visualCheck.state == .on,
                isOriginal: originalCheck.state == .on,
                isTextDescription: textDescriptionCheck.state == .on
            )
            guard edit != (try TrackEditorPresentation.normalizedEdit(for: track)) else {
                statusLabel.stringValue = "Change at least one value before previewing."
                return
            }
            statusLabel.stringValue = ""
            onPreview?(edit)
        } catch {
            statusLabel.stringValue = UserFacingErrorPresentation.message(
                failure: "Could not prepare the track edit.",
                recovery: "The original is unchanged; review the track fields and try again.",
                error: error
            )
        }
    }

    private var selectedTrack: MediaTrack? {
        guard trackPopup.indexOfSelectedItem >= 0,
            trackPopup.indexOfSelectedItem < tracks.count
        else { return nil }
        return tracks[trackPopup.indexOfSelectedItem]
    }

    private func populateFields() {
        guard let track = selectedTrack else { return }
        nameField.stringValue = track.title ?? ""
        languageField.stringValue =
            (try? TrackLanguageTag.canonical(track.language ?? "und")) ?? "und"
        defaultCheck.state = track.isDefault ? .on : .off
        forcedCheck.state = track.isForced ? .on : .off
        enabledCheck.state = track.isEnabled ? .on : .off
        commentaryCheck.state = track.isCommentary ? .on : .off
        hearingCheck.state = track.isHearingImpaired ? .on : .off
        visualCheck.state = track.isVisualImpaired ? .on : .off
        originalCheck.state = track.isOriginal ? .on : .off
        textDescriptionCheck.state = track.isTextDescription ? .on : .off
        statusLabel.stringValue = ""
    }

    private func fieldLabel(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.alignment = .right
        return label
    }

    private func requiredUID(_ track: MediaTrack) throws -> UInt64 {
        guard let uid = track.uid else { throw TrackMetadataEditValidationError.missingTrackUID }
        return uid
    }
}

enum TrackEditorPresentation {
    static func label(_ track: MediaTrack) -> String {
        var parts = [
            "#\(track.id + 1) \(track.kind.rawValue.capitalized)", track.codec.uppercased(),
        ]
        if let language = track.language { parts.append(language) }
        if let title = track.title, !title.isEmpty { parts.append(title) }
        return parts.joined(separator: " — ")
    }

    static func normalizedEdit(for track: MediaTrack) throws -> TrackMetadataEdit {
        let edit = try TrackMetadataEdit(track: track)
        return TrackMetadataEdit(
            trackUID: edit.trackUID,
            name: edit.name,
            language: try TrackLanguageTag.canonical(edit.language),
            isDefault: edit.isDefault,
            isForced: edit.isForced,
            isEnabled: edit.isEnabled,
            isCommentary: edit.isCommentary,
            isHearingImpaired: edit.isHearingImpaired,
            isVisualImpaired: edit.isVisualImpaired,
            isOriginal: edit.isOriginal,
            isTextDescription: edit.isTextDescription
        )
    }
}
