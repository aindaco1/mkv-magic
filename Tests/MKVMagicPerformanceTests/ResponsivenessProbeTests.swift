import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicPerformance

final class ResponsivenessProbeTests: XCTestCase {
    func testMetricUsesNearestRankPercentilesAndP95Budget() throws {
        let passing = try ResponsivenessMetric(
            id: .largeTrackWorkflowCompilation,
            operationSamples: [1, 2, 3, 4, 100],
            operationsPerRound: 10,
            budgetNanosecondsPerOperation: 100
        )
        let failing = try ResponsivenessMetric(
            id: .productionQueueScheduling,
            operationSamples: [1, 2, 3, 4, 101],
            operationsPerRound: 10,
            budgetNanosecondsPerOperation: 100
        )

        XCTAssertEqual(passing.medianNanosecondsPerOperation, 3)
        XCTAssertEqual(passing.p95NanosecondsPerOperation, 100)
        XCTAssertTrue(passing.isWithinBudget)
        XCTAssertFalse(failing.isWithinBudget)
    }

    func testRejectsUnboundedOrEmptyConfigurations() async {
        for configuration in [
            ResponsivenessProbeConfiguration(
                rounds: 0,
                workflowCompilationsPerRound: 1,
                queueSchedulesPerRound: 1,
                trackCount: 4,
                queueJobCount: 1
            ),
            ResponsivenessProbeConfiguration(
                rounds: 1,
                workflowCompilationsPerRound: 1,
                queueSchedulesPerRound: 1,
                trackCount: 4,
                queueJobCount: 100_001
            ),
            ResponsivenessProbeConfiguration(
                rounds: 1,
                workflowCompilationsPerRound: 1,
                queueSchedulesPerRound: 1,
                trackCount: 4,
                queueJobCount: 1,
                cancellationStartupDelayNanoseconds: 0
            ),
        ] {
            do {
                _ = try await ResponsivenessProbe(configuration: configuration).run()
                XCTFail("Expected an invalid configuration")
            } catch {
                XCTAssertEqual(error as? ResponsivenessProbeError, .invalidConfiguration)
            }
        }
        XCTAssertThrowsError(
            try ResponsivenessMetric(
                id: .productionQueueScheduling,
                operationSamples: [],
                operationsPerRound: 1,
                budgetNanosecondsPerOperation: 1
            )
        )
    }

    func testAppBaselineReportUsesNearestRankAndEnforcesEveryBudget() throws {
        let samples = [1, 2, 3, 4, 100].map { value in
            AppBaselineSample(
                architecture: "arm64",
                operatingSystem: AppBaselineOperatingSystem(
                    OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
                ),
                activeProcessorCount: 8,
                mainViewReadyNanoseconds: UInt64(value),
                residentMemoryBytes: UInt64(value * 10),
                windowCount: 0,
                rootSubviewCount: 1
            )
        }
        let passing = try AppBaselineProbeReport(
            samples: samples,
            processLaunchNanoseconds: [10, 20, 30, 40, 1_000],
            processLaunchBudgetNanoseconds: 1_000,
            mainViewReadyBudgetNanoseconds: 100,
            residentMemoryBudgetBytes: 1_000
        )
        let failingLaunch = try AppBaselineProbeReport(
            samples: samples,
            processLaunchNanoseconds: [10, 20, 30, 40, 1_001],
            processLaunchBudgetNanoseconds: 1_000,
            mainViewReadyBudgetNanoseconds: 100,
            residentMemoryBudgetBytes: 1_000
        )
        let failingView = try AppBaselineProbeReport(
            samples: samples,
            processLaunchNanoseconds: [10, 20, 30, 40, 1_000],
            processLaunchBudgetNanoseconds: 1_000,
            mainViewReadyBudgetNanoseconds: 99,
            residentMemoryBudgetBytes: 1_000
        )
        let failingMemory = try AppBaselineProbeReport(
            samples: samples,
            processLaunchNanoseconds: [10, 20, 30, 40, 1_000],
            processLaunchBudgetNanoseconds: 1_000,
            mainViewReadyBudgetNanoseconds: 100,
            residentMemoryBudgetBytes: 999
        )

        XCTAssertEqual(passing.rounds, 5)
        XCTAssertEqual(passing.medianProcessLaunchNanoseconds, 30)
        XCTAssertEqual(passing.p95ProcessLaunchNanoseconds, 1_000)
        XCTAssertEqual(passing.medianMainViewReadyNanoseconds, 3)
        XCTAssertEqual(passing.p95MainViewReadyNanoseconds, 100)
        XCTAssertEqual(passing.medianResidentMemoryBytes, 30)
        XCTAssertEqual(passing.p95ResidentMemoryBytes, 1_000)
        XCTAssertTrue(passing.isWithinBudget)
        XCTAssertFalse(failingLaunch.isWithinBudget)
        XCTAssertFalse(failingView.isWithinBudget)
        XCTAssertFalse(failingMemory.isWithinBudget)
    }

