import AppKit
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning

struct CommonFormatJoinPreview: Equatable, Sendable {
    let candidate: CommonFormatJoinCandidate
    let resolvedPlan: ResolvedJoinNormalizationPlan
    let normalizationPreview: JoinNormalizationPreview
}

enum CommonFormatJoinChoicePolicyError: Error, Equatable {
    case incompleteProposal
    case unsupportedDynamicRange(Int)
    case unsupportedSubtitleLane(Int)
}

extension CommonFormatJoinChoicePolicyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .incompleteProposal:
            "The recommended common-format choices are incomplete."
        case .unsupportedDynamicRange(let laneIndex):
            "Video lane \(laneIndex + 1) needs an HDR/color conversion that Join cannot execute yet."
        case .unsupportedSubtitleLane(let laneIndex):
            "Subtitle lane \(laneIndex + 1) needs a timed conversion that Join cannot execute yet."
        }
    }
}

enum CommonFormatJoinChoicePolicy {
    static func recommendedChoices(
        for candidate: CommonFormatJoinCandidate
    ) throws -> JoinNormalizationChoices {
        let proposal = candidate.proposal
        var videoTargets = [Int: JoinVideoTargetChoice]()
        var audioTargets = [Int: JoinAudioTargetChoice]()
        var retainedAttachments = [Int: Set<Int>]()
        var metadataSources = [Int: Int]()
        var emptySubtitleLanes = Set<Int>()
        var variableRateLanes = Set<Int>()

        for decision in proposal.decisions {
            switch decision.kind {
            case .videoTarget, .mixedDynamicRange:
                guard let laneIndex = decision.laneIndex,
                    let lane = proposal.videoLanes.first(where: { $0.laneIndex == laneIndex }),
                    let preset = lane.recommendedPreset,
                    let canvas = lane.recommendedCanvas,
                    let timing = lane.recommendedFrameRatePolicy
                else { throw CommonFormatJoinChoicePolicyError.incompleteProposal }
                guard lane.dynamicRangeChoices.count == 1,
                    let dynamicRange = lane.recommendedDynamicRange,
                    lane.dynamicRangeChoices == [dynamicRange]
                else {
                    throw CommonFormatJoinChoicePolicyError.unsupportedDynamicRange(laneIndex)
                }
                guard
                    let choice = videoTargetChoice(
                        lane: lane,
                        preset: preset,
                        qualityTier: .balanced
                    ), choice.canvas == canvas, choice.frameRatePolicy == timing,
                    choice.dynamicRange == dynamicRange
                else { throw CommonFormatJoinChoicePolicyError.incompleteProposal }
                videoTargets[laneIndex] = choice
            case .audioTarget, .missingAudio:
                guard let laneIndex = decision.laneIndex,
                    let lane = proposal.audioLanes.first(where: { $0.laneIndex == laneIndex }),
                    let codec = lane.outputCodec,
                    let channels = lane.outputChannels,
                    let layout = lane.outputChannelLayout,
                    let sampleRate = lane.outputSampleRate,
                    let bitrate = lane.outputBitrate
                else { throw CommonFormatJoinChoicePolicyError.incompleteProposal }
                audioTargets[laneIndex] = JoinAudioTargetChoice(
                    codec: codec,
                    channels: channels,
                    channelLayout: layout,
                    sampleRate: sampleRate,
                    bitrate: bitrate,
                    allowsSyntheticSilence: lane.sourceActions.contains(.synthesizeSilence)
                )
            case .attachmentPolicy:
                guard let sourceIndex = decision.sourceIndex,
                    candidate.sources.indices.contains(sourceIndex)
                else { throw CommonFormatJoinChoicePolicyError.incompleteProposal }
                retainedAttachments[sourceIndex] = Set(
                    candidate.sources[sourceIndex].attachments.map(\.id)
                )
            case .trackMetadata:
                guard let laneIndex = decision.laneIndex,
                    proposal.report.mapping.lanes.indices.contains(laneIndex),
                    let sourceIndex = proposal.report.mapping.lanes[laneIndex]
                        .trackIDsBySource.firstIndex(where: { $0 != nil })
                else { throw CommonFormatJoinChoicePolicyError.incompleteProposal }
                metadataSources[laneIndex] = sourceIndex
            case .missingSubtitle:
                guard let laneIndex = decision.laneIndex else {
                    throw CommonFormatJoinChoicePolicyError.incompleteProposal
                }
                emptySubtitleLanes.insert(laneIndex)
            case .variableFrameRate:
                guard let laneIndex = decision.laneIndex else {
                    throw CommonFormatJoinChoicePolicyError.incompleteProposal
                }
                variableRateLanes.insert(laneIndex)
            }
        }
        if let unsupported = proposal.subtitleLanes.first(where: {
            $0.mechanism == .normalizeTextToASS || $0.sourceActions.contains(.emptyTimeline)
        }) {
            throw CommonFormatJoinChoicePolicyError.unsupportedSubtitleLane(
                unsupported.laneIndex
            )
        }
        return JoinNormalizationChoices(
            videoTargetsByLane: videoTargets,
            audioTargetsByLane: audioTargets,
            retainedAttachmentIDsBySource: retainedAttachments,
            metadataSourceByLane: metadataSources,
            approvedEmptySubtitleLanes: emptySubtitleLanes,
            approvedVariableFrameRateLanes: variableRateLanes
        )
    }

