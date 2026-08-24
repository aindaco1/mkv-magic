import Foundation
import MKVMagicCore

public enum JoinVideoRateControl: Codable, Hashable, Sendable {
    case averageBitrate(Int)
    case constantQuality(Int)
    case codecDefault
}

public enum VideoEncoderTuning: Codable, Hashable, Sendable {
    case codecDefault
    case svtAV1Preset(Int)

    public static let defaultSVTAV1Preset = 8
    public static let minimumSVTAV1Preset = 0
    public static let maximumSVTAV1Preset = 13
}

public enum VideoQualityTier: String, Codable, CaseIterable, Hashable, Sendable {
    case smallerFile
    case balanced
    case higherQuality

    public var displayName: String {
        switch self {
        case .smallerFile: "Smaller File"
        case .balanced: "Balanced"
        case .higherQuality: "Higher Quality"
        }
    }
}

public enum VideoQualityTierPolicy {
    public static func rateControl(
        preset: VideoPreset,
        recommended: JoinVideoRateControl,
        tier: VideoQualityTier
    ) -> JoinVideoRateControl? {
        switch (preset, recommended) {
        case (.av1Quality, .constantQuality):
            let quality =
                switch tier {
                case .smallerFile: 34
                case .balanced: 30
                case .higherQuality: 24
                }
            return .constantQuality(quality)
        case (.hevcCompatibility, .averageBitrate(let value)),
            (.h264Compatibility, .averageBitrate(let value)):
            guard (100_000...200_000_000).contains(value) else { return nil }
            let scaled =
                switch tier {
                case .smallerFile: value * 7 / 10
                case .balanced: value
                case .higherQuality: value * 3 / 2
                }
            return .averageBitrate(min(200_000_000, max(100_000, scaled)))
        case (.proRes, .codecDefault):
            return .codecDefault
        default:
            return nil
        }
    }
}

public struct JoinVideoTargetChoice: Codable, Hashable, Sendable {
    public let preset: VideoPreset
    public let canvas: MediaDimensions
    public let frameRatePolicy: JoinVideoFrameRatePolicy
    public let dynamicRange: JoinVideoDynamicRangeTarget
    public let rateControl: JoinVideoRateControl
    public let encoderTuning: VideoEncoderTuning

    public init(
        preset: VideoPreset,
        canvas: MediaDimensions,
        frameRatePolicy: JoinVideoFrameRatePolicy,
        dynamicRange: JoinVideoDynamicRangeTarget,
        rateControl: JoinVideoRateControl,
        encoderTuning: VideoEncoderTuning = .codecDefault
    ) {
        self.preset = preset
        self.canvas = canvas
        self.frameRatePolicy = frameRatePolicy
        self.dynamicRange = dynamicRange
        self.rateControl = rateControl
        self.encoderTuning = encoderTuning
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case canvas
        case frameRatePolicy
        case dynamicRange
        case rateControl
        case encoderTuning
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        preset = try values.decode(VideoPreset.self, forKey: .preset)
        canvas = try values.decode(MediaDimensions.self, forKey: .canvas)
        frameRatePolicy = try values.decode(
            JoinVideoFrameRatePolicy.self,
            forKey: .frameRatePolicy
        )
        dynamicRange = try values.decode(
            JoinVideoDynamicRangeTarget.self,
            forKey: .dynamicRange
        )
        rateControl = try values.decode(JoinVideoRateControl.self, forKey: .rateControl)
        encoderTuning =
            try values.decodeIfPresent(
                VideoEncoderTuning.self,
                forKey: .encoderTuning
            ) ?? .codecDefault
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(preset, forKey: .preset)
        try values.encode(canvas, forKey: .canvas)
        try values.encode(frameRatePolicy, forKey: .frameRatePolicy)
        try values.encode(dynamicRange, forKey: .dynamicRange)
        try values.encode(rateControl, forKey: .rateControl)
        try values.encode(encoderTuning, forKey: .encoderTuning)
    }
}

