import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

@testable import MKVMagic

final class RealToolAdvancedSubtitleQueueTests: XCTestCase {
    @MainActor
    func testAutomaticQueueReconstructsReviewedASSAndSSAWorkflows() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-advanced-subtitle-queue-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let rawAudio = fixtureRoot.appendingPathComponent("silence.pcm")
        let source = fixtureRoot.appendingPathComponent("Queued Movie.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)
        let createResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-c:a", "aac", "-metadata", "title=Remove Automatically",
                    source.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(createResult.exitCode, 0, createResult.standardError.text)
        let sourceDigest = SHA256.hash(data: try Data(contentsOf: source))

        let fixtures = [
            AdvancedSubtitleQueueFixture.ass,
            AdvancedSubtitleQueueFixture.ssa,
        ]
        for fixture in fixtures {
            let sidecar = fixtureRoot.appendingPathComponent(
                "Queued Movie.en.\(fixture.format.filenameExtension)"
            )
            let output = fixtureRoot.appendingPathComponent(
                "Queued Movie — \(fixture.format.displayName) Prepared.mkv"
            )
            let extracted = fixtureRoot.appendingPathComponent(
                "Extracted.\(fixture.format.filenameExtension)"
            )
            try Data(fixture.contents.utf8).write(to: sidecar)
            let sidecarDigest = SHA256.hash(data: try Data(contentsOf: sidecar))

            let applicationSupport = fixtureRoot.appendingPathComponent(
                "Application Support \(fixture.format.displayName)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: applicationSupport,
                withIntermediateDirectories: false
            )
            let historyStore = try AppHistoryLocation.makeStore(
                applicationSupportURL: applicationSupport
            )
            let queueStore = try AppHistoryLocation.makeQueueStore(
                applicationSupportURL: applicationSupport
            )
            let model = AppModel(
                historyRecorderFactory: { historyStore },
                queueStoreFactory: { queueStore },
                queueEnvironmentReader: AdvancedSubtitleQueueEnvironmentReader()
            )
            await model.addFiles([source])
            let asset = try XCTUnwrap(model.assets.first)
            let reviewedSourceRevision = try XCTUnwrap(
                model.reviewedSourceRevision(for: asset)
            )
            let preview = try await model.previewAdvancedSubtitleCleanup(at: sidecar)
            XCTAssertEqual(preview.cleanup.changes.count, 3, fixture.format.displayName)
            XCTAssertEqual(
                preview.cleanup.changes.map(\.id),
                [0, 1, 2],
                fixture.format.displayName
            )
            let restoredChangeIDs: Set<Int> = [2]
            let payload = ExternalSubtitleMuxPayload.reviewedCleanup(
                .advanced(preview),
                restoringIDs: restoredChangeIDs
            )
            let metadata = ExternalSubtitleTrackMetadata(
                language: "en",
                name: "English \(fixture.format.displayName)",
                isDefault: true,
                isForced: true,
                isHearingImpaired: true
            )
            let workflow = SavedWorkflow(
                name: "Clean and add \(fixture.format.displayName) subtitles",
                steps: [
                    SavedWorkflowStep(action: .cleanExternalSubtitleText),
                    SavedWorkflowStep(action: .addExternalSubtitle),
                    SavedWorkflowStep(action: .removeSegmentTitle),
                ]
            )
            let compiled = try SavedWorkflowCompiler().compile(
                workflow,
                for: asset,
                inputs: SavedWorkflowResolvedInputs(
                    externalSubtitle: SavedWorkflowExternalSubtitleInput(
                        sourceURL: sidecar,
                        metadata: metadata,
                        format: fixture.format,
                        reviewedCleanupChangeCount: payload.reviewedCleanupChangeCount
                    )
                )
            )
            XCTAssertEqual(
                compiled.plan.stages.map(\.mechanism),
                [.mkvMerge, .mkvPropEdit, .verify, .commit],
                fixture.format.displayName
            )

            let waiting = try await model.enqueueSavedWorkflow(
                compiled,
                recipe: workflow,
                externalSubtitlePayload: payload,
                expectedSourceRevision: reviewedSourceRevision,
                in: asset,
                destinationURL: output
            )
            let waitingJob = try XCTUnwrap(waiting.jobs.first)
            XCTAssertTrue(MediaQueueAutomaticWorkflowPolicy.supports(waitingJob))
            XCTAssertEqual(waitingJob.events.map(\.state), [.waiting])
            XCTAssertEqual(waitingJob.resourceClass, .lightweight)
            XCTAssertEqual(waitingJob.reviewedPlan, compiled.plan)
            XCTAssertEqual(
                waitingJob.inputs.map(\.displayName),
                [source.lastPathComponent, sidecar.lastPathComponent])
            XCTAssertEqual(
                waitingJob.workflow,
                .savedWithExternalSubtitle(
                    workflow,
                    MediaQueueExternalSubtitleReview(
                        format: fixture.format,
                        metadata: metadata,
                        restoredCleanupChangeIDs: [2],
                        sourceSHA256: preview.sourceSHA256
                    )
                )
            )

            let completed = try await model.runAutomaticQueueCycle()

            let completedJob = try XCTUnwrap(completed.jobs.first)
            XCTAssertEqual(
                completedJob.events.map(\.state),
                [.waiting, .running, .succeeded],
                fixture.format.displayName
            )
            XCTAssertEqual(completedJob.attemptCount, 1)
            XCTAssertNil(model.activeQueueJobID)
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: source)),
                sourceDigest,
                fixture.format.displayName
            )
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: sidecar)),
                sidecarDigest,
                fixture.format.displayName
            )

            let outputAsset = try XCTUnwrap(
                model.assets.first { $0.sourceURL == output }
            )
            XCTAssertNil(outputAsset.metadata["title"], fixture.format.displayName)
            let subtitleTrack = try XCTUnwrap(outputAsset.tracks.last)
            XCTAssertEqual(subtitleTrack.kind, .subtitle)
            XCTAssertEqual(subtitleTrack.codecID, fixture.codecID)
            XCTAssertEqual(subtitleTrack.title, metadata.name)
            XCTAssertEqual(
                try TrackLanguageTag.canonical(try XCTUnwrap(subtitleTrack.language)),
                "en"
            )
            XCTAssertTrue(subtitleTrack.isDefault)
            XCTAssertTrue(subtitleTrack.isForced)
            XCTAssertTrue(subtitleTrack.isHearingImpaired)

            let extractResult = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .mkvextract),
                    arguments: [
                        "tracks", output.path,
                        "\(try XCTUnwrap(subtitleTrack.id)):\(extracted.path)",
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(
                extractResult.exitCode,
                0,
                extractResult.standardError.text
            )
            let extractedText = String(
                decoding: try Data(contentsOf: extracted),
                as: UTF8.self
            )
            XCTAssertTrue(extractedText.contains(fixture.styleNeedle), extractedText)
            XCTAssertTrue(extractedText.contains("Hello styled"), extractedText)
            XCTAssertTrue(extractedText.contains(#"{\an8}HE11O"#), extractedText)
            XCTAssertFalse(extractedText.contains("YTS.MX"), extractedText)

            let records = try await historyStore.load()
            let record = try XCTUnwrap(records.first)
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(record.workflowID, workflow.id)
            XCTAssertEqual(
                record.inputs.map(\.displayName),
                [source.lastPathComponent, sidecar.lastPathComponent]
            )
            XCTAssertEqual(record.outputDisplayName, output.lastPathComponent)
            XCTAssertEqual(
                record.events.map(\.state),
                [
                    .queued, .inspecting, .planned, .ready, .running, .verifying, .committing,
                    .succeeded,
                ]
            )
            XCTAssertEqual(
                record.privacySafePlan,
                MediaJobPlanFacts(videoEncodeGenerations: 0, audioTracksEncoded: 0)
            )
        }
    }
}

