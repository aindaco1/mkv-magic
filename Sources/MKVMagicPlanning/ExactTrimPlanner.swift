import Foundation
import MKVMagicCore

public enum ExactVideoOperation: String, Codable, Hashable, Sendable {
    case trim
    case transcode
}

public enum ExactTrimAudioPolicy: String, Codable, Hashable, Sendable {
    case packetCopy
    case aacPreserveLayout
    case opusPreserveLayout
    case ac3PreserveLayout
    case eac3PreserveLayout
    case flacPreserveLayout

    public init(preset: AudioTranscodePreset) {
        switch preset {
        case .aacCompatibility: self = .aacPreserveLayout
        case .opusQuality: self = .opusPreserveLayout
        case .ac3Compatibility: self = .ac3PreserveLayout
        case .eac3Compatibility: self = .eac3PreserveLayout
        case .flacLossless: self = .flacPreserveLayout
        }
    }

    public var transcodePreset: AudioTranscodePreset? {
        switch self {
        case .packetCopy: nil
        case .aacPreserveLayout: .aacCompatibility
        case .opusPreserveLayout: .opusQuality
        case .ac3PreserveLayout: .ac3Compatibility
        case .eac3PreserveLayout: .eac3Compatibility
        case .flacPreserveLayout: .flacLossless
        }
    }
}

public struct ExactTrimChoice: Codable, Hashable, Sendable {
    public let videoPreset: VideoPreset
    public let videoRateControl: JoinVideoRateControl
    public let encoderTuning: VideoEncoderTuning
    public let audioPolicy: ExactTrimAudioPolicy

    public init(
        videoPreset: VideoPreset,
        videoRateControl: JoinVideoRateControl,
        encoderTuning: VideoEncoderTuning = .codecDefault,
        audioPolicy: ExactTrimAudioPolicy = .packetCopy
    ) {
        self.videoPreset = videoPreset
        self.videoRateControl = videoRateControl
        self.encoderTuning = encoderTuning
        self.audioPolicy = audioPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case videoPreset
        case videoRateControl
        case encoderTuning
        case audioPolicy
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        videoPreset = try values.decode(VideoPreset.self, forKey: .videoPreset)
        videoRateControl = try values.decode(
            JoinVideoRateControl.self,
            forKey: .videoRateControl
        )
        encoderTuning =
            try values.decodeIfPresent(
                VideoEncoderTuning.self,
                forKey: .encoderTuning
            ) ?? .codecDefault
        audioPolicy = try values.decode(ExactTrimAudioPolicy.self, forKey: .audioPolicy)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(videoPreset, forKey: .videoPreset)
        try values.encode(videoRateControl, forKey: .videoRateControl)
        try values.encode(encoderTuning, forKey: .encoderTuning)
        try values.encode(audioPolicy, forKey: .audioPolicy)
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
    case unavailableAudioPreset(AudioTranscodePreset)
    case invalidChoice
}

extension ExactTrimPlanningError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "One-generation video processing currently accepts an inspected Matroska MKV."
        case .invalidDuration: "Video processing needs a known positive source duration."
        case .invalidRange: "The reviewed range must be positive and inside the source."
        case .noChange: "The requested range keeps the complete source."
        case .unsupportedTracks:
            "Complete-file conversion supports packet-copied subtitles; exact trimming of subtitles and data tracks needs a later timing-safe path."
        case .unsupportedTags:
            "Video processing cannot yet prove preservation of this source's Matroska tags."
        case .unsupportedDynamicRange:
            "Video processing requires reviewed BT.709 SDR or static HDR10 video; other HDR formats fail closed."
        case .incompleteVideoFacts:
            "Video processing needs complete even video dimensions and color facts."
        case .incompleteAudioFacts(let trackID):
            "Audio track \(trackID) needs a layout and sample rate the selected audio format can preserve safely."
        case .unavailableVideoPreset(let preset):
            "The selected \(preset.rawValue) encoder did not pass the active local probe."
        case .unavailableAAC: "The bundled AAC encoder did not pass the active local probe."
        case .unavailableAudioPreset(let preset):
            "The bundled \(preset.displayName) encoder did not pass the active local probe."
        case .invalidChoice: "The video encoding choice is outside its safe bounds."
        }
    }
}

