import AppKit
import MKVMagicCore
import MKVMagicExecution

@MainActor
final class ChapterThumbnailWindowController: NSWindowController {
    private let chooserViewController: ChapterThumbnailViewController
    private var completion: ((MediaTime?) -> Void)?

    init?(thumbnails: [ChapterThumbnail], currentTime: MediaTime) {
        guard
            let chooser = ChapterThumbnailViewController(
                thumbnails: thumbnails,
                currentTime: currentTime
            )
        else { return nil }
        chooserViewController = chooser
        let window = NSPanel(contentViewController: chooser)
        window.title = "Chapter Start Preview"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 350))
        window.minSize = NSSize(width: 560, height: 300)
        window.configureMKVMagicKeyboardNavigation(
            startingAt: chooser.preferredInitialFirstResponder
        )
        super.init(window: window)
        chooser.onCancel = { [weak self] in self?.finish(with: nil) }
        chooser.onChoose = { [weak self] time in self?.finish(with: time) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (MediaTime?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            completion(nil)
            self.completion = nil
            return
        }
        parentWindow.beginSheet(window)
    }

    func cancel() {
        finish(with: nil)
    }

    private func finish(with time: MediaTime?) {
        guard let completion else { return }
        if let window {
            window.sheetParent?.endSheet(window)
        }
        self.completion = nil
        completion(time)
    }
}

@MainActor
private final class ChapterThumbnailViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onChoose: ((MediaTime) -> Void)?

    private let thumbnails: [(thumbnail: ChapterThumbnail, image: NSImage)]
    private let currentTime: MediaTime
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var chooseButtons = [NSButton]()

    var preferredInitialFirstResponder: NSView {
        _ = view
        return chooseButtons.first ?? cancelButton
    }

    init?(thumbnails: [ChapterThumbnail], currentTime: MediaTime) {
        guard !thumbnails.isEmpty, thumbnails.count <= 5 else { return nil }
        var decoded = [(ChapterThumbnail, NSImage)]()
        decoded.reserveCapacity(thumbnails.count)
        for thumbnail in thumbnails {
            guard let image = NSImage(data: thumbnail.imageData), image.isValid else { return nil }
            decoded.append((thumbnail, image))
        }
        self.thumbnails = decoded
        self.currentTime = currentTime
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Choose a chapter start")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString:
                "These local frames preview the exact numeric times shown below. Choose a time or cancel; the source file is never changed."
        )
        explanation.textColor = .secondaryLabelColor

        let cards = thumbnails.enumerated().map { makeCard(index: $0.offset, entry: $0.element) }
        let cardRow = NSStackView(views: cards)
        cardRow.orientation = .horizontal
        cardRow.alignment = .top
        cardRow.distribution = .fillEqually
        cardRow.spacing = 10

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityHelp("Close without changing the chapter start time.")
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [footerSpacer, cancelButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let stack = NSStackView(views: [heading, explanation, cardRow, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardRow.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.contentWidthConstraint(for: cardRow),
            cardRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 175),
            stack.contentWidthConstraint(for: footer),
        ])
        view = root
    }

    private func makeCard(
        index: Int,
        entry: (thumbnail: ChapterThumbnail, image: NSImage)
    ) -> NSView {
        let relationship = relationshipLabel(for: entry.thumbnail.time)
        let title = NSTextField(labelWithString: relationship)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let imageView = NSImageView(image: entry.image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .grayBezel
        imageView.setAccessibilityLabel(
            "Frame at \(ChapterTimestamp.format(entry.thumbnail.time, digits: 3))"
        )
        let time = NSTextField(
            labelWithString: ChapterTimestamp.format(entry.thumbnail.time, digits: 3))
        time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        time.alignment = .center
        let choose = NSButton(title: "Use This Time", target: self, action: #selector(choose(_:)))
        choose.tag = index
        choose.setAccessibilityLabel(
            "Use \(relationship.lowercased()) time \(time.stringValue)"
        )
        choose.setAccessibilityHelp("Set this exact numeric time as the chapter start.")
        chooseButtons.append(choose)

        let card = NSStackView(views: [title, imageView, time, choose])
        card.orientation = .vertical
        card.alignment = .centerX
        card.spacing = 6
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: card.widthAnchor),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 105),
        ])
        return card
    }

    private func relationshipLabel(for time: MediaTime) -> String {
        if time < currentTime { return "Before" }
        if time > currentTime { return "After" }
        return "Current"
    }

    @objc private func choose(_ sender: NSButton) {
        guard thumbnails.indices.contains(sender.tag) else { return }
        onChoose?(thumbnails[sender.tag].thumbnail.time)
    }

    @objc private func cancel() {
        onCancel?()
    }
}
