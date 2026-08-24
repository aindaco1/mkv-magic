import Foundation
import MKVMagicCore

public enum JoinNormalizationPlanningError: Error, Equatable, Sendable {
    case reportChanged
}

extension JoinNormalizationPlanningError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .reportChanged:
            "The inspected join facts changed while the normalization proposal was built."
        }
    }
}

public enum JoinNormalizationSourceAction: String, Codable, Hashable, Sendable {
    case copyAppend
    case encodeOnce
    case synthesizeSilence
    case timelineRemux
    case convertTextOnce
    case emptyTimeline
}

public enum JoinVideoFrameRatePolicy: String, Codable, Hashable, Sendable {
    case preserveSourceTiming
}

public enum JoinVideoDynamicRangeTarget: String, Codable, Hashable, Sendable {
    case sdr
    case hdr10
}

public enum JoinNormalizationDecisionKind: String, Codable, Hashable, Sendable {
    case videoTarget
    case mixedDynamicRange
    case audioTarget
    case attachmentPolicy
    case trackMetadata
    case missingAudio
    case missingSubtitle
    case variableFrameRate
}

public struct JoinNormalizationDecisionRequirement: Codable, Hashable, Sendable {
    public let kind: JoinNormalizationDecisionKind
    public let laneIndex: Int?
    public let sourceIndex: Int?
    public let summary: String

    public init(
        kind: JoinNormalizationDecisionKind,
        laneIndex: Int? = nil,
        sourceIndex: Int? = nil,
        summary: String
    ) {
        self.kind = kind
        self.laneIndex = laneIndex
        self.sourceIndex = sourceIndex
        self.summary = summary
    }
}

public struct JoinNormalizationBlocker: Codable, Hashable, Sendable {
    public let laneIndex: Int?
    public let sourceIndex: Int?
    public let summary: String

    public init(laneIndex: Int? = nil, sourceIndex: Int? = nil, summary: String) {
        self.laneIndex = laneIndex
        self.sourceIndex = sourceIndex
        self.summary = summary
    }
}

public struct JoinVideoLaneProposal: Codable, Hashable, Sendable {
    public let laneIndex: Int
    public let sourceActions: [JoinNormalizationSourceAction]
    public let recommendedPreset: VideoPreset?
    public let recommendedCanvas: MediaDimensions?
    public let recommendedFrameRatePolicy: JoinVideoFrameRatePolicy?
    public let recommendedDynamicRange: JoinVideoDynamicRangeTarget?
    public let dynamicRangeChoices: [JoinVideoDynamicRangeTarget]
    public let outputPixelFormat: String?
    public let outputBitDepth: Int?

    public init(
        laneIndex: Int,
        sourceActions: [JoinNormalizationSourceAction],
        recommendedPreset: VideoPreset?,
        recommendedCanvas: MediaDimensions?,
        recommendedFrameRatePolicy: JoinVideoFrameRatePolicy?,
        recommendedDynamicRange: JoinVideoDynamicRangeTarget?,
        dynamicRangeChoices: [JoinVideoDynamicRangeTarget],
        outputPixelFormat: String?,
        outputBitDepth: Int?
    ) {
        self.laneIndex = laneIndex
        self.sourceActions = sourceActions
        self.recommendedPreset = recommendedPreset
        self.recommendedCanvas = recommendedCanvas
        self.recommendedFrameRatePolicy = recommendedFrameRatePolicy
        self.recommendedDynamicRange = recommendedDynamicRange
        self.dynamicRangeChoices = dynamicRangeChoices
        self.outputPixelFormat = outputPixelFormat
        self.outputBitDepth = outputBitDepth
    }

    public var encodesVideo: Bool { sourceActions.contains(.encodeOnce) }
}

public struct JoinAudioLaneProposal: Codable, Hashable, Sendable {
    public let laneIndex: Int
    public let sourceActions: [JoinNormalizationSourceAction]
    public let outputCodec: String?
    public let outputChannels: Int?
    public let outputChannelLayout: String?
    public let outputSampleRate: Int?
    public let outputBitrate: Int?

