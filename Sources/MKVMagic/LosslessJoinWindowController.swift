import AppKit
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning

struct LosslessJoinSourceOption: Equatable, Sendable {
    let chapterPreview: ChapterEditPreview

    var source: MediaAsset { chapterPreview.source }
    var editions: [MatroskaChapterEdition] { chapterPreview.original.editions }
}

struct LosslessJoinSourceSelection: Equatable, Sendable {
    let option: LosslessJoinSourceOption
    let editionID: UUID?
}

struct LosslessJoinManualMapping: Equatable, Sendable {
    let sourceIDs: [UUID]
    let mapping: JoinTrackMapping
}

struct LosslessJoinCandidate: Equatable, Sendable {
    let sources: [MediaAsset]
    let chapterPreviews: [ChapterEditPreview]
    let mapping: JoinTrackMapping
    let report: JoinCompatibilityReport
    let chapters: JoinedChapterComposition
}

struct CommonFormatJoinCandidate: Equatable, Sendable {
    let sources: [MediaAsset]
    let chapterPreviews: [ChapterEditPreview]
    let mapping: JoinTrackMapping
    let report: JoinCompatibilityReport
    let chapters: JoinedChapterComposition
    let proposal: JoinNormalizationProposal
    let capabilities: FFmpegEncodingCapabilities
}

enum JoinReviewSelection: Equatable, Sendable {
    case lossless(LosslessJoinCandidate)
    case commonFormat(CommonFormatJoinCandidate)
}

struct LosslessJoinReviewSnapshot: Equatable, Sendable {
    let candidate: LosslessJoinCandidate?
    let commonFormatCandidate: CommonFormatJoinCandidate?
    let reviewedMapping: JoinTrackMapping?
    let unresolvedAmbiguities: [JoinTrackMappingAmbiguity]
    let usesManualMapping: Bool
    let laneSummaries: [String]
    let issueSummaries: [String]
    let normalizationSummaries: [String]
    let blockerSummaries: [String]

    var selection: JoinReviewSelection? {
        if let candidate { return .lossless(candidate) }
        if let commonFormatCandidate { return .commonFormat(commonFormatCandidate) }
        return nil
    }

    var isReady: Bool { selection != nil }
}

