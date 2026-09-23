import AppKit
import MKVMagicCore

@MainActor
final class TrackRemovalWindowController: NSWindowController {
    private let removalViewController: TrackRemovalViewController
    private var completion: ((TrackRemoval?) -> Void)?

    init(asset: MediaAsset) {
        removalViewController = TrackRemovalViewController(asset: asset)
        let window = NSPanel(contentViewController: removalViewController)
        window.title = "Remove Tracks"
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
    private var checkboxes = [NSButton]()
    private let statusLabel = NSTextField(labelWithString: "")
    private let previewButton = NSButton(
        title: "Preview Removal", target: nil, action: nil)

    var preferredInitialFirstResponder: NSView {
        checkboxes.first(where: \.isEnabled) ?? previewButton
    }

    init(asset: MediaAsset) {
        tracks = asset.tracks.filter { $0.kind != .attachment }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Choose tracks to remove")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString:
                "Checked tracks will be omitted from a new MKV. Retained streams are copied without encoding; the original file stays untouched."
        )
        help.textColor = AppPalette.secondaryText

        checkboxes = tracks.map { track in
            let checkbox = NSButton(
                checkboxWithTitle: TrackEditorPresentation.label(track),
                target: self,
                action: #selector(selectionChanged)
            )
            checkbox.state = .off
            checkbox.isEnabled = TrackRemovalPresentation.canRemove(track)
            checkbox.toolTip =
                checkbox.isEnabled
                ? "Remove this track from the verified copy."
                : "This track type or identity cannot be removed safely yet."
            checkbox.setAccessibilityHelp(checkbox.toolTip)
            return checkbox
        }
        let scroll = NativeFormLayout.scrollingChoices(checkboxes)

        statusLabel.textColor = AppPalette.errorText
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
        let buttons = NativeFormLayout.footer(
            status: statusLabel, buttons: [cancelButton, previewButton])

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
            stack.contentWidthConstraint(for: heading),
            stack.contentWidthConstraint(for: help),
            stack.contentWidthConstraint(for: scroll),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            stack.contentWidthConstraint(for: buttons),
        ])
        view = root
        selectionChanged()
    }

    @objc private func selectionChanged() {
        do {
            _ = try currentRemoval()
            previewButton.isEnabled = true
            statusLabel.textColor = AppPalette.secondaryText
            statusLabel.stringValue =
                "Review these omissions, then use Verify & Run in the main window."
        } catch {
            previewButton.isEnabled = false
            statusLabel.textColor = AppPalette.secondaryText
            statusLabel.stringValue = UserFacingErrorPresentation.shortReason(error)
        }
    }

    @objc private func cancel() {
        onCancel?()
    }

    @objc private func preview() {
        do {
            let removal = try currentRemoval()
            statusLabel.stringValue = ""
            onPreview?(removal)
        } catch {
            statusLabel.textColor = AppPalette.errorText
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

    private func currentRemoval() throws -> TrackRemoval {
        try TrackRemovalPresentation.removal(
            tracks: tracks,
            selectedIndexes: Set(checkboxes.indices.filter { checkboxes[$0].state == .on })
        )
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
