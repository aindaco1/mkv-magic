import AppKit
import MKVMagicCore

enum SubtitleTrackPickerPurpose {
    case embeddedCleanup
    case textExtraction
    case timedTextConversion

    func accepts(_ track: MediaTrack) -> Bool {
        switch self {
        case .embeddedCleanup:
            track.uid != nil && EmbeddedTextSubtitlePolicy.format(for: track) != nil
        case .textExtraction:
            track.id >= 0 && track.uid != nil
                && EmbeddedTextSubtitlePolicy.format(for: track) != nil
        case .timedTextConversion:
            track.id >= 0
                && track.kind == .subtitle
                && MediaCodecFamily(codec: track.codec, kind: .subtitle) == .timedText
        }
    }

    var windowTitle: String {
        switch self {
        case .embeddedCleanup: "Choose Embedded Subtitle"
        case .textExtraction: "Choose Subtitle to Extract"
        case .timedTextConversion: "Choose MP4 Subtitle"
        }
    }

    var heading: String {
        switch self {
        case .embeddedCleanup: "Choose a text subtitle to clean"
        case .textExtraction: "Choose a text subtitle to extract"
        case .timedTextConversion: "Choose a timed-text subtitle to convert"
        }
    }

    var explanation: String {
        switch self {
        case .embeddedCleanup:
            "MKV Magic can edit embedded SRT, ASS, and SSA text. Image subtitles such as PGS and VobSub remain untouched."
        case .textExtraction:
            "MKV Magic extracts one embedded SRT, ASS, or SSA track into a separate exact subtitle file. The MKV remains unchanged."
        case .timedTextConversion:
            "MKV Magic converts one MP4 TX3G text track into a separate editable UTF-8 ASS subtitle. The video remains unchanged."
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .embeddedCleanup: "Embedded subtitle track"
        case .textExtraction: "Embedded subtitle extraction track"
        case .timedTextConversion: "MP4 timed-text track"
        }
    }

    var accessibilityHelp: String {
        switch self {
        case .embeddedCleanup:
            "Choose one embedded SRT, ASS, or SSA text track to extract privately for review."
        case .textExtraction:
            "Choose one embedded SRT, ASS, or SSA track to extract exactly and verify."
        case .timedTextConversion:
            "Choose one TX3G text track to convert privately and verify as ASS."
        }
    }

    var note: String {
        switch self {
        case .embeddedCleanup:
            "The selected track will be extracted privately for review. Nothing is changed until a new MKV passes both structural and subtitle-payload verification."
        case .textExtraction:
            "Review extracts the selected track privately. Save repeats the extraction and commits only the exact reviewed bytes after parsing and reopening the result."
        case .timedTextConversion:
            "The conversion is checked during review and repeated before save. MKV Magic commits only an exact, reopened ASS result; it never edits or replaces the source video."
        }
    }

    var cancelHelp: String {
        switch self {
        case .embeddedCleanup: "Close without extracting or changing a subtitle track."
        case .textExtraction: "Close without extracting or saving a subtitle."
        case .timedTextConversion: "Close without converting or saving a subtitle."
        }
    }

    var reviewTitle: String {
        switch self {
        case .embeddedCleanup: "Review Cleanup"
        case .textExtraction: "Review Extraction"
        case .timedTextConversion: "Review Conversion"
        }
    }

    var reviewHelp: String {
        switch self {
        case .embeddedCleanup:
            "Extract the selected text track privately and open its cleanup review."
        case .textExtraction:
            "Extract the selected text track privately and prepare an exact verified sidecar plan."
        case .timedTextConversion:
            "Convert the selected TX3G track privately and prepare a verified ASS save plan."
        }
    }

    var validationMessage: String {
        switch self {
        case .embeddedCleanup: "Choose an editable text subtitle."
        case .textExtraction: "Choose a text subtitle to extract."
        case .timedTextConversion: "Choose a TX3G subtitle."
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
        window.title = purpose.windowTitle
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
        let heading = NSTextField(labelWithString: purpose.heading)
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: purpose.explanation)
        explanation.textColor = .secondaryLabelColor
        trackPopup.addItems(withTitles: tracks.map { Self.title($0, purpose: purpose) })
        trackPopup.setAccessibilityLabel(purpose.accessibilityLabel)
        trackPopup.setAccessibilityHelp(purpose.accessibilityHelp)
        let selector = NSGridView(views: [
            [NSTextField(labelWithString: "Subtitle"), trackPopup]
        ])
        selector.rowSpacing = 8
        selector.columnSpacing = 12
        selector.column(at: 0).xPlacement = .trailing
        selector.column(at: 1).width = 450

        let note = NSTextField(wrappingLabelWithString: purpose.note)
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        validationLabel.setAccessibilityLabel("Embedded subtitle selection status")
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityHelp(purpose.cancelHelp)
        let review = NSButton(
            title: purpose.reviewTitle,
            target: self,
            action: #selector(reviewAction)
        )
        review.keyEquivalent = "\r"
        review.isEnabled = !tracks.isEmpty
        review.setAccessibilityHelp(purpose.reviewHelp)
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
            stack.contentWidthConstraint(for: selector),
            stack.contentWidthConstraint(for: note),
            stack.contentWidthConstraint(for: actions),
        ])
        view = root
    }

    @objc private func cancelAction() { onCancel?() }

    @objc private func reviewAction() {
        guard tracks.indices.contains(trackPopup.indexOfSelectedItem) else {
            validationLabel.stringValue = purpose.validationMessage
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
            purpose == .timedTextConversion
            ? "TX3G" : EmbeddedTextSubtitlePolicy.format(for: track)?.displayName ?? "Text"
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