enum LosslessJoinReviewBuilder {
    static func make(
        selections: [LosslessJoinSourceSelection],
        manualMapping: LosslessJoinManualMapping? = nil,
        encodingCapabilities: FFmpegEncodingCapabilities? = nil
    ) -> LosslessJoinReviewSnapshot {
        guard selections.count >= 2 else {
            return blocked("Select at least two inspected Matroska files.")
        }

        let sources = selections.map(\.option.source)
        let proposal: JoinTrackMappingProposal
        do {
            proposal = try JoinTrackMappingProposer().propose(sources: sources)
        } catch {
            return blocked("The track map could not be built: \(error.localizedDescription)")
        }
        let mapping: JoinTrackMapping
        let unresolvedAmbiguities: [JoinTrackMappingAmbiguity]
        let usesManualMapping: Bool
        if let manualMapping {
            guard manualMapping.sourceIDs == sources.map(\.id) else {
                return blocked(
                    "The reviewed track map no longer matches the selected source order.")
            }
            mapping = manualMapping.mapping
            unresolvedAmbiguities = []
            usesManualMapping = true
        } else {
            mapping = proposal.mapping
            unresolvedAmbiguities = proposal.ambiguities
            usesManualMapping = false
        }
        let report: JoinCompatibilityReport
        do {
            report = try JoinCompatibilityAnalyzer().analyze(
                sources: sources,
                mapping: mapping
            )
        } catch {
            return blocked("The track map could not be built: \(error.localizedDescription)")
        }

        let lanes = laneSummaries(mapping: mapping, sources: sources)
        let issues = report.issues.map { issueSummary($0, sources: sources) }
        var sharedBlockers = [String]()
        if !unresolvedAmbiguities.isEmpty {
            for ambiguity in unresolvedAmbiguities {
                sharedBlockers.append(
                    "Part \(ambiguity.sourceIndex + 1) has ambiguous "
                        + "\(ambiguity.kind.rawValue) tracks "
                        + ambiguity.trackIDs.map { "#\($0)" }.joined(separator: ", ")
                        + "; automatic mapping will not guess."
                )
            }
        }
        if let firstSource = sources.first {
            var stableUIDs = Set<UInt64>()
            for lane in mapping.lanes {
                guard let trackID = lane.trackIDsBySource.first ?? nil,
                    let track = firstSource.tracks.first(where: { $0.id == trackID }),
                    let uid = track.uid,
                    stableUIDs.insert(uid).inserted
                else {
                    sharedBlockers.append(
                        "The first source needs a unique stable Matroska UID for every output lane."
                    )
                    break
                }
            }
        }

        var joinedSources = [JoinedChapterSource]()
        for (index, selection) in selections.enumerated() {
            guard let duration = selection.option.source.duration, duration > .zero else {
                sharedBlockers.append("Part \(index + 1) needs a known positive duration.")
                continue
            }
            let selectedChapters: [MatroskaChapterAtom]
            if selection.option.editions.isEmpty {
                selectedChapters = []
            } else if let editionID = selection.editionID,
                let edition = selection.option.editions.first(where: { $0.id == editionID })
            {
                selectedChapters = edition.chapters
            } else {
                sharedBlockers.append(
                    "Choose the source chapter edition for Part \(index + 1)."
                )
                continue
            }
            let source = selection.option.source
            joinedSources.append(
                JoinedChapterSource(
                    title: source.metadata["title"]
                        ?? source.sourceURL.deletingPathExtension().lastPathComponent,
                    duration: duration,
                    retainedStart: .zero,
                    retainedEnd: duration,
                    selectedEditionChapters: selectedChapters
                )
            )
        }

        let composition: JoinedChapterComposition?
        if joinedSources.count == selections.count {
            do {
                composition = try JoinedChapterComposer().compose(joinedSources)
            } catch {
                sharedBlockers.append("Joined chapters are invalid: \(error.localizedDescription)")
                composition = nil
            }
        } else {
            composition = nil
        }

        var losslessBlockers = sharedBlockers
        if report.disposition != .losslessCandidate {
            losslessBlockers.append(dispositionSummary(report.disposition))
        }
        let candidate =
            losslessBlockers.isEmpty
            ? composition.map {
                LosslessJoinCandidate(
                    sources: sources,
                    chapterPreviews: selections.map(\.option.chapterPreview),
                    mapping: mapping,
                    report: report,
                    chapters: $0
                )
            }
            : nil

        let normalization = normalizationReview(
            sources: sources,
            mapping: mapping,
            report: report,
            hasAmbiguities: !unresolvedAmbiguities.isEmpty,
            encodingCapabilities: encodingCapabilities
        )
        let commonFormatCandidate: CommonFormatJoinCandidate?
        if report.disposition == .normalizationRequired,
            sharedBlockers.isEmpty,
            normalization.blockers.isEmpty,
            let normalizationProposal = normalization.proposal,
            let capabilities = encodingCapabilities,
            let chapters = composition
        {
            commonFormatCandidate = CommonFormatJoinCandidate(
                sources: sources,
                chapterPreviews: selections.map(\.option.chapterPreview),
                mapping: mapping,
                report: report,
                chapters: chapters,
                proposal: normalizationProposal,
                capabilities: capabilities
            )
        } else {
            commonFormatCandidate = nil
        }
        let blockers =
            candidate == nil && commonFormatCandidate != nil
            ? []
            : stableUnique(sharedBlockers + normalization.blockers + losslessBlockers)
        return LosslessJoinReviewSnapshot(
            candidate: candidate,
            commonFormatCandidate: commonFormatCandidate,
            reviewedMapping: mapping,
            unresolvedAmbiguities: unresolvedAmbiguities,
            usesManualMapping: usesManualMapping,
            laneSummaries: lanes,
            issueSummaries: issues,
            normalizationSummaries: normalization.summaries,
            blockerSummaries: blockers
        )
    }

