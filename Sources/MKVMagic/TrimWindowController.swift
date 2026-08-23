import AppKit
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning

enum TrimMode: Int, Equatable, Sendable {
    case fast
    case exact
}

struct TrimReviewRequest: Equatable, Sendable {
    let mode: TrimMode
    let range: MediaTrimRange
    let exactChoice: ExactTrimChoice?
}

enum TrimExecutionPreview: Equatable, Sendable {
    case fast(FastTrimPreview)
    case exact(ExactTrimPreview)

    var source: MediaAsset {
        switch self {
        case .fast(let preview): preview.source
        case .exact(let preview): preview.resolvedPlan.source
        }
    }

    var requestedRange: MediaTrimRange {
        switch self {
        case .fast(let preview): preview.plan.requested
        case .exact(let preview): preview.resolvedPlan.range
        }
    }

    var outputRange: MediaTrimRange {
        switch self {
        case .fast(let preview): preview.plan.adjusted
        case .exact(let preview): preview.resolvedPlan.range
        }
    }

    var videoEncodeCount: Int {
        switch self {
        case .fast: 0
        case .exact(let preview): preview.resolvedPlan.videoEncodeCount
        }
    }

    var workflowName: String {
        switch self {
        case .fast: "Fast Trim"
        case .exact: "Exact Trim"
        }
    }
}

enum TrimPresentationPolicy {
    static func canOfferTrim(for source: MediaAsset) -> Bool {
        source.sourceURL.pathExtension.lowercased() == "mkv"
            && MatroskaEditingPolicy.supports(source)
            && source.tracks.filter { $0.kind == .video }.count == 1
            && source.duration?.nanoseconds ?? 0 > 0
    }

    static func thumbnailTimes(duration: MediaTime) -> [MediaTime] {
        guard duration > .zero else { return [] }
        let last = max(0, duration.nanoseconds - 1)
        let candidates = (0...4).map { part -> MediaTime in
            let product = last.multipliedReportingOverflow(by: Int64(part))
            let value = product.overflow ? last : product.partialValue / 4
            return MediaTime(nanoseconds: value)
        }
        return Array(Set(candidates)).sorted()
    }

    static func presetName(_ preset: VideoPreset) -> String {
        switch preset {
        case .av1Quality: "Best Compression — AV1 10-bit"
        case .hevcCompatibility: "Fast — HEVC 10-bit"
        case .h264Compatibility: "Most Compatible — H.264"
        case .proRes: "Editing/Master — ProRes"
        }
    }

    static func reviewSummary(_ preview: TrimExecutionPreview) -> String {
        let requested = range(preview.requestedRange)
        let output = range(preview.outputRange)
        switch preview {
        case .fast(let fast):
            let adjustment =
                fast.plan.startWasAdjusted || fast.plan.endWasAdjusted
                ? "Keyframes change the saved range to \(output)."
                : "Both boundaries already land on usable keyframes."
            return "FAST • 0 video encodes\nRequested: \(requested)\n\(adjustment)"
        case .exact(let exact):
            let choice = exact.resolvedPlan.choice
            let audio =
                choice.audioPolicy == .packetCopy
                ? "all audio packet-copied"
                : "\(exact.encodedAudioTrackIDs.count) audio track(s) encoded once to AAC"
            return "EXACT • 1 video encode • \(presetName(choice.videoPreset))\n"
                + "Saved range: \(output) • \(audio)"
        }
    }

    private static func range(_ range: MediaTrimRange) -> String {
        "\(ChapterTimestamp.format(range.start, digits: 3))–"
            + ChapterTimestamp.format(range.end, digits: 3)
    }
}

@MainActor
final class TrimWindowController: NSWindowController {
    typealias ReviewProvider = (TrimReviewRequest) async throws -> TrimExecutionPreview

    private let trimViewController: TrimViewController
    private var completion: ((TrimExecutionPreview?) -> Void)?