private struct AdvancedSubtitleQueueFixture {
    let format: ExternalTextSubtitleFormat
    let codecID: String
    let contents: String
    let styleNeedle: String

    static let ass = AdvancedSubtitleQueueFixture(
        format: .ass,
        codecID: "S_TEXT/ASS",
        contents:
            "[Script Info]\nScriptType: v4.00+\nTitle: Preserve ASS Header\n"
            + "[V4+ Styles]\nFormat: Name, Fontname, Fontsize\n"
            + "Style: Default,Arial,48\n"
            + "[Events]\n"
            + "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
            + #"Dialogue: 0,0:00:00.00,0:00:00.25,Default,,0,0,0,,{\i1}Downloaded from YTS.MX{\i0}"#
            + "\n"
            + "Dialogue: 0,0:00:00.25,0:00:00.50,Default,,0,0,0,,  Hello styled  \n"
            + #"Dialogue: 0,0:00:00.50,0:00:00.75,Default,,0,0,0,,{\an8}HE11O"# + "\n",
        styleNeedle: "Style: Default,Arial,48"
    )

    static let ssa = AdvancedSubtitleQueueFixture(
        format: .ssa,
        codecID: "S_TEXT/SSA",
        contents:
            "[Script Info]\nScriptType: v4.00\nTitle: Preserve SSA Header\n"
            + "[V4 Styles]\n"
            + "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, "
            + "TertiaryColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, "
            + "Alignment, MarginL, MarginR, MarginV, AlphaLevel, Encoding\n"
            + "Style: Default,Arial,24,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,"
            + "-1,0,1,2,0,2,10,10,10,0,0\n"
            + "[Events]\n"
            + "Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
            + #"Dialogue: Marked=0,0:00:00.00,0:00:00.25,Default,,0,0,0,,{\i1}Downloaded from YTS.MX{\i0}"#
            + "\n"
            + "Dialogue: Marked=0,0:00:00.25,0:00:00.50,Default,,0,0,0,,  Hello styled  \n"
            + #"Dialogue: Marked=0,0:00:00.50,0:00:00.75,Default,,0,0,0,,{\an8}HE11O"# + "\n",
        styleNeedle: "Style: Default,Arial,24"
    )
}

private struct AdvancedSubtitleQueueEnvironmentReader:
    MediaQueueSchedulingEnvironmentReading
{
    func read() -> MediaQueueSchedulingEnvironment {
        MediaQueueSchedulingEnvironment(isOnBattery: false, thermalPressure: .nominal)
    }
}