    public init(
        laneIndex: Int,
        sourceActions: [JoinNormalizationSourceAction],
        outputCodec: String?,
        outputChannels: Int?,
        outputChannelLayout: String?,
        outputSampleRate: Int?,
        outputBitrate: Int?
    ) {
        self.laneIndex = laneIndex
        self.sourceActions = sourceActions
        self.outputCodec = outputCodec
        self.outputChannels = outputChannels
        self.outputChannelLayout = outputChannelLayout
        self.outputSampleRate = outputSampleRate
        self.outputBitrate = outputBitrate
    }

    public var encodesAudio: Bool { sourceActions.contains(.encodeOnce) }
}

public enum JoinSubtitleLaneMechanism: String, Codable, Hashable, Sendable {
    case packetTimeline
    case normalizeTextToASS
    case unsupported
}

public struct JoinSubtitleLaneProposal: Codable, Hashable, Sendable {
    public let laneIndex: Int
    public let sourceActions: [JoinNormalizationSourceAction]
    public let mechanism: JoinSubtitleLaneMechanism
    public let outputCodec: String?

    public init(
        laneIndex: Int,
        sourceActions: [JoinNormalizationSourceAction],
        mechanism: JoinSubtitleLaneMechanism,
        outputCodec: String?
    ) {
        self.laneIndex = laneIndex
        self.sourceActions = sourceActions
        self.mechanism = mechanism
        self.outputCodec = outputCodec
    }
}

public struct JoinNormalizationProposal: Hashable, Sendable {
    public let report: JoinCompatibilityReportSnapshot
    public let videoLanes: [JoinVideoLaneProposal]
    public let audioLanes: [JoinAudioLaneProposal]
    public let subtitleLanes: [JoinSubtitleLaneProposal]
    public let decisions: [JoinNormalizationDecisionRequirement]
    public let blockers: [JoinNormalizationBlocker]
    public let impact: PlanImpact

    public init(
        report: JoinCompatibilityReportSnapshot,
        videoLanes: [JoinVideoLaneProposal],
        audioLanes: [JoinAudioLaneProposal],
        subtitleLanes: [JoinSubtitleLaneProposal],
        decisions: [JoinNormalizationDecisionRequirement],
        blockers: [JoinNormalizationBlocker],
        impact: PlanImpact
    ) {
        self.report = report
        self.videoLanes = videoLanes
        self.audioLanes = audioLanes
        self.subtitleLanes = subtitleLanes
        self.decisions = decisions
        self.blockers = blockers
        self.impact = impact
    }

    public var canAdvanceToExplicitChoices: Bool { blockers.isEmpty }
}

/// Hashable facts needed to bind a proposal without making the richer
/// compatibility report part of the portable workflow schema yet.
public struct JoinCompatibilityReportSnapshot: Hashable, Sendable {
    public let mapping: JoinTrackMapping
    public let disposition: JoinAppendDisposition
    public let issues: [JoinCompatibilityIssue]
    private let inspectedSources: [MediaAsset]

    public init(_ report: JoinCompatibilityReport, sources: [MediaAsset]) {
        mapping = report.mapping
        disposition = report.disposition
        issues = report.issues
        inspectedSources = sources.map(Self.normalizedSourceFacts)
    }

    private static func normalizedSourceFacts(_ source: MediaAsset) -> MediaAsset {
        MediaAsset(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
            sourceURL: source.sourceURL.standardizedFileURL,
            container: source.container,
            formatLongName: source.formatLongName,
            duration: source.duration,
            fileSize: source.fileSize,
            bitrate: source.bitrate,
            tracks: source.tracks,
            chapters: source.chapters,
            attachments: source.attachments,
            metadata: source.metadata,
            chapterEntryCount: source.chapterEntryCount,
            globalTagCount: source.globalTagCount,
            trackTagCount: source.trackTagCount,
            segmentUID: source.segmentUID,
            muxingApplication: source.muxingApplication,
            writingApplication: source.writingApplication,
            warnings: source.warnings
        )
    }
}

