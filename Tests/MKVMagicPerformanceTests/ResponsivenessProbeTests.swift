import Foundation
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

    func testRejectsUnboundedOrEmptyConfigurations() {
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
        ] {
            XCTAssertThrowsError(try ResponsivenessProbe(configuration: configuration).run()) {
                XCTAssertEqual($0 as? ResponsivenessProbeError, .invalidConfiguration)
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

    func testMinimalSyntheticProbeIsPathFreeAndMachineReadable() throws {
        let report = try ResponsivenessProbe(
            configuration: ResponsivenessProbeConfiguration(
                rounds: 1,
                workflowCompilationsPerRound: 1,
                queueSchedulesPerRound: 1,
                trackCount: 4,
                queueJobCount: 3,
                workflowCompilationBudgetNanoseconds: .max,
                queueSchedulingBudgetNanoseconds: .max
            )
        ).run()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: encoder.encode(report), encoding: .utf8))

        XCTAssertEqual(report.schema, ResponsivenessProbeReport.schema)
        XCTAssertEqual(report.metrics.map(\.id), ResponsivenessMetricID.allCases)
        XCTAssertTrue(report.isWithinBudget)
        XCTAssertGreaterThan(report.workloadChecksum, 0)
        XCTAssertFalse(json.contains("/private/"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("hostname"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("sourceURL"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("timestamp"))
        XCTAssertFalse(json.contains("Synthetic library workflow"))
        XCTAssertFalse(json.contains("Synthetic queue workflow"))
        XCTAssertFalse(json.contains("Movie.2025"))
        XCTAssertFalse(json.contains("synthetic.mkv"))
    }
}
