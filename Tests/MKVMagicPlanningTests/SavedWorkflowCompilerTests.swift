import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicPlanning

final class SavedWorkflowCompilerTests: XCTestCase {
    func testFilenameOnlyWorkflowCreatesReviewedUnchangedCopyPlan() throws {
        let workflow = SavedWorkflow(
            name: "Jellyfin filename",
            steps: [SavedWorkflowStep(action: .normalizeFilename)]
        )
        let asset = MediaAsset(
            sourceURL: URL(
                fileURLWithPath: "/private/media/Eddington.2025.1080p.BluRay.clean.mkv"
            ),
            container: "matroska",
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1", uid: 1)]
        )

        let preview = try SavedWorkflowCompiler().preview(workflow, for: asset)
        let compiled = try XCTUnwrap(preview.compiledWorkflow)

        XCTAssertTrue(compiled.createsUnchangedCopy)
        XCTAssertTrue(compiled.operations.isEmpty)
        XCTAssertEqual(compiled.suggestedOutputFilename, "Eddington (2025).mkv")
        XCTAssertEqual(compiled.plan.stages.map(\.mechanism), [.verify, .commit])
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 0)
        XCTAssertEqual(
            preview.stepOutcomes.map(\.detail),
            ["Suggest the output filename “Eddington (2025).mkv”"]
        )
    }

    func testFilenameSuggestionComposesWithoutAddingAnotherMediaPass() throws {
        let workflow = SavedWorkflow(
            name: "Clean name and title",
            steps: [
                SavedWorkflowStep(action: .normalizeFilename),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Movie.2025.1080p.mkv"),
            container: "matroska",
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1", uid: 1)],
            metadata: ["title": "Movie"]
        )

        let compiled = try SavedWorkflowCompiler().compile(workflow, for: asset)

        XCTAssertFalse(compiled.createsUnchangedCopy)
        XCTAssertTrue(compiled.removesSegmentTitle)
        XCTAssertEqual(compiled.suggestedOutputFilename, "Movie (2025).mkv")
        XCTAssertEqual(compiled.plan.stages.map(\.mechanism), [.mkvPropEdit, .verify, .commit])
    }

    func testAlreadySimpleFilenameOnlyWorkflowHasNoApplicableOutput() throws {
        let workflow = SavedWorkflow(
            name: "Already named",
            steps: [SavedWorkflowStep(action: .normalizeFilename)]
        )

        let preview = try SavedWorkflowCompiler().preview(workflow, for: makeAsset())

        XCTAssertNil(preview.compiledWorkflow)
        XCTAssertEqual(preview.stepOutcomes.map(\.disposition), [.skipped])
        XCTAssertThrowsError(try SavedWorkflowCompiler().compile(workflow, for: makeAsset())) {
            XCTAssertEqual($0 as? SavedWorkflowCompilationError, .noApplicableChanges)
        }
    }

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

    func testExternalSubtitleInputFusesWithCleanupAndTitleRemoval() throws {
        let workflow = SavedWorkflow(
            name: "Clean and subtitle",
            steps: [
                SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                SavedWorkflowStep(action: .addExternalSubtitle),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        let subtitleURL = URL(fileURLWithPath: "/private/input/Movie.en.ass")
        let externalInput = SavedWorkflowExternalSubtitleInput(
            sourceURL: subtitleURL,
            metadata: ExternalSubtitleTrackMetadata(
                language: "en",
                name: "RUNTIME_ONLY_TRACK_NAME",
                isDefault: true
            ),
            format: .ass
        )

        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: makeAsset(foreignSubtitleUID: 77, title: "Movie"),
            inputs: SavedWorkflowResolvedInputs(externalSubtitle: externalInput)
        )

        XCTAssertEqual(compiled.trackRemoval?.trackUIDs, [77])
        XCTAssertTrue(compiled.removesSegmentTitle)
        XCTAssertEqual(compiled.externalSubtitleInput, externalInput)
        XCTAssertEqual(
            compiled.plan.stages.map(\.mechanism),
            [.mkvMerge, .mkvPropEdit, .verify, .commit]
        )
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
        XCTAssertTrue(
            compiled.summaries.contains("Add one reviewed ASS subtitle as the last track")
        )
        let portableJSON = try XCTUnwrap(
            String(data: JSONEncoder().encode(workflow), encoding: .utf8)
        )
        XCTAssertFalse(portableJSON.contains(subtitleURL.path))
        XCTAssertFalse(portableJSON.contains("RUNTIME_ONLY_TRACK_NAME"))
    }

    func testExternalSubtitleCardRequiresOneMatchingEphemeralInput() {
        let workflow = SavedWorkflow(
            name: "Add subtitle",
            steps: [SavedWorkflowStep(action: .addExternalSubtitle)]
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(workflow, for: makeAsset())
        ) { error in
            XCTAssertEqual(
                error as? SavedWorkflowCompilationError,
                .missingExternalSubtitleInput
            )
        }
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                workflow,
                for: makeAsset(),
                inputs: SavedWorkflowResolvedInputs(
                    externalSubtitle: SavedWorkflowExternalSubtitleInput(
                        sourceURL: URL(fileURLWithPath: "/private/input/Movie.srt"),
                        metadata: ExternalSubtitleTrackMetadata(language: "en"),
                        format: .ass
                    )
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? SavedWorkflowCompilationError,
                .invalidExternalSubtitleInput
            )
        }
    }

    func testReviewedSubtitleCleanupFusesWithExternalInputWithoutPersistingReviewData() throws {
        let workflow = SavedWorkflow(
            name: "Clean and add subtitle",
            steps: [
                SavedWorkflowStep(action: .cleanExternalSubtitleText),
                SavedWorkflowStep(action: .addExternalSubtitle),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        let subtitleURL = URL(fileURLWithPath: "/private/input/Movie.en.srt")
        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: makeAsset(title: "Movie"),
            inputs: SavedWorkflowResolvedInputs(
                externalSubtitle: SavedWorkflowExternalSubtitleInput(
                    sourceURL: subtitleURL,
                    metadata: ExternalSubtitleTrackMetadata(language: "en"),
                    format: .subRip,
                    reviewedCleanupChangeCount: 2
                )
            )
        )

        XCTAssertEqual(compiled.operations.count, 2)
        XCTAssertEqual(compiled.externalSubtitleInput?.reviewedCleanupChangeCount, 2)
        XCTAssertEqual(
            compiled.plan.stages.map(\.mechanism),
            [.mkvMerge, .mkvPropEdit, .verify, .commit]
        )
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
        XCTAssertEqual(
            compiled.stepOutcomes.map(\.detail),
            [
                "Apply 2 reviewed subtitle text changes inside the same remux",
                "Add one reviewed SRT subtitle as the last track",
                "Remove the segment title",
            ]
        )
        let portableJSON = try XCTUnwrap(
            String(data: JSONEncoder().encode(workflow), encoding: .utf8)
        )
        XCTAssertTrue(portableJSON.contains("cleanExternalSubtitleText"))
        XCTAssertFalse(portableJSON.contains(subtitleURL.path))
        XCTAssertFalse(portableJSON.contains("reviewedCleanupChangeCount"))
    }

    func testSubtitleCleanupRequiresEnabledAddStepAndEphemeralReview() {
        let missingAdd = SavedWorkflow(
            name: "Invalid cleanup",
            steps: [SavedWorkflowStep(action: .cleanExternalSubtitleText)]
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(missingAdd, for: makeAsset())
        ) { error in
            XCTAssertEqual(
                error as? SavedWorkflowCompilationError,
                .externalSubtitleCleanupRequiresAddStep
            )
        }

        let missingReview = SavedWorkflow(
            name: "Review required",
            steps: [
                SavedWorkflowStep(action: .addExternalSubtitle),
                SavedWorkflowStep(action: .cleanExternalSubtitleText),
            ]
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                missingReview,
                for: makeAsset(),
                inputs: SavedWorkflowResolvedInputs(
                    externalSubtitle: SavedWorkflowExternalSubtitleInput(
                        sourceURL: URL(fileURLWithPath: "/private/input/Movie.en.srt"),
                        metadata: ExternalSubtitleTrackMetadata(language: "en"),
                        format: .subRip
                    )
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? SavedWorkflowCompilationError,
                .missingExternalSubtitleCleanupReview
            )
        }
    }

    func testGranularSubtitleConditionsFuseIntoOneStableUIDRemoval() throws {
        let workflow = SavedWorkflow(
            name: "Selective English cleanup",
            steps: [
                SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                SavedWorkflowStep(action: .removeSegmentTitle),
                SavedWorkflowStep(action: .removeRedundantEnglishSDH),
            ]
        )
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Movie.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1", uid: 1),
                MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 10,
                    language: "en",
                    title: "English"
                ),
                MediaTrack(
                    id: 2,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 11,
                    language: "en",
                    title: "English SDH",
                    isHearingImpaired: true
                ),
                MediaTrack(
                    id: 3,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 12,
                    language: "fr",
                    title: "French"
                ),
            ],
            metadata: ["title": "Movie"]
        )

        let compiled = try SavedWorkflowCompiler().compile(workflow, for: asset)

        XCTAssertEqual(compiled.trackRemoval?.trackUIDs, [11, 12])
        XCTAssertEqual(
            compiled.operations.filter {
                if case .removeTracksByUID = $0 { return true }
                return false
            }.count,
            1
        )
        XCTAssertEqual(
            compiled.plan.stages.map(\.mechanism),
            [.mkvMerge, .mkvPropEdit, .verify, .commit]
        )
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
        XCTAssertTrue(
            compiled.summaries.contains("Remove 1 explicitly non-English subtitle track")
        )
        XCTAssertTrue(
            compiled.summaries.contains("Remove 1 redundant English SDH subtitle track")
        )
    }

    func testPreviewExplainsAppliedSkippedAndDisabledStepsInRecipeOrder() throws {
        let workflow = SavedWorkflow(
            name: "Explain this run",
            steps: [
                SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                SavedWorkflowStep(action: .removeRedundantEnglishSDH),
                SavedWorkflowStep(isEnabled: false, action: .removeSegmentTitle),
            ]
        )
        let asset = makeAsset(foreignSubtitleUID: 72)

        let preview = try SavedWorkflowCompiler().preview(workflow, for: asset)
        let compiled = try XCTUnwrap(preview.compiledWorkflow)

        XCTAssertEqual(preview.workflowID, workflow.id)
        XCTAssertEqual(preview.stepOutcomes.map(\.stepID), workflow.steps.map(\.id))
        XCTAssertEqual(
            preview.stepOutcomes.map(\.disposition),
            [.applied, .skipped, .disabled]
        )
        XCTAssertEqual(
            preview.stepOutcomes.map(\.detail),
            [
                "Remove 1 explicitly non-English subtitle track",
                "No redundant English SDH subtitle tracks were found.",
                "Not included in this run.",
            ]
        )
        XCTAssertEqual(compiled.summaries, [preview.stepOutcomes[0].detail])
        XCTAssertEqual(compiled.stepOutcomes, preview.stepOutcomes)
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

        let granularCleanupAlreadySatisfied = SavedWorkflow(
            name: "No subtitle cleanup needed",
            steps: [
                SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                SavedWorkflowStep(action: .removeRedundantEnglishSDH),
            ]
        )
        let noChangePreview = try SavedWorkflowCompiler().preview(
            granularCleanupAlreadySatisfied,
            for: makeAsset()
        )
        XCTAssertNil(noChangePreview.compiledWorkflow)
        XCTAssertEqual(
            noChangePreview.stepOutcomes.map(\.disposition),
            [.skipped, .skipped]
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(granularCleanupAlreadySatisfied, for: makeAsset())
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
