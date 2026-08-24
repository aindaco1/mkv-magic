import AppKit
import MKVMagicCore

enum TrackRemovalSheetMode: Equatable {
    case manual
    case englishLibraryCleanup

    var windowTitle: String {
        switch self {
        case .manual: "Remove Tracks"
        case .englishLibraryCleanup: "Clean MKV Preview"
        }
    }

    var heading: String {
        switch self {
        case .manual: "Choose tracks to remove"
        case .englishLibraryCleanup: "Review English Library suggestions"
        }
    }

    var help: String {
        switch self {
        case .manual:
            "Checked tracks will be omitted from a new MKV. Retained streams are copied without encoding; the original file stays untouched."
        case .englishLibraryCleanup:
            "Suggested subtitle removals are checked below. Commentary and the only useful English or unknown subtitle are preserved. Nothing changes until you review and run."
        }
    }
}

@MainActor
final class TrackRemovalWindowController: NSWindowController {
    private let removalViewController: TrackRemovalViewController
    private var completion: ((TrackRemoval?) -> Void)?

    init(asset: MediaAsset, mode: TrackRemovalSheetMode = .manual) {
        removalViewController = TrackRemovalViewController(asset: asset, mode: mode)
        let window = NSPanel(contentViewController: removalViewController)
        window.title = mode.windowTitle
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 480))
        window.minSize = NSSize(width: 540, height: 420)
        window.configureMKVMagicKeyboardNavigation(
            startingAt: removalViewController.preferredInitialFirstResponder
        )
        super.init(window: window)
        removalViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        removalViewController.onPreview = { [weak self] removal in
            self?.finish(with: removal)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(for parentWindow: NSWindow, completion: @escaping (TrackRemoval?) -> Void) {
        self.completion = completion
        guard let window else {
            self.completion = nil
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with removal: TrackRemoval?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(removal)
        completion = nil
    }
}

@MainActor
final class TrackRemovalViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onPreview: ((TrackRemoval) -> Void)?

    private let tracks: [MediaTrack]
    private let mode: TrackRemovalSheetMode
    private let suggestions: [UInt64: CleanMKVTrackSuggestion]
    private var checkboxes = [NSButton]()
    private let statusLabel = NSTextField(labelWithString: "")
    private let previewButton = NSButton(
        title: "Preview Removal", target: nil, action: nil)

    var preferredInitialFirstResponder: NSView {
        checkboxes.first(where: \.isEnabled) ?? previewButton
    }

    init(asset: MediaAsset, mode: TrackRemovalSheetMode) {
        tracks = asset.tracks.filter { $0.kind != .attachment }
        self.mode = mode
        suggestions = Dictionary(
            uniqueKeysWithValues: EnglishLibraryCleanupPolicy.trackSuggestions(for: asset).map {
                ($0.trackUID, $0)
            })
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: mode.heading)
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString: mode.help
        )
        help.textColor = .secondaryLabelColor

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 9
        checkboxes = tracks.map { track in
            let suggestion = track.uid.flatMap { suggestions[$0] }
            let title =
                TrackEditorPresentation.label(track)
                + suggestion.map { " — Suggested: \(TrackRemovalPresentation.reason($0.reason))" }
                .orEmpty
            let checkbox = NSButton(
                checkboxWithTitle: title,
                target: self,
                action: #selector(selectionChanged)
            )
            checkbox.state = mode == .englishLibraryCleanup && suggestion != nil ? .on : .off
            checkbox.isEnabled = TrackRemovalPresentation.canRemove(track)
            checkbox.toolTip =
                checkbox.isEnabled
                ? "Remove this track from the verified copy."
                : "This track type or identity cannot be removed safely yet."
            checkbox.setAccessibilityHelp(checkbox.toolTip)
            rows.addArrangedSubview(checkbox)
            return checkbox
        }
        let scroll = NSScrollView()
        scroll.documentView = rows
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        rows.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor, constant: 12),
            rows.trailingAnchor.constraint(
                equalTo: scroll.contentView.trailingAnchor, constant: -12),
            rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor, constant: 10),
            rows.widthAnchor.constraint(
                lessThanOrEqualTo: scroll.contentView.widthAnchor, constant: -24),
        ])

        statusLabel.textColor = .systemRed
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.setAccessibilityLabel("Track removal status")
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityHelp("Close without removing any tracks.")
        previewButton.target = self
        previewButton.action = #selector(preview)
        previewButton.keyEquivalent = "\r"
        previewButton.setAccessibilityHelp(
            "Review the selected omissions before creating a verified MKV copy."
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [statusLabel, spacer, cancelButton, previewButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        let stack = NSStackView(views: [heading, help, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
    }

    @objc private func selectionChanged() {
        statusLabel.stringValue = ""
    }

    @objc private func cancel() {
        onCancel?()
    }

    @objc private func preview() {
        do {
            let selected = Set(
                tracks.indices.compactMap { index in
                    checkboxes[index].state == .on ? index : nil
                })
            let removal = try TrackRemovalPresentation.removal(
                tracks: tracks,
                selectedIndexes: selected
            )
            statusLabel.stringValue = ""
            onPreview?(removal)
        } catch {
            AccessibleStatusPresentation.present(
                UserFacingErrorPresentation.message(
                    failure: "Could not prepare track removal.",
                    recovery: "No tracks were removed; revise the selection and try again.",
                    error: error
                ),
                in: statusLabel,
                returningFocusTo: preferredInitialFirstResponder
            )
        }
    }
}

enum TrackRemovalPresentationError: Error, Equatable {
    case emptySelection
    case unsafeTrack
    case allTracksRemoved
}

extension TrackRemovalPresentationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptySelection: "Check at least one track to remove."
        case .unsafeTrack: "One selected track cannot be addressed safely."
        case .allTracksRemoved: "At least one playable track must remain."
        }
    }
}

enum TrackRemovalPresentation {
    static func canOfferRemoval(for tracks: [MediaTrack]) -> Bool {
        let playable = tracks.filter { $0.kind != .attachment }
        return playable.count >= 2
            && playable.allSatisfy({ $0.uid != nil })
            && playable.contains(where: canRemove)
    }

    static func canRemove(_ track: MediaTrack) -> Bool {
        track.uid != nil && [.video, .audio, .subtitle, .data].contains(track.kind)
    }

    static func reason(_ reason: CleanMKVTrackSuggestion.Reason) -> String {
        switch reason {
        case .nonEnglishSubtitle(let language): "non-English (\(language))"
        case .redundantSDH: "redundant SDH"
        }
    }

    static func removal(
        tracks: [MediaTrack],
        selectedIndexes: Set<Int>
    ) throws -> TrackRemoval {
        guard !selectedIndexes.isEmpty else {
            throw TrackRemovalPresentationError.emptySelection
        }
        let selectedTracks = tracks.indices.compactMap { index in
            selectedIndexes.contains(index) ? tracks[index] : nil
        }
        guard selectedTracks.count == selectedIndexes.count,
            selectedTracks.allSatisfy(canRemove),
            selectedTracks.allSatisfy({ $0.uid != nil })
        else {
            throw TrackRemovalPresentationError.unsafeTrack
        }
        guard selectedTracks.count < tracks.count else {
            throw TrackRemovalPresentationError.allTracksRemoved
        }
        return TrackRemoval(trackUIDs: Set(selectedTracks.compactMap(\.uid)))
    }
}

extension Optional where Wrapped == String {
    fileprivate var orEmpty: String { self ?? "" }
}