    static func resolveRecommended(
        for candidate: CommonFormatJoinCandidate
    ) throws -> ResolvedJoinNormalizationPlan {
        try resolve(
            choices: recommendedChoices(for: candidate),
            for: candidate
        )
    }

    static func resolve(
        choices: JoinNormalizationChoices,
        for candidate: CommonFormatJoinCandidate
    ) throws -> ResolvedJoinNormalizationPlan {
        try JoinNormalizationChoiceResolver().resolve(
            sources: candidate.sources,
            proposal: candidate.proposal,
            choices: choices,
            availableVideoPresets: Set(candidate.capabilities.availableVideoPresets),
            aacAvailable: candidate.capabilities.aac == .verified
        )
    }

    static func availableVideoPresets(
        for lane: JoinVideoLaneProposal,
        capabilities: FFmpegEncodingCapabilities
    ) -> [VideoPreset] {
        guard lane.encodesVideo, lane.dynamicRangeChoices.count == 1,
            let dynamicRange = lane.dynamicRangeChoices.first
        else { return [] }
        return capabilities.availableVideoPresets.filter { preset in
            dynamicRange != .hdr10
                || preset == .av1Quality
                || preset == .hevcCompatibility
        }
    }

    static func videoTargetChoice(
        lane: JoinVideoLaneProposal,
        preset: VideoPreset,
        qualityTier: VideoQualityTier
    ) -> JoinVideoTargetChoice? {
        guard lane.encodesVideo,
            let canvas = lane.recommendedCanvas,
            let timing = lane.recommendedFrameRatePolicy,
            lane.dynamicRangeChoices.count == 1,
            let dynamicRange = lane.dynamicRangeChoices.first,
            dynamicRange != .hdr10
                || preset == .av1Quality
                || preset == .hevcCompatibility
        else { return nil }
        let recommended = recommendedRateControl(preset: preset, canvas: canvas)
        guard
            let rateControl = VideoQualityTierPolicy.rateControl(
                preset: preset,
                recommended: recommended,
                tier: qualityTier
            )
        else { return nil }
        return JoinVideoTargetChoice(
            preset: preset,
            canvas: canvas,
            frameRatePolicy: timing,
            dynamicRange: dynamicRange,
            rateControl: rateControl,
            encoderTuning: preset == .av1Quality
                ? .svtAV1Preset(VideoEncoderTuning.defaultSVTAV1Preset)
                : .codecDefault
        )
    }

