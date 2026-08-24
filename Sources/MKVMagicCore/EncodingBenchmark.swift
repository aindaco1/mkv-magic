import Foundation

public struct EncodingBenchmarkEnvironment: Codable, Equatable, Sendable {
    public let ffmpegSHA256: String
    public let architecture: String
    public let activeProcessorCount: Int

    public init(
        ffmpegSHA256: String,
        architecture: String,
        activeProcessorCount: Int
    ) {
        self.ffmpegSHA256 = ffmpegSHA256
        self.architecture = architecture
        self.activeProcessorCount = activeProcessorCount
    }
}

public enum EncodingBenchmarkOutcome: String, Codable, Equatable, Sendable {
    case completed
    case failed
    case timedOut
}

public struct EncodingBenchmarkMetrics: Codable, Equatable, Sendable {
    public let elapsedSeconds: Double
    public let framesPerSecond: Double
    public let sourceRealtimeFactor: Double
    public let estimated1080pRealtimeFactor: Double
    public let outputBytes: Int64
    public let outputBitrate: Int64
    public let averagePSNR: Double?

    public init(
        elapsedSeconds: Double,
        framesPerSecond: Double,
        sourceRealtimeFactor: Double,
        estimated1080pRealtimeFactor: Double,
        outputBytes: Int64,
        outputBitrate: Int64,
        averagePSNR: Double?
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.framesPerSecond = framesPerSecond
        self.sourceRealtimeFactor = sourceRealtimeFactor
        self.estimated1080pRealtimeFactor = estimated1080pRealtimeFactor
        self.outputBytes = outputBytes
        self.outputBitrate = outputBitrate
        self.averagePSNR = averagePSNR
    }
}

public struct EncodingBenchmarkAttempt: Codable, Equatable, Sendable {
    public let preset: VideoPreset
    public let encoder: String
    public let outcome: EncodingBenchmarkOutcome
    public let metrics: EncodingBenchmarkMetrics?

    public init(
        preset: VideoPreset,
        encoder: String,
        outcome: EncodingBenchmarkOutcome,
        metrics: EncodingBenchmarkMetrics?
    ) {
        self.preset = preset
        self.encoder = encoder
        self.outcome = outcome
        self.metrics = metrics
    }
}

public struct EncodingBenchmarkReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let environment: EncodingBenchmarkEnvironment
    public let completedAt: Date
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let sourceFrameRate: Int
    public let sourceFrameCount: Int
    public let attempts: [EncodingBenchmarkAttempt]
    public let recommendedPreset: VideoPreset

    public init(
        schemaVersion: Int = EncodingBenchmarkReport.currentSchemaVersion,
        environment: EncodingBenchmarkEnvironment,
        completedAt: Date,
        sourceWidth: Int,
        sourceHeight: Int,
        sourceFrameRate: Int,
        sourceFrameCount: Int,
        attempts: [EncodingBenchmarkAttempt],
        recommendedPreset: VideoPreset
    ) {
        self.schemaVersion = schemaVersion
        self.environment = environment
        self.completedAt = completedAt
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.sourceFrameRate = sourceFrameRate
        self.sourceFrameCount = sourceFrameCount
        self.attempts = attempts
        self.recommendedPreset = recommendedPreset
    }

    public func matches(_ currentEnvironment: EncodingBenchmarkEnvironment) -> Bool {
        environment == currentEnvironment
    }
}

public enum EncodingBenchmarkRecommendation {
    /// A quality-first AV1 recommendation remains practical when the estimated
    /// 1080p encode completes at least one source second for every two wall-clock seconds.
    public static let minimumAV1Estimated1080pRealtimeFactor = 0.5

    public static func choose(from attempts: [EncodingBenchmarkAttempt]) -> VideoPreset? {
        var completed = [VideoPreset: EncodingBenchmarkAttempt]()
        for attempt in attempts
        where attempt.outcome == .completed && attempt.metrics != nil
            && completed[attempt.preset] == nil
        {
            completed[attempt.preset] = attempt
        }
        let av1 = completed[.av1Quality]
        let hevc = completed[.hevcCompatibility]
        if let av1, let hevc {
            guard let metrics = av1.metrics else { return hevc.preset }
            return metrics.estimated1080pRealtimeFactor
                >= minimumAV1Estimated1080pRealtimeFactor
                ? av1.preset : hevc.preset
        }
        return av1?.preset ?? hevc?.preset
    }
}
