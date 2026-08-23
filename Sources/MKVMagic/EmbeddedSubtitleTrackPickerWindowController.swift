import AppKit
import MKVMagicCore

@MainActor
final class EmbeddedSubtitleTrackPickerWindowController: NSWindowController {
    private let pickerViewController: EmbeddedSubtitleTrackPickerViewController
    private var completion: ((UInt64?) -> Void)?

    init(tracks: [MediaTrack]) {
        pickerViewController = EmbeddedSubtitleTrackPickerViewController(tracks: tracks)
        let window = NSPanel(contentViewController: pickerViewController)
        window.title = "Choose Embedded Subtitle"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 280))
        window.minSize = NSSize(width: 540, height: 260)
        window.tabbingMode = .disallowed
        super.init(window: window)
        pickerViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        pickerViewController.onContinue = { [weak self] trackUID in
            self?.finish(with: trackUID)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(for parentWindow: NSWindow, completion: @escaping (UInt64?) -> Void) {
        self.completion = completion
        guard let window else {
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with trackUID: UInt64?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(trackUID)
        completion = nil
    }
}

@MainActor
final class EmbeddedSubtitleTrackPickerViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onContinue: ((UInt64) -> Void)?
    private let tracks: [MediaTrack]
    private let trackPopup = NSPopUpButton()
    private let validationLabel = NSTextField(labelWithString: "")

    init(tracks: [MediaTrack]) {
        self.tracks = tracks.filter {
            $0.uid != nil && EmbeddedTextSubtitlePolicy.format(for: $0) != nil
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Choose a text subtitle to clean")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString:
                "MKV Magic can edit embedded SRT, ASS, and SSA text. Image subtitles such as PGS and VobSub remain untouched."
        )
        explanation.textColor = .secondaryLabelColor
        trackPopup.addItems(withTitles: tracks.map(Self.title))
        trackPopup.setAccessibilityLabel("Embedded subtitle track")
        let selector = NSGridView(views: [
            [NSTextField(labelWithString: "Subtitle"), trackPopup]
        ])
        selector.rowSpacing = 8
        selector.columnSpacing = 12
        selector.column(at: 0).xPlacement = .trailing
        selector.column(at: 1).width = 450

        let note = NSTextField(
            wrappingLabelWithString:
                "The selected track will be extracted privately for review. Nothing is changed until a new MKV passes both structural and subtitle-payload verification."
        )
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        let review = NSButton(
            title: "Review Cleanup", target: self, action: #selector(reviewAction))
        review.keyEquivalent = "\r"
        review.isEnabled = !tracks.isEmpty
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [validationLabel, spacer, cancel, review])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let stack = NSStackView(views: [heading, explanation, selector, note, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        selector.translatesAutoresizingMaskIntoConstraints = false
        note.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            selector.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
    }

    @objc private func cancelAction() { onCancel?() }

    @objc private func reviewAction() {
        guard tracks.indices.contains(trackPopup.indexOfSelectedItem),
            let trackUID = tracks[trackPopup.indexOfSelectedItem].uid
        else {
            validationLabel.stringValue = "Choose an editable text subtitle."
            return
        }
        validationLabel.stringValue = ""
        onContinue?(trackUID)
    }

    static func title(_ track: MediaTrack) -> String {
        let format = EmbeddedTextSubtitlePolicy.format(for: track)?.displayName ?? "Text"
        var details = ["#\(track.id + 1)", format, track.language ?? "und"]
        if let title = track.title, !title.isEmpty { details.append(title) }
        var flags = [String]()
        if track.isDefault { flags.append("default") }
        if track.isForced { flags.append("forced") }
        if track.isHearingImpaired { flags.append("SDH") }
        if !flags.isEmpty { details.append(flags.joined(separator: ", ")) }
        return details.joined(separator: " • ")
    }
}