    func testAppBaselineReportRejectsVisibleOrInconsistentSamplesAndStaysPathFree() throws {
        let sample = AppBaselineSample(
            architecture: "x86_64",
            operatingSystem: AppBaselineOperatingSystem(
                OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)
            ),
            activeProcessorCount: 4,
            mainViewReadyNanoseconds: 1,
            residentMemoryBytes: 1,
            windowCount: 0,
            rootSubviewCount: 1
        )
        let report = try AppBaselineProbeReport(
            samples: [sample],
            processLaunchNanoseconds: [1]
        )
        let json = try XCTUnwrap(
            String(data: JSONEncoder().encode(report), encoding: .utf8)
        )

        XCTAssertEqual(report.schema, AppBaselineProbeReport.schema)
        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("hostname"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("timestamp"))
        XCTAssertThrowsError(
            try AppBaselineProbeReport(
                samples: [
                    AppBaselineSample(
                        architecture: "x86_64",
                        operatingSystem: sample.operatingSystem,
                        activeProcessorCount: 4,
                        mainViewReadyNanoseconds: 1,
                        residentMemoryBytes: 1,
                        windowCount: 1,
                        rootSubviewCount: 1
                    )
                ],
                processLaunchNanoseconds: [1]
            )
        )
        XCTAssertThrowsError(
            try AppBaselineProbeReport(
                samples: [sample],
                processLaunchNanoseconds: []
            )
        )
    }

    func testMinimalSyntheticProbeIsPathFreeAndMachineReadable() async throws {
        let report = try await ResponsivenessProbe(
            configuration: ResponsivenessProbeConfiguration(
                rounds: 1,
                workflowCompilationsPerRound: 1,
                queueSchedulesPerRound: 1,
                trackCount: 4,
                queueJobCount: 3,
                workflowCompilationBudgetNanoseconds: .max,
                queueSchedulingBudgetNanoseconds: .max,
                commandCancellationBudgetNanoseconds: .max,
                cancellationStartupDelayNanoseconds: 50_000_000
            )
        ).run()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: encoder.encode(report), encoding: .utf8))

        XCTAssertEqual(report.schema, ResponsivenessProbeReport.schema)
        XCTAssertEqual(report.metrics.map(\.id), ResponsivenessMetricID.allCases)
        XCTAssertTrue(report.isWithinBudget)
        XCTAssertGreaterThan(report.workloadChecksum, 0)
        XCTAssertEqual(report.metrics.last?.id, .commandCancellation)
        XCTAssertEqual(report.metrics.last?.operationsPerRound, 1)
        XCTAssertGreaterThan(report.metrics.last?.p95NanosecondsPerOperation ?? 0, 0)
        XCTAssertFalse(json.contains("/private/"))
        XCTAssertFalse(json.contains("/bin/sleep"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("hostname"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("sourceURL"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("timestamp"))
        XCTAssertFalse(json.contains("Synthetic library workflow"))
        XCTAssertFalse(json.contains("Synthetic queue workflow"))
        XCTAssertFalse(json.contains("Movie.2025"))
        XCTAssertFalse(json.contains("synthetic.mkv"))
    }
}
