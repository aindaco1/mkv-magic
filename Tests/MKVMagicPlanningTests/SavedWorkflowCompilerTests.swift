import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicPlanning

final class SavedWorkflowCompilerTests: XCTestCase {
    func testCompilesPortableIntentAgainstEachAssetsStableTrackUIDs() throws {
        let workflow = SavedWorkflow(
            id: UUID(uuidString: "B989848F-887B-4861-AF7E-ADE3E6E64883")!,
            name: "English library",
            steps: [
                SavedWorkflowStep(
                    id: UUID(uuidString: "22D43583-1382-4778-A4EC-D8618D3A6A4B")!,
                    action: .englishLibraryCleanup
                )
            ]
        )
        let frenchFirst = makeAsset(foreignSubtitleUID: 41)
        let frenchSecond = makeAsset(foreignSubtitleUID: 902)

        let first = try SavedWorkflowCompiler().compile(workflow, for: frenchFirst)
        let second = try SavedWorkflowCompiler().compile(workflow, for: frenchSecond)

        XCTAssertEqual(first.trackRemoval?.trackUIDs, [41])
        XCTAssertEqual(second.trackRemoval?.trackUIDs, [902])
        XCTAssertEqual(first.workflowID, workflow.id)
        XCTAssertEqual(first.plan.stages.map(\.mechanism), [.mkvMerge, .verify, .commit])
        let json = String(
            data: try JSONEncoder().encode(workflow),
            encoding: .utf8
        )!
        XCTAssertFalse(json.contains(frenchFirst.sourceURL.path))
        XCTAssertFalse(json.contains("41"))
        XCTAssertFalse(json.contains("902"))
    }

    func testCombinesCleanupAndTitleRemovalIntoOneRemuxThenOnePropertyPass() throws {
        let workflow = SavedWorkflow(
            name: "Clean metadata",
            steps: [
                SavedWorkflowStep(action: .englishLibraryCleanup),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: makeAsset(foreignSubtitleUID: 77, title: "Movie")
        )

        XCTAssertEqual(compiled.operations.count, 2)
        XCTAssertTrue(compiled.removesSegmentTitle)
        XCTAssertEqual(
            compiled.plan.stages.map(\.mechanism),
            [.mkvMerge, .mkvPropEdit, .verify, .commit]
        )
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
    }

    func testDisabledStepsDoNotCompileAndNoApplicableChangesIsExplicit() throws {
        let onlyDisabled = SavedWorkflow(
            name: "Disabled",
            steps: [SavedWorkflowStep(isEnabled: false, action: .removeSegmentTitle)]
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(onlyDisabled, for: makeAsset())
        ) { error in
            XCTAssertEqual(error as? SavedWorkflowCompilationError, .noEnabledSteps)
        }

        let alreadyClean = SavedWorkflow(
            name: "Already clean",
            steps: [SavedWorkflowStep(action: .removeSegmentTitle)]
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(alreadyClean, for: makeAsset())
        ) { error in
            XCTAssertEqual(error as? SavedWorkflowCompilationError, .noApplicableChanges)
        }
    }

    func testRejectsNonMatroskaAssetsBeforePlanning() {
        let workflow = SavedWorkflow(
            name: "Clean",
            steps: [SavedWorkflowStep(action: .removeSegmentTitle)]
        )
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/tmp/Movie.mp4"),
            container: "mov,mp4",
            metadata: ["title": "Movie"]
        )

        XCTAssertThrowsError(try SavedWorkflowCompiler().compile(workflow, for: asset)) { error in
            XCTAssertEqual(error as? SavedWorkflowCompilationError, .unsupportedContainer)
        }
    }

    func testRejectsDuplicateActionsAndUnsafeTrackIdentityDuringPreview() {
        let duplicate = SavedWorkflow(
            name: "Duplicate",
            steps: [
                SavedWorkflowStep(action: .removeSegmentTitle),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                duplicate,
                for: makeAsset(title: "Movie")
            )
        ) { error in
            XCTAssertEqual(error as? SavedWorkflowCompilationError, .duplicateAction)
        }

        let cleanup = SavedWorkflow(
            name: "Cleanup",
            steps: [SavedWorkflowStep(action: .englishLibraryCleanup)]
        )
        let unstable = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/tmp/Movie.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1"),
                MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 42,
                    language: "fr"
                ),
            ]
        )
        XCTAssertThrowsError(try SavedWorkflowCompiler().compile(cleanup, for: unstable)) { error in
            XCTAssertEqual(error as? SavedWorkflowCompilationError, .unstableTrackIdentity)
        }
    }

    func testRecognizesCaseInsensitiveSegmentTitleMetadata() throws {
        let workflow = SavedWorkflow(
            name: "Remove title",
            steps: [SavedWorkflowStep(action: .removeSegmentTitle)]
        )
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/tmp/Movie.mkv"),
            container: "matroska",
            metadata: ["TITLE": "Movie"]
        )

        XCTAssertTrue(try SavedWorkflowCompiler().compile(workflow, for: asset).removesSegmentTitle)
    }

    private func makeAsset(foreignSubtitleUID: UInt64? = nil, title: String? = nil) -> MediaAsset {
        var tracks = [MediaTrack(id: 0, kind: .video, codec: "av1", uid: 1)]
        if let foreignSubtitleUID {
            tracks.append(
                MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: foreignSubtitleUID,
                    language: "fr"
                )
            )
        }
        return MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Movie.mkv"),
            container: "matroska,webm",
            tracks: tracks,
            metadata: title.map { ["title": $0] } ?? [:]
        )
    }
}