    private static func blocked(_ message: String) -> LosslessJoinReviewSnapshot {
        LosslessJoinReviewSnapshot(
            candidate: nil,
            commonFormatCandidate: nil,
            reviewedMapping: nil,
            unresolvedAmbiguities: [],
            usesManualMapping: false,
            laneSummaries: [],
            issueSummaries: [],
            normalizationSummaries: [],
            blockerSummaries: [message]
        )
    }

    private struct NormalizationReview {
        let proposal: JoinNormalizationProposal?
        let summaries: [String]
        let blockers: [String]
    }

    private static func normalizationReview(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        report: JoinCompatibilityReport,
        hasAmbiguities: Bool,
        encodingCapabilities: FFmpegEncodingCapabilities?
    ) -> NormalizationReview {
        switch report.disposition {
        case .losslessCandidate:
            return NormalizationReview(
                proposal: nil,
                summaries: ["Not needed; every reviewed lane remains a packet copy."],
                blockers: []
            )
        case .confirmationRequired:
            return NormalizationReview(
                proposal: nil,
                summaries: [
                    "No encode requirement is known; explicit metadata, gap, or attachment confirmation is still required."
                ],
                blockers: [dispositionSummary(report.disposition)]
            )
        case .unsupported:
            return NormalizationReview(
                proposal: nil,
                summaries: ["No supported common-format plan is available for this source set."],
                blockers: [dispositionSummary(report.disposition)]
            )
        case .normalizationRequired:
            break
        }
        if hasAmbiguities {
            return NormalizationReview(
                proposal: nil,
                summaries: ["Resolve ambiguous track lanes before choosing common output formats."],
                blockers: ["Resolve ambiguous track lanes before choosing common output formats."]
            )
        }
        guard
            let proposal = try? JoinNormalizationPlanner().propose(
                sources: sources,
                mapping: mapping,
                reviewedReport: report,
                preferredVideoPreset: encodingCapabilities?.recommendedVideoPreset
                    ?? .av1Quality
            )
        else {
            return NormalizationReview(
                proposal: nil,
                summaries: ["The common-format proposal could not be bound to this review."],
                blockers: ["The common-format proposal could not be bound to this review."]
            )
        }
        var summaries = [String]()
        var blockers = proposal.blockers.map(\.summary)
        for lane in proposal.videoLanes where lane.encodesVideo {
            let preset = lane.recommendedPreset.map(videoPresetSummary) ?? "format needs review"
            let canvas =
                lane.recommendedCanvas.map { "\($0.width)×\($0.height) fit/pad" }
                ?? "canvas needs review"
            let range =
                lane.recommendedDynamicRange.map {
                    $0 == .hdr10 ? "HDR10" : "SDR"
                } ?? "choose SDR or HDR10"
            summaries.append(
                "Video lane \(lane.laneIndex + 1): one \(preset) generation • \(canvas) • \(range) • preserve source timing."
            )
        }
        for lane in proposal.audioLanes where lane.encodesAudio {
            let preset =
                encodingCapabilities?.availableAudioPresets.first(where: {
                    CommonFormatJoinChoicePolicy.audioTargetChoice(
                        lane: lane,
                        preset: $0,
                        allowsSyntheticSilence: lane.sourceActions.contains(.synthesizeSilence)
                    ) != nil
                }) ?? .aacCompatibility
            let choice = CommonFormatJoinChoicePolicy.audioTargetChoice(
                lane: lane,
                preset: preset,
                allowsSyntheticSilence: lane.sourceActions.contains(.synthesizeSilence)
            )
            let layout = choice?.channelLayout ?? lane.outputChannelLayout ?? "layout needs review"
            let rate = choice.map { "\($0.sampleRate / 1_000) kHz" } ?? "rate needs review"
            let bitrate =
                choice.map {
                    $0.bitrate.map { "\($0 / 1_000) kbps" } ?? "lossless"
                } ?? "bitrate needs review"
            let silence =
                lane.sourceActions.contains(.synthesizeSilence)
                ? " • silent missing sections"
                : ""
            summaries.append(
                "Audio lane \(lane.laneIndex + 1): \(preset.displayName) once • \(layout) • \(rate) • \(bitrate)\(silence)."
            )
        }
        for lane in proposal.subtitleLanes where lane.mechanism == .normalizeTextToASS {
            summaries.append(
                "Subtitle lane \(lane.laneIndex + 1): normalize text once to ASS; video remains unaffected."
            )
        }
        summaries.append(
            "Impact: \(proposal.impact.videoEncodeCount) video generation • \(proposal.impact.audioEncodeCount) audio lane encode(s)."
        )
        let needsVideoEncode = proposal.videoLanes.contains(where: \.encodesVideo)
        let needsAudioEncode = proposal.audioLanes.contains(where: \.encodesAudio)
        if let capabilities = encodingCapabilities,
            needsVideoEncode, capabilities.recommendedVideoPreset == nil
        {
            let message = "No bundled video encoder passed the active local probe."
            summaries.append("Blocked: \(message)")
            blockers.append(message)
        } else if let capabilities = encodingCapabilities,
            needsAudioEncode,
            proposal.audioLanes.filter(\.encodesAudio).contains(where: {
                CommonFormatJoinChoicePolicy.availableAudioPresets(
                    for: $0,
                    capabilities: capabilities
                ).isEmpty
            })
        {
            let message =
                "No locally verified bundled audio format can represent every reviewed Join lane."
            summaries.append("Blocked: \(message)")
            blockers.append(message)
        } else if let capabilities = encodingCapabilities,
            needsVideoEncode || needsAudioEncode,
            let missingFilter = capabilities.missingJoinFilters.first
        {
            let message = "Bundled FFmpeg did not report the required \(missingFilter) filter."
            summaries.append("Blocked: \(message)")
            blockers.append(message)
        } else if let blocker = proposal.blockers.first {
            summaries.append("Blocked: \(blocker.summary)")
        } else {
            if let capabilities = encodingCapabilities,
                needsVideoEncode,
                capabilities.softwareAV1 != .verified,
                let fallback = capabilities.recommendedVideoPreset
            {
                summaries.append(
                    "AV1 remains preferred, but this runtime has no verified AV1 encoder; \(videoPresetSummary(fallback)) is the verified fallback."
                )
            }
            summaries.append(
                "Planning preview only; every listed target still requires explicit approval before execution."
            )
        }
        if encodingCapabilities == nil, needsVideoEncode || needsAudioEncode {
            let message =
                "Bundled encoders must be actively probed before common-format choices can run."
            summaries.append("Blocked: \(message)")
            blockers.append(message)
        }
        for lane in proposal.videoLanes
        where lane.encodesVideo
            && lane.dynamicRangeChoices != [.sdr]
            && lane.dynamicRangeChoices != [.hdr10]
        {
            let message =
                "Video lane \(lane.laneIndex + 1) needs HDR/color conversion that is not executable yet."
            summaries.append("Blocked: \(message)")
            blockers.append(message)
        }
        for lane in proposal.subtitleLanes where lane.mechanism == .normalizeTextToASS {
            let message =
                "Subtitle lane \(lane.laneIndex + 1) needs text conversion that is not executable in Join yet."
            summaries.append("Blocked: \(message)")
            blockers.append(message)
        }
        for lane in proposal.subtitleLanes where lane.sourceActions.contains(.emptyTimeline) {
            let message =
                "Subtitle lane \(lane.laneIndex + 1) needs an empty timed section that is not executable in Join yet."
            summaries.append("Blocked: \(message)")
            blockers.append(message)
        }
        do {
            try JoinFinalAssemblySourcePolicy().validate(sources)
        } catch {
            let message = error.localizedDescription
            summaries.append("Blocked: \(message)")
            blockers.append(message)
        }
        return NormalizationReview(
            proposal: proposal,
            summaries: stableUnique(summaries),
            blockers: stableUnique(blockers)
        )
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func videoPresetSummary(_ preset: VideoPreset) -> String {
        preset.displayName
    }

    private static func laneSummaries(
        mapping: JoinTrackMapping,
        sources: [MediaAsset]
    ) -> [String] {
        var kindCounts = [MediaTrackKind: Int]()
        return mapping.lanes.map { lane in
            kindCounts[lane.kind, default: 0] += 1
            let laneNumber = kindCounts[lane.kind]!
            let tracks = lane.trackIDsBySource.enumerated().map { sourceIndex, trackID in
                guard let trackID else { return "Part \(sourceIndex + 1): missing" }
                let codec =
                    sources[sourceIndex].tracks.first(where: { $0.id == trackID })?.codec
                    .uppercased() ?? "unknown"
                return "Part \(sourceIndex + 1): #\(trackID) \(codec)"
            }
            return "\(lane.kind.rawValue.capitalized) \(laneNumber)  "
                + tracks.joined(separator: "  →  ")
        }
    }

    private static func issueSummary(
        _ issue: JoinCompatibilityIssue,
        sources: [MediaAsset]
    ) -> String {
        var location = "Part \(issue.sourceIndex + 1)"
        if let trackID = issue.trackID { location += " track #\(trackID)" }
        if let laneIndex = issue.laneIndex { location += " in lane \(laneIndex + 1)" }
        let requirement: String
        switch issue.severity {
        case .confirmationRequired: requirement = "needs confirmation"
        case .normalizationRequired: requirement = "needs normalization"
        case .unsupported: requirement = "is unsupported"
        }
        return "\(location): \(reasonSummary(issue.reason)) \(requirement)."
    }

    private static func reasonSummary(_ reason: JoinCompatibilityIssueReason) -> String {
        switch reason {
        case .nonMatroskaSource: "the source is not Matroska"
        case .attachmentSelection: "attachments need an explicit keep/drop choice"
        case .unsupportedTrackKind: "the track type"
        case .missingTrack: "a corresponding track is missing"
        case .codec: "the codec differs"
        case .profile: "the codec profile differs"
        case .level: "the codec level differs"
        case .dimensions: "the encoded dimensions differ"
        case .displayDimensions: "the display dimensions differ"
        case .pixelFormat: "the pixel format differs"
        case .bitDepth: "the bit depth differs"
        case .frameRate: "the frame rate differs"
        case .color: "the color metadata differs"
        case .hdr: "the HDR metadata differs"
        case .sampleRate: "the audio sample rate differs"
        case .channels: "the audio channel count differs"
        case .channelLayout: "the audio channel layout differs"
        case .language: "the language metadata differs"
        case .role: "the accessibility or commentary role differs"
        case .title: "the track title differs"
        case .flags: "the playback flags differ"
        case .incompleteParameters: "inspection parameters are incomplete"
        }
    }

    private static func dispositionSummary(_ disposition: JoinAppendDisposition) -> String {
        switch disposition {
        case .losslessCandidate:
            "The files are a strict lossless candidate."
        case .confirmationRequired:
            "Resolve every confirmation item before a lossless join."
        case .normalizationRequired:
            "These files need one normalization/transcode pass before joining."
        case .unsupported:
            "This source set contains a track MKV Magic cannot join."
        }
    }
}

@MainActor
final class LosslessJoinWindowController: NSWindowController {
    private let joinViewController: LosslessJoinViewController
    private var trackMappingWindowController: JoinTrackMappingWindowController?
    private var completion: ((JoinReviewSelection?) -> Void)?

