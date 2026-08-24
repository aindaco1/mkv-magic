import Foundation
import MKVMagicCore

public struct AppBaselineProbeReport: Codable, Equatable, Sendable {
    public static let schema = "mkv-magic-app-baseline-v1"
    public static let defaultProcessLaunchBudgetNanoseconds: UInt64 = 2_000_000_000
    public static let defaultMainViewBudgetNanoseconds: UInt64 = 1_000_000_000
    public static let defaultResidentMemoryBudgetBytes: UInt64 = 256 * 1_024 * 1_024

    public let schema: String
    public let architecture: String
    public let operatingSystem: AppBaselineOperatingSystem
    public let activeProcessorCount: Int
    public let rounds: Int
    public let medianProcessLaunchNanoseconds: UInt64
    public let p95ProcessLaunchNanoseconds: UInt64
    public let processLaunchBudgetNanoseconds: UInt64
    public let medianMainViewReadyNanoseconds: UInt64
    public let p95MainViewReadyNanoseconds: UInt64
    public let mainViewReadyBudgetNanoseconds: UInt64
    public let medianResidentMemoryBytes: UInt64
    public let p95ResidentMemoryBytes: UInt64
    public let residentMemoryBudgetBytes: UInt64

    public init(
        samples: [AppBaselineSample],
        processLaunchNanoseconds: [UInt64],
        processLaunchBudgetNanoseconds: UInt64 = Self.defaultProcessLaunchBudgetNanoseconds,
        mainViewReadyBudgetNanoseconds: UInt64 = Self.defaultMainViewBudgetNanoseconds,
        residentMemoryBudgetBytes: UInt64 = Self.defaultResidentMemoryBudgetBytes
    ) throws {
        guard !samples.isEmpty, samples.count <= 21,
            samples.count == processLaunchNanoseconds.count,
            processLaunchBudgetNanoseconds > 0,
            mainViewReadyBudgetNanoseconds > 0,
            residentMemoryBudgetBytes > 0,
            let first = samples.first,
            first.schema == AppBaselineSample.schema,
            first.architecture == "arm64" || first.architecture == "x86_64",
            first.activeProcessorCount > 0,
            samples.allSatisfy({ sample in
                sample.schema == first.schema
                    && sample.architecture == first.architecture
                    && sample.operatingSystem == first.operatingSystem
                    && sample.activeProcessorCount == first.activeProcessorCount
                    && sample.mainViewReadyNanoseconds > 0
                    && sample.residentMemoryBytes > 0
                    && sample.windowCount == 0
                    && sample.rootSubviewCount > 0
            }),
            processLaunchNanoseconds.allSatisfy({ $0 > 0 })
        else {
            throw AppBaselineProbeError.invalidSamples
        }

        let launch = processLaunchNanoseconds.sorted()
        let view = samples.map(\.mainViewReadyNanoseconds).sorted()
        let memory = samples.map(\.residentMemoryBytes).sorted()
        schema = Self.schema
        architecture = first.architecture
        operatingSystem = first.operatingSystem
        activeProcessorCount = first.activeProcessorCount
        rounds = samples.count
        medianProcessLaunchNanoseconds = PerformanceStatistics.nearestRank(
            launch,
            percentile: 50
        )
        p95ProcessLaunchNanoseconds = PerformanceStatistics.nearestRank(
            launch,
            percentile: 95
        )
        self.processLaunchBudgetNanoseconds = processLaunchBudgetNanoseconds
        medianMainViewReadyNanoseconds = PerformanceStatistics.nearestRank(
            view,
            percentile: 50
        )
        p95MainViewReadyNanoseconds = PerformanceStatistics.nearestRank(
            view,
            percentile: 95
        )
        self.mainViewReadyBudgetNanoseconds = mainViewReadyBudgetNanoseconds
        medianResidentMemoryBytes = PerformanceStatistics.nearestRank(
            memory,
            percentile: 50
        )
        p95ResidentMemoryBytes = PerformanceStatistics.nearestRank(
            memory,
            percentile: 95
        )
        self.residentMemoryBudgetBytes = residentMemoryBudgetBytes
    }

    public var isWithinBudget: Bool {
        p95ProcessLaunchNanoseconds <= processLaunchBudgetNanoseconds
            && p95MainViewReadyNanoseconds <= mainViewReadyBudgetNanoseconds
            && p95ResidentMemoryBytes <= residentMemoryBudgetBytes
    }
}

public enum AppBaselineProbeError: Error, Equatable, Sendable {
    case invalidSamples
}

extension AppBaselineProbeError: LocalizedError {
    public var errorDescription: String? {
        "The app baseline samples are missing, inconsistent, or unsafe."
    }
}

enum PerformanceStatistics {
    static func nearestRank(_ sorted: [UInt64], percentile: Int) -> UInt64 {
        guard !sorted.isEmpty, (1...100).contains(percentile) else { return 0 }
        let multiplied = sorted.count.multipliedReportingOverflow(by: percentile)
        guard !multiplied.overflow else { return sorted.last ?? 0 }
        let roundedUp = multiplied.partialValue.addingReportingOverflow(99)
        guard !roundedUp.overflow else { return sorted.last ?? 0 }
        let rank = max(1, roundedUp.partialValue / 100)
        return sorted[min(sorted.count - 1, rank - 1)]
    }
}