    static func summaries(
        for candidate: CommonFormatJoinCandidate,
        resolvedPlan: ResolvedJoinNormalizationPlan
    ) -> [String] {
        var values = [String]()
        for lane in candidate.proposal.videoLanes where lane.encodesVideo {
            guard let choice = resolvedPlan.choices.videoTargetsByLane[lane.laneIndex] else {
                continue
            }
            values.append(
                "Video lane \(lane.laneIndex + 1): \(presetName(choice.preset)), "
                    + "\(choice.canvas.width)×\(choice.canvas.height) fit-and-pad, "
                    + "\(dynamicRangeName(choice.dynamicRange)), preserve source timing, "
                    + "\(rateControlName(choice.rateControl))"
                    + encoderTuningName(choice.encoderTuning) + "."
            )
        }
        for lane in candidate.proposal.audioLanes where lane.encodesAudio {
            guard let choice = resolvedPlan.choices.audioTargetsByLane[lane.laneIndex] else {
                continue
            }
            let silence =
                choice.allowsSyntheticSilence
                ? "; add silence only where this lane is missing" : ""
            values.append(
                "Audio lane \(lane.laneIndex + 1): AAC, \(choice.channelLayout), "
                    + "\(choice.sampleRate / 1_000) kHz, \(choice.bitrate / 1_000) kbps\(silence)."
            )
        }
        for sourceIndex in resolvedPlan.choices.retainedAttachmentIDsBySource.keys.sorted() {
            let retained = resolvedPlan.choices.retainedAttachmentIDsBySource[sourceIndex] ?? []
            values.append(
                "Part \(sourceIndex + 1): keep all \(retained.count) reviewed attachment(s)."
            )
        }
        for laneIndex in resolvedPlan.choices.metadataSourceByLane.keys.sorted() {
            let sourceIndex = resolvedPlan.choices.metadataSourceByLane[laneIndex] ?? 0
            values.append(
                "Lane \(laneIndex + 1): use reviewed track metadata from Part \(sourceIndex + 1)."
            )
        }
        for laneIndex in resolvedPlan.choices.approvedVariableFrameRateLanes.sorted() {
            values.append("Video lane \(laneIndex + 1): preserve reviewed source timing changes.")
        }
        values.append(
            "Chapters: one default nested Matroska edition with "
                + "\(candidate.chapters.document.chapterCount) entries."
        )
        values.append(
            "Execution: one fused normalization pass, then one final verified MKV assembly; compatible lanes remain packet copies."
        )
        return values
    }

    private static func recommendedRateControl(
        preset: VideoPreset,
        canvas: MediaDimensions
    ) -> JoinVideoRateControl {
        switch preset {
        case .av1Quality:
            .constantQuality(30)
        case .hevcCompatibility:
            .averageBitrate(scaledBitrate(canvas: canvas, base: 5_000_000))
        case .h264Compatibility:
            .averageBitrate(scaledBitrate(canvas: canvas, base: 8_000_000))
        case .proRes:
            .codecDefault
        }
    }

    private static func scaledBitrate(canvas: MediaDimensions, base: Int) -> Int {
        let pixels = max(1, Int64(canvas.width) * Int64(canvas.height))
        let reference = Int64(1_920 * 1_080)
        let raw = max(500_000, min(80_000_000, Int(Int64(base) * pixels / reference)))
        return max(100_000, (raw / 100_000) * 100_000)
    }

    private static func presetName(_ preset: VideoPreset) -> String {
        preset.displayName
    }

    private static func dynamicRangeName(_ dynamicRange: JoinVideoDynamicRangeTarget) -> String {
        switch dynamicRange {
        case .sdr: "SDR"
        case .hdr10: "HDR10 with static metadata preserved"
        }
    }

    private static func rateControlName(_ rateControl: JoinVideoRateControl) -> String {
        switch rateControl {
        case .averageBitrate(let value): "\(value / 1_000) kbps"
        case .constantQuality(let value): "quality \(value)"
        case .codecDefault: "codec-managed data rate"
        }
    }

    private static func encoderTuningName(_ tuning: VideoEncoderTuning) -> String {
        switch tuning {
        case .codecDefault: ""
        case .svtAV1Preset(let value): ", SVT speed preset \(value)"
        }
    }
}

@MainActor
final class CommonFormatJoinWindowController: NSWindowController {
    private let choiceViewController: CommonFormatJoinViewController
    private var completion: ((ResolvedJoinNormalizationPlan?) -> Void)?