public struct JoinNormalizationPlanner: Sendable {
    public init() {}

    public func propose(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        reviewedReport: JoinCompatibilityReport? = nil,
        preferredVideoPreset: VideoPreset = .av1Quality
    ) throws -> JoinNormalizationProposal {
        let report = try JoinCompatibilityAnalyzer().analyze(sources: sources, mapping: mapping)
        if let reviewedReport, reviewedReport != report {
            throw JoinNormalizationPlanningError.reportChanged
        }
        let indexedTracks = sources.map { source in
            Dictionary(uniqueKeysWithValues: source.tracks.map { ($0.id, $0) })
        }
        var videoLanes = [JoinVideoLaneProposal]()
        var audioLanes = [JoinAudioLaneProposal]()
        var subtitleLanes = [JoinSubtitleLaneProposal]()
        var decisions = [JoinNormalizationDecisionRequirement]()
        var blockers = globalBlockers(report: report)
        decisions.append(contentsOf: globalDecisions(report: report))

        for (laneIndex, lane) in mapping.lanes.enumerated() {
            let tracks = lane.trackIDsBySource.enumerated().map { sourceIndex, trackID in
                trackID.flatMap { indexedTracks[sourceIndex][$0] }
            }
            let issues = report.issues.filter { $0.laneIndex == laneIndex }
            switch lane.kind {
            case .video:
                videoLanes.append(
                    videoProposal(
                        laneIndex: laneIndex,
                        tracks: tracks,
                        issues: issues,
                        preferredPreset: preferredVideoPreset,
                        decisions: &decisions,
                        blockers: &blockers
                    )
                )
            case .audio:
                audioLanes.append(
                    audioProposal(
                        laneIndex: laneIndex,
                        tracks: tracks,
                        issues: issues,
                        decisions: &decisions,
                        blockers: &blockers
                    )
                )
            case .subtitle:
                subtitleLanes.append(
                    subtitleProposal(
                        laneIndex: laneIndex,
                        tracks: tracks,
                        issues: issues,
                        decisions: &decisions,
                        blockers: &blockers
                    )
                )
            default:
                blockers.append(
                    JoinNormalizationBlocker(
                        laneIndex: laneIndex,
                        summary: "Lane \(laneIndex + 1) has an unsupported track type."
                    )
                )
            }
        }

        decisions = stableUnique(decisions)
        blockers = stableUnique(blockers)
        let videoEncodeCount = videoLanes.contains(where: \.encodesVideo) ? 1 : 0
        let audioEncodeCount = audioLanes.filter(\.encodesAudio).count
        var warnings = decisions.map(\.summary)
        if videoEncodeCount == 1 {
            warnings.append(
                "Every video transform must be fused into one filter graph and one final encoded generation."
            )
        }
        if audioEncodeCount > 0 {
            warnings.append(
                "Each affected audio lane is converted once; compatible audio lanes remain packet copies."
            )
        }
        return JoinNormalizationProposal(
            report: JoinCompatibilityReportSnapshot(report, sources: sources),
            videoLanes: videoLanes,
            audioLanes: audioLanes,
            subtitleLanes: subtitleLanes,
            decisions: decisions,
            blockers: blockers,
            impact: PlanImpact(
                videoEncodeCount: videoEncodeCount,
                audioEncodeCount: audioEncodeCount,
                copiesVideo: videoEncodeCount == 0,
                warnings: warnings
            )
        )
    }