public struct JoinAudioTargetChoice: Codable, Hashable, Sendable {
    public let codec: String
    public let channels: Int
    public let channelLayout: String
    public let sampleRate: Int
    public let bitrate: Int
    public let allowsSyntheticSilence: Bool

    public init(
        codec: String,
        channels: Int,
        channelLayout: String,
        sampleRate: Int,
        bitrate: Int,
        allowsSyntheticSilence: Bool
    ) {
        self.codec = codec
        self.channels = channels
        self.channelLayout = channelLayout
        self.sampleRate = sampleRate
        self.bitrate = bitrate
        self.allowsSyntheticSilence = allowsSyntheticSilence
    }
}

/// File-specific, revision-bound decisions for one joined group. These choices
/// are deliberately separate from portable saved workflows: lane/source indices
/// are meaningful only for the exact inspected group that produced the proposal.
public struct JoinNormalizationChoices: Codable, Hashable, Sendable {
    public let videoTargetsByLane: [Int: JoinVideoTargetChoice]
    public let audioTargetsByLane: [Int: JoinAudioTargetChoice]
    public let retainedAttachmentIDsBySource: [Int: Set<Int>]
    public let metadataSourceByLane: [Int: Int]
    public let approvedEmptySubtitleLanes: Set<Int>
    public let approvedVariableFrameRateLanes: Set<Int>

    public init(
        videoTargetsByLane: [Int: JoinVideoTargetChoice] = [:],
        audioTargetsByLane: [Int: JoinAudioTargetChoice] = [:],
        retainedAttachmentIDsBySource: [Int: Set<Int>] = [:],
        metadataSourceByLane: [Int: Int] = [:],
        approvedEmptySubtitleLanes: Set<Int> = [],
        approvedVariableFrameRateLanes: Set<Int> = []
    ) {
        self.videoTargetsByLane = videoTargetsByLane
        self.audioTargetsByLane = audioTargetsByLane
        self.retainedAttachmentIDsBySource = retainedAttachmentIDsBySource
        self.metadataSourceByLane = metadataSourceByLane
        self.approvedEmptySubtitleLanes = approvedEmptySubtitleLanes
        self.approvedVariableFrameRateLanes = approvedVariableFrameRateLanes
    }
}

public enum JoinNormalizationChoiceError: Error, Equatable, Sendable {
    case proposalBlocked
    case reportChanged
    case malformedProposal
    case missingDecision(
        kind: JoinNormalizationDecisionKind,
        laneIndex: Int?,
        sourceIndex: Int?
    )
    case invalidChoice
    case unexpectedChoice
    case unavailableVideoPreset(VideoPreset)
    case unavailableAAC
}

extension JoinNormalizationChoiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .proposalBlocked:
            return "Resolve the common-format proposal blockers before choosing output formats."
        case .reportChanged:
            return "The inspected join facts changed while common-format choices were reviewed."
        case .malformedProposal:
            return "The common-format proposal is incomplete or internally inconsistent."
        case .missingDecision(let kind, let laneIndex, let sourceIndex):
            var location = ""
            if let laneIndex { location += " for lane \(laneIndex + 1)" }
            if let sourceIndex { location += " in Part \(sourceIndex + 1)" }
            return "Confirm the \(kind.rawValue) decision\(location)."
        case .invalidChoice:
            return "A common-format choice does not match the inspected proposal."
        case .unexpectedChoice:
            return "The choice set contains a lane or source that does not need that decision."
        case .unavailableVideoPreset(let preset):
            return "The selected \(preset.rawValue) encoder did not pass the active local probe."
        case .unavailableAAC:
            return "The bundled AAC encoder did not pass the active local probe."
        }
    }
}

public struct ResolvedJoinNormalizationPlan: Hashable, Sendable {
    public let proposal: JoinNormalizationProposal
    public let choices: JoinNormalizationChoices

    fileprivate init(
        proposal: JoinNormalizationProposal,
        choices: JoinNormalizationChoices
    ) {
        self.proposal = proposal
        self.choices = choices
    }
}

public struct JoinNormalizationChoiceResolver: Sendable {
    public init() {}

