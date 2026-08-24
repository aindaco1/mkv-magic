import Foundation
import MKVMagicCore
import MKVMagicPlanning
import MKVMagicSystem

public enum ResponsivenessMetricID: String, Codable, CaseIterable, Sendable {
    case largeTrackWorkflowCompilation
    case productionQueueScheduling
    case commandCancellation
}

public struct ResponsivenessMetric: Codable, Equatable, Sendable {
    public let id: ResponsivenessMetricID
    public let rounds: Int
    public let operationsPerRound: Int
    public let medianNanosecondsPerOperation: UInt64
    public let p95NanosecondsPerOperation: UInt64
    public let budgetNanosecondsPerOperation: UInt64

    public init(
        id: ResponsivenessMetricID,
        operationSamples: [UInt64],
        operationsPerRound: Int,
        budgetNanosecondsPerOperation: UInt64
    ) throws {
        guard !operationSamples.isEmpty, operationsPerRound > 0,
            budgetNanosecondsPerOperation > 0
        else {
            throw ResponsivenessProbeError.invalidConfiguration
        }
        let sorted = operationSamples.sorted()
        self.id = id
        rounds = sorted.count
        self.operationsPerRound = operationsPerRound
        medianNanosecondsPerOperation = PerformanceStatistics.nearestRank(
            sorted,
            percentile: 50
        )
        p95NanosecondsPerOperation = PerformanceStatistics.nearestRank(
            sorted,
            percentile: 95
        )
        self.budgetNanosecondsPerOperation = budgetNanosecondsPerOperation
    }

    public var isWithinBudget: Bool {
        p95NanosecondsPerOperation <= budgetNanosecondsPerOperation
    }

}

public struct ResponsivenessProbeConfiguration: Equatable, Sendable {
    public static let standard = ResponsivenessProbeConfiguration(
        rounds: 7,
        workflowCompilationsPerRound: 200,
        queueSchedulesPerRound: 200,
        trackCount: 200,
        queueJobCount: 5_000
    )

    public static let quick = ResponsivenessProbeConfiguration(
        rounds: 3,
        workflowCompilationsPerRound: 20,
        queueSchedulesPerRound: 20,
        trackCount: 100,
        queueJobCount: 1_000
    )

    public let rounds: Int
    public let workflowCompilationsPerRound: Int
    public let queueSchedulesPerRound: Int
    public let trackCount: Int
    public let queueJobCount: Int
    public let workflowCompilationBudgetNanoseconds: UInt64
    public let queueSchedulingBudgetNanoseconds: UInt64
    public let commandCancellationBudgetNanoseconds: UInt64
    public let cancellationStartupDelayNanoseconds: UInt64

    public init(
        rounds: Int,
        workflowCompilationsPerRound: Int,
        queueSchedulesPerRound: Int,
        trackCount: Int,
        queueJobCount: Int,
        workflowCompilationBudgetNanoseconds: UInt64 = 15_000_000,
        queueSchedulingBudgetNanoseconds: UInt64 = 15_000_000,
        commandCancellationBudgetNanoseconds: UInt64 = 500_000_000,
        cancellationStartupDelayNanoseconds: UInt64 = 75_000_000
    ) {
        self.rounds = rounds
        self.workflowCompilationsPerRound = workflowCompilationsPerRound
        self.queueSchedulesPerRound = queueSchedulesPerRound
        self.trackCount = trackCount
        self.queueJobCount = queueJobCount
        self.workflowCompilationBudgetNanoseconds = workflowCompilationBudgetNanoseconds
        self.queueSchedulingBudgetNanoseconds = queueSchedulingBudgetNanoseconds
        self.commandCancellationBudgetNanoseconds = commandCancellationBudgetNanoseconds
        self.cancellationStartupDelayNanoseconds = cancellationStartupDelayNanoseconds
    }

    fileprivate func validate() throws {
        guard (1...21).contains(rounds),
            (1...10_000).contains(workflowCompilationsPerRound),
            (1...10_000).contains(queueSchedulesPerRound),
            (4...1_000).contains(trackCount),
            (1...100_000).contains(queueJobCount),
            workflowCompilationBudgetNanoseconds > 0,
            queueSchedulingBudgetNanoseconds > 0,
            commandCancellationBudgetNanoseconds > 0,
            (1_000_000...1_000_000_000).contains(cancellationStartupDelayNanoseconds)
        else {
            throw ResponsivenessProbeError.invalidConfiguration
        }
    }
}

public enum ResponsivenessProbeError: Error, Equatable, Sendable {
    case invalidConfiguration
    case inconsistentWorkload
    case clockOverflow
    case unexpectedCancellationOutcome
}

extension ResponsivenessProbeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "The responsiveness probe configuration is out of bounds."
        case .inconsistentWorkload: "The synthetic responsiveness workload changed unexpectedly."
        case .clockOverflow: "The monotonic responsiveness clock could not represent a sample."
        case .unexpectedCancellationOutcome:
            "The synthetic command did not report the expected cancellation outcome."
        }
    }
}