    private func videoProposal(
        laneIndex: Int,
        tracks: [MediaTrack?],
        issues: [JoinCompatibilityIssue],
        preferredPreset: VideoPreset,
        decisions: inout [JoinNormalizationDecisionRequirement],
        blockers: inout [JoinNormalizationBlocker]
    ) -> JoinVideoLaneProposal {
        let needsEncode = issues.contains { $0.severity == .normalizationRequired }
        guard needsEncode else {
            if tracks.contains(where: { $0 == nil }) {
                blockers.append(
                    JoinNormalizationBlocker(
                        laneIndex: laneIndex,
                        summary: "Video lane \(laneIndex + 1) is missing from at least one part."
                    )
                )
            }
            if issues.contains(where: { $0.reason == .incompleteParameters }) {
                blockers.append(
                    JoinNormalizationBlocker(
                        laneIndex: laneIndex,
                        summary:
                            "Video lane \(laneIndex + 1) lacks facts required for a safe copy plan."
                    )
                )
            }
            if issues.contains(where: { $0.reason == .frameRate }) {
                decisions.append(
                    JoinNormalizationDecisionRequirement(
                        kind: .variableFrameRate,
                        laneIndex: laneIndex,
                        summary:
                            "Confirm source-timed frame-rate changes in video lane \(laneIndex + 1)."
                    )
                )
            }
            return JoinVideoLaneProposal(
                laneIndex: laneIndex,
                sourceActions: tracks.map { $0 == nil ? .emptyTimeline : .copyAppend },
                recommendedPreset: nil,
                recommendedCanvas: nil,
                recommendedFrameRatePolicy: nil,
                recommendedDynamicRange: nil,
                dynamicRangeChoices: [],
                outputPixelFormat: nil,
                outputBitDepth: nil
            )
        }

        if tracks.contains(where: { $0 == nil }) {
            blockers.append(
                JoinNormalizationBlocker(
                    laneIndex: laneIndex,
                    summary:
                        "Video lane \(laneIndex + 1) cannot synthesize a missing picture track."
                )
            )
        }
        let presentTracks = tracks.compactMap { $0 }
        let dimensions = presentTracks.compactMap(\.dimensions)
        let safeDimensions = dimensions.filter {
            (1...Self.maximumVideoDimension).contains($0.width)
                && (1...Self.maximumVideoDimension).contains($0.height)
        }
        if safeDimensions.count != presentTracks.count {
            blockers.append(
                JoinNormalizationBlocker(
                    laneIndex: laneIndex,
                    summary:
                        "Video lane \(laneIndex + 1) needs known, bounded positive encoded dimensions."
                )
            )
        }
        let largestCanvas = safeDimensions.max { lhs, rhs in
            let leftArea = Int64(lhs.width) * Int64(lhs.height)
            let rightArea = Int64(rhs.width) * Int64(rhs.height)
            if leftArea == rightArea { return lhs.width < rhs.width }
            return leftArea < rightArea
        }
        let canvas = largestCanvas.flatMap(evenCanvas)
        if largestCanvas != nil, canvas == nil {
            blockers.append(
                JoinNormalizationBlocker(
                    laneIndex: laneIndex,
                    summary:
                        "Video lane \(laneIndex + 1) cannot produce a bounded even-sized output canvas."
                )
            )
        }

        let dynamicRanges = presentTracks.map(dynamicRange)
        var recommendedDynamicRange: JoinVideoDynamicRangeTarget?
        var dynamicRangeChoices = [JoinVideoDynamicRangeTarget]()
        if dynamicRanges.contains(.dolbyVision) {
            blockers.append(
                JoinNormalizationBlocker(
                    laneIndex: laneIndex,
                    summary:
                        "Dolby Vision in video lane \(laneIndex + 1) cannot be normalized with guaranteed metadata preservation."
                )
            )
        } else if dynamicRanges.contains(.otherHDR) || dynamicRanges.contains(.unknown) {
            blockers.append(
                JoinNormalizationBlocker(
                    laneIndex: laneIndex,
                    summary:
                        "Video lane \(laneIndex + 1) has unknown or unsupported dynamic-range metadata."
                )
            )
        } else if Set(dynamicRanges) == [.hdr10] {
            recommendedDynamicRange = .hdr10
            dynamicRangeChoices = [.hdr10]
            let signals = presentTracks.compactMap(MediaHDR10Signal.init(track:))
            if signals.count != presentTracks.count || Set(signals).count != 1 {
                blockers.append(
                    JoinNormalizationBlocker(
                        laneIndex: laneIndex,
                        summary:
                            "Video lane \(laneIndex + 1) has differing or incomplete static HDR10 metadata that cannot be preserved as one joined signal."
                    )
                )
            }
            if preferredPreset != .av1Quality && preferredPreset != .hevcCompatibility {
                blockers.append(
                    JoinNormalizationBlocker(
                        laneIndex: laneIndex,
                        summary:
                            "Video lane \(laneIndex + 1) needs an AV1 or HEVC 10-bit target to preserve HDR10."
                    )
                )
            }
        } else if Set(dynamicRanges) == [.sdr] {
            recommendedDynamicRange = .sdr
            dynamicRangeChoices = [.sdr]
        } else if Set(dynamicRanges) == [.sdr, .hdr10] {
            dynamicRangeChoices = [.sdr, .hdr10]
            decisions.append(
                JoinNormalizationDecisionRequirement(
                    kind: .mixedDynamicRange,
                    laneIndex: laneIndex,
                    summary:
                        "Choose SDR tone mapping or an HDR10 signal for mixed SDR/HDR Part content in video lane \(laneIndex + 1)."
                )
            )
        }
        decisions.append(
            JoinNormalizationDecisionRequirement(
                kind: .videoTarget,
                laneIndex: laneIndex,
                summary:
                    "Confirm \(videoPresetSummary(preferredPreset)), fit-and-pad canvas, source timing, pixel format, and color target for video lane \(laneIndex + 1)."
            )
        )
        let pixelFormat: String
        let bitDepth: Int
        switch preferredPreset {
        case .av1Quality, .hevcCompatibility:
            pixelFormat = "yuv420p10le"
            bitDepth = 10
        case .h264Compatibility:
            pixelFormat = "yuv420p"
            bitDepth = 8
        case .proRes:
            pixelFormat = "yuv422p10le"
            bitDepth = 10
        }
        return JoinVideoLaneProposal(
            laneIndex: laneIndex,
            sourceActions: tracks.map { $0 == nil ? .emptyTimeline : .encodeOnce },
            recommendedPreset: preferredPreset,
            recommendedCanvas: canvas,
            recommendedFrameRatePolicy: .preserveSourceTiming,
            recommendedDynamicRange: recommendedDynamicRange,
            dynamicRangeChoices: dynamicRangeChoices,
            outputPixelFormat: pixelFormat,
            outputBitDepth: bitDepth
        )
    }