public struct ResolvedExactTrimPlan: Hashable, Sendable {
    public let operation: ExactVideoOperation
    public let source: MediaAsset
    public let range: MediaTrimRange
    public let choice: ExactTrimChoice
    public let videoTrackID: Int
    public let videoDynamicRange: JoinVideoDynamicRangeTarget
    public let hdr10Signal: MediaHDR10Signal?
    public let audioTrackIDs: [Int]
    public let encodedAudioTrackIDs: [Int]
    public let copiedAudioTrackIDs: [Int]
    public let subtitleTrackIDs: [Int]
    public let trackIDsInOutputOrder: [Int]

    fileprivate init(
        operation: ExactVideoOperation,
        source: MediaAsset,
        range: MediaTrimRange,
        choice: ExactTrimChoice,
        videoTrackID: Int,
        videoDynamicRange: JoinVideoDynamicRangeTarget,
        hdr10Signal: MediaHDR10Signal?,
        audioTrackIDs: [Int],
        encodedAudioTrackIDs: [Int],
        copiedAudioTrackIDs: [Int],
        subtitleTrackIDs: [Int],
        trackIDsInOutputOrder: [Int]
    ) {
        self.operation = operation
        self.source = source
        self.range = range
        self.choice = choice
        self.videoTrackID = videoTrackID
        self.videoDynamicRange = videoDynamicRange
        self.hdr10Signal = hdr10Signal
        self.audioTrackIDs = audioTrackIDs
        self.encodedAudioTrackIDs = encodedAudioTrackIDs
        self.copiedAudioTrackIDs = copiedAudioTrackIDs
        self.subtitleTrackIDs = subtitleTrackIDs
        self.trackIDsInOutputOrder = trackIDsInOutputOrder
    }

    public var videoEncodeCount: Int { 1 }
    public var audioEncodeCount: Int { encodedAudioTrackIDs.count }
}

public struct ExactTrimPlanner: Sendable {
    public init() {}