    init(
        source: MediaAsset,
        thumbnails: [ChapterThumbnail],
        capabilities: FFmpegEncodingCapabilities,
        reviewProvider: @escaping ReviewProvider
    ) {
        trimViewController = TrimViewController(
            source: source,
            thumbnails: thumbnails,
            capabilities: capabilities,
            reviewProvider: reviewProvider
        )
        let window = NSPanel(contentViewController: trimViewController)
        window.title = "Trim MKV"
        window.styleMask = [.titled, .resizable]
        window.setContentSize(NSSize(width: 840, height: 650))
        window.minSize = NSSize(width: 700, height: 570)
        super.init(window: window)
        trimViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        trimViewController.onContinue = { [weak self] preview in
            self?.finish(with: preview)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (TrimExecutionPreview?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            completion(nil)
            self.completion = nil
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with preview: TrimExecutionPreview?) {
        guard let completion else { return }
        trimViewController.cancelReview()
        if let window { window.sheetParent?.endSheet(window) }
        self.completion = nil
        completion(preview)
    }
}

@MainActor
private final class TrimViewController: NSViewController, NSTextFieldDelegate {
    var onCancel: (() -> Void)?
    var onContinue: ((TrimExecutionPreview) -> Void)?

    private let source: MediaAsset
    private let thumbnails: [(ChapterThumbnail, NSImage)]
    private let capabilities: FFmpegEncodingCapabilities
    private let reviewProvider: TrimWindowController.ReviewProvider
    private let modeControl = NSSegmentedControl(
        labels: ["Fast (No Encoding)", "Exact"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let inField = NSTextField()
    private let outField = NSTextField()
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let audioPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let exactOptions = NSStackView()
    private let inputMessage = NSTextField(wrappingLabelWithString: "")
    private let reviewText = NSTextField(wrappingLabelWithString: "")
    private let reviewButton = NSButton(title: "Review Trim", target: nil, action: nil)
    private let continueButton = NSButton(title: "Continue to Save…", target: nil, action: nil)
    private var reviewTask: Task<Void, Never>?
    private var reviewedRequest: TrimReviewRequest?
    private var reviewedPreview: TrimExecutionPreview?
    private var reviewErrorMessage: String?
    private var presets: [VideoPreset] { capabilities.availableVideoPresets }

    init(
        source: MediaAsset,
        thumbnails: [ChapterThumbnail],
        capabilities: FFmpegEncodingCapabilities,
        reviewProvider: @escaping TrimWindowController.ReviewProvider
    ) {
        self.source = source
        self.capabilities = capabilities
        self.reviewProvider = reviewProvider
        self.thumbnails = thumbnails.compactMap { thumbnail in
            NSImage(data: thumbnail.imageData).map { (thumbnail, $0) }
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Choose what to keep")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let explanation = NSTextField(
            wrappingLabelWithString:
                "Set exact numeric in and out points. Fast Trim may move them forward to keyframes; Exact Trim keeps them and encodes video once. The original is never replaced."
        )
        explanation.textColor = .secondaryLabelColor

        let thumbnailRow = NSStackView(
            views: thumbnails.enumerated().map { makeThumbnailCard(index: $0, entry: $1) }
        )
        thumbnailRow.orientation = .horizontal
        thumbnailRow.alignment = .top
        thumbnailRow.distribution = .fillEqually
        thumbnailRow.spacing = 8

        let inLabel = NSTextField(labelWithString: "In")
        inLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let outLabel = NSTextField(labelWithString: "Out")
        outLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        for field in [inField, outField] {
            field.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
            field.delegate = self
            field.placeholderString = "00:00:00.000"
        }
        inField.stringValue = ChapterTimestamp.format(.zero, digits: 3)
        outField.stringValue = ChapterTimestamp.format(source.duration ?? .zero, digits: 3)
        inField.setAccessibilityLabel("Trim in point")
        outField.setAccessibilityLabel("Trim out point")
        let inStack = NSStackView(views: [inLabel, inField])
        inStack.orientation = .vertical
        inStack.alignment = .leading
        inStack.spacing = 4
        let outStack = NSStackView(views: [outLabel, outField])
        outStack.orientation = .vertical
        outStack.alignment = .leading
        outStack.spacing = 4
        let rangeRow = NSStackView(views: [inStack, outStack])
        rangeRow.orientation = .horizontal
        rangeRow.distribution = .fillEqually
        rangeRow.spacing = 12

        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.setAccessibilityLabel("Trim mode")

        presetPopup.addItems(withTitles: presets.map(TrimPresentationPolicy.presetName))
        presetPopup.setAccessibilityLabel("Exact video format")
        presetPopup.target = self
        presetPopup.action = #selector(inputChanged)
        audioPopup.addItem(withTitle: "Preserve Audio Exactly (Packet Copy)")
        if capabilities.aac == .verified {
            audioPopup.addItem(withTitle: "Convert Audio Once to AAC (Keep Layout)")
        }
        audioPopup.target = self
        audioPopup.action = #selector(inputChanged)
        audioPopup.setAccessibilityLabel("Exact audio handling")
        let presetLabel = NSTextField(labelWithString: "Exact video format")
        let audioLabel = NSTextField(labelWithString: "Audio")
        let presetStack = NSStackView(views: [presetLabel, presetPopup])
        presetStack.orientation = .vertical
        presetStack.alignment = .leading
        presetStack.spacing = 4
        let audioStack = NSStackView(views: [audioLabel, audioPopup])
        audioStack.orientation = .vertical
        audioStack.alignment = .leading
        audioStack.spacing = 4
        exactOptions.addArrangedSubview(presetStack)
        exactOptions.addArrangedSubview(audioStack)
        exactOptions.orientation = .horizontal
        exactOptions.distribution = .fillEqually
        exactOptions.spacing = 12
        exactOptions.isHidden = true

        inputMessage.textColor = .secondaryLabelColor
        inputMessage.font = .systemFont(ofSize: 12)
        reviewText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        reviewText.textColor = .secondaryLabelColor

        reviewButton.target = self
        reviewButton.action = #selector(reviewTrim)
        continueButton.target = self
        continueButton.action = #selector(continueToSave)
        continueButton.keyEquivalent = "\r"
        continueButton.isEnabled = false
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [spacer, cancelButton, reviewButton, continueButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10

        let stack = NSStackView(views: [
            heading, explanation, thumbnailRow, rangeRow, modeControl, exactOptions,
            inputMessage, reviewText, footer,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        thumbnailRow.translatesAutoresizingMaskIntoConstraints = false
        rangeRow.translatesAutoresizingMaskIntoConstraints = false
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        exactOptions.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            thumbnailRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            thumbnailRow.heightAnchor.constraint(equalToConstant: 155),
            rangeRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            inField.widthAnchor.constraint(equalTo: inStack.widthAnchor),
            outField.widthAnchor.constraint(equalTo: outStack.widthAnchor),
            modeControl.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            exactOptions.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        view = root
        updateInputState()
    }

    func controlTextDidChange(_ notification: Notification) {
        invalidateReview()
        updateInputState()
    }

    func cancelReview() {
        reviewTask?.cancel()
        reviewTask = nil
    }

    private func makeThumbnailCard(
        index: Int,
        entry: (ChapterThumbnail, NSImage)
    ) -> NSView {
        let image = NSImageView(image: entry.1)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.imageFrameStyle = .grayBezel
        image.setAccessibilityLabel(
            "Frame at \(ChapterTimestamp.format(entry.0.time, digits: 3))"
        )
        let time = NSTextField(
            labelWithString: ChapterTimestamp.format(entry.0.time, digits: 3)
        )
        time.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let setIn = NSButton(title: "Set In", target: self, action: #selector(useThumbnail(_:)))
        setIn.tag = index * 2
        let setOut = NSButton(
            title: "Set Out", target: self, action: #selector(useThumbnail(_:)))
        setOut.tag = index * 2 + 1
        let buttons = NSStackView(views: [setIn, setOut])
        buttons.orientation = .horizontal
        buttons.spacing = 4
        let card = NSStackView(views: [image, time, buttons])
        card.orientation = .vertical
        card.alignment = .centerX
        card.spacing = 5
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalTo: card.widthAnchor),
            image.heightAnchor.constraint(equalToConstant: 95),
        ])
        return card
    }

    @objc private func useThumbnail(_ sender: NSButton) {
        let index = sender.tag / 2
        guard thumbnails.indices.contains(index) else { return }
        let formatted = ChapterTimestamp.format(thumbnails[index].0.time, digits: 3)
        if sender.tag.isMultiple(of: 2) {
            inField.stringValue = formatted
        } else {
            outField.stringValue = formatted
        }
        inputChanged()
    }

    @objc private func modeChanged() {
        exactOptions.isHidden = modeControl.selectedSegment != TrimMode.exact.rawValue
        inputChanged()
    }

    @objc private func inputChanged() {
        invalidateReview()
        updateInputState()
    }

    @objc private func reviewTrim() {
        guard let request = request() else {
            updateInputState()
            return
        }
        invalidateReview()
        reviewedRequest = request
        reviewButton.isEnabled = false
        modeControl.isEnabled = false
        inField.isEnabled = false
        outField.isEnabled = false
        presetPopup.isEnabled = false
        audioPopup.isEnabled = false
        inputMessage.textColor = .secondaryLabelColor
        inputMessage.stringValue =
            request.mode == .fast
            ? "Reading keyframes and exact nested chapters locally…"
            : "Binding the selected encoder, range, tracks, and exact nested chapters…"
        reviewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await reviewProvider(request)
                try Task.checkCancellation()
                guard reviewedRequest == request else { return }
                reviewedPreview = preview
                reviewErrorMessage = nil
                reviewText.stringValue = TrimPresentationPolicy.reviewSummary(preview)
                reviewText.textColor =
                    preview.outputRange == preview.requestedRange
                    ? .labelColor : .systemOrange
                inputMessage.stringValue =
                    "Review passed. Continue to choose a new MKV; the original stays unchanged."
                continueButton.isEnabled = true
            } catch is CancellationError {
                guard reviewedRequest == request else { return }
                reviewedRequest = nil
            } catch {
                guard reviewedRequest == request else { return }
                reviewedRequest = nil
                reviewErrorMessage = "Cannot run this trim: \(error.localizedDescription)"
            }
            reviewTask = nil
            modeControl.isEnabled = true
            inField.isEnabled = true
            outField.isEnabled = true
            presetPopup.isEnabled = true
            audioPopup.isEnabled = true
            updateInputState()
        }
    }

    @objc private func continueToSave() {
        guard let reviewedPreview else { return }
        onContinue?(reviewedPreview)
    }

    @objc private func cancel() {
        onCancel?()
    }

    private func invalidateReview() {
        reviewTask?.cancel()
        reviewTask = nil
        reviewedRequest = nil
        reviewedPreview = nil
        reviewErrorMessage = nil
        continueButton.isEnabled = false
        reviewText.stringValue = ""
        inputMessage.textColor = .secondaryLabelColor
    }

    private func updateInputState() {
        guard reviewTask == nil else { return }
        guard let duration = source.duration, let request = request() else {
            reviewButton.isEnabled = false
            inputMessage.textColor = .secondaryLabelColor
            inputMessage.stringValue =
                "Enter times as HH:MM:SS.mmm; out must be after in and inside the file."
            return
        }
        let isWholeFile = request.range.start == .zero && request.range.end == duration
        let exactUnavailable = request.mode == .exact && request.exactChoice == nil
        reviewButton.isEnabled = !isWholeFile && !exactUnavailable
        if let reviewErrorMessage {
            inputMessage.textColor = .systemRed
            inputMessage.stringValue = reviewErrorMessage
        } else if isWholeFile {
            inputMessage.textColor = .secondaryLabelColor
            inputMessage.stringValue = "Move the in point or out point to remove part of the file."
        } else if exactUnavailable {
            inputMessage.textColor = .secondaryLabelColor
            inputMessage.stringValue = "No video encoder passed the active local probe."
        } else if reviewedPreview == nil {
            inputMessage.textColor = .secondaryLabelColor
            inputMessage.stringValue =
                request.mode == .fast
                ? "Fast Trim copies every stream; review will disclose keyframe adjustments."
                : "Exact Trim encodes video once; audio is preserved according to your choice."
        }
    }

    private func request() -> TrimReviewRequest? {
        guard let duration = source.duration,
            let start = try? ChapterTimestamp.parse(inField.stringValue),
            let end = try? ChapterTimestamp.parse(outField.stringValue),
            start >= .zero, end > start, end <= duration
        else { return nil }
        let mode = TrimMode(rawValue: modeControl.selectedSegment) ?? .fast
        let choice: ExactTrimChoice?
        if mode == .exact, presets.indices.contains(presetPopup.indexOfSelectedItem) {
            let preset = presets[presetPopup.indexOfSelectedItem]
            let recommended = ExactTrimPlanner().recommendedChoice(
                for: source,
                availableVideoPresets: [preset]
            )
            if let recommended {
                choice = ExactTrimChoice(
                    videoPreset: preset,
                    videoRateControl: recommended.videoRateControl,
                    audioPolicy: audioPopup.indexOfSelectedItem == 1
                        ? .aacPreserveLayout : .packetCopy
                )
            } else {
                choice = nil
            }
        } else {
            choice = nil
        }
        return TrimReviewRequest(
            mode: mode,
            range: MediaTrimRange(start: start, end: end),
            exactChoice: choice
        )
    }
}
