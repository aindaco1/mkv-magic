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
                guard lane.dynamicRangeChoices == [.sdr] else {
                    throw CommonFormatJoinChoicePolicyError.unsupportedDynamicRange(laneIndex)
                }
                videoTargets[laneIndex] = JoinVideoTargetChoice(
                    preset: preset,
                    canvas: canvas,
                    frameRatePolicy: timing,
                    dynamicRange: .sdr,
                    rateControl: recommendedRateControl(preset: preset, canvas: canvas)
                )
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
        try JoinNormalizationChoiceResolver().resolve(
            sources: candidate.sources,
            proposal: candidate.proposal,
            choices: recommendedChoices(for: candidate),
            availableVideoPresets: Set(candidate.capabilities.availableVideoPresets),
            aacAvailable: candidate.capabilities.aac == .verified
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
                    + "SDR, preserve source timing, \(rateControlName(choice.rateControl))."
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

    private static func rateControlName(_ rateControl: JoinVideoRateControl) -> String {
        switch rateControl {
        case .averageBitrate(let value): "\(value / 1_000) kbps"
        case .constantQuality(let value): "quality \(value)"
        case .codecDefault: "codec-managed data rate"
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
        window.setContentSize(NSSize(width: 700, height: 520))
        window.minSize = NSSize(width: 620, height: 460)
        super.init(window: window)
        choiceViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        choiceViewController.onContinue = { [weak self] plan in self?.finish(with: plan) }
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
private final class CommonFormatJoinViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onContinue: ((ResolvedJoinNormalizationPlan) -> Void)?

    private let candidate: CommonFormatJoinCandidate
    private let resolvedPlan: ResolvedJoinNormalizationPlan
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
        self.resolvedPlan = resolvedPlan
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

        let review = NSTextView()
        review.isEditable = false
        review.isSelectable = true
        review.drawsBackground = false
        review.font = .systemFont(ofSize: 12)
        review.textContainerInset = NSSize(width: 10, height: 10)
        review.string = CommonFormatJoinChoicePolicy.summaries(
            for: candidate,
            resolvedPlan: resolvedPlan
        ).map { "• \($0)" }.joined(separator: "\n\n")
        review.setAccessibilityLabel("Recommended common-format choices")
        let scroll = NSScrollView()
        scroll.documentView = review
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        approval.target = self
        approval.action = #selector(toggleApproval)
        approval.setAccessibilityLabel("Approve every recommended common-format choice")
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
            heading, help, scroll, approval, warning, actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 20, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 210),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
    }

    @objc private func toggleApproval() {
        continueButton.isEnabled = approval.state == .on
    }

    @objc private func cancel() { onCancel?() }

    @objc private func continueJoin() {
        guard approval.state == .on else { return }
        onContinue?(resolvedPlan)
    }
}