    init(
        options: [LosslessJoinSourceOption],
        encodingCapabilities: FFmpegEncodingCapabilities? = nil
    ) {
        joinViewController = LosslessJoinViewController(
            options: options,
            encodingCapabilities: encodingCapabilities
        )
        let window = NSPanel(contentViewController: joinViewController)
        window.title = "Join MKV Files"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 860, height: 650))
        window.minSize = NSSize(width: 720, height: 560)
        super.init(window: window)
        joinViewController.onCancel = { [weak self] in self?.finish(with: nil) }
        joinViewController.onContinue = { [weak self] selection in
            self?.finish(with: selection)
        }
        joinViewController.onEditMapping = { [weak self] sources, mapping, requiresResolution in
            self?.editMapping(
                sources: sources,
                mapping: mapping,
                requiresResolution: requiresResolution
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(
        for parentWindow: NSWindow,
        completion: @escaping (JoinReviewSelection?) -> Void
    ) {
        self.completion = completion
        guard let window else {
            self.completion = nil
            completion(nil)
            return
        }
        parentWindow.beginSheet(window)
    }

    private func finish(with selection: JoinReviewSelection?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(selection)
        completion = nil
    }

    private func editMapping(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        requiresResolution: Bool
    ) {
        guard let window else { return }
        let controller = JoinTrackMappingWindowController(
            sources: sources,
            mapping: mapping,
            requiresResolution: requiresResolution
        )
        trackMappingWindowController = controller
        controller.beginSheet(for: window) { [weak self] editedMapping in
            guard let self else { return }
            self.trackMappingWindowController = nil
            guard let editedMapping else { return }
            self.joinViewController.acceptManualMapping(
                editedMapping,
                sourceIDs: sources.map(\.id)
            )
        }
    }
}

@MainActor
final class LosslessJoinViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate
{
    var onCancel: (() -> Void)?
    var onContinue: ((JoinReviewSelection) -> Void)?
    var onEditMapping: (([MediaAsset], JoinTrackMapping, Bool) -> Void)?

    private var options: [LosslessJoinSourceOption]
    private let encodingCapabilities: FFmpegEncodingCapabilities?
    private var includedIDs: Set<UUID>
    private var editionIDs = [UUID: UUID]()
    private var manualMapping: LosslessJoinManualMapping?
    private var snapshot = LosslessJoinReviewSnapshot(
        candidate: nil,
        commonFormatCandidate: nil,
        reviewedMapping: nil,
        unresolvedAmbiguities: [],
        usesManualMapping: false,
        laneSummaries: [],
        issueSummaries: [],
        normalizationSummaries: [],
        blockerSummaries: []
    )
    private let tableView = NSTableView()
    private let reviewText = NSTextView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let continueButton = NSButton(title: "Continue to Save…", target: nil, action: nil)
    private let moveUpButton = NSButton(title: "Move Up", target: nil, action: nil)
    private let moveDownButton = NSButton(title: "Move Down", target: nil, action: nil)
    private let mappingButton = NSButton(title: "Edit Track Mapping…", target: nil, action: nil)

    init(
        options: [LosslessJoinSourceOption],
        encodingCapabilities: FFmpegEncodingCapabilities?
    ) {
        self.options = options
        self.encodingCapabilities = encodingCapabilities
        includedIDs = Set(options.map { $0.source.id })
        for option in options where option.editions.count == 1 {
            editionIDs[option.source.id] = option.editions[0].id
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let heading = NSTextField(labelWithString: "Join MKV files")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let help = NSTextField(
            wrappingLabelWithString:
                "Choose and order complete MKVs. MKV Magic maps every track, keeps one explicitly selected chapter edition per source, creates nested Part chapters, and recommends a common format only when lossless joining is not safe."
        )
        help.textColor = .secondaryLabelColor

        for (identifier, title, width) in [
            ("include", "Use", 42.0),
            ("order", "Part", 50.0),
            ("file", "Source", 330.0),
            ("duration", "Duration", 82.0),
            ("chapters", "Source chapters", 210.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 30
        tableView.allowsEmptySelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        let tableScroll = NSScrollView()
        tableScroll.documentView = tableView
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = false
        tableScroll.borderType = .bezelBorder

        moveUpButton.target = self
        moveUpButton.action = #selector(moveSourceUp)
        moveDownButton.target = self
        moveDownButton.action = #selector(moveSourceDown)
        mappingButton.target = self
        mappingButton.action = #selector(editMapping)
        let orderSpacer = NSView()
        orderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let orderButtons = NSStackView(views: [
            moveUpButton, moveDownButton, orderSpacer, mappingButton,
        ])
        orderButtons.orientation = .horizontal
        orderButtons.alignment = .centerY
        orderButtons.spacing = 8

        let reviewHeading = NSTextField(labelWithString: "Compatibility review")
        reviewHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        reviewText.isEditable = false
        reviewText.isSelectable = true
        reviewText.drawsBackground = false
        reviewText.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        reviewText.textContainerInset = NSSize(width: 8, height: 8)
        let reviewScroll = NSScrollView()
        reviewScroll.documentView = reviewText
        reviewScroll.hasVerticalScroller = true
        reviewScroll.borderType = .bezelBorder

        statusLabel.maximumNumberOfLines = 2
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        continueButton.target = self
        continueButton.action = #selector(continueJoin)
        continueButton.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [statusLabel, spacer, cancel, continueButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10

        let stack = NSStackView(views: [
            heading, help, tableScroll, orderButtons, reviewHeading, reviewScroll, actions,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        reviewScroll.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            tableScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            reviewScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            reviewScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            orderButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        if !options.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        refreshReview()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { options.count }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn else { return nil }
        let option = options[row]
        switch tableColumn.identifier.rawValue {
        case "include":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle))
            checkbox.state = includedIDs.contains(option.source.id) ? .on : .off
            checkbox.tag = row
            checkbox.toolTip = "Include \(option.source.sourceURL.lastPathComponent)"
            return checkbox
        case "chapters":
            return editionPopup(option: option, row: row)
        default:
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: cellText(column: tableColumn, row: row))
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            label.textColor =
                includedIDs.contains(option.source.id) ? .labelColor : .tertiaryLabelColor
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateMoveButtons()
    }

    private func editionPopup(option: LosslessJoinSourceOption, row: Int) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = self
        popup.action = #selector(selectEdition)
        popup.tag = row
        if option.editions.isEmpty {
            popup.addItem(withTitle: "No source chapters")
            popup.isEnabled = false
            return popup
        }
        if option.editions.count > 1 {
            popup.addItem(withTitle: "Choose an edition…")
            popup.lastItem?.representedObject = nil
        }
        for (index, edition) in option.editions.enumerated() {
            var facts = ["Edition \(index + 1)", "\(recursiveCount(edition.chapters)) entries"]
            if edition.isDefault { facts.append("default") }
            if edition.isOrdered { facts.append("ordered") }
            popup.addItem(withTitle: facts.joined(separator: " • "))
            popup.lastItem?.representedObject = edition.id.uuidString
        }
        if let selectedID = editionIDs[option.source.id],
            let item = popup.itemArray.first(where: {
                ($0.representedObject as? String) == selectedID.uuidString
            })
        {
            popup.select(item)
        } else {
            popup.selectItem(at: 0)
        }
        popup.isEnabled = includedIDs.contains(option.source.id)
        return popup
    }

    private func cellText(column: NSTableColumn, row: Int) -> String {
        let option = options[row]
        switch column.identifier.rawValue {
        case "order":
            guard includedIDs.contains(option.source.id) else { return "—" }
            let part = options.prefix(row + 1).filter { includedIDs.contains($0.source.id) }.count
            return String(part)
        case "file": return option.source.sourceURL.lastPathComponent
        case "duration": return duration(option.source.duration)
        default: return ""
        }
    }

    @objc private func toggle(_ sender: NSButton) {
        guard options.indices.contains(sender.tag) else { return }
        let id = options[sender.tag].source.id
        if sender.state == .on { includedIDs.insert(id) } else { includedIDs.remove(id) }
        manualMapping = nil
        tableView.reloadData()
        refreshReview()
    }

    @objc private func selectEdition(_ sender: NSPopUpButton) {
        guard options.indices.contains(sender.tag) else { return }
        let sourceID = options[sender.tag].source.id
        if let rawID = sender.selectedItem?.representedObject as? String,
            let editionID = UUID(uuidString: rawID)
        {
            editionIDs[sourceID] = editionID
        } else {
            editionIDs.removeValue(forKey: sourceID)
        }
        refreshReview()
    }

    @objc private func moveSourceUp() { moveSelection(by: -1) }
    @objc private func moveSourceDown() { moveSelection(by: 1) }

    private func moveSelection(by offset: Int) {
        let row = tableView.selectedRow
        let destination = row + offset
        guard options.indices.contains(row), options.indices.contains(destination) else { return }
        options.swapAt(row, destination)
        manualMapping = nil
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: destination), byExtendingSelection: false)
        refreshReview()
    }

    private func updateMoveButtons() {
        moveUpButton.isEnabled = tableView.selectedRow > 0
        moveDownButton.isEnabled =
            tableView.selectedRow >= 0
            && tableView.selectedRow < options.count - 1
    }

    private func refreshReview() {
        let selections = selectedSources()
        snapshot = LosslessJoinReviewBuilder.make(
            selections: selections,
            manualMapping: manualMapping,
            encodingCapabilities: encodingCapabilities
        )
        var lines = ["TRACK LANES"]
        if snapshot.usesManualMapping {
            lines.append("  Explicit mapping confirmed for this exact source order.")
        }
        lines.append(
            contentsOf: snapshot.laneSummaries.isEmpty
                ? ["  None yet"] : snapshot.laneSummaries.map { "  \($0)" })
        lines.append("")
        lines.append("REVIEW")
        if snapshot.issueSummaries.isEmpty {
            lines.append("  No static compatibility issues found.")
        } else {
            lines.append(contentsOf: snapshot.issueSummaries.map { "  • \($0)" })
        }
        lines.append("")
        lines.append("CHAPTER OUTPUT")
        if let chapters = snapshot.candidate?.chapters
            ?? snapshot.commonFormatCandidate?.chapters
        {
            lines.append(
                "  One default nested edition • \(chapters.document.chapterCount) entries • \(duration(chapters.duration))"
            )
        } else {
            lines.append("  Waiting for a complete strict review.")
        }
        lines.append("")
        lines.append("COMMON-FORMAT OPTION")
        lines.append(
            contentsOf: snapshot.normalizationSummaries.isEmpty
                ? ["  Waiting for a complete track map."]
                : snapshot.normalizationSummaries.map { "  \($0)" }
        )
        reviewText.string = lines.joined(separator: "\n")
        mappingButton.isEnabled = snapshot.reviewedMapping != nil
        mappingButton.title =
            snapshot.unresolvedAmbiguities.isEmpty
            ? "Edit Track Mapping…" : "Resolve Track Mapping…"
        continueButton.isEnabled = snapshot.isReady
        if snapshot.candidate != nil {
            continueButton.title = "Continue to Save…"
            statusLabel.stringValue =
                "Ready: zero video encodes. Bundled mkvmerge and the committed output will still be verified."
            statusLabel.textColor = .systemGreen
        } else if let common = snapshot.commonFormatCandidate {
            continueButton.title = "Review Common Format…"
            statusLabel.stringValue =
                "Ready to review: \(common.proposal.impact.videoEncodeCount) video generation and \(common.proposal.impact.audioEncodeCount) audio lane encode(s)."
            statusLabel.textColor = .systemOrange
        } else {
            continueButton.title = "Continue to Save…"
            statusLabel.stringValue = snapshot.blockerSummaries.first ?? "Review is incomplete."
            statusLabel.textColor = .systemOrange
        }
        updateMoveButtons()
    }

    private func selectedSources() -> [LosslessJoinSourceSelection] {
        options.compactMap { option -> LosslessJoinSourceSelection? in
            guard includedIDs.contains(option.source.id) else { return nil }
            return LosslessJoinSourceSelection(
                option: option,
                editionID: editionIDs[option.source.id]
            )
        }
    }

    @objc private func editMapping() {
        guard let mapping = snapshot.reviewedMapping else { return }
        let sources = selectedSources().map(\.option.source)
        onEditMapping?(sources, mapping, !snapshot.unresolvedAmbiguities.isEmpty)
    }

    func acceptManualMapping(_ mapping: JoinTrackMapping, sourceIDs: [UUID]) {
        guard selectedSources().map(\.option.source.id) == sourceIDs else { return }
        manualMapping = LosslessJoinManualMapping(sourceIDs: sourceIDs, mapping: mapping)
        refreshReview()
    }

    @objc private func cancel() { onCancel?() }

    @objc private func continueJoin() {
        guard let selection = snapshot.selection else { return }
        onContinue?(selection)
    }

    private func recursiveCount(_ atoms: [MatroskaChapterAtom]) -> Int {
        atoms.reduce(0) { $0 + 1 + recursiveCount($1.children) }
    }

    private func duration(_ time: MediaTime?) -> String {
        guard let time else { return "Unknown" }
        let total = max(0, Int(time.seconds.rounded()))
        return String(format: "%d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
    }
}