public struct ResponsivenessProbeReport: Codable, Equatable, Sendable {
    public static let schema = "mkv-magic-responsiveness-v2"

    public let schema: String
    public let architecture: String
    public let operatingSystem: ResponsivenessOperatingSystem
    public let activeProcessorCount: Int
    public let syntheticTrackCount: Int
    public let syntheticQueueJobCount: Int
    public let metrics: [ResponsivenessMetric]
    public let workloadChecksum: UInt64

    public init(
        architecture: String,
        operatingSystem: ResponsivenessOperatingSystem,
        activeProcessorCount: Int,
        syntheticTrackCount: Int,
        syntheticQueueJobCount: Int,
        metrics: [ResponsivenessMetric],
        workloadChecksum: UInt64
    ) {
        schema = Self.schema
        self.architecture = architecture
        self.operatingSystem = operatingSystem
        self.activeProcessorCount = activeProcessorCount
        self.syntheticTrackCount = syntheticTrackCount
        self.syntheticQueueJobCount = syntheticQueueJobCount
        self.metrics = metrics
        self.workloadChecksum = workloadChecksum
    }

    public var isWithinBudget: Bool {
        metrics.count == ResponsivenessMetricID.allCases.count
            && metrics.allSatisfy(\.isWithinBudget)
    }
}

public struct ResponsivenessOperatingSystem: Codable, Equatable, Sendable {
    public let majorVersion: Int
    public let minorVersion: Int
    public let patchVersion: Int

    public init(_ version: OperatingSystemVersion) {
        majorVersion = version.majorVersion
        minorVersion = version.minorVersion
        patchVersion = version.patchVersion
    }
}

public struct ResponsivenessProbe: Sendable {
    private let configuration: ResponsivenessProbeConfiguration

    public init(configuration: ResponsivenessProbeConfiguration = .standard) {
        self.configuration = configuration
    }

    public func run() async throws -> ResponsivenessProbeReport {
        try configuration.validate()
        let workflowFixture = makeWorkflowFixture(trackCount: configuration.trackCount)
        let queueFixture = makeQueueFixture(jobCount: configuration.queueJobCount)

        _ = try compile(workflowFixture)
        _ = schedule(queueFixture)

        let workflowMeasurement = try measure(
            rounds: configuration.rounds,
            operationsPerRound: configuration.workflowCompilationsPerRound
        ) {
            try compile(workflowFixture)
        }
        let queueMeasurement = try measure(
            rounds: configuration.rounds,
            operationsPerRound: configuration.queueSchedulesPerRound
        ) {
            schedule(queueFixture)
        }
        let cancellationSamples = try await measureCommandCancellation()
        guard workflowMeasurement.checksum > 0, queueMeasurement.checksum > 0 else {
            throw ResponsivenessProbeError.inconsistentWorkload
        }

        let metrics = [
            try ResponsivenessMetric(
                id: .largeTrackWorkflowCompilation,
                operationSamples: workflowMeasurement.samples,
                operationsPerRound: configuration.workflowCompilationsPerRound,
                budgetNanosecondsPerOperation:
                    configuration.workflowCompilationBudgetNanoseconds
            ),
            try ResponsivenessMetric(
                id: .productionQueueScheduling,
                operationSamples: queueMeasurement.samples,
                operationsPerRound: configuration.queueSchedulesPerRound,
                budgetNanosecondsPerOperation: configuration.queueSchedulingBudgetNanoseconds
            ),
            try ResponsivenessMetric(
                id: .commandCancellation,
                operationSamples: cancellationSamples,
                operationsPerRound: 1,
                budgetNanosecondsPerOperation: configuration.commandCancellationBudgetNanoseconds
            ),
        ]
        return ResponsivenessProbeReport(
            architecture: architecture,
            operatingSystem: ResponsivenessOperatingSystem(
                ProcessInfo.processInfo.operatingSystemVersion
            ),
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            syntheticTrackCount: configuration.trackCount,
            syntheticQueueJobCount: configuration.queueJobCount,
            metrics: metrics,
            workloadChecksum: workflowMeasurement.checksum &+ queueMeasurement.checksum
                &+ UInt64(cancellationSamples.count)
        )
    }

    private func measureCommandCancellation() async throws -> [UInt64] {
        var samples = [UInt64]()
        samples.reserveCapacity(configuration.rounds)
        for _ in 0..<configuration.rounds {
            let command = Task {
                try await FoundationCommandRunner().run(
                    CommandRequest(
                        executableURL: URL(fileURLWithPath: "/bin/sleep"),
                        arguments: ["5"],
                        timeout: 10,
                        outputLimit: 1_024
                    )
                )
            }
            do {
                try await Task.sleep(
                    nanoseconds: configuration.cancellationStartupDelayNanoseconds
                )
            } catch {
                command.cancel()
                _ = try? await command.value
                throw error
            }

            let start = DispatchTime.now().uptimeNanoseconds
            command.cancel()
            do {
                _ = try await command.value
                throw ResponsivenessProbeError.unexpectedCancellationOutcome
            } catch let error as CommandRunnerError {
                guard error == .cancelled else {
                    throw ResponsivenessProbeError.unexpectedCancellationOutcome
                }
            } catch let error as ResponsivenessProbeError {
                throw error
            } catch {
                throw ResponsivenessProbeError.unexpectedCancellationOutcome
            }
            let end = DispatchTime.now().uptimeNanoseconds
            let elapsed = end.subtractingReportingOverflow(start)
            guard !elapsed.overflow else { throw ResponsivenessProbeError.clockOverflow }
            samples.append(elapsed.partialValue)
        }
        return samples
    }