    private func audioProposal(
        laneIndex: Int,
        tracks: [MediaTrack?],
        issues: [JoinCompatibilityIssue],
        decisions: inout [JoinNormalizationDecisionRequirement],
        blockers: inout [JoinNormalizationBlocker]
    ) -> JoinAudioLaneProposal {
        let isMissing = tracks.contains(where: { $0 == nil })
        let needsEncode = isMissing || issues.contains { $0.severity == .normalizationRequired }
        guard needsEncode else {
            if issues.contains(where: { $0.reason == .incompleteParameters }) {
                blockers.append(
                    JoinNormalizationBlocker(
                        laneIndex: laneIndex,
                        summary:
                            "Audio lane \(laneIndex + 1) lacks facts required for a safe copy plan."
                    )
                )
            }
            return JoinAudioLaneProposal(
                laneIndex: laneIndex,
                sourceActions: tracks.map { $0 == nil ? .emptyTimeline : .copyAppend },
                outputCodec: nil,
                outputChannels: nil,
                outputChannelLayout: nil,
                outputSampleRate: nil,
                outputBitrate: nil
            )
        }

        let presentTracks = tracks.compactMap { $0 }
        let complete = presentTracks.allSatisfy {
            (1...Self.maximumAudioChannels).contains($0.channels ?? 0)
                && (1...Self.maximumAudioSampleRate).contains($0.sampleRate ?? 0)
                && !normalized($0.channelLayout).isEmpty
        }
        guard complete else {
            blockers.append(
                JoinNormalizationBlocker(
                    laneIndex: laneIndex,
                    summary:
                        "Audio lane \(laneIndex + 1) needs known channels, layout, and sample rate."
                )
            )
            return JoinAudioLaneProposal(
                laneIndex: laneIndex,
                sourceActions: tracks.map { $0 == nil ? .synthesizeSilence : .encodeOnce },
                outputCodec: "AAC",
                outputChannels: nil,
                outputChannelLayout: nil,
                outputSampleRate: nil,
                outputBitrate: nil
            )
        }
        let targetTrack = presentTracks.enumerated().max { lhs, rhs in
            let leftChannels = lhs.element.channels ?? 0
            let rightChannels = rhs.element.channels ?? 0
            if leftChannels == rightChannels { return lhs.offset > rhs.offset }
            return leftChannels < rightChannels
        }?.element
        let channels = targetTrack?.channels
        let sampleRate = presentTracks.compactMap(\.sampleRate).max()
        decisions.append(
            JoinNormalizationDecisionRequirement(
                kind: .audioTarget,
                laneIndex: laneIndex,
                summary:
                    "Choose one locally verified common format for the largest source layout in audio lane \(laneIndex + 1); no downmix is automatic."
            )
        )
        if isMissing {
            decisions.append(
                JoinNormalizationDecisionRequirement(
                    kind: .missingAudio,
                    laneIndex: laneIndex,
                    summary:
                        "Confirm silence for parts without audio lane \(laneIndex + 1); available channels are never fabricated from other content."
                )
            )
        }
        return JoinAudioLaneProposal(
            laneIndex: laneIndex,
            sourceActions: tracks.map { $0 == nil ? .synthesizeSilence : .encodeOnce },
            outputCodec: "AAC",
            outputChannels: channels,
            outputChannelLayout: targetTrack?.channelLayout,
            outputSampleRate: sampleRate,
            outputBitrate: channels.map(aacBitrate)
        )
    }

