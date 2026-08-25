import Foundation

public struct WorkflowDefinition: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public var schemaVersion: Int
    public var name: String
    public var operations: [WorkflowOperation]

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = WorkflowDefinition.currentSchemaVersion,
        name: String,
        operations: [WorkflowOperation]
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.operations = operations
    }
}

public enum VideoPreset: String, Codable, CaseIterable, Hashable, Sendable {
    case av1Quality
    case hevcCompatibility
    case h264Compatibility
    case proRes

    public var displayName: String {
        switch self {
        case .av1Quality: "AV1 10-bit"
        case .hevcCompatibility: "HEVC 10-bit VideoToolbox"
        case .h264Compatibility: "H.264 8-bit"
        case .proRes: "ProRes 10-bit"
        }
    }
}

public enum WorkflowOperation: Codable, Hashable, Sendable {
    case editSegmentTitle(String?)
    case clearAllTags
    case editTrackMetadata(TrackMetadataEdit)
    case setTrackLanguage(trackID: Int, language: String)
    case removeTracks(Set<Int>)
    case removeTracksByUID(TrackRemoval)
    case addExternalSubtitle(
        url: URL,
        metadata: ExternalSubtitleTrackMetadata,
        format: ExternalTextSubtitleFormat
    )
    case trim(start: MediaTime, end: MediaTime, exact: Bool)
    case transcodeVideo(VideoPreset)
    case transcodeAudio(AudioTranscodePreset)
}

public enum ExecutionMechanism: String, Codable, Hashable, Sendable {
    case mkvPropEdit
    case mkvMerge
    case ffmpegStreamCopy
    case ffmpegEncode
    case verify
    case commit
}

public struct PlanStage: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let mechanism: ExecutionMechanism
    public let summary: String

    public init(id: UUID = UUID(), mechanism: ExecutionMechanism, summary: String) {
        self.id = id
        self.mechanism = mechanism
        self.summary = summary
    }
}

public struct PlanImpact: Codable, Hashable, Sendable {
    public let videoEncodeCount: Int
    public let audioEncodeCount: Int
    public let copiesVideo: Bool
    public let changesSourceBeforeVerification: Bool
    public let warnings: [String]

    public init(
        videoEncodeCount: Int,
        audioEncodeCount: Int,
        copiesVideo: Bool,
        changesSourceBeforeVerification: Bool = false,
        warnings: [String] = []
    ) {
        self.videoEncodeCount = videoEncodeCount
        self.audioEncodeCount = audioEncodeCount
        self.copiesVideo = copiesVideo
        self.changesSourceBeforeVerification = changesSourceBeforeVerification
        self.warnings = warnings
    }
}

public struct ExecutionPlan: Codable, Hashable, Sendable {
    public let stages: [PlanStage]
    public let impact: PlanImpact

    public init(stages: [PlanStage], impact: PlanImpact) {
        self.stages = stages
        self.impact = impact
    }

    public func hasSameReviewedWork(as other: Self) -> Bool {
        guard impact == other.impact, stages.count == other.stages.count else { return false }
        return zip(stages, other.stages).allSatisfy { lhs, rhs in
            lhs.mechanism == rhs.mechanism && lhs.summary == rhs.summary
        }
    }
}