    public func resolve(
        sources: [MediaAsset],
        proposal: JoinNormalizationProposal,
        choices: JoinNormalizationChoices,
        availableVideoPresets: Set<VideoPreset>,
        aacAvailable: Bool
    ) throws -> ResolvedJoinNormalizationPlan {
        guard proposal.blockers.isEmpty else {
            throw JoinNormalizationChoiceError.proposalBlocked
        }
        let currentReport = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: proposal.report.mapping
        )
        guard JoinCompatibilityReportSnapshot(currentReport, sources: sources) == proposal.report
        else {
            throw JoinNormalizationChoiceError.reportChanged
        }

        let videoLanes = Dictionary(
            uniqueKeysWithValues: proposal.videoLanes.map { ($0.laneIndex, $0) }
        )
        let audioLanes = Dictionary(
            uniqueKeysWithValues: proposal.audioLanes.map { ($0.laneIndex, $0) }
        )
        guard videoLanes.count == proposal.videoLanes.count,
            audioLanes.count == proposal.audioLanes.count
        else {
            throw JoinNormalizationChoiceError.malformedProposal
        }

        var expectedVideoLanes = Set<Int>()
        var expectedAudioLanes = Set<Int>()
        var expectedAttachmentSources = Set<Int>()
        var expectedMetadataLanes = Set<Int>()
        var expectedEmptySubtitleLanes = Set<Int>()
        var expectedVariableRateLanes = Set<Int>()

        for decision in proposal.decisions {
            switch decision.kind {
            case .videoTarget, .mixedDynamicRange:
                let laneIndex = try requiredLane(for: decision)
                expectedVideoLanes.insert(laneIndex)
                guard let lane = videoLanes[laneIndex],
                    let choice = choices.videoTargetsByLane[laneIndex]
                else {
                    throw missing(decision)
                }
                try validate(
                    videoChoice: choice,
                    lane: lane,
                    availableVideoPresets: availableVideoPresets
                )
            case .audioTarget, .missingAudio:
                let laneIndex = try requiredLane(for: decision)
                expectedAudioLanes.insert(laneIndex)
                guard let lane = audioLanes[laneIndex],
                    let choice = choices.audioTargetsByLane[laneIndex]
                else {
                    throw missing(decision)
                }
                guard aacAvailable else { throw JoinNormalizationChoiceError.unavailableAAC }
                try validate(audioChoice: choice, lane: lane)
                if decision.kind == .missingAudio, !choice.allowsSyntheticSilence {
                    throw missing(decision)
                }
            case .attachmentPolicy:
                guard let sourceIndex = decision.sourceIndex,
                    sources.indices.contains(sourceIndex),
                    let retained = choices.retainedAttachmentIDsBySource[sourceIndex]
                else {
                    throw missing(decision)
                }
                expectedAttachmentSources.insert(sourceIndex)
                let available = Set(sources[sourceIndex].attachments.map(\.id))
                guard retained.isSubset(of: available) else {
                    throw JoinNormalizationChoiceError.invalidChoice
                }
            case .trackMetadata:
                let laneIndex = try requiredLane(for: decision)
                guard let sourceIndex = choices.metadataSourceByLane[laneIndex],
                    sources.indices.contains(sourceIndex),
                    proposal.report.mapping.lanes.indices.contains(laneIndex),
                    proposal.report.mapping.lanes[laneIndex].trackIDsBySource[sourceIndex] != nil
                else {
                    throw missing(decision)
                }
                expectedMetadataLanes.insert(laneIndex)
            case .missingSubtitle:
                let laneIndex = try requiredLane(for: decision)
                guard choices.approvedEmptySubtitleLanes.contains(laneIndex) else {
                    throw missing(decision)
                }
                expectedEmptySubtitleLanes.insert(laneIndex)
            case .variableFrameRate:
                let laneIndex = try requiredLane(for: decision)
                guard choices.approvedVariableFrameRateLanes.contains(laneIndex) else {
                    throw missing(decision)
                }
                expectedVariableRateLanes.insert(laneIndex)
            }
        }