    private func subtitleProposal(
        laneIndex: Int,
        tracks: [MediaTrack?],
        issues: [JoinCompatibilityIssue],
        decisions: inout [JoinNormalizationDecisionRequirement],
        blockers: inout [JoinNormalizationBlocker]
    ) -> JoinSubtitleLaneProposal {
        let hasCodecMismatch = issues.contains {
            $0.severity == .normalizationRequired && ($0.reason == .codec || $0.reason == .profile)
        }
        let isMissing = tracks.contains(where: { $0 == nil })
        if isMissing {
            decisions.append(
                JoinNormalizationDecisionRequirement(
                    kind: .missingSubtitle,
                    laneIndex: laneIndex,
                    summary:
                        "Confirm an empty timed section for parts without subtitle lane \(laneIndex + 1)."
                )
            )
        }
        if issues.contains(where: { $0.reason == .incompleteParameters }) {
            blockers.append(
                JoinNormalizationBlocker(
                    laneIndex: laneIndex,
                    summary:
                        "Subtitle lane \(laneIndex + 1) lacks facts required for a safe conversion or copy plan."
                )
            )
        }
        guard hasCodecMismatch else {
            return JoinSubtitleLaneProposal(
                laneIndex: laneIndex,
                sourceActions: tracks.map { $0 == nil ? .emptyTimeline : .timelineRemux },
                mechanism: .packetTimeline,
                outputCodec: tracks.compactMap { $0?.codecID ?? $0?.codec }.first
            )
        }
        if tracks.compactMap({ $0 }).allSatisfy(isTextSubtitle) {
            return JoinSubtitleLaneProposal(
                laneIndex: laneIndex,
                sourceActions: tracks.map { $0 == nil ? .emptyTimeline : .convertTextOnce },
                mechanism: .normalizeTextToASS,
                outputCodec: "S_TEXT/ASS"
            )
        }
        blockers.append(
            JoinNormalizationBlocker(
                laneIndex: laneIndex,
                summary:
                    "Subtitle lane \(laneIndex + 1) mixes image or unsupported formats; image-to-text conversion is not in v1."
            )
        )
        return JoinSubtitleLaneProposal(
            laneIndex: laneIndex,
            sourceActions: tracks.map { $0 == nil ? .emptyTimeline : .timelineRemux },
            mechanism: .unsupported,
            outputCodec: nil
        )
    }

