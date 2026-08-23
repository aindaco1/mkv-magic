import Foundation
import MKVMagicCore

public enum ExactTrimAudioPolicy: String, Codable, Hashable, Sendable {
    case packetCopy
    case aacPreserveLayout
}

public struct ExactTrimChoice: Codable, Hashable, Sendable {
    public let videoPreset: VideoPreset
    public let videoRateControl: JoinVideoRateControl
    public let audioPolicy: ExactTrimAudioPolicy

    public init(
        videoPreset: VideoPreset,
        videoRateControl: JoinVideoRateControl,
        audioPolicy: ExactTrimAudioPolicy = .packetCopy
    ) {
        self.videoPreset = videoPreset
        self.videoRateControl = videoRateControl
        self.audioPolicy = audioPolicy
    }
}

public enum ExactTrimPlanningError: Error, Equatable, Sendable {
    case unsupportedSource
    case invalidDuration
    case invalidRange
    case noChange
    case unsupportedTracks
    case unsupportedTags
    case unsupportedDynamicRange
    case incompleteVideoFacts
    case incompleteAudioFacts(trackID: Int)
    case unavailableVideoPreset(VideoPreset)
    case unavailableAAC
    case invalidChoice
}

extension ExactTrimPlanningError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource: "Exact Trim currently accepts an inspected Matroska MKV."
        case .invalidDuration: "Exact Trim needs a known positive source duration."
        case .invalidRange: "The exact in/out range must be positive and inside the source."
        case .noChange: "The requested range keeps the complete source."
        case .unsupportedTracks:
            "Exact Trim currently supports one video plus audio; subtitle and data tracks need a later timing-safe path."
        case .unsupportedTags:
            "Exact Trim cannot yet prove preservation of this source's Matroska tags."
        case .unsupportedDynamicRange:
            "Exact Trim currently requires reviewed BT.709 SDR video; HDR and Dolby Vision fail closed."
        case .incompleteVideoFacts:
            "Exact Trim needs complete even video dimensions and color facts."
        case .incompleteAudioFacts(let trackID):
            "Audio track \(trackID) needs complete layout facts before AAC conversion."
        case .unavailableVideoPreset(let preset):
            "The selected \(preset.rawValue) encoder did not pass the active local probe."
        case .unavailableAAC: "The bundled AAC encoder did not pass the active local probe."
        case .invalidChoice: "The Exact Trim encoding choice is outside its safe bounds."
        }
    }
}

public struct ResolvedExactTrimPlan: Hashable, Sendable {
    public let source: MediaAsset
    public let range: MediaTrimRange
    public let choice: ExactTrimChoice
    public let videoTrackID: Int
    public let audioTrackIDs: [Int]
    public let trackIDsInOutputOrder: [Int]

    fileprivate init(
        source: MediaAsset,
        range: MediaTrimRange,
        choice: ExactTrimChoice,
        videoTrackID: Int,
        audioTrackIDs: [Int],
        trackIDsInOutputOrder: [Int]
    ) {
        self.source = source
        self.range = range
        self.choice = choice
        self.videoTrackID = videoTrackID
        self.audioTrackIDs = audioTrackIDs
        self.trackIDsInOutputOrder = trackIDsInOutputOrder
    }

    public var videoEncodeCount: Int { 1 }
    public var audioEncodeCount: Int {
        choice.audioPolicy == .aacPreserveLayout ? audioTrackIDs.count : 0
    }
}

public struct ExactTrimPlanner: Sendable {
    public init() {}

    public func recommendedChoice(
        for source: MediaAsset,
        availableVideoPresets: [VideoPreset]
    ) -> ExactTrimChoice? {
        guard let preset = availableVideoPresets.first,
            let video = source.tracks.first(where: { $0.kind == .video })
        else { return nil }
        let rateControl: JoinVideoRateControl
        switch preset {
        case .av1Quality:
            rateControl = .constantQuality(30)
        case .hevcCompatibility:
            rateControl = .averageBitrate(recommendedBitrate(video: video, multiplier: 4))
        case .h264Compatibility:
            rateControl = .averageBitrate(recommendedBitrate(video: video, multiplier: 6))
        case .proRes:
            rateControl = .codecDefault
        }
        return ExactTrimChoice(
            videoPreset: preset,
            videoRateControl: rateControl,
            audioPolicy: .packetCopy
        )
    }

