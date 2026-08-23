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
}

public enum WorkflowOperation: Codable, Hashable, Sendable {
    case editSegmentTitle(String?)
    case setTrackLanguage(trackID: Int, language: String)
    case removeTracks(Set<Int>)
    case muxSubtitle(url: URL, language: String?, forced: Bool)
    case trim(start: MediaTime, end: MediaTime, exact: Bool)
    case transcodeVideo(VideoPreset)
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
}