    init(candidate: CommonFormatJoinCandidate) throws {
        let resolvedPlan = try CommonFormatJoinChoicePolicy.resolveRecommended(for: candidate)
        choiceViewController = CommonFormatJoinViewController(
            candidate: candidate,
            resolvedPlan: resolvedPlan
        )
        let window = NSPanel(contentViewController: choiceViewController)
        window.title = "Review Common Format"
        window.styleMask = [.titled, .closable, .resizable]
        let hasVideoTarget = candidate.proposal.videoLanes.contains(where: \.encodesVideo)
        window.setContentSize(NSSize(width: 700, height: hasVideoTarget ? 650 : 520))
        window.minSize = NSSize(width: 620, height: hasVideoTarget ? 560 : 460)
        super.init(window: window)
        choiceViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        choiceViewController.onContinue = { [weak self] plan in self?.finish(with: plan) }
    }

    var reviewedPlan: ResolvedJoinNormalizationPlan {
        choiceViewController.reviewedPlan
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (ResolvedJoinNormalizationPlan?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            self.completion = nil
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with plan: ResolvedJoinNormalizationPlan?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(plan)
        completion = nil
    }
}

@MainActor
private final class CommonFormatJoinVideoLaneControls: NSObject, NSTextFieldDelegate {
    let laneIndex: Int
    let view = NSStackView()
    var onChange: (() -> Void)?

    private let lane: JoinVideoLaneProposal
    private let presets: [VideoPreset]
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let qualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let advancedToggle: NSButton
    private let advancedControls = NSStackView()
    private let rateLabel = NSTextField(labelWithString: "")
    private let rateField = NSTextField()
    private let speedStack = NSStackView()
    private let speedField = NSTextField()

