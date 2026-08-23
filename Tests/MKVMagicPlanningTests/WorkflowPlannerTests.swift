import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicPlanning

final class WorkflowPlannerTests: XCTestCase {
    private let asset = MediaAsset(
        sourceURL: URL(fileURLWithPath: "/tmp/example.mkv"),
        container: "matroska",
        tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
    )

    func testMetadataEditUsesPropEditWithoutEncodingOrEarlySourceChange() throws {
        let plan = try WorkflowPlanner().plan(
            asset: asset,
            workflow: WorkflowDefinition(
                name: "Rename",
                operations: [.editSegmentTitle("Example")]
            )
        )
        XCTAssertEqual(plan.stages.map(\.mechanism), [.mkvPropEdit, .verify, .commit])
        XCTAssertEqual(plan.impact.videoEncodeCount, 0)
        XCTAssertTrue(plan.impact.copiesVideo)
        XCTAssertFalse(plan.impact.changesSourceBeforeVerification)
    }

    func testTrackRemovalRemuxesWithoutEncoding() throws {
        let plan = try WorkflowPlanner().plan(
            asset: asset,
            workflow: WorkflowDefinition(name: "Remove", operations: [.removeTracks([4])])
        )
        XCTAssertEqual(plan.stages.map(\.mechanism), [.mkvMerge, .verify, .commit])
        XCTAssertEqual(plan.impact.videoEncodeCount, 0)
    }

    func testMultipleVideoOperationsFuseIntoOneEncode() throws {
        let plan = try WorkflowPlanner().plan(
            asset: asset,
            workflow: WorkflowDefinition(
                name: "Exact trim and AV1",
                operations: [
                    .trim(
                        start: MediaTime(nanoseconds: 1_000_000_000),
                        end: MediaTime(nanoseconds: 5_000_000_000),
                        exact: true
                    ),
                    .transcodeVideo(.av1Quality),
                ]
            )
        )
        XCTAssertEqual(plan.stages.filter { $0.mechanism == .ffmpegEncode }.count, 1)
        XCTAssertEqual(plan.impact.videoEncodeCount, 1)
    }

    func testInvalidTrimRangeFailsPlanning() {
        XCTAssertThrowsError(
            try WorkflowPlanner().plan(
                asset: asset,
                workflow: WorkflowDefinition(
                    name: "Invalid",
                    operations: [.trim(start: .zero, end: .zero, exact: false)]
                )
            )
        ) { error in
            XCTAssertEqual(error as? PlanningError, .invalidTrimRange)
        }
    }
}