        guard Set(choices.videoTargetsByLane.keys) == expectedVideoLanes,
            Set(choices.audioTargetsByLane.keys) == expectedAudioLanes,
            Set(choices.retainedAttachmentIDsBySource.keys) == expectedAttachmentSources,
            Set(choices.metadataSourceByLane.keys) == expectedMetadataLanes,
            choices.approvedEmptySubtitleLanes == expectedEmptySubtitleLanes,
            choices.approvedVariableFrameRateLanes == expectedVariableRateLanes
        else {
            throw JoinNormalizationChoiceError.unexpectedChoice
        }
        return ResolvedJoinNormalizationPlan(proposal: proposal, choices: choices)
    }

    private func validate(
        videoChoice: JoinVideoTargetChoice,
        lane: JoinVideoLaneProposal,
        availableVideoPresets: Set<VideoPreset>
    ) throws {
        guard lane.encodesVideo,
            lane.recommendedCanvas == videoChoice.canvas,
            lane.recommendedFrameRatePolicy == videoChoice.frameRatePolicy,
            lane.dynamicRangeChoices.contains(videoChoice.dynamicRange),
            videoChoice.dynamicRange != .hdr10
                || videoChoice.preset == .av1Quality
                || videoChoice.preset == .hevcCompatibility
        else {
            throw JoinNormalizationChoiceError.invalidChoice
        }
        guard availableVideoPresets.contains(videoChoice.preset) else {
            throw JoinNormalizationChoiceError.unavailableVideoPreset(videoChoice.preset)
        }
        switch (videoChoice.preset, videoChoice.rateControl) {
        case (.hevcCompatibility, .averageBitrate(let bitrate)),
            (.h264Compatibility, .averageBitrate(let bitrate)):
            guard (100_000...200_000_000).contains(bitrate) else {
                throw JoinNormalizationChoiceError.invalidChoice
            }
        case (.av1Quality, .constantQuality(let quality)):
            guard (0...63).contains(quality) else {
                throw JoinNormalizationChoiceError.invalidChoice
            }
        case (.proRes, .codecDefault):
            break
        default:
            throw JoinNormalizationChoiceError.invalidChoice
        }
        switch (videoChoice.preset, videoChoice.encoderTuning) {
        case (.av1Quality, .codecDefault):
            break
        case (.av1Quality, .svtAV1Preset(let value)):
            guard
                (VideoEncoderTuning.minimumSVTAV1Preset...VideoEncoderTuning.maximumSVTAV1Preset)
                    .contains(value)
            else {
                throw JoinNormalizationChoiceError.invalidChoice
            }
        case (_, .codecDefault):
            break
        default:
            throw JoinNormalizationChoiceError.invalidChoice
        }
    }

    private func validate(
        audioChoice: JoinAudioTargetChoice,
        lane: JoinAudioLaneProposal
    ) throws {
        guard lane.encodesAudio,
            audioChoice.codec.caseInsensitiveCompare(lane.outputCodec ?? "") == .orderedSame,
            audioChoice.channels == lane.outputChannels,
            audioChoice.channelLayout == lane.outputChannelLayout,
            audioChoice.sampleRate == lane.outputSampleRate,
            audioChoice.bitrate == lane.outputBitrate,
            (8_000...768_000).contains(audioChoice.sampleRate),
            (1...64).contains(audioChoice.channels),
            (32_000...1_536_000).contains(audioChoice.bitrate)
        else {
            throw JoinNormalizationChoiceError.invalidChoice
        }
    }

    private func requiredLane(
        for decision: JoinNormalizationDecisionRequirement
    ) throws -> Int {
        guard let laneIndex = decision.laneIndex, laneIndex >= 0 else {
            throw JoinNormalizationChoiceError.malformedProposal
        }
        return laneIndex
    }

    private func missing(
        _ decision: JoinNormalizationDecisionRequirement
    ) -> JoinNormalizationChoiceError {
        .missingDecision(
            kind: decision.kind,
            laneIndex: decision.laneIndex,
            sourceIndex: decision.sourceIndex
        )
    }
}
