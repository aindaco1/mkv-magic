import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicPlanning

final class SavedWorkflowCompilerTests: XCTestCase {
    func testImageAttachmentCleanupIsConditionalPortableAndFused() throws {
        let poster = MediaAttachment(
            id: 2,
            filename: "Private Poster.jpg",
            mimeType: "image/jpeg",
            uid: 22
        )
        let font = MediaAttachment(
            id: 4,
            filename: "Subtitle Font.ttf",
            mimeType: "font/ttf",
            uid: 44
        )
        let workflow = SavedWorkflow(
            name: "Remove images",
            steps: [
                SavedWorkflowStep(action: .removeImageAttachments),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )

        let preview = try SavedWorkflowCompiler().preview(
            workflow,
            for: makeConvertibleAsset(
                title: "Remove Me",
                attachments: [poster, font]
            )
        )
        let compiled = try XCTUnwrap(preview.compiledWorkflow)

        XCTAssertEqual(compiled.attachmentRemoval?.attachmentUIDs, [22])
        XCTAssertEqual(
            compiled.operations,
            [
                .removeAttachments(MatroskaAttachmentRemoval(attachmentUIDs: [22])),
                .editSegmentTitle(nil),
            ]
        )
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
        XCTAssertEqual(
            compiled.plan.stages.map(\.mechanism),
            [.mkvMerge, .mkvPropEdit, .verify, .commit]
        )
        XCTAssertEqual(
            preview.stepOutcomes.first?.detail,
            "Remove 1 MIME-identified image attachment"
        )
        XCTAssertFalse(compiled.summaries.joined().contains(poster.filename))

        let alreadyClean = try SavedWorkflowCompiler().preview(
            workflow,
            for: makeConvertibleAsset(attachments: [font])
        )
        XCTAssertNil(alreadyClean.compiledWorkflow)
        XCTAssertEqual(alreadyClean.stepOutcomes.first?.disposition, .skipped)
    }

    func testImageAttachmentCleanupPreparesOneVideoConversionAndRequiresStableIDs() throws {
        let poster = MediaAttachment(
            id: 2,
            filename: "Poster.jpg",
            mimeType: "image/jpeg",
            uid: 22
        )
        let workflow = SavedWorkflow(
            name: "Clean and convert",
            steps: [
                SavedWorkflowStep(action: .removeImageAttachments),
                SavedWorkflowStep(action: .convertVideoHEVC),
            ]
        )
        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: makeConvertibleAsset(attachments: [poster]),
            inputs: SavedWorkflowResolvedInputs(
                availableVideoPresets: [.hevcCompatibility]
            )
        )

        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 1)
        XCTAssertEqual(
            compiled.plan.stages.map(\.mechanism),
            [.mkvMerge, .ffmpegEncode, .verify, .commit]
        )

        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                workflow,
                for: makeConvertibleAsset(
                    attachments: [
                        MediaAttachment(
                            id: 2,
                            filename: "Unstable.jpg",
                            mimeType: "image/jpeg"
                        )
                    ]
                ),
                inputs: SavedWorkflowResolvedInputs(
                    availableVideoPresets: [.hevcCompatibility]
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .unavailableAttachmentIdentity
            )
        }
    }

    func testClearAllTagsCompilesConditionallyAndFusesWithTitleRemoval() throws {
        let workflow = SavedWorkflow(
            name: "Privacy cleanup",
            steps: [
                SavedWorkflowStep(action: .clearAllTags),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        let tagged = makeConvertibleAsset(
            title: "Feature",
            globalTagCount: 2,
            trackTagCount: 3
        )

        let preview = try SavedWorkflowCompiler().preview(workflow, for: tagged)
        let compiled = try XCTUnwrap(preview.compiledWorkflow)

        XCTAssertTrue(compiled.clearsAllTags)
        XCTAssertTrue(compiled.removesSegmentTitle)
        XCTAssertEqual(compiled.operations, [.clearAllTags, .editSegmentTitle(nil)])
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 0)
        XCTAssertEqual(compiled.plan.stages.map(\.mechanism), [.mkvPropEdit, .verify, .commit])
        XCTAssertEqual(
            preview.stepOutcomes.map(\.detail),
            ["Remove 2 global and 3 track Matroska tags", "Remove the segment title"]
        )

        let alreadyClean = try SavedWorkflowCompiler().preview(
            SavedWorkflow(
                name: "Tags only",
                steps: [SavedWorkflowStep(action: .clearAllTags)]
            ),
            for: makeConvertibleAsset()
        )
        XCTAssertNil(alreadyClean.compiledWorkflow)
        XCTAssertEqual(alreadyClean.stepOutcomes.first?.disposition, .skipped)
    }

    func testExplicitTagRemovalUnlocksOneVideoConversionForTaggedMKV() throws {
        let tagged = makeConvertibleAsset(globalTagCount: 1, trackTagCount: 2)
        let conversionOnly = SavedWorkflow(
            name: "Convert tagged file",
            steps: [SavedWorkflowStep(action: .convertVideoHEVC)]
        )
        let inputs = SavedWorkflowResolvedInputs(
            availableVideoPresets: [.hevcCompatibility]
        )

        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(conversionOnly, for: tagged, inputs: inputs)
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .unsupportedMediaConversion(.unsupportedTags)
            )
        }

        let compiled = try SavedWorkflowCompiler().compile(
            SavedWorkflow(
                name: "Clear then convert",
                steps: [
                    SavedWorkflowStep(action: .convertVideoHEVC),
                    SavedWorkflowStep(action: .clearAllTags),
                ]
            ),
            for: tagged,
            inputs: inputs
        )

        XCTAssertTrue(compiled.clearsAllTags)
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 1)
        XCTAssertEqual(
            compiled.plan.stages.map(\.mechanism),
            [.mkvPropEdit, .ffmpegEncode, .verify, .commit]
        )
    }

    func testClearAllTagsRequiresReviewedTagCounts() {
        let workflow = SavedWorkflow(
            name: "Tags",
            steps: [SavedWorkflowStep(action: .clearAllTags)]
        )

        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(workflow, for: makeAsset())
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .unavailableMatroskaTagCounts
            )
        }
    }

    func testRecommendedConversionBindsLocalPresetAndRunsAfterDeterministicEdits() throws {
        let workflow = SavedWorkflow(
            name: "Clean and convert",
            steps: [
                SavedWorkflowStep(action: .convertVideoRecommended),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )

        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: makeConvertibleAsset(title: "Feature"),
            inputs: SavedWorkflowResolvedInputs(
                availableVideoPresets: [.hevcCompatibility, .av1Quality]
            )
        )

        XCTAssertEqual(compiled.videoConversionChoice?.videoPreset, .hevcCompatibility)
        XCTAssertEqual(compiled.videoConversionChoice?.audioPolicy, .packetCopy)
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 1)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 0)
        XCTAssertEqual(
            compiled.plan.stages.map(\.mechanism),
            [.mkvPropEdit, .ffmpegEncode, .verify, .commit]
        )
        XCTAssertEqual(
            compiled.plan.stages.first(where: { $0.mechanism == .ffmpegEncode })?.summary,
            "Encode video once as HEVC 10-bit VideoToolbox while packet-copying audio and subtitles"
        )
        XCTAssertTrue(compiled.hasDeterministicMediaOperations)
        XCTAssertFalse(compiled.createsUnchangedCopy)
    }

    func testRecommendedConversionSkipsLocallyPreferredPresetWhenHDRIncompatible() throws {
        let workflow = SavedWorkflow(
            name: "Preserve HDR",
            steps: [SavedWorkflowStep(action: .convertVideoRecommended)]
        )

        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: makeConvertibleAsset(hdr10: true),
            inputs: SavedWorkflowResolvedInputs(
                availableVideoPresets: [.h264Compatibility, .hevcCompatibility]
            )
        )

        XCTAssertEqual(compiled.videoConversionChoice?.videoPreset, .hevcCompatibility)
    }

    func testConditionalConversionKeepsModernVideoAndDependentAudioUnchanged() throws {
        let workflow = SavedWorkflow(
            name: "Modern video guard",
            steps: [
                SavedWorkflowStep(action: .convertVideoIfNotAV1OrHEVC),
                SavedWorkflowStep(action: .convertAudioFLAC),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        let asset = makeConvertibleAsset(title: "Remove", hdr10: true)

        XCTAssertFalse(
            SavedWorkflowCompiler().needsEncodingCapabilities(for: workflow, asset: asset)
        )
        let preview = try SavedWorkflowCompiler().preview(workflow, for: asset)
        let compiled = try XCTUnwrap(preview.compiledWorkflow)

        XCTAssertNil(compiled.videoConversionChoice)
        XCTAssertNil(compiled.audioConversionPreset)
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 0)
        XCTAssertEqual(
            preview.stepOutcomes.map(\.disposition),
            [.skipped, .skipped, .applied]
        )
        XCTAssertEqual(compiled.plan.stages.map(\.mechanism), [.mkvPropEdit, .verify, .commit])

        let conversionOnly = SavedWorkflow(
            name: "Already modern",
            steps: [SavedWorkflowStep(action: .convertVideoIfNotAV1OrHEVC)]
        )
        XCTAssertNil(
            try SavedWorkflowCompiler().preview(conversionOnly, for: asset).compiledWorkflow
        )
    }

    func testConditionalConversionResolvesOneGenerationForLegacyVideo() throws {
        let workflow = SavedWorkflow(
            name: "Legacy video guard",
            steps: [
                SavedWorkflowStep(action: .convertVideoIfNotAV1OrHEVC),
                SavedWorkflowStep(action: .convertAudioOpus),
            ]
        )
        let asset = makeConvertibleAsset()

        XCTAssertTrue(
            SavedWorkflowCompiler().needsEncodingCapabilities(for: workflow, asset: asset)
        )
        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: asset,
            inputs: SavedWorkflowResolvedInputs(
                availableVideoPresets: [.hevcCompatibility],
                availableAudioPresets: [.opusQuality]
            )
        )

        XCTAssertEqual(compiled.videoConversionChoice?.videoPreset, .hevcCompatibility)
        XCTAssertEqual(compiled.audioConversionPreset, .opusQuality)
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 1)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 1)
    }

    func testFixedConversionRequiresItsLocallyVerifiedEncoder() {
        let workflow = SavedWorkflow(
            name: "AV1 conversion",
            steps: [SavedWorkflowStep(action: .convertVideoAV1)]
        )

        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                workflow,
                for: makeConvertibleAsset(),
                inputs: SavedWorkflowResolvedInputs(
                    availableVideoPresets: [.hevcCompatibility]
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .unavailableVideoPreset(.av1Quality)
            )
        }
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(workflow, for: makeConvertibleAsset())
        ) {
            XCTAssertEqual($0 as? SavedWorkflowCompilationError, .noAvailableVideoEncoder)
        }
    }

    func testMultipleEnabledConversionStepsFailClosed() {
        let workflow = SavedWorkflow(
            name: "Ambiguous conversion",
            steps: [
                SavedWorkflowStep(action: .convertVideoAV1),
                SavedWorkflowStep(action: .convertVideoHEVC),
            ]
        )

        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                workflow,
                for: makeConvertibleAsset(),
                inputs: SavedWorkflowResolvedInputs(
                    availableVideoPresets: [.av1Quality, .hevcCompatibility]
                )
            )
        ) {
            XCTAssertEqual($0 as? SavedWorkflowCompilationError, .multipleVideoConversions)
        }
    }

    func testAudioConversionRequiresExactlyOneVideoConversion() {
        let audioOnly = SavedWorkflow(
            name: "Audio only is not fused yet",
            steps: [SavedWorkflowStep(action: .convertAudioAAC)]
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                audioOnly,
                for: makeConvertibleAsset(),
                inputs: SavedWorkflowResolvedInputs(
                    availableAudioPresets: [.aacCompatibility]
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .audioConversionRequiresVideoConversion
            )
        }

        let multiple = SavedWorkflow(
            name: "Ambiguous audio",
            steps: [
                SavedWorkflowStep(action: .convertVideoH264),
                SavedWorkflowStep(action: .convertAudioAAC),
                SavedWorkflowStep(action: .convertAudioOpus),
            ]
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                multiple,
                for: makeConvertibleAsset(),
                inputs: SavedWorkflowResolvedInputs(
                    availableVideoPresets: [.h264Compatibility],
                    availableAudioPresets: [.aacCompatibility, .opusQuality]
                )
            )
        ) {
            XCTAssertEqual($0 as? SavedWorkflowCompilationError, .multipleAudioConversions)
        }
    }

    func testAudioConversionFusesIntoVideoPassAndRequiresCompatibleLocalEncoder() throws {
        let workflow = SavedWorkflow(
            name: "Compact audio and video",
            steps: [
                SavedWorkflowStep(action: .convertAudioOpus),
                SavedWorkflowStep(action: .convertVideoH264),
            ]
        )
        let inputs = SavedWorkflowResolvedInputs(
            availableVideoPresets: [.h264Compatibility],
            availableAudioPresets: [.opusQuality]
        )

        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: makeConvertibleAsset(),
            inputs: inputs
        )

        XCTAssertEqual(compiled.audioConversionPreset, .opusQuality)
        XCTAssertEqual(compiled.videoConversionChoice?.audioPolicy, .opusPreserveLayout)
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 1)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 1)
        XCTAssertEqual(
            compiled.plan.stages.first(where: { $0.mechanism == .ffmpegEncode })?.summary,
            "Encode video once as H.264 8-bit and 1 mismatched audio track once as Opus; packet-copy already-matching audio and subtitles"
        )

        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                workflow,
                for: makeConvertibleAsset(),
                inputs: SavedWorkflowResolvedInputs(
                    availableVideoPresets: [.h264Compatibility]
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .unavailableAudioPreset(.opusQuality)
            )
        }
    }

    func testAudioConversionRejectsImplicitDownmixOrRematrix() {
        let workflow = SavedWorkflow(
            name: "Unsafe AC-3",
            steps: [
                SavedWorkflowStep(action: .convertVideoH264),
                SavedWorkflowStep(action: .convertAudioAC3),
            ]
        )

        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                workflow,
                for: makeConvertibleAsset(audioChannels: 8, audioLayout: "7.1"),
                inputs: SavedWorkflowResolvedInputs(
                    availableVideoPresets: [.h264Compatibility],
                    availableAudioPresets: [.ac3Compatibility]
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .unsupportedMediaConversion(.incompleteAudioFacts(trackID: 1))
            )
        }
    }

    func testStandaloneAudioConversionCompilesWithoutVideoAndCopiesVideo() throws {
        let workflow = SavedWorkflow(
            name: "Audio only",
            steps: [SavedWorkflowStep(action: .transcodeAllAudioFLAC)]
        )
        let asset = makeConvertibleAsset()

        XCTAssertTrue(
            SavedWorkflowCompiler().needsEncodingCapabilities(for: workflow, asset: asset)
        )
        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: asset,
            inputs: SavedWorkflowResolvedInputs(
                availableAudioPresets: [.flacLossless]
            )
        )

        XCTAssertNil(compiled.videoConversionChoice)
        XCTAssertEqual(compiled.audioConversionPreset, .flacLossless)
        XCTAssertEqual(compiled.operations, [.transcodeAudio(.flacLossless)])
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 1)
        XCTAssertTrue(compiled.plan.impact.copiesVideo)
        XCTAssertEqual(
            compiled.plan.stages.map(\.mechanism),
            [.ffmpegEncode, .verify, .commit]
        )
        XCTAssertEqual(
            compiled.plan.stages[0].summary,
            "Encode 1 mismatched audio track once as FLAC (Lossless) while packet-copying video, matching audio, and subtitles"
        )
    }

    func testStandaloneAudioSkipsMatchingTracksAndNeedsNoEncoderForANoOp() throws {
        let workflow = SavedWorkflow(
            name: "Selective FLAC",
            steps: [SavedWorkflowStep(action: .transcodeAllAudioFLAC)]
        )
        let matchingAsset = makeConvertibleAsset(audioCodec: "FLAC")

        XCTAssertFalse(
            SavedWorkflowCompiler().needsEncodingCapabilities(
                for: workflow,
                asset: matchingAsset
            )
        )
        let matchingPreview = try SavedWorkflowCompiler().preview(
            workflow,
            for: matchingAsset
        )
        XCTAssertNil(matchingPreview.compiledWorkflow)
        XCTAssertEqual(matchingPreview.stepOutcomes.map(\.disposition), [.skipped])

        let mixedAsset = makeConvertibleAsset(
            audioCodec: "flac",
            additionalAudioCodec: "aac"
        )
        let mixedPreview = try SavedWorkflowCompiler().preview(
            workflow,
            for: mixedAsset,
            inputs: SavedWorkflowResolvedInputs(
                availableAudioPresets: [.flacLossless]
            )
        )
        let compiled = try XCTUnwrap(mixedPreview.compiledWorkflow)

        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 1)
        XCTAssertEqual(
            mixedPreview.stepOutcomes.map(\.detail),
            [
                "Encode 1 audio track once as FLAC (Lossless), preserving each channel layout; packet-copy 1 already-matching audio track"
            ]
        )
    }

    func testVideoConversionCopiesAudioWhenEveryTrackAlreadyMatchesTarget() throws {
        let workflow = SavedWorkflow(
            name: "Video plus already Opus",
            steps: [
                SavedWorkflowStep(action: .convertVideoH264),
                SavedWorkflowStep(action: .transcodeAllAudioOpus),
            ]
        )
        let preview = try SavedWorkflowCompiler().preview(
            workflow,
            for: makeConvertibleAsset(audioCodec: "opus"),
            inputs: SavedWorkflowResolvedInputs(
                availableVideoPresets: [.h264Compatibility]
            )
        )
        let compiled = try XCTUnwrap(preview.compiledWorkflow)

        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 1)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 0)
        XCTAssertEqual(compiled.videoConversionChoice?.audioPolicy, .packetCopy)
        XCTAssertNil(compiled.audioConversionPreset)
        XCTAssertEqual(preview.stepOutcomes.map(\.disposition), [.applied, .skipped])
    }

    func testStandaloneAudioConversionFusesWithVideoAndSkipsFilesWithoutAudio() throws {
        let workflow = SavedWorkflow(
            name: "One media pass",
            steps: [
                SavedWorkflowStep(action: .convertVideoH264),
                SavedWorkflowStep(action: .transcodeAllAudioOpus),
            ]
        )
        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: makeConvertibleAsset(),
            inputs: SavedWorkflowResolvedInputs(
                availableVideoPresets: [.h264Compatibility],
                availableAudioPresets: [.opusQuality]
            )
        )

        XCTAssertEqual(
            compiled.plan.stages.filter { $0.mechanism == .ffmpegEncode }.count,
            1
        )
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 1)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 1)
        XCTAssertEqual(compiled.videoConversionChoice?.audioPolicy, .opusPreserveLayout)

        let noAudio = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Silent.mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 10),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
        let audioOnly = SavedWorkflow(
            name: "No-op on silent files",
            steps: [SavedWorkflowStep(action: .transcodeAllAudioAAC)]
        )
        XCTAssertFalse(
            SavedWorkflowCompiler().needsEncodingCapabilities(for: audioOnly, asset: noAudio)
        )
        XCTAssertNil(
            try SavedWorkflowCompiler().preview(audioOnly, for: noAudio).compiledWorkflow
        )
    }

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

    func testRemuxIntentCompilesAgainstCompatibleInputWithoutEncoding() throws {
        let workflow = SavedWorkflow(
            name: "Portable MKV",
            steps: [
                SavedWorkflowStep(action: .remuxToMKV),
                SavedWorkflowStep(action: .normalizeFilename),
            ]
        )
        let source = makeMP4Asset(path: "/private/media/Movie.2025.1080p.mp4")

        XCTAssertFalse(
            SavedWorkflowCompiler().needsEncodingCapabilities(for: workflow, asset: source)
        )
        let compiled = try SavedWorkflowCompiler().compile(workflow, for: source)

        XCTAssertEqual(compiled.mkvRemuxPlan?.source, source)
        XCTAssertEqual(compiled.mkvRemuxPlan?.trackIDsInOutputOrder, [4, 9])
        XCTAssertTrue(compiled.operations.isEmpty)
        XCTAssertFalse(compiled.createsUnchangedCopy)
        XCTAssertTrue(compiled.hasDeterministicMediaOperations)
        XCTAssertEqual(compiled.suggestedOutputFilename, "Movie (2025).mp4")
        XCTAssertEqual(compiled.plan.stages.map(\.mechanism), [.mkvMerge, .verify, .commit])
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 0)
        XCTAssertTrue(compiled.plan.impact.copiesVideo)
        XCTAssertEqual(compiled.stepOutcomes.map(\.disposition), [.applied, .applied])
        XCTAssertTrue(compiled.stepOutcomes[0].detail.contains("Packet-copy 2 media tracks"))
    }

    func testRemuxIntentSkipsMKVAndLetsExistingMatroskaStepsRun() throws {
        let remuxOnly = SavedWorkflow(
            name: "Already MKV",
            steps: [SavedWorkflowStep(action: .remuxToMKV)]
        )
        let preview = try SavedWorkflowCompiler().preview(remuxOnly, for: makeAsset())

        XCTAssertNil(preview.compiledWorkflow)
        XCTAssertEqual(preview.stepOutcomes.map(\.disposition), [.skipped])

        let withTitleEdit = SavedWorkflow(
            name: "Edit existing MKV",
            steps: [
                SavedWorkflowStep(action: .remuxToMKV),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        let compiled = try SavedWorkflowCompiler().compile(
            withTitleEdit,
            for: makeAsset(title: "Movie")
        )
        XCTAssertNil(compiled.mkvRemuxPlan)
        XCTAssertTrue(compiled.removesSegmentTitle)
        XCTAssertEqual(compiled.stepOutcomes.map(\.disposition), [.skipped, .applied])
    }

    func testCommonInputConversionCompilesAsOneDirectMKVPass() throws {
        let workflow = SavedWorkflow(
            name: "Portable compact conversion",
            steps: [
                SavedWorkflowStep(action: .normalizeFilename),
                SavedWorkflowStep(action: .convertVideoH264),
                SavedWorkflowStep(action: .transcodeAllAudioOpus),
            ]
        )
        let source = makeCommonConvertibleAsset(
            path: "/private/media/Feature.2025.1080p.mp4"
        )
        XCTAssertTrue(
            SavedWorkflowCompiler().needsEncodingCapabilities(for: workflow, asset: source)
        )

        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: source,
            inputs: SavedWorkflowResolvedInputs(
                availableVideoPresets: [.h264Compatibility],
                availableAudioPresets: [.opusQuality]
            )
        )

        XCTAssertEqual(compiled.videoConversionChoice?.videoPreset, .h264Compatibility)
        XCTAssertEqual(compiled.videoConversionChoice?.audioPolicy, .opusPreserveLayout)
        XCTAssertFalse(compiled.hasDeterministicMediaOperations)
        XCTAssertTrue(compiled.requiresMKVOutputExtension)
        XCTAssertEqual(compiled.suggestedOutputFilename, "Feature (2025).mp4")
        XCTAssertEqual(compiled.plan.stages.map(\.mechanism), [.ffmpegEncode, .verify, .commit])
        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 1)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 1)
        XCTAssertEqual(compiled.plan.stages.filter { $0.mechanism == .ffmpegEncode }.count, 1)
    }

    func testCommonInputConversionFailsClosedAtItsCompositionBoundary() {
        let source = makeCommonConvertibleAsset()
        let matroskaEdit = SavedWorkflow(
            name: "Edit before conversion",
            steps: [
                SavedWorkflowStep(action: .removeSegmentTitle),
                SavedWorkflowStep(action: .convertVideoH264),
            ]
        )
        XCTAssertFalse(
            SavedWorkflowCompiler().needsEncodingCapabilities(for: matroskaEdit, asset: source)
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                matroskaEdit,
                for: source,
                inputs: SavedWorkflowResolvedInputs(
                    availableVideoPresets: [.h264Compatibility]
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .commonInputCannotCombineWithMatroskaEdits
            )
        }

        let standaloneAudio = SavedWorkflow(
            name: "Audio without video",
            steps: [SavedWorkflowStep(action: .transcodeAllAudioOpus)]
        )
        XCTAssertFalse(
            SavedWorkflowCompiler().needsEncodingCapabilities(for: standaloneAudio, asset: source)
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                standaloneAudio,
                for: source,
                inputs: SavedWorkflowResolvedInputs(
                    availableAudioPresets: [.opusQuality]
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .commonInputRequiresVideoConversion
            )
        }

        let alreadyHEVC = makeCommonConvertibleAsset(videoCodec: "hevc")
        let conditional = SavedWorkflow(
            name: "Modern common video",
            steps: [SavedWorkflowStep(action: .convertVideoIfNotAV1OrHEVC)]
        )
        XCTAssertFalse(
            SavedWorkflowCompiler().needsEncodingCapabilities(for: conditional, asset: alreadyHEVC)
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(conditional, for: alreadyHEVC)
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .commonInputRequiresVideoConversion
            )
        }
    }

    func testCommonInputConversionSurfacesExactTranslationFailure() {
        let workflow = SavedWorkflow(
            name: "Convert unsupported metadata",
            steps: [SavedWorkflowStep(action: .convertVideoH264)]
        )
        let source = makeCommonConvertibleAsset(metadata: ["artist": "Private metadata"])

        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(
                workflow,
                for: source,
                inputs: SavedWorkflowResolvedInputs(
                    availableVideoPresets: [.h264Compatibility]
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .unsupportedMediaConversion(.unsupportedCommonMetadata)
            )
        }
    }

    func testActiveRemuxRejectsOtherMediaActionsAndSurfacesPlannerFailure() {
        let conflicting = SavedWorkflow(
            name: "Ambiguous pipeline",
            steps: [
                SavedWorkflowStep(action: .remuxToMKV),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        XCTAssertThrowsError(
            try SavedWorkflowCompiler().compile(conflicting, for: makeMP4Asset())
        ) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .remuxCannotCombineWithOtherActions
            )
        }

        let timedText = makeMP4Asset(
            tracks: [
                MediaTrack(id: 4, kind: .video, codec: "h264"),
                MediaTrack(id: 9, kind: .subtitle, codec: "mov_text"),
            ]
        )
        let remuxOnly = SavedWorkflow(
            name: "Unsupported subtitle",
            steps: [SavedWorkflowStep(action: .remuxToMKV)]
        )
        XCTAssertThrowsError(try SavedWorkflowCompiler().compile(remuxOnly, for: timedText)) {
            XCTAssertEqual(
                $0 as? SavedWorkflowCompilationError,
                .unsupportedMKVRemux(.unsupportedTrack(trackID: 9, codec: "mov_text"))
            )
        }
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

    func testRejectsMatroskaOnlyEditForRecognizedCommonInput() {
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
            XCTAssertEqual(
                error as? SavedWorkflowCompilationError,
                .commonInputCannotCombineWithMatroskaEdits
            )
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

    private func makeConvertibleAsset(
        title: String? = nil,
        hdr10: Bool = false,
        audioCodec: String = "aac",
        additionalAudioCodec: String? = nil,
        audioChannels: Int = 2,
        audioLayout: String = "stereo",
        globalTagCount: Int = 0,
        trackTagCount: Int = 0,
        attachments: [MediaAttachment] = []
    ) -> MediaAsset {
        var tracks = [
            MediaTrack(
                id: 0,
                kind: .video,
                codec: hdr10 ? "hevc" : "h264",
                codecID: hdr10 ? "V_MPEGH/ISO/HEVC" : "V_MPEG4/ISO/AVC",
                profile: hdr10 ? "Main 10" : "High",
                uid: 100,
                isDefault: true,
                dimensions: MediaDimensions(width: 160, height: 90),
                pixelFormat: hdr10 ? "yuv420p10le" : "yuv420p",
                bitDepth: hdr10 ? 10 : 8,
                frameRate: "24/1",
                colorInfo: MediaColorInfo(
                    range: "tv",
                    primaries: hdr10 ? "bt2020" : "bt709",
                    transfer: hdr10 ? "smpte2084" : "bt709",
                    matrix: hdr10 ? "bt2020nc" : "bt709"
                ),
                masteringDisplayMetadata: hdr10 ? savedWorkflowMasteringDisplay : nil,
                contentLightLevelMetadata: hdr10 ? savedWorkflowContentLight : nil,
                hdrFormats: hdr10 ? ["HDR10 metadata"] : []
            ),
            MediaTrack(
                id: 1,
                kind: .audio,
                codec: audioCodec,
                codecID: audioCodec.lowercased() == "aac" ? "A_AAC" : nil,
                profile: audioCodec.lowercased() == "aac" ? "LC" : nil,
                uid: 101,
                language: "en",
                isDefault: true,
                channels: audioChannels,
                channelLayout: audioLayout,
                sampleRate: 48_000
            ),
        ]
        if let additionalAudioCodec {
            tracks.append(
                MediaTrack(
                    id: 2,
                    kind: .audio,
                    codec: additionalAudioCodec,
                    uid: 102,
                    language: "fr",
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: 48_000
                )
            )
        }
        return MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Feature.mkv"),
            container: "matroska,webm",
            duration: MediaTime(seconds: 10),
            fileSize: 1_000,
            tracks: tracks,
            attachments: attachments,
            metadata: title.map { ["title": $0] } ?? [:],
            chapterEntryCount: 0,
            globalTagCount: globalTagCount,
            trackTagCount: trackTagCount,
            segmentUID: "SOURCE"
        )
    }

    private func makeMP4Asset(
        path: String = "/private/media/Movie.mp4",
        tracks: [MediaTrack]? = nil
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: path),
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            duration: MediaTime(seconds: 10),
            fileSize: 1_000,
            tracks: tracks ?? [
                MediaTrack(id: 4, kind: .video, codec: "h264"),
                MediaTrack(id: 9, kind: .audio, codec: "aac", language: "en"),
            ],
            chapterEntryCount: 0
        )
    }

    private func makeCommonConvertibleAsset(
        path: String = "/private/media/Feature.mp4",
        videoCodec: String = "h264",
        metadata: [String: String] = ["title": "Feature", "major_brand": "isom"]
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: path),
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            duration: MediaTime(seconds: 10),
            fileSize: 1_000,
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: videoCodec,
                    profile: videoCodec == "hevc" ? "Main" : "High",
                    dimensions: MediaDimensions(width: 160, height: 90),
                    pixelFormat: "yuv420p",
                    bitDepth: 8,
                    frameRate: "24/1",
                    colorInfo: MediaColorInfo(
                        range: "tv",
                        primaries: "bt709",
                        transfer: "bt709",
                        matrix: "bt709"
                    )
                ),
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    profile: "LC",
                    language: "en",
                    title: "Main Audio",
                    isDefault: true,
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: 48_000,
                    tags: ["handler_name": "SoundHandler"]
                ),
            ],
            metadata: metadata,
            chapterEntryCount: 0
        )
    }
}

private let savedWorkflowMasteringDisplay = MediaMasteringDisplayMetadata(
    redX: 34_000,
    redY: 16_000,
    greenX: 13_250,
    greenY: 34_500,
    blueX: 7_500,
    blueY: 3_000,
    whitePointX: 15_635,
    whitePointY: 16_450,
    maxLuminance: 10_000_000,
    minLuminance: 50
)

private let savedWorkflowContentLight = MediaContentLightLevelMetadata(
    maxContentLightLevel: 1_000,
    maxFrameAverageLightLevel: 400
)
