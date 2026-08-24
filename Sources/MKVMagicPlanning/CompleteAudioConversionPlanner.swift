import Foundation
import MKVMagicCore

public enum CompleteAudioConversionPlanningError: Error, Equatable, Sendable {
    case unsupportedSource
    case invalidDuration
    case unsupportedTracks
    case unsupportedTags
    case noAudioTracks
    case noAudioConversionNeeded(AudioTranscodePreset)
    case unavailableAudioPreset(AudioTranscodePreset)
    case incompleteAudioFacts(trackID: Int)
}

extension CompleteAudioConversionPlanningError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Audio-only conversion currently accepts an inspected Matroska MKV."
        case .invalidDuration:
            "Audio-only conversion needs a known positive source duration."
        case .unsupportedTracks:
            "Audio-only conversion supports packet-copied video and subtitle tracks, but not data or unknown tracks."
        case .unsupportedTags:
            "Audio-only conversion cannot yet prove preservation of this source's Matroska tags."
        case .noAudioTracks:
            "This file has no audio tracks to convert."
        case .noAudioConversionNeeded(let preset):
            "Every audio track is already \(preset.displayName); no conversion is needed."
        case .unavailableAudioPreset(let preset):
            "The selected \(preset.displayName) audio encoder did not pass the active local probe."
        case .incompleteAudioFacts(let trackID):
            "Audio track \(trackID) needs a layout and sample rate that the selected format can preserve without downmixing or rematrixing."
        }
    }
}

public struct ResolvedCompleteAudioConversionPlan: Hashable, Sendable {
    public let source: MediaAsset
    public let preset: AudioTranscodePreset
    public let encodedAudioTrackIDs: [Int]
    public let copiedTrackIDs: [Int]
    public let trackIDsInOutputOrder: [Int]

    public init(
        source: MediaAsset,
        preset: AudioTranscodePreset,
        encodedAudioTrackIDs: [Int],
        copiedTrackIDs: [Int],
        trackIDsInOutputOrder: [Int]
    ) {
        self.source = source
        self.preset = preset
        self.encodedAudioTrackIDs = encodedAudioTrackIDs
        self.copiedTrackIDs = copiedTrackIDs
        self.trackIDsInOutputOrder = trackIDsInOutputOrder
    }

    public var videoEncodeCount: Int { 0 }
    public var audioEncodeCount: Int { encodedAudioTrackIDs.count }
}

public struct CompleteAudioConversionPlanner: Sendable {
    public init() {}

    public func resolve(
        source: MediaAsset,
        preset: AudioTranscodePreset,
        availableAudioPresets: Set<AudioTranscodePreset>
    ) throws -> ResolvedCompleteAudioConversionPlan {
        guard source.sourceURL.pathExtension.lowercased() == "mkv",
            source.container.localizedCaseInsensitiveContains("matroska")
                || source.container.localizedCaseInsensitiveContains("webm")
        else {
            throw CompleteAudioConversionPlanningError.unsupportedSource
        }
        guard let duration = source.duration, duration > .zero else {
            throw CompleteAudioConversionPlanningError.invalidDuration
        }
        let mediaTracks = source.tracks.filter { $0.kind != .attachment }
        guard !mediaTracks.isEmpty,
            mediaTracks.allSatisfy({
                $0.kind == .video || $0.kind == .audio || $0.kind == .subtitle
            }),
            Set(mediaTracks.map(\.id)).count == mediaTracks.count
        else {
            throw CompleteAudioConversionPlanningError.unsupportedTracks
        }
        guard source.globalTagCount == 0, source.trackTagCount == 0 else {
            throw CompleteAudioConversionPlanningError.unsupportedTags
        }
        let audioTracks = mediaTracks.filter { $0.kind == .audio }
        guard !audioTracks.isEmpty else {
            throw CompleteAudioConversionPlanningError.noAudioTracks
        }
        let encodedAudioTracks = audioTracks.filter {
            !preset.matches(sourceCodec: $0.codec)
        }
        guard !encodedAudioTracks.isEmpty else {
            throw CompleteAudioConversionPlanningError.noAudioConversionNeeded(preset)
        }
        guard availableAudioPresets.contains(preset) else {
            throw CompleteAudioConversionPlanningError.unavailableAudioPreset(preset)
        }
        for track in encodedAudioTracks {
            guard let channels = track.channels,
                let layout = track.channelLayout,
                let sampleRate = track.sampleRate,
                preset.preserves(channelLayout: layout, channels: channels),
                preset.outputSampleRate(forInput: sampleRate) != nil
            else {
                throw CompleteAudioConversionPlanningError.incompleteAudioFacts(
                    trackID: track.id
                )
            }
        }
        let encodedAudioTrackIDs = Set(encodedAudioTracks.map(\.id))
        return ResolvedCompleteAudioConversionPlan(
            source: source,
            preset: preset,
            encodedAudioTrackIDs: encodedAudioTracks.map(\.id),
            copiedTrackIDs: mediaTracks.filter {
                !encodedAudioTrackIDs.contains($0.id)
            }.map(\.id),
            trackIDsInOutputOrder: mediaTracks.map(\.id)
        )
    }
}
