import AppKit
import MKVMagicCore

enum SubtitleTrackPickerPurpose {
    case embeddedCleanup
    case timedTextConversion

    func accepts(_ track: MediaTrack) -> Bool {
        switch self {
        case .embeddedCleanup:
            track.uid != nil && EmbeddedTextSubtitlePolicy.format(for: track) != nil
        case .timedTextConversion:
            track.id >= 0
                && track.kind == .subtitle
                && MediaCodecFamily(codec: track.codec, kind: .subtitle) == .timedText
        }
    }
}

@MainActor
final class EmbeddedSubtitleTrackPickerWindowController: NSWindowController {
    private let pickerViewController: EmbeddedSubtitleTrackPickerViewController
    private var completion: ((MediaTrack?) -> Void)?

    init(
        tracks: [MediaTrack],
        purpose: SubtitleTrackPickerPurpose = .embeddedCleanup
    ) {
        pickerViewController = EmbeddedSubtitleTrackPickerViewController(
            tracks: tracks,
            purpose: purpose
        )
        let window = NSPanel(contentViewController: pickerViewController)
        window.title =
            purpose == .embeddedCleanup
            ? "Choose Embedded Subtitle" : "Choose MP4 Subtitle"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 280))
        window.minSize = NSSize(width: 540, height: 260)
        window.tabbingMode = .disallowed
        window.configureMKVMagicKeyboardNavigation(
            startingAt: pickerViewController.preferredInitialFirstResponder
        )
        super.init(window: window)
        pickerViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        pickerViewController.onContinue = { [weak self] track in
            self?.finish(with: track)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(for parentWindow: NSWindow, completion: @escaping (MediaTrack?) -> Void) {
        self.completion = completion
        guard let window else {
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with track: MediaTrack?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(track)
        completion = nil
    }
}

@MainActor
final class EmbeddedSubtitleTrackPickerViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onContinue: ((MediaTrack) -> Void)?
    private let tracks: [MediaTrack]
    private let purpose: SubtitleTrackPickerPurpose
    private let trackPopup = NSPopUpButton()
    private let validationLabel = NSTextField(labelWithString: "")

    var preferredInitialFirstResponder: NSView { trackPopup }

    init(tracks: [MediaTrack], purpose: SubtitleTrackPickerPurpose) {
        self.purpose = purpose
        self.tracks = tracks.filter(purpose.accepts)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(
            labelWithString:
                purpose == .embeddedCleanup
                ? "Choose a text subtitle to clean" : "Choose a timed-text subtitle to convert"
        )
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString:
                purpose == .embeddedCleanup
                ? "MKV Magic can edit embedded SRT, ASS, and SSA text. Image subtitles such as PGS and VobSub remain untouched."
                : "MKV Magic converts one MP4 TX3G text track into a separate editable UTF-8 ASS subtitle. The video remains unchanged."
        )
        explanation.textColor = .secondaryLabelColor
        trackPopup.addItems(withTitles: tracks.map { Self.title($0, purpose: purpose) })
        trackPopup.setAccessibilityLabel(
            purpose == .embeddedCleanup ? "Embedded subtitle track" : "MP4 timed-text track"
        )
        trackPopup.setAccessibilityHelp(
            purpose == .embeddedCleanup
                ? "Choose one embedded SRT, ASS, or SSA text track to extract privately for review."
                : "Choose one TX3G text track to convert privately and verify as ASS."
        )
        let selector = NSGridView(views: [
            [NSTextField(labelWithString: "Subtitle"), trackPopup]
        ])
        selector.rowSpacing = 8
        selector.columnSpacing = 12
        selector.column(at: 0).xPlacement = .trailing
        selector.column(at: 1).width = 450

        let note = NSTextField(
            wrappingLabelWithString:
                purpose == .embeddedCleanup
                ? "The selected track will be extracted privately for review. Nothing is changed until a new MKV passes both structural and subtitle-payload verification."
                : "The conversion is checked during review and repeated before save. MKV Magic commits only an exact, reopened ASS result; it never edits or replaces the source video."
        )
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        validationLabel.setAccessibilityLabel("Embedded subtitle selection status")
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityHelp(
            purpose == .embeddedCleanup
                ? "Close without extracting or changing a subtitle track."
                : "Close without converting or saving a subtitle."
        )
        let review = NSButton(
            title: purpose == .embeddedCleanup ? "Review Cleanup" : "Review Conversion",
            target: self,
            action: #selector(reviewAction)
        )
        review.keyEquivalent = "\r"
        review.isEnabled = !tracks.isEmpty
        review.setAccessibilityHelp(
            purpose == .embeddedCleanup
                ? "Extract the selected text track privately and open its cleanup review."
                : "Convert the selected TX3G track privately and prepare a verified ASS save plan."
        )
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
        guard tracks.indices.contains(trackPopup.indexOfSelectedItem) else {
            validationLabel.stringValue =
                purpose == .embeddedCleanup
                ? "Choose an editable text subtitle." : "Choose a TX3G subtitle."
            return
        }
        validationLabel.stringValue = ""
        onContinue?(tracks[trackPopup.indexOfSelectedItem])
    }

    static func title(
        _ track: MediaTrack,
        purpose: SubtitleTrackPickerPurpose = .embeddedCleanup
    ) -> String {
        let format =
            purpose == .embeddedCleanup
            ? EmbeddedTextSubtitlePolicy.format(for: track)?.displayName ?? "Text"
            : "TX3G"
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