    private func globalBlockers(report: JoinCompatibilityReport) -> [JoinNormalizationBlocker] {
        var blockers = [JoinNormalizationBlocker]()
        for issue in report.issues where issue.laneIndex == nil {
            switch issue.reason {
            case .nonMatroskaSource:
                blockers.append(
                    JoinNormalizationBlocker(
                        sourceIndex: issue.sourceIndex,
                        summary:
                            "Part \(issue.sourceIndex + 1) is not Matroska; its structural join policy is not implemented yet."
                    )
                )
            case .unsupportedTrackKind:
                blockers.append(
                    JoinNormalizationBlocker(
                        sourceIndex: issue.sourceIndex,
                        summary:
                            "Part \(issue.sourceIndex + 1) contains an unsupported track type."
                    )
                )
            default:
                break
            }
        }
        return blockers
    }

    private func globalDecisions(
        report: JoinCompatibilityReport
    ) -> [JoinNormalizationDecisionRequirement] {
        var decisions = [JoinNormalizationDecisionRequirement]()
        for issue in report.issues {
            switch issue.reason {
            case .attachmentSelection:
                decisions.append(
                    JoinNormalizationDecisionRequirement(
                        kind: .attachmentPolicy,
                        sourceIndex: issue.sourceIndex,
                        summary:
                            "Choose which attachments to keep from Part \(issue.sourceIndex + 1)."
                    )
                )
            case .language, .role, .title, .flags:
                decisions.append(
                    JoinNormalizationDecisionRequirement(
                        kind: .trackMetadata,
                        laneIndex: issue.laneIndex,
                        sourceIndex: issue.sourceIndex,
                        summary:
                            "Confirm output metadata for lane \((issue.laneIndex ?? 0) + 1)."
                    )
                )
            default:
                break
            }
        }
        return decisions
    }

    private func aacBitrate(channels: Int) -> Int {
        switch channels {
        case ...1: 96_000
        case 2: 192_000
        case 3...6: 512_000
        default: 640_000
        }
    }

    private func isTextSubtitle(_ track: MediaTrack) -> Bool {
        let facts = [track.codec, track.codecID].compactMap { $0 }.map(normalized)
        return facts.contains { fact in
            fact.contains("subrip") || fact.contains("s_text/utf8")
                || fact.contains("s_text/ass") || fact.contains("s_text/ssa")
                || fact == "ass" || fact == "ssa" || fact.contains("webvtt")
        }
    }

    private enum DynamicRange: Hashable {
        case sdr
        case hdr10
        case dolbyVision
        case otherHDR
        case unknown
    }

    private func dynamicRange(_ track: MediaTrack) -> DynamicRange {
        let formats = track.hdrFormats.map(normalized)
        if formats.contains(where: { $0.contains("dolby vision") || $0.contains("dovi") }) {
            return .dolbyVision
        }
        if formats.contains(where: {
            $0.contains("hdr10+") || $0.contains("hdr10 plus") || $0.contains("hlg")
        }) {
            return .otherHDR
        }
        if MediaHDR10Signal(track: track) != nil { return .hdr10 }
        if !formats.isEmpty { return .otherHDR }
        if MediaHDR10Signal.isBT709SDR(track) { return .sdr }
        if track.colorInfo != nil { return .otherHDR }
        return .unknown
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func evenCanvas(_ dimensions: MediaDimensions) -> MediaDimensions? {
        let width = dimensions.width + dimensions.width % 2
        let height = dimensions.height + dimensions.height % 2
        guard width <= Self.maximumVideoDimension, height <= Self.maximumVideoDimension else {
            return nil
        }
        return MediaDimensions(width: width, height: height)
    }

    private func videoPresetSummary(_ preset: VideoPreset) -> String {
        preset.displayName
    }

    private func stableUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private static let maximumVideoDimension = 65_535
    private static let maximumAudioChannels = 64
    private static let maximumAudioSampleRate = 768_000
}