    private var architecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unsupported"
        #endif
    }

    private func compile(_ fixture: WorkflowFixture) throws -> UInt64 {
        let compiled = try SavedWorkflowCompiler().compile(fixture.workflow, for: fixture.asset)
        return UInt64(compiled.operations.count + compiled.stepOutcomes.count)
    }

    private func schedule(_ snapshot: MediaQueueSnapshot) -> UInt64 {
        UInt64(
            MediaQueueScheduler().jobsToStart(
                in: snapshot,
                environment: MediaQueueSchedulingEnvironment(
                    isOnBattery: false,
                    thermalPressure: .nominal
                )
            ).count
        )
    }

    private func measure(
        rounds: Int,
        operationsPerRound: Int,
        operation: () throws -> UInt64
    ) throws -> Measurement {
        var samples = [UInt64]()
        samples.reserveCapacity(rounds)
        var checksum: UInt64 = 0
        for _ in 0..<rounds {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<operationsPerRound {
                checksum &+= try operation()
            }
            let end = DispatchTime.now().uptimeNanoseconds
            let elapsed = end.subtractingReportingOverflow(start)
            guard !elapsed.overflow else { throw ResponsivenessProbeError.clockOverflow }
            samples.append(elapsed.partialValue / UInt64(operationsPerRound))
        }
        return Measurement(samples: samples, checksum: checksum)
    }

    private func makeWorkflowFixture(trackCount: Int) -> WorkflowFixture {
        var tracks = [
            MediaTrack(id: 0, kind: .video, codec: "av1", uid: 1),
            MediaTrack(
                id: 1,
                kind: .audio,
                codec: "aac",
                uid: 2,
                language: "en",
                isDefault: true
            ),
        ]
        tracks.reserveCapacity(trackCount)
        for id in 2..<trackCount {
            let isEnglish = id.isMultiple(of: 3)
            tracks.append(
                MediaTrack(
                    id: id,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: UInt64(id + 1),
                    language: isEnglish ? "en" : "fr",
                    title: isEnglish ? (id.isMultiple(of: 6) ? "English SDH" : "English") : nil,
                    isDefault: id == 3,
                    isHearingImpaired: isEnglish && id.isMultiple(of: 6)
                )
            )
        }
        return WorkflowFixture(
            workflow: SavedWorkflow(
                name: "Synthetic library workflow",
                steps: [
                    SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                    SavedWorkflowStep(action: .removeRedundantEnglishSDH),
                    SavedWorkflowStep(action: .removeSegmentTitle),
                    SavedWorkflowStep(action: .normalizeFilename),
                ]
            ),
            asset: MediaAsset(
                sourceURL: URL(fileURLWithPath: "/private/synthetic/Movie.2025.1080p.mkv"),
                container: "matroska",
                tracks: tracks,
                metadata: ["title": "Synthetic"]
            )
        )
    }

    private func makeQueueFixture(jobCount: Int) -> MediaQueueSnapshot {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let reference = MediaQueueFileReference(
            displayName: "synthetic.mkv",
            securityScopedBookmark: Data([1])
        )
        let workflow = SavedWorkflow(
            name: "Synthetic queue workflow",
            steps: [SavedWorkflowStep(action: .removeSegmentTitle)]
        )
        let jobs = (0..<jobCount).map { index in
            let impact: PlanImpact
            switch index % 3 {
            case 0:
                impact = PlanImpact(videoEncodeCount: 0, audioEncodeCount: 0, copiesVideo: true)
            case 1:
                impact = PlanImpact(videoEncodeCount: 0, audioEncodeCount: 1, copiesVideo: true)
            default:
                impact = PlanImpact(videoEncodeCount: 1, audioEncodeCount: 0, copiesVideo: false)
            }
            return MediaQueueJob(
                createdAt: createdAt,
                workflow: .saved(workflow),
                inputs: [reference],
                destinationDirectory: reference,
                outputDisplayName: "synthetic-output.mkv",
                reviewedPlan: ExecutionPlan(
                    stages: [PlanStage(mechanism: .verify, summary: "Synthetic verification")],
                    impact: impact
                )
            )
        }
        return MediaQueueSnapshot(jobs: jobs, updatedAt: createdAt)
    }
}

private struct WorkflowFixture {
    let workflow: SavedWorkflow
    let asset: MediaAsset
}

private struct Measurement {
    let samples: [UInt64]
    let checksum: UInt64
}
