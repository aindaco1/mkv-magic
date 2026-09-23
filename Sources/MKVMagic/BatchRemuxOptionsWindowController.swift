import AppKit
import MKVMagicCore
import MKVMagicExecution

struct BatchRemuxTrackChoice {
    let id: UUID
    let filename: String
    let metadata: ExternalSubtitleTrackMetadata
    let included: Bool
    let explanation: String
}

struct BatchRemuxOptions {
    let subtitles: [UUID: ExternalSubtitleTrackMetadata]
    let audioLanguages: [Int: String]
}

@MainActor
final class BatchRemuxOptionsWindowController: NSWindowController {
    private let editor: BatchRemuxOptionsViewController
    init(media: MediaAsset, choices: [BatchRemuxTrackChoice], audioLanguages: [Int: String]) {
        editor = BatchRemuxOptionsViewController(
            media: media, choices: choices, audioLanguages: audioLanguages)
        let window = NSWindow(contentViewController: editor)
        window.title = "Review Video and Subtitles"
        window.setContentSize(NSSize(width: 820, height: 580))
        window.minSize = NSSize(width: 720, height: 480)
        window.tabbingMode = .disallowed
        window.configureMKVMagicKeyboardNavigation(startingAt: editor.view)
        super.init(window: window)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func beginSheet(for parent: NSWindow, completion: @escaping (BatchRemuxOptions?) -> Void) {
        guard let window else {
            completion(nil)
            return
        }
        editor.onFinish = { [weak window, weak parent] options in
            if let window { parent?.endSheet(window) }
            completion(options)
        }
        parent.beginSheet(window)
    }
}

@MainActor
final class BatchRemuxOptionsViewController: NSViewController {
    private struct Fields {
        let include: NSButton
        let language: NSTextField
        let name: NSTextField
        let isDefault: NSButton
        let forced: NSButton
        let sdh: NSButton
    }
    private let media: MediaAsset
    private let choices: [BatchRemuxTrackChoice]
    private let initialAudio: [Int: String]
    private var subtitleFields = [UUID: Fields]()
    private var audioFields = [Int: NSTextField]()
    private let validation = NSTextField(wrappingLabelWithString: "")
    var onFinish: ((BatchRemuxOptions?) -> Void)?

    init(media: MediaAsset, choices: [BatchRemuxTrackChoice], audioLanguages: [Int: String]) {
        self.media = media
        self.choices = choices
        initialAudio = audioLanguages
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(wrappingLabelWithString: media.sourceURL.lastPathComponent)
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString:
                "Select the subtitles that belong to this video. Languages, names, and flags stay editable. With none selected, this becomes a video-only MKV remux. No source is changed."
        )
        help.textColor = AppPalette.secondaryText
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        for (id, language) in initialAudio.sorted(by: { $0.key < $1.key }) {
            let field = text(language, label: "Audio track \(id) language")
            audioFields[id] = field
            let grid = NSGridView(views: [
                [NSTextField(labelWithString: "Audio #\(id) language"), field]
            ])
            NativeFormLayout.configureLabeledGrid(grid)
            content.addArrangedSubview(grid)
        }
        for choice in choices {
            let include = NSButton(checkboxWithTitle: choice.filename, target: nil, action: nil)
            include.state = choice.included ? .on : .off
            include.setAccessibilityLabel("Include subtitle \(choice.filename)")
            let language = text(choice.metadata.language, label: "\(choice.filename) language")
            let name = text(choice.metadata.name ?? "", label: "\(choice.filename) track name")
            let fields = Fields(
                include: include, language: language, name: name,
                isDefault: check("Default", choice.metadata.isDefault),
                forced: check("Forced", choice.metadata.isForced),
                sdh: check("SDH", choice.metadata.isHearingImpaired))
            subtitleFields[choice.id] = fields
            let grid = NSGridView(views: [
                [NSTextField(labelWithString: "Language"), language],
                [NSTextField(labelWithString: "Track name"), name],
            ])
            NativeFormLayout.configureLabeledGrid(grid)
            let roles = NSStackView(views: [fields.isDefault, fields.forced, fields.sdh])
            roles.spacing = 16
            let explanation = NSTextField(wrappingLabelWithString: choice.explanation)
            explanation.textColor = AppPalette.secondaryText
            for item in [include, grid, roles, explanation] as [NSView] {
                content.addArrangedSubview(item)
                item.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor).isActive = true
            }
            let separator = NSBox()
            separator.boxType = .separator
            content.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = content
        content.translatesAutoresizingMaskIntoConstraints = false
        content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor, constant: -20)
            .isActive = true
        content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor, constant: 8)
            .isActive = true
        content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor, constant: 8).isActive =
            true
        validation.textColor = AppPalette.warningText
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let accept = NSButton(title: "Use These Choices", target: self, action: #selector(accept))
        accept.keyEquivalent = "\r"
        let footer = NativeFormLayout.footer(status: validation, buttons: [cancel, accept])
        let stack = NSStackView(views: [heading, help, scroll, footer])
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
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.contentWidthConstraint(for: heading), stack.contentWidthConstraint(for: help),
            stack.contentWidthConstraint(for: scroll),
            stack.contentWidthConstraint(for: footer),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
        view = root
    }

    private func text(_ value: String, label: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.setAccessibilityLabel(label)
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        return field
    }
    private func check(_ title: String, _ value: Bool) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = value ? .on : .off
        return button
    }
    @objc private func cancel() { onFinish?(nil) }
    @objc private func accept() {
        // Commit the active field editor before reading any reviewed values.
        guard view.window?.makeFirstResponder(nil) != false else { return }
        do {
            var subtitles = [UUID: ExternalSubtitleTrackMetadata]()
            for (id, fields) in subtitleFields where fields.include.state == .on {
                subtitles[id] = try ExternalSubtitleMuxPresentation.metadata(
                    language: fields.language.stringValue, name: fields.name.stringValue,
                    isDefault: fields.isDefault.state == .on, isForced: fields.forced.state == .on,
                    isHearingImpaired: fields.sdh.state == .on)
            }
            guard subtitles.count <= ExternalSubtitleBatchPolicy.maximumSubtitlesPerVideo else {
                validation.stringValue =
                    "Select at most \(ExternalSubtitleBatchPolicy.maximumSubtitlesPerVideo) subtitles for one video."
                return
            }
            guard subtitles.values.filter(\.isDefault).count <= 1 else {
                validation.stringValue = "Choose at most one default subtitle."
                return
            }
            let audio = try audioFields.mapValues { try TrackLanguageTag.canonical($0.stringValue) }
            onFinish?(BatchRemuxOptions(subtitles: subtitles, audioLanguages: audio))
        } catch {
            AccessibleStatusPresentation.present(
                "Check the language tags and track names: \(UserFacingErrorPresentation.shortReason(error))",
                in: validation)
        }
    }
}