    init(
        lane: JoinVideoLaneProposal,
        capabilities: FFmpegEncodingCapabilities,
        initialChoice: JoinVideoTargetChoice
    ) {
        laneIndex = lane.laneIndex
        self.lane = lane
        presets = CommonFormatJoinChoicePolicy.availableVideoPresets(
            for: lane,
            capabilities: capabilities
        )
        advancedToggle = NSButton(
            checkboxWithTitle: "Show exact controls for video lane \(lane.laneIndex + 1)",
            target: nil,
            action: nil
        )
        super.init()

        let title = NSTextField(labelWithString: "Video lane \(lane.laneIndex + 1)")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        formatPopup.addItems(withTitles: presets.map(\.displayName))
        if let index = presets.firstIndex(of: initialChoice.preset) {
            formatPopup.selectItem(at: index)
        }
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        formatPopup.setAccessibilityLabel("Common format video lane \(lane.laneIndex + 1) format")

        qualityPopup.addItems(withTitles: VideoQualityTier.allCases.map(\.displayName))
        qualityPopup.selectItem(
            at: VideoQualityTier.allCases.firstIndex(of: .balanced) ?? 0
        )
        qualityPopup.target = self
        qualityPopup.action = #selector(qualityChanged)
        qualityPopup.setAccessibilityLabel(
            "Common format video lane \(lane.laneIndex + 1) quality and file size"
        )

        let formatStack = labeledStack(title: "Video format", control: formatPopup)
        let qualityStack = labeledStack(title: "Quality / file size", control: qualityPopup)
        let choiceRow = NSStackView(views: [formatStack, qualityStack])
        choiceRow.orientation = .horizontal
        choiceRow.distribution = .fillEqually
        choiceRow.spacing = 12

        advancedToggle.target = self
        advancedToggle.action = #selector(advancedChanged)
        advancedToggle.setAccessibilityLabel(
            "Show exact controls for common format video lane \(lane.laneIndex + 1)"
        )
        for field in [rateField, speedField] {
            field.delegate = self
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        }
        rateField.setAccessibilityLabel(
            "Common format video lane \(lane.laneIndex + 1) exact rate control"
        )
        speedField.setAccessibilityLabel(
            "Common format video lane \(lane.laneIndex + 1) AV1 SVT speed"
        )
        let rateStack = NSStackView(views: [rateLabel, rateField])
        rateStack.orientation = .vertical
        rateStack.alignment = .leading
        rateStack.spacing = 4
        speedStack.addArrangedSubview(NSTextField(labelWithString: "AV1 speed (0–13)"))
        speedStack.addArrangedSubview(speedField)
        speedStack.orientation = .vertical
        speedStack.alignment = .leading
        speedStack.spacing = 4
        advancedControls.addArrangedSubview(rateStack)
        advancedControls.addArrangedSubview(speedStack)
        advancedControls.orientation = .horizontal
        advancedControls.distribution = .fillEqually
        advancedControls.spacing = 12

        view.addArrangedSubview(title)
        view.addArrangedSubview(choiceRow)
        view.addArrangedSubview(advancedToggle)
        view.addArrangedSubview(advancedControls)
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 7
        view.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        choiceRow.translatesAutoresizingMaskIntoConstraints = false
        advancedControls.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            choiceRow.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -24),
            advancedControls.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -24),
        ])
        if presets.indices.contains(formatPopup.indexOfSelectedItem) {
            configureQualityPopup(
                for: presets[formatPopup.indexOfSelectedItem],
                resetSelection: true
            )
        }
        refreshControls(resetExactValues: true)
    }

    func selectedChoice() -> JoinVideoTargetChoice? {
        guard presets.indices.contains(formatPopup.indexOfSelectedItem) else { return nil }
        let preset = presets[formatPopup.indexOfSelectedItem]
        let tier =
            VideoQualityTier.allCases.indices.contains(qualityPopup.indexOfSelectedItem)
            ? VideoQualityTier.allCases[qualityPopup.indexOfSelectedItem]
            : .balanced
        guard
            let base = CommonFormatJoinChoicePolicy.videoTargetChoice(
                lane: lane,
                preset: preset,
                qualityTier: tier
            )
        else { return nil }
        guard advancedToggle.state == .on else { return base }
        switch preset {
        case .av1Quality:
            guard let rf = Int(rateField.stringValue), (0...63).contains(rf),
                let speed = Int(speedField.stringValue),
                (VideoEncoderTuning.minimumSVTAV1Preset...VideoEncoderTuning.maximumSVTAV1Preset)
                    .contains(speed)
            else { return nil }
            return replacing(
                base,
                rateControl: .constantQuality(rf),
                encoderTuning: .svtAV1Preset(speed)
            )
        case .hevcCompatibility, .h264Compatibility:
            guard let kbps = Int(rateField.stringValue), kbps > 0 else { return nil }
            let bitrate = kbps.multipliedReportingOverflow(by: 1_000)
            guard !bitrate.overflow, (100_000...200_000_000).contains(bitrate.partialValue)
            else { return nil }
            return replacing(
                base,
                rateControl: .averageBitrate(bitrate.partialValue),
                encoderTuning: .codecDefault
            )
        case .proRes:
            return base
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange?()
    }

    @objc private func formatChanged() {
        if presets.indices.contains(formatPopup.indexOfSelectedItem) {
            configureQualityPopup(
                for: presets[formatPopup.indexOfSelectedItem],
                resetSelection: true
            )
        }
        refreshControls(resetExactValues: true)
        onChange?()
    }

    @objc private func qualityChanged() {
        refreshControls(resetExactValues: true)
        onChange?()
    }

    @objc private func advancedChanged() {
        refreshControls(resetExactValues: true)
        onChange?()
    }

    private func refreshControls(resetExactValues: Bool) {
        guard presets.indices.contains(formatPopup.indexOfSelectedItem) else {
            advancedToggle.isEnabled = false
            advancedControls.isHidden = true
            return
        }
        let preset = presets[formatPopup.indexOfSelectedItem]
        let supportsExact = preset != .proRes
        advancedToggle.isHidden = !supportsExact
        if !supportsExact { advancedToggle.state = .off }
        let showsExact = supportsExact && advancedToggle.state == .on
        advancedControls.isHidden = !showsExact
        qualityPopup.isEnabled = supportsExact && advancedToggle.state != .on
        speedStack.isHidden = preset != .av1Quality
        rateField.isEditable = showsExact
        speedField.isEditable = showsExact && preset == .av1Quality
        rateLabel.stringValue =
            preset == .av1Quality
            ? "AV1 quality RF (0–63; lower is higher quality)"
            : "Video bitrate (kbps)"
        guard resetExactValues,
            let choice = selectedChoiceIgnoringAdvanced(preset: preset)
        else { return }
        switch choice.rateControl {
        case .constantQuality(let value): rateField.stringValue = String(value)
        case .averageBitrate(let value): rateField.stringValue = String(value / 1_000)
        case .codecDefault: rateField.stringValue = ""
        }
        switch choice.encoderTuning {
        case .codecDefault:
            speedField.stringValue = String(VideoEncoderTuning.defaultSVTAV1Preset)
        case .svtAV1Preset(let value):
            speedField.stringValue = String(value)
        }
    }

    private func configureQualityPopup(
        for preset: VideoPreset,
        resetSelection: Bool
    ) {
        if preset == .proRes {
            if qualityPopup.itemTitles != ["Codec Default"] {
                qualityPopup.removeAllItems()
                qualityPopup.addItem(withTitle: "Codec Default")
            }
            qualityPopup.selectItem(at: 0)
        } else {
            let titles = VideoQualityTier.allCases.map(\.displayName)
            if qualityPopup.itemTitles != titles {
                qualityPopup.removeAllItems()
                qualityPopup.addItems(withTitles: titles)
            }
            if resetSelection {
                qualityPopup.selectItem(
                    at: VideoQualityTier.allCases.firstIndex(of: .balanced) ?? 0
                )
            }
        }
    }

    private func selectedChoiceIgnoringAdvanced(preset: VideoPreset) -> JoinVideoTargetChoice? {
        let tier =
            VideoQualityTier.allCases.indices.contains(qualityPopup.indexOfSelectedItem)
            ? VideoQualityTier.allCases[qualityPopup.indexOfSelectedItem]
            : .balanced
        return CommonFormatJoinChoicePolicy.videoTargetChoice(
            lane: lane,
            preset: preset,
            qualityTier: tier
        )
    }

    private func replacing(
        _ choice: JoinVideoTargetChoice,
        rateControl: JoinVideoRateControl,
        encoderTuning: VideoEncoderTuning
    ) -> JoinVideoTargetChoice {
        JoinVideoTargetChoice(
            preset: choice.preset,
            canvas: choice.canvas,
            frameRatePolicy: choice.frameRatePolicy,
            dynamicRange: choice.dynamicRange,
            rateControl: rateControl,
            encoderTuning: encoderTuning
        )
    }

    private func labeledStack(title: String, control: NSView) -> NSStackView {
        let stack = NSStackView(views: [NSTextField(labelWithString: title), control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }
}

@MainActor
private final class CommonFormatJoinViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onContinue: ((ResolvedJoinNormalizationPlan) -> Void)?

    private let candidate: CommonFormatJoinCandidate
    fileprivate(set) var reviewedPlan: ResolvedJoinNormalizationPlan
    private var videoControls = [CommonFormatJoinVideoLaneControls]()
    private let review = NSTextView()
    private let validationMessage = NSTextField(wrappingLabelWithString: "")
    private let approval = NSButton(
        checkboxWithTitle: "I approve every common-format choice above.",
        target: nil,
        action: nil
    )
    private let continueButton = NSButton(
        title: "Continue to Save…",
        target: nil,
        action: nil
    )

    init(
        candidate: CommonFormatJoinCandidate,
        resolvedPlan: ResolvedJoinNormalizationPlan
    ) {
        self.candidate = candidate
        reviewedPlan = resolvedPlan
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Review the one-pass conversion")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString:
                "Only incompatible lanes are converted. MKV Magic keeps compatible streams unchanged, performs every required video transform in one generation, and verifies the final file before saving it."
        )
        help.textColor = .secondaryLabelColor

        review.isEditable = false
        review.isSelectable = true
        review.drawsBackground = false
        review.font = .systemFont(ofSize: 12)
        review.textContainerInset = NSSize(width: 10, height: 10)
        review.setAccessibilityLabel("Reviewed common-format choices")
        refreshReviewText()
        let scroll = NSScrollView()
        scroll.documentView = review
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let targets = NSStackView()
        targets.orientation = .vertical
        targets.alignment = .leading
        targets.spacing = 8
        for lane in candidate.proposal.videoLanes.filter(\.encodesVideo).sorted(by: {
            $0.laneIndex < $1.laneIndex
        }) {
            guard let choice = reviewedPlan.choices.videoTargetsByLane[lane.laneIndex] else {
                continue
            }
            let controls = CommonFormatJoinVideoLaneControls(
                lane: lane,
                capabilities: candidate.capabilities,
                initialChoice: choice
            )
            controls.onChange = { [weak self] in self?.refreshPlanFromControls() }
            videoControls.append(controls)
            targets.addArrangedSubview(controls.view)
            controls.view.translatesAutoresizingMaskIntoConstraints = false
            controls.view.widthAnchor.constraint(equalTo: targets.widthAnchor).isActive = true
        }
        targets.isHidden = videoControls.isEmpty
        validationMessage.textColor = .systemRed
        validationMessage.font = .systemFont(ofSize: 12)
        validationMessage.isHidden = true
        validationMessage.setAccessibilityLabel("Common format target validation")

        approval.target = self
        approval.action = #selector(toggleApproval)
        approval.setAccessibilityLabel("Approve every reviewed common-format choice")
        let warning = NSTextField(
            wrappingLabelWithString:
                "The source files are never modified. Cancelled or failed work is removed; only a fully verified final MKV is committed."
        )
        warning.textColor = .secondaryLabelColor

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        continueButton.target = self
        continueButton.action = #selector(continueJoin)
        continueButton.keyEquivalent = "\r"
        continueButton.isEnabled = false
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [spacer, cancel, continueButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10

        let stack = NSStackView(views: [
            heading, help, targets, validationMessage, scroll, approval, warning, actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 20, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        targets.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            targets.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(
                greaterThanOrEqualToConstant: videoControls.isEmpty ? 210 : 130
            ),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
    }

    @objc private func toggleApproval() {
        continueButton.isEnabled = approval.state == .on && validationMessage.isHidden
    }

    @objc private func cancel() { onCancel?() }

    @objc private func continueJoin() {
        guard approval.state == .on, validationMessage.isHidden else { return }
        onContinue?(reviewedPlan)
    }

    private func refreshPlanFromControls() {
        approval.state = .off
        continueButton.isEnabled = false
        var videoTargets = [Int: JoinVideoTargetChoice]()
        for controls in videoControls {
            guard let choice = controls.selectedChoice() else {
                showValidation(
                    "Enter a valid bounded rate and AV1 speed for every visible video lane."
                )
                return
            }
            videoTargets[controls.laneIndex] = choice
        }
        let existing = reviewedPlan.choices
        let choices = JoinNormalizationChoices(
            videoTargetsByLane: videoTargets,
            audioTargetsByLane: existing.audioTargetsByLane,
            retainedAttachmentIDsBySource: existing.retainedAttachmentIDsBySource,
            metadataSourceByLane: existing.metadataSourceByLane,
            approvedEmptySubtitleLanes: existing.approvedEmptySubtitleLanes,
            approvedVariableFrameRateLanes: existing.approvedVariableFrameRateLanes
        )
        do {
            reviewedPlan = try CommonFormatJoinChoicePolicy.resolve(
                choices: choices,
                for: candidate
            )
            validationMessage.isHidden = true
            validationMessage.stringValue = ""
            refreshReviewText()
        } catch {
            showValidation(error.localizedDescription)
        }
    }

    private func refreshReviewText() {
        review.string = CommonFormatJoinChoicePolicy.summaries(
            for: candidate,
            resolvedPlan: reviewedPlan
        ).map { "• \($0)" }.joined(separator: "\n\n")
    }

    private func showValidation(_ message: String) {
        validationMessage.stringValue = message
        validationMessage.isHidden = false
    }
}