    public func recommendedChoice(
        for source: MediaAsset,
        availableVideoPresets: [VideoPreset]
    ) -> ExactTrimChoice? {
        guard let video = source.tracks.first(where: { $0.kind == .video })
        else { return nil }
        let compatiblePresets =
            MediaHDR10Signal(track: video) == nil
            ? availableVideoPresets
            : availableVideoPresets.filter {
                $0 == .av1Quality || $0 == .hevcCompatibility
            }
        guard let preset = compatiblePresets.first else { return nil }
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
            encoderTuning: preset == .av1Quality
                ? .svtAV1Preset(VideoEncoderTuning.defaultSVTAV1Preset)
                : .codecDefault,
            audioPolicy: .packetCopy
        )
    }

    public func resolve(
        source: MediaAsset,
        range: MediaTrimRange,
        choice: ExactTrimChoice,
        operation: ExactVideoOperation = .trim,
        availableVideoPresets: Set<VideoPreset>,
        aacAvailable: Bool,
        availableAudioPresets: Set<AudioTranscodePreset> = []
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
        guard operation == .trim || (range.start == .zero && range.end == duration) else {
            throw ExactTrimPlanningError.invalidRange
        }
        guard operation == .transcode || range.start != .zero || range.end != duration else {
            throw ExactTrimPlanningError.noChange
        }
        let videos = source.tracks.filter { $0.kind == .video }
        let audios = source.tracks.filter { $0.kind == .audio }
        let subtitles = source.tracks.filter { $0.kind == .subtitle }
        let supportedTrackCount = videos.count + audios.count + subtitles.count
        guard videos.count == 1,
            source.tracks.count == supportedTrackCount,
            operation == .transcode || subtitles.isEmpty,
            Set(source.tracks.map(\.id)).count == source.tracks.count
        else {
            throw ExactTrimPlanningError.unsupportedTracks
        }
        guard source.globalTagCount == 0, source.trackTagCount == 0 else {
            throw ExactTrimPlanningError.unsupportedTags
        }
        let video = videos[0]
        let hdr10Signal = MediaHDR10Signal(track: video)
        let videoDynamicRange: JoinVideoDynamicRangeTarget
        if MediaHDR10Signal.isBT709SDR(video) {
            videoDynamicRange = .sdr
        } else if hdr10Signal != nil {
            videoDynamicRange = .hdr10
        } else {
            throw ExactTrimPlanningError.unsupportedDynamicRange
        }
        if videoDynamicRange == .hdr10,
            choice.videoPreset != .av1Quality && choice.videoPreset != .hevcCompatibility
        {
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
        let encodedAudioTracks: [MediaTrack]
        if let audioPreset = choice.audioPolicy.transcodePreset {
            encodedAudioTracks = audios.filter {
                !audioPreset.matches(sourceCodec: $0.codec)
            }
            let effectiveAudioPresets = availableAudioPresets.union(
                aacAvailable ? [.aacCompatibility] : []
            )
            guard encodedAudioTracks.isEmpty || effectiveAudioPresets.contains(audioPreset) else {
                if audioPreset == .aacCompatibility {
                    throw ExactTrimPlanningError.unavailableAAC
                }
                throw ExactTrimPlanningError.unavailableAudioPreset(audioPreset)
            }
            for audio in encodedAudioTracks {
                guard let channels = audio.channels,
                    let sampleRate = audio.sampleRate,
                    let layout = audio.channelLayout,
                    audioPreset.preserves(channelLayout: layout, channels: channels),
                    audioPreset.outputSampleRate(forInput: sampleRate) != nil
                else {
                    throw ExactTrimPlanningError.incompleteAudioFacts(trackID: audio.id)
                }
            }
        } else {
            encodedAudioTracks = []
        }
        let encodedAudioTrackIDs = Set(encodedAudioTracks.map(\.id))
        return ResolvedExactTrimPlan(
            operation: operation,
            source: source,
            range: range,
            choice: choice,
            videoTrackID: video.id,
            videoDynamicRange: videoDynamicRange,
            hdr10Signal: hdr10Signal,
            audioTrackIDs: audios.map(\.id),
            encodedAudioTrackIDs: audios.filter {
                encodedAudioTrackIDs.contains($0.id)
            }.map(\.id),
            copiedAudioTrackIDs: audios.filter {
                !encodedAudioTrackIDs.contains($0.id)
            }.map(\.id),
            subtitleTrackIDs: subtitles.map(\.id),
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
        switch (choice.videoPreset, choice.encoderTuning) {
        case (.av1Quality, .codecDefault):
            break
        case (.av1Quality, .svtAV1Preset(let value)):
            guard
                (VideoEncoderTuning.minimumSVTAV1Preset...VideoEncoderTuning.maximumSVTAV1Preset)
                    .contains(value)
            else {
                throw ExactTrimPlanningError.invalidChoice
            }
        case (_, .codecDefault):
            break
        default:
            throw ExactTrimPlanningError.invalidChoice
        }
    }

    private func recommendedBitrate(video: MediaTrack, multiplier: Int) -> Int {
        guard let dimensions = video.dimensions else { return 8_000_000 }
        let pixels = dimensions.width.multipliedReportingOverflow(by: dimensions.height)
        guard !pixels.overflow else { return 50_000_000 }
        let bitrate = pixels.partialValue.multipliedReportingOverflow(by: multiplier)
        guard !bitrate.overflow else { return 50_000_000 }
        return min(50_000_000, max(500_000, bitrate.partialValue))
    }

}