    public func resolve(
        source: MediaAsset,
        range: MediaTrimRange,
        choice: ExactTrimChoice,
        availableVideoPresets: Set<VideoPreset>,
        aacAvailable: Bool
    ) throws -> ResolvedExactTrimPlan {
        guard source.sourceURL.pathExtension.lowercased() == "mkv",
            source.container.localizedCaseInsensitiveContains("matroska")
                || source.container.localizedCaseInsensitiveContains("webm")
        else {
            throw ExactTrimPlanningError.unsupportedSource
        }
        guard let duration = source.duration, duration > .zero else {
            throw ExactTrimPlanningError.invalidDuration
        }
        guard range.start >= .zero, range.end > range.start, range.end <= duration else {
            throw ExactTrimPlanningError.invalidRange
        }
        guard range.start != .zero || range.end != duration else {
            throw ExactTrimPlanningError.noChange
        }
        let videos = source.tracks.filter { $0.kind == .video }
        let audios = source.tracks.filter { $0.kind == .audio }
        guard videos.count == 1,
            source.tracks.count == videos.count + audios.count,
            Set(source.tracks.map(\.id)).count == source.tracks.count
        else {
            throw ExactTrimPlanningError.unsupportedTracks
        }
        guard source.globalTagCount == 0, source.trackTagCount == 0 else {
            throw ExactTrimPlanningError.unsupportedTags
        }
        let video = videos[0]
        guard video.hdrFormats.isEmpty, isBT709SDR(video) else {
            throw ExactTrimPlanningError.unsupportedDynamicRange
        }
        guard let dimensions = video.dimensions,
            dimensions.width > 0,
            dimensions.height > 0,
            dimensions.width.isMultiple(of: 2),
            dimensions.height.isMultiple(of: 2)
        else {
            throw ExactTrimPlanningError.incompleteVideoFacts
        }
        guard availableVideoPresets.contains(choice.videoPreset) else {
            throw ExactTrimPlanningError.unavailableVideoPreset(choice.videoPreset)
        }
        try validate(choice)
        if choice.audioPolicy == .aacPreserveLayout {
            guard aacAvailable else { throw ExactTrimPlanningError.unavailableAAC }
            for audio in audios {
                guard let channels = audio.channels, (1...8).contains(channels),
                    let sampleRate = audio.sampleRate, (8_000...192_000).contains(sampleRate),
                    let layout = audio.channelLayout, !layout.isEmpty
                else {
                    throw ExactTrimPlanningError.incompleteAudioFacts(trackID: audio.id)
                }
            }
        }
        return ResolvedExactTrimPlan(
            source: source,
            range: range,
            choice: choice,
            videoTrackID: video.id,
            audioTrackIDs: audios.map(\.id),
            trackIDsInOutputOrder: source.tracks.map(\.id)
        )
    }

    private func validate(_ choice: ExactTrimChoice) throws {
        switch (choice.videoPreset, choice.videoRateControl) {
        case (.av1Quality, .constantQuality(let quality)):
            guard (0...63).contains(quality) else {
                throw ExactTrimPlanningError.invalidChoice
            }
        case (.hevcCompatibility, .averageBitrate(let bitrate)),
            (.h264Compatibility, .averageBitrate(let bitrate)):
            guard (100_000...200_000_000).contains(bitrate) else {
                throw ExactTrimPlanningError.invalidChoice
            }
        case (.proRes, .codecDefault):
            break
        default:
            throw ExactTrimPlanningError.invalidChoice
        }
    }

    private func isBT709SDR(_ track: MediaTrack) -> Bool {
        guard let color = track.colorInfo else { return false }
        return normalized(color.primaries) == "bt709"
            && normalized(color.transfer) == "bt709"
            && normalized(color.matrix) == "bt709"
    }

    private func recommendedBitrate(video: MediaTrack, multiplier: Int) -> Int {
        guard let dimensions = video.dimensions else { return 8_000_000 }
        let pixels = dimensions.width.multipliedReportingOverflow(by: dimensions.height)
        guard !pixels.overflow else { return 50_000_000 }
        let bitrate = pixels.partialValue.multipliedReportingOverflow(by: multiplier)
        guard !bitrate.overflow else { return 50_000_000 }
        return min(50_000_000, max(500_000, bitrate.partialValue))
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
