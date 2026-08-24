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

    func testStableUIDTrackRemovalRemuxesWithoutEncoding() throws {
        let plan = try WorkflowPlanner().plan(
            asset: asset,
            workflow: WorkflowDefinition(
                name: "Remove by UID",
                operations: [.removeTracksByUID(TrackRemoval(trackUIDs: [42]))]
            )
        )

        XCTAssertEqual(plan.stages.first?.mechanism, .mkvMerge)
        XCTAssertEqual(plan.impact.videoEncodeCount, 0)
        XCTAssertTrue(plan.impact.copiesVideo)
    }

    func testFullTrackMetadataEditUsesPropEditWithoutEncoding() throws {
        let edit = TrackMetadataEdit(
            trackUID: 42,
            name: "English Commentary",
            language: "en",
            isDefault: false,
            isForced: false,
            isEnabled: true,
            isCommentary: true,
            isHearingImpaired: false,
            isVisualImpaired: false,
            isOriginal: true,
            isTextDescription: false
        )
        let plan = try WorkflowPlanner().plan(
            asset: asset,
            workflow: WorkflowDefinition(
                name: "Edit commentary track",
                operations: [.editTrackMetadata(edit)]
            )
        )

        XCTAssertEqual(plan.stages.map(\.mechanism), [.mkvPropEdit, .verify, .commit])
        XCTAssertEqual(plan.impact.videoEncodeCount, 0)
        XCTAssertTrue(plan.impact.copiesVideo)
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

    func testAudioOnlyAndVideoAudioPlansUseOneEncodingStage() throws {
        let audioAsset = MediaAsset(
            sourceURL: asset.sourceURL,
            container: asset.container,
            tracks: asset.tracks + [
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: 48_000
                )
            ]
        )
        let audioOnly = try WorkflowPlanner().plan(
            asset: audioAsset,
            workflow: WorkflowDefinition(
                name: "Audio",
                operations: [.transcodeAudio(.flacLossless)]
            )
        )
        XCTAssertEqual(audioOnly.stages.map(\.mechanism), [.ffmpegEncode, .verify, .commit])
        XCTAssertEqual(audioOnly.impact.videoEncodeCount, 0)
        XCTAssertEqual(audioOnly.impact.audioEncodeCount, 1)
        XCTAssertTrue(audioOnly.impact.copiesVideo)

        let fused = try WorkflowPlanner().plan(
            asset: audioAsset,
            workflow: WorkflowDefinition(
                name: "Media",
                operations: [
                    .transcodeVideo(.av1Quality),
                    .transcodeAudio(.opusQuality),
                ]
            )
        )
        XCTAssertEqual(fused.stages.filter { $0.mechanism == .ffmpegEncode }.count, 1)
        XCTAssertEqual(fused.impact.videoEncodeCount, 1)
        XCTAssertEqual(fused.impact.audioEncodeCount, 1)
        XCTAssertFalse(fused.impact.copiesVideo)
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
