import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

@testable import MKVMagic

final class RealToolAppHistoryTests: XCTestCase {
    @MainActor
    func testMatchingPersistedBenchmarkReordersDefaultsWithoutRemovingAV1() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let ffmpeg = try XCTUnwrap(
            catalog.manifest.tools.first(where: { $0.name == .ffmpeg })
        )
        let metrics = EncodingBenchmarkMetrics(
            elapsedSeconds: 4,
            framesPerSecond: 18,
            sourceRealtimeFactor: 0.75,
            estimated1080pRealtimeFactor: 0.08,
            outputBytes: 250_000,
            outputBitrate: 666_667,
            averagePSNR: 40
        )
        let report = EncodingBenchmarkReport(
            environment: EncodingBenchmarkEnvironment(
                ffmpegSHA256: ffmpeg.sha256,
                architecture: catalog.architecture.rawValue,
                activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
            ),
            completedAt: Date(),
            sourceWidth: 640,
            sourceHeight: 360,
            sourceFrameRate: 24,
            sourceFrameCount: 72,
            attempts: [
                EncodingBenchmarkAttempt(
                    preset: .av1Quality,
                    encoder: "libsvtav1",
                    outcome: .completed,
                    metrics: metrics
                ),
                EncodingBenchmarkAttempt(
                    preset: .hevcCompatibility,
                    encoder: "hevc_videotoolbox",
                    outcome: .completed,
                    metrics: metrics
                ),
            ],
            recommendedPreset: .hevcCompatibility
        )
        let store = BenchmarkMemoryStore(report: report)
        let model = AppModel(encodingBenchmarkStoreFactory: { store })

        let capabilities = await model.probeEncodingCapabilities()

        XCTAssertEqual(capabilities.recommendedVideoPreset, .hevcCompatibility)
        XCTAssertEqual(capabilities.availableVideoPresets.first, .hevcCompatibility)
        XCTAssertTrue(capabilities.availableVideoPresets.contains(.av1Quality))
        let loadedReport = try await model.loadEncodingBenchmarkReport()
        XCTAssertEqual(loadedReport, report)
    }

    @MainActor
    func testExternalSubtitleWorkflowUsesOneVerifiedTransactionAndPortableIntent() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "mkv-magic-real-workflow-subtitle-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let rawAudio = fixtureRoot.appendingPathComponent("silence.pcm")
        let originalSubtitle = fixtureRoot.appendingPathComponent("Movie.fr.srt")
        let externalSubtitle = fixtureRoot.appendingPathComponent("Movie.en.srt")
        let source = fixtureRoot.appendingPathComponent("Movie.mkv")
        let output = fixtureRoot.appendingPathComponent("Movie — Prepared.mkv")
        let extractedOutputSubtitle = fixtureRoot.appendingPathComponent("Verified English.srt")
        try Data(repeating: 0, count: 192_000).write(to: rawAudio)
        try Data(
            "1\n00:00:00,000 --> 00:00:01,000\nBonjour\n".utf8
        ).write(to: originalSubtitle)
        try Data(
            ("1\n00:00:00,000 --> 00:00:01,000\nDownloaded from\nYTS.MX\n\n"
                + "2\n00:00:01,000 --> 00:00:02,000\n  Hello  \n").utf8
        ).write(to: externalSubtitle)
        let externalSubtitleDigest = SHA256.hash(data: try Data(contentsOf: externalSubtitle))

        let createResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-f", "srt", "-i", originalSubtitle.path,
                    "-map", "0:a", "-map", "1:s",
                    "-c:a", "aac", "-c:s", "srt",
                    "-metadata:s:a:0", "language=eng",
                    "-metadata:s:s:0", "language=fra",
                    "-metadata", "title=Remove Me",
                    source.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(createResult.exitCode, 0, createResult.standardError.text)
        let sourceDigest = SHA256.hash(data: try Data(contentsOf: source))

        let applicationSupport = fixtureRoot.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: false
        )
        let store = try AppHistoryLocation.makeStore(
            applicationSupportURL: applicationSupport
        )
        let model = AppModel(historyRecorderFactory: { store })
        await model.addFiles([source])
        let asset = try XCTUnwrap(model.assets.first)
        let subtitlePreview = try await model.previewSubtitleCleanup(at: externalSubtitle)
        let metadata = ExternalSubtitleTrackMetadata(
            language: "en",
            name: "English",
            isDefault: true
        )
        let workflow = SavedWorkflow(
            name: "Clean and add English subtitles",
            steps: [
                SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                SavedWorkflowStep(action: .cleanExternalSubtitleText),
                SavedWorkflowStep(action: .addExternalSubtitle),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        XCTAssertEqual(subtitlePreview.cleanup.changes.count, 2)
        let compiled = try SavedWorkflowCompiler().compile(
            workflow,
            for: asset,
            inputs: SavedWorkflowResolvedInputs(
                externalSubtitle: SavedWorkflowExternalSubtitleInput(
                    sourceURL: externalSubtitle,
                    metadata: metadata,
                    format: .subRip,
                    reviewedCleanupChangeCount: 2
                )
            )
        )

        XCTAssertEqual(
            compiled.plan.stages.map(\.mechanism),
            [.mkvMerge, .mkvPropEdit, .verify, .commit]
        )
        let outputAsset = try await model.runSavedWorkflow(
            compiled,
            externalSubtitlePayload: .reviewedCleanup(
                .subRip(subtitlePreview),
                restoringIDs: []
            ),
            in: asset,
            destinationURL: output
        )

        XCTAssertEqual(outputAsset.tracks.map(\.kind), [.audio, .subtitle])
        XCTAssertEqual(outputAsset.tracks.last?.title, "English")
        XCTAssertTrue(outputAsset.tracks.last?.isDefault == true)
        XCTAssertEqual(
            try TrackLanguageTag.canonical(try XCTUnwrap(outputAsset.tracks.last?.language)),
            "en"
        )
        XCTAssertNil(outputAsset.metadata["title"])
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)
        XCTAssertEqual(
            SHA256.hash(data: try Data(contentsOf: externalSubtitle)),
            externalSubtitleDigest
        )
        let addedTrackID = try XCTUnwrap(outputAsset.tracks.last?.id)
        let extractResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .mkvextract),
                arguments: [
                    "tracks", output.path,
                    "\(addedTrackID):\(extractedOutputSubtitle.path)",
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(extractResult.exitCode, 0, extractResult.standardError.text)
        let extractedText = try String(contentsOf: extractedOutputSubtitle, encoding: .utf8)
        XCTAssertTrue(extractedText.contains("Hello"))
        XCTAssertFalse(extractedText.contains("YTS.MX"))
        let portableJSON = try XCTUnwrap(
            String(data: JSONEncoder().encode(workflow), encoding: .utf8)
        )
        XCTAssertFalse(portableJSON.contains(externalSubtitle.path))
        XCTAssertFalse(portableJSON.contains("restoringIDs"))

        let records = try await store.load()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.workflowID, workflow.id)
        XCTAssertEqual(record.workflowName, workflow.name)
        XCTAssertEqual(record.inputDisplayNames, ["Movie.mkv", "Movie.en.srt"])
        XCTAssertEqual(record.outputDisplayName, "Movie — Prepared.mkv")
        XCTAssertEqual(
            record.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
    }

    @MainActor
    func testRealEditPersistsSanitizedVerifiedLifecycle() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "mkv-magic-real-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let rawAudio = fixtureRoot.appendingPathComponent("silence.pcm")
        let subtitle = fixtureRoot.appendingPathComponent("french.srt")
        let styledSubtitle = fixtureRoot.appendingPathComponent("english.ass")
        let source = fixtureRoot.appendingPathComponent("source.mkv")
        let output = fixtureRoot.appendingPathComponent("source — Edited.mkv")
        let trackOutput = fixtureRoot.appendingPathComponent("source — Track Edited.mkv")
        let workflowOutput = fixtureRoot.appendingPathComponent("source — Workflow.mkv")
        let removalOutput = fixtureRoot.appendingPathComponent("source — Track Removed.mkv")
        let muxOutput = fixtureRoot.appendingPathComponent("source — Subtitled.mkv")
        let styledMuxOutput = fixtureRoot.appendingPathComponent("source — Styled.mkv")
        let embeddedCleanupOutput = fixtureRoot.appendingPathComponent(
            "source — Embedded Cleaned.mkv")
        let chapterOutput = fixtureRoot.appendingPathComponent("source — Chapters.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)
        try Data("1\n00:00:00,000 --> 00:00:00,500\nBonjour\n".utf8).write(to: subtitle)
        try Data(
            ("[Script Info]\nScriptType: v4.00+\n"
                + "[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
                + "[Events]\n"
                + "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
                + "Dialogue: 0,0:00:00.00,0:00:00.50,Default,,0,0,0,,{\\an8}HE11O\n").utf8
        ).write(to: styledSubtitle)

        let createResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-f", "srt", "-i", subtitle.path,
                    "-map", "0:a", "-map", "0:a", "-map", "1:s",
                    "-c:a", "aac", "-c:s", "srt",
                    "-metadata:s:a:0", "language=eng",
                    "-metadata:s:a:1", "language=spa",
                    "-metadata:s:s:0", "language=fra",
                    "-metadata", "title=Original Title",
                    source.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(createResult.exitCode, 0, createResult.standardError.text)
        let sourceDigest = SHA256.hash(data: try Data(contentsOf: source))

        let applicationSupport = fixtureRoot.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: false
        )
        let store = try AppHistoryLocation.makeStore(
            applicationSupportURL: applicationSupport
        )
        let model = AppModel(historyRecorderFactory: { store })
        await model.addFiles([source])
        let asset = try XCTUnwrap(model.assets.first)

        let outputAsset = try await model.editSegmentTitle(
            in: asset,
            title: "Verified Title",
            destinationURL: output
        )

        XCTAssertEqual(outputAsset.metadata["title"], "Verified Title")
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)
        let track = try XCTUnwrap(outputAsset.tracks.first)
        let trackUID = try XCTUnwrap(track.uid)
        let trackEdit = TrackMetadataEdit(
            trackUID: trackUID,
            name: "English Commentary",
            language: "en",
            isDefault: track.isDefault,
            isForced: true,
            isEnabled: track.isEnabled,
            isCommentary: true,
            isHearingImpaired: track.isHearingImpaired,
            isVisualImpaired: track.isVisualImpaired,
            isOriginal: true,
            isTextDescription: track.isTextDescription
        )
        let trackOutputAsset = try await model.editTrackMetadata(
            in: outputAsset,
            edit: trackEdit,
            destinationURL: trackOutput
        )
        let editedTrack = try XCTUnwrap(trackOutputAsset.tracks.first)
        XCTAssertEqual(editedTrack.title, "English Commentary")
        XCTAssertEqual(try TrackEditorPresentation.normalizedEdit(for: editedTrack).language, "en")
        XCTAssertTrue(editedTrack.isForced)
        XCTAssertTrue(editedTrack.isCommentary)
        XCTAssertTrue(editedTrack.isOriginal)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)
        let savedWorkflow = SavedWorkflow(
            id: UUID(uuidString: "9B4FF1CE-EA70-46CD-8163-F3608F0BD65B")!,
            name: "Prepare for Jellyfin",
            steps: [
                SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                SavedWorkflowStep(action: .removeRedundantEnglishSDH),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        let compiledWorkflow = try SavedWorkflowCompiler().compile(
            savedWorkflow,
            for: trackOutputAsset
        )
        let workflowAsset = try await model.runSavedWorkflow(
            compiledWorkflow,
            in: trackOutputAsset,
            destinationURL: workflowOutput
        )
        XCTAssertNil(workflowAsset.metadata["title"])
        XCTAssertEqual(workflowAsset.tracks.count, 2)
        XCTAssertFalse(workflowAsset.tracks.contains { $0.kind == .subtitle })
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)

        let removedTrackUID = try XCTUnwrap(workflowAsset.tracks.last?.uid)
        let removalAsset = try await model.removeTracks(
            in: workflowAsset,
            removal: TrackRemoval(trackUIDs: [removedTrackUID]),
            destinationURL: removalOutput
        )
        XCTAssertEqual(removalAsset.tracks.count, 1)
        XCTAssertEqual(removalAsset.tracks.first?.uid, trackUID)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)

        let subtitlePreview = try await model.previewSubtitleCleanup(at: subtitle)
        let muxAsset = try await model.muxExternalSubtitle(
            in: removalAsset,
            subtitlePreview: subtitlePreview,
            metadata: ExternalSubtitleTrackMetadata(
                language: "fr",
                name: "French",
                isDefault: true
            ),
            destinationURL: muxOutput
        )
        XCTAssertEqual(muxAsset.tracks.count, 2)
        XCTAssertEqual(muxAsset.tracks.last?.kind, .subtitle)
        XCTAssertEqual(muxAsset.tracks.last?.title, "French")
        XCTAssertTrue(muxAsset.tracks.last?.isDefault == true)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)

        let styledPreview = try await model.previewAdvancedSubtitleCleanup(at: styledSubtitle)
        let styledMuxAsset = try await model.muxExternalSubtitle(
            in: muxAsset,
            subtitlePreview: styledPreview,
            metadata: ExternalSubtitleTrackMetadata(
                language: "en",
                name: "English Styled"
            ),
            destinationURL: styledMuxOutput
        )
        XCTAssertEqual(styledMuxAsset.tracks.count, 3)
        XCTAssertEqual(styledMuxAsset.tracks.last?.codecID, "S_TEXT/ASS")
        XCTAssertEqual(styledMuxAsset.tracks.last?.title, "English Styled")
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)
        let styledTrackUID = try XCTUnwrap(styledMuxAsset.tracks.last?.uid)
        let embeddedPreview = try await model.previewEmbeddedSubtitleCleanup(
            in: styledMuxAsset,
            trackUID: styledTrackUID
        )
        XCTAssertEqual(embeddedPreview.cleanupChangeCount, 1)
        let embeddedCleanedAsset = try await model.cleanEmbeddedSubtitle(
            preview: embeddedPreview,
            restoringIDs: [],
            destinationURL: embeddedCleanupOutput
        )
        XCTAssertEqual(
            embeddedCleanedAsset.tracks.compactMap(\.uid),
            styledMuxAsset.tracks.compactMap(\.uid)
        )
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)

        let chapterPreview = try await model.previewChapters(in: embeddedCleanedAsset)
        let chapterDocument = try MatroskaChapterDocument.fixedInterval(
            duration: try XCTUnwrap(embeddedCleanedAsset.duration),
            interval: MediaTime(nanoseconds: 500_000_000)
        )
        let chapteredAsset = try await model.editChapters(
            preview: chapterPreview,
            desired: chapterDocument,
            destinationURL: chapterOutput
        )
        XCTAssertGreaterThan(chapteredAsset.chapterEntryCount ?? 0, 0)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)

        let records = try await store.load()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 8)
        XCTAssertEqual(record.inputDisplayNames, ["source.mkv"])
        XCTAssertNil(record.inputs.first?.bookmarkID)
        XCTAssertEqual(record.outputDisplayName, "source — Edited.mkv")
        XCTAssertEqual(
            record.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let trackRecord = records[1]
        XCTAssertEqual(trackRecord.workflowName, "Edit track metadata")
        XCTAssertEqual(trackRecord.inputDisplayNames, ["source — Edited.mkv"])
        XCTAssertEqual(trackRecord.outputDisplayName, "source — Track Edited.mkv")
        XCTAssertEqual(
            trackRecord.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let workflowRecord = records[2]
        XCTAssertEqual(workflowRecord.workflowID, savedWorkflow.id)
        XCTAssertEqual(workflowRecord.workflowName, "Prepare for Jellyfin")
        XCTAssertEqual(workflowRecord.outputDisplayName, "source — Workflow.mkv")
        XCTAssertTrue(
            workflowRecord.events.contains {
                $0.state == .planned && $0.message?.contains("one verified output") == true
            }
        )
        XCTAssertEqual(
            workflowRecord.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let removalRecord = records[3]
        XCTAssertEqual(removalRecord.workflowName, "Remove tracks")
        XCTAssertEqual(removalRecord.inputDisplayNames, ["source — Workflow.mkv"])
        XCTAssertEqual(removalRecord.outputDisplayName, "source — Track Removed.mkv")
        XCTAssertTrue(
            removalRecord.events.contains {
                $0.state == .planned && $0.message?.contains("mkvmerge") == true
            })
        XCTAssertEqual(
            removalRecord.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let muxRecord = records[4]
        XCTAssertEqual(muxRecord.workflowName, "Add external SRT subtitle")
        XCTAssertEqual(
            muxRecord.inputDisplayNames,
            ["source — Track Removed.mkv", "french.srt"]
        )
        XCTAssertEqual(muxRecord.outputDisplayName, "source — Subtitled.mkv")
        XCTAssertTrue(
            muxRecord.events.contains {
                $0.state == .planned && $0.message?.contains("Zero encodes") == true
            })
        XCTAssertEqual(
            muxRecord.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let styledMuxRecord = records[5]
        XCTAssertEqual(styledMuxRecord.workflowName, "Add external ASS subtitle")
        XCTAssertEqual(
            styledMuxRecord.inputDisplayNames,
            ["source — Subtitled.mkv", "english.ass"]
        )
        XCTAssertEqual(styledMuxRecord.outputDisplayName, "source — Styled.mkv")
        XCTAssertEqual(
            styledMuxRecord.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let embeddedCleanupRecord = records[6]
        XCTAssertEqual(embeddedCleanupRecord.workflowName, "Clean embedded ASS subtitle")
        XCTAssertEqual(embeddedCleanupRecord.inputDisplayNames, ["source — Styled.mkv"])
        XCTAssertEqual(
            embeddedCleanupRecord.outputDisplayName,
            "source — Embedded Cleaned.mkv"
        )
        XCTAssertTrue(
            embeddedCleanupRecord.events.contains {
                $0.state == .planned
                    && $0.message?.contains("original position") == true
            }
        )
        XCTAssertEqual(
            embeddedCleanupRecord.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let chapterRecord = records[7]
        XCTAssertEqual(chapterRecord.workflowName, "Edit Matroska chapters")
        XCTAssertEqual(chapterRecord.inputDisplayNames, ["source — Embedded Cleaned.mkv"])
        XCTAssertEqual(chapterRecord.outputDisplayName, "source — Chapters.mkv")
        XCTAssertTrue(
            chapterRecord.events.contains {
                $0.state == .planned
                    && $0.message?.contains("nested entries") == true
            }
        )
        XCTAssertEqual(
            chapterRecord.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )

        let historyURL =
            applicationSupport
            .appendingPathComponent("com.dustwave.mkvmagic", isDirectory: true)
            .appendingPathComponent("job-history.json")
        let historyText = String(decoding: try Data(contentsOf: historyURL), as: UTF8.self)
        XCTAssertFalse(historyText.contains(fixtureRoot.path))
        XCTAssertFalse(historyText.contains(rawAudio.path))
    }

    @MainActor
    func testRealLosslessJoinUsesNativeReviewAndRecordsEveryInput() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-app-join-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let rawOne = fixtureRoot.appendingPathComponent("one.pcm")
        let rawTwo = fixtureRoot.appendingPathComponent("two.pcm")
        let sourceOne = fixtureRoot.appendingPathComponent("Part One.mkv")
        let sourceTwo = fixtureRoot.appendingPathComponent("Part Two.mkv")
        let destination = fixtureRoot.appendingPathComponent("Joined.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawOne)
        try Data(repeating: 1, count: 96_000).write(to: rawTwo)
        for (raw, output) in [(rawOne, sourceOne), (rawTwo, sourceTwo)] {
            let result = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .ffmpeg),
                    arguments: [
                        "-hide_banner", "-loglevel", "error",
                        "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", raw.path,
                        "-c:a", "aac",
                        "-metadata", "title=Native Join Fixture",
                        "-metadata:s:a:0", "language=eng",
                        "-metadata:s:a:0", "title=Main Audio",
                        output.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        }
        let sourceURLs = [sourceOne, sourceTwo]
        let sourceDigests = try sourceURLs.map {
            SHA256.hash(data: try Data(contentsOf: $0))
        }

        let applicationSupport = fixtureRoot.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: false
        )
        let store = try AppHistoryLocation.makeStore(
            applicationSupportURL: applicationSupport
        )
        let model = AppModel(historyRecorderFactory: { store })
        await model.addFiles(sourceURLs)
        XCTAssertEqual(model.assets.count, 2)
        let options = try await model.loadLosslessJoinSourceOptions(model.assets)
        let review = LosslessJoinReviewBuilder.make(
            selections: options.map {
                LosslessJoinSourceSelection(
                    option: $0,
                    editionID: $0.editions.count == 1 ? $0.editions[0].id : nil
                )
            }
        )
        let candidate = try XCTUnwrap(review.candidate)
        let preview = try await model.previewLosslessJoin(candidate)
        let output = try await model.executeLosslessJoin(
            preview: preview,
            destinationURL: destination
        )

        XCTAssertEqual(output.sourceURL, destination)
        XCTAssertEqual(output.tracks.count, 1)
        XCTAssertEqual(output.metadata["title"], "Native Join Fixture")
        XCTAssertEqual(output.chapterEntryCount, 2)
        XCTAssertEqual(
            try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
            sourceDigests
        )
        let records = try await store.load()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.workflowName, "Join MKV files losslessly")
        XCTAssertEqual(record.inputDisplayNames, ["Part One.mkv", "Part Two.mkv"])
        XCTAssertEqual(
            record.privacySafePlan,
            MediaJobPlanFacts(videoEncodeGenerations: 0, audioTracksEncoded: 0)
        )
        XCTAssertEqual(record.inputs.compactMap(\.privacySafeFacts).count, 2)
        XCTAssertTrue(
            record.inputs.compactMap(\.privacySafeFacts).allSatisfy {
                $0.container == .matroska && $0.codecs == [.aac]
            })
        XCTAssertEqual(record.outputDisplayName, "Joined.mkv")
        XCTAssertEqual(
            record.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let serialized = record.events.compactMap(\.message).joined(separator: " ")
        XCTAssertFalse(serialized.contains(fixtureRoot.path))
        XCTAssertTrue(serialized.contains("Zero encodes"))

        let supportURL = fixtureRoot.appendingPathComponent("support.json")
        try await model.exportPrivacySafeSupportReport(records: records, to: supportURL)
        let supportData = try Data(contentsOf: supportURL)
        let support = try JSONDecoder().decode(PrivacySafeSupportReport.self, from: supportData)
        XCTAssertEqual(support.history.jobs.first?.workflow, .losslessJoin)
        let supportText = try XCTUnwrap(String(data: supportData, encoding: .utf8))
        XCTAssertFalse(supportText.contains("Part One.mkv"))
        XCTAssertFalse(supportText.contains("Part Two.mkv"))
        XCTAssertFalse(supportText.contains(fixtureRoot.path))
    }

    @MainActor
    func testRealCommonFormatJoinNormalizesOnceAndRecordsOneVerifiedJob() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-app-common-join-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let sourceOne = fixtureRoot.appendingPathComponent("Part 48k.mkv")
        let sourceTwo = fixtureRoot.appendingPathComponent("Part 44k.mkv")
        for (index, fixture) in [
            (sourceOne, 48_000, UInt8(0)),
            (sourceTwo, 44_100, UInt8(1)),
        ].enumerated() {
            let raw = fixtureRoot.appendingPathComponent("audio-\(index).pcm")
            try Data(repeating: fixture.2, count: fixture.1 * 2).write(to: raw)
            let result = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .ffmpeg),
                    arguments: [
                        "-hide_banner", "-nostdin", "-loglevel", "error",
                        "-f", "s16le", "-ar", String(fixture.1), "-ac", "1",
                        "-i", raw.path,
                        "-c:a", "aac",
                        "-metadata", "title=Common Join Fixture",
                        "-metadata:s:a:0", "language=eng",
                        "-metadata:s:a:0", "title=Main Audio",
                        fixture.0.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(result.exitCode, 0, result.standardError.text)
            let clearTags = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .mkvpropedit),
                    arguments: [fixture.0.path, "--tags", "all:"],
                    timeout: 60
                )
            )
            XCTAssertEqual(clearTags.exitCode, 0, clearTags.standardError.text)
        }
        let sourceURLs = [sourceOne, sourceTwo]
        let sourceDigests = try sourceURLs.map {
            SHA256.hash(data: try Data(contentsOf: $0))
        }
        let destination = fixtureRoot.appendingPathComponent("Joined Normalized.mkv")
        let applicationSupport = fixtureRoot.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: false
        )
        let store = try AppHistoryLocation.makeStore(
            applicationSupportURL: applicationSupport
        )
        let model = AppModel(historyRecorderFactory: { store })
        await model.addFiles(sourceURLs)
        XCTAssertEqual(model.assets.count, 2)
        let options = try await model.loadLosslessJoinSourceOptions(model.assets)
        let capabilities = await model.probeEncodingCapabilities()
        XCTAssertEqual(capabilities.aac, .verified)
        let review = LosslessJoinReviewBuilder.make(
            selections: options.map {
                LosslessJoinSourceSelection(
                    option: $0,
                    editionID: $0.editions.count == 1 ? $0.editions[0].id : nil
                )
            },
            encodingCapabilities: capabilities
        )
        let candidate = try XCTUnwrap(
            review.commonFormatCandidate,
            "\(review.blockerSummaries); \(review.normalizationSummaries)"
        )
        let resolved = try CommonFormatJoinChoicePolicy.resolveRecommended(for: candidate)
        let preview = try await model.previewCommonFormatJoin(
            candidate,
            resolvedPlan: resolved
        )
        var stages = [CommonFormatJoinExecutionStage]()
        let output = try await model.executeCommonFormatJoin(
            preview: preview,
            destinationURL: destination,
            onStage: { stages.append($0) }
        )

        XCTAssertEqual(stages, [.normalizing, .assembling, .verifying, .committing])
        XCTAssertEqual(output.sourceURL, destination)
        XCTAssertEqual(output.tracks.count, 1)
        XCTAssertEqual(output.tracks[0].kind, .audio)
        XCTAssertEqual(output.tracks[0].codec, "aac")
        XCTAssertEqual(output.tracks[0].sampleRate, 48_000)
        XCTAssertEqual(output.chapterEntryCount, 2)
        XCTAssertEqual(
            try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
            sourceDigests
        )
        let records = try await store.load()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.workflowName, "Join MKV files with one normalization pass")
        XCTAssertEqual(record.privacySafePlan?.videoEncodeGenerations, 0)
        XCTAssertEqual(record.privacySafePlan?.audioTracksEncoded, 1)
        XCTAssertEqual(record.inputs.compactMap(\.privacySafeFacts).count, 2)
        XCTAssertEqual(
            record.inputDisplayNames,
            candidate.sources.map { $0.sourceURL.lastPathComponent }
        )
        XCTAssertEqual(record.outputDisplayName, "Joined Normalized.mkv")
        XCTAssertEqual(
            record.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let serialized = record.events.compactMap(\.message).joined(separator: " ")
        XCTAssertFalse(serialized.contains(fixtureRoot.path))
        XCTAssertTrue(serialized.contains("audio lane(s) once"))
    }

    @MainActor
    func testRealManualMappingJoinsAmbiguousTracksExactlyOnce() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-manual-map-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let sourceURLs = [
            fixtureRoot.appendingPathComponent("Ambiguous One.mkv"),
            fixtureRoot.appendingPathComponent("Ambiguous Two.mkv"),
        ]
        for (index, sourceURL) in sourceURLs.enumerated() {
            let raw = fixtureRoot.appendingPathComponent("audio-\(index).pcm")
            try Data(repeating: UInt8(index), count: 96_000).write(to: raw)
            let result = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .ffmpeg),
                    arguments: [
                        "-hide_banner", "-nostdin", "-loglevel", "error",
                        "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", raw.path,
                        "-map", "0:a", "-map", "0:a", "-c:a", "aac",
                        "-metadata", "title=Manual Mapping Fixture",
                        "-metadata:s:a:0", "language=eng",
                        "-metadata:s:a:1", "language=eng",
                        "-disposition:a:0", "default",
                        "-disposition:a:1", "0",
                        sourceURL.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        }
        let sourceDigests = try sourceURLs.map {
            SHA256.hash(data: try Data(contentsOf: $0))
        }
        let destination = fixtureRoot.appendingPathComponent("Mapped Join.mkv")
        let applicationSupport = fixtureRoot.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: false
        )
        let store = try AppHistoryLocation.makeStore(
            applicationSupportURL: applicationSupport
        )
        let model = AppModel(historyRecorderFactory: { store })
        await model.addFiles(sourceURLs)
        let options = try await model.loadLosslessJoinSourceOptions(model.assets)
        let selections = options.map {
            LosslessJoinSourceSelection(
                option: $0,
                editionID: $0.editions.count == 1 ? $0.editions[0].id : nil
            )
        }
        let automatic = LosslessJoinReviewBuilder.make(selections: selections)
        XCTAssertNil(automatic.candidate)
        XCTAssertEqual(automatic.unresolvedAmbiguities.count, 1)
        let ambiguity = try XCTUnwrap(automatic.unresolvedAmbiguities.first)
        XCTAssertEqual(ambiguity.trackIDs.count, 2)
        XCTAssertEqual(ambiguity.candidateLaneIndices.count, 2)
        var mapping = try XCTUnwrap(automatic.reviewedMapping)
        for (trackID, laneIndex) in zip(
            ambiguity.trackIDs,
            ambiguity.candidateLaneIndices
        ) {
            mapping = try JoinTrackMappingEditor().assigning(
                trackID: trackID,
                fromSource: ambiguity.sourceIndex,
                toLane: laneIndex,
                sources: selections.map(\.option.source),
                mapping: mapping
            )
        }
        let reviewed = LosslessJoinReviewBuilder.make(
            selections: selections,
            manualMapping: LosslessJoinManualMapping(
                sourceIDs: selections.map(\.option.source.id),
                mapping: mapping
            )
        )
        let candidate = try XCTUnwrap(
            reviewed.candidate,
            "\(reviewed.blockerSummaries); \(reviewed.issueSummaries)"
        )
        let preview = try await model.previewLosslessJoin(candidate)
        let output = try await model.executeLosslessJoin(
            preview: preview,
            destinationURL: destination
        )

        XCTAssertEqual(output.tracks.filter { $0.kind == .audio }.count, 2)
        XCTAssertEqual(output.chapterEntryCount, 2)
        XCTAssertEqual(
            try sourceURLs.map { SHA256.hash(data: try Data(contentsOf: $0)) },
            sourceDigests
        )
        let records = try await store.load()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.workflowName, "Join MKV files losslessly")
        XCTAssertEqual(record.inputDisplayNames, ["Ambiguous One.mkv", "Ambiguous Two.mkv"])
        XCTAssertEqual(record.outputDisplayName, "Mapped Join.mkv")
        XCTAssertEqual(record.events.last?.state, .succeeded)
    }

    @MainActor
    func testRealFastTrimUsesReviewedKeyframesAndRecordsVerifiedLifecycle() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-app-trim-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let rawURL = fixtureRoot.appendingPathComponent("frames.yuv")
        let sourceURL = fixtureRoot.appendingPathComponent("Feature.mkv")
        let destinationURL = fixtureRoot.appendingPathComponent("Feature — Trimmed.mkv")
        let chapterURL = fixtureRoot.appendingPathComponent("chapters.xml")
        let width = 64
        let height = 48
        let frameCount = 100
        try Data(repeating: 32, count: width * height * 3 / 2 * frameCount).write(to: rawURL)

        let encode = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-nostdin", "-loglevel", "error",
                    "-f", "rawvideo", "-pixel_format", "yuv420p",
                    "-video_size", "\(width)x\(height)", "-framerate", "10",
                    "-i", rawURL.path,
                    "-frames:v", "\(frameCount)",
                    "-c:v", "mpeg4", "-g", "20", "-bf", "0", "-q:v", "5",
                    "-metadata", "title=App Trim Fixture",
                    sourceURL.path,
                ],
                timeout: 120
            )
        )
        XCTAssertEqual(encode.exitCode, 0, encode.standardError.text)
        let duration = MediaTime(nanoseconds: 10_000_000_000)
        let chapters = MatroskaChapterDocument(editions: [
            MatroskaChapterEdition(
                isDefault: true,
                chapters: [
                    MatroskaChapterAtom(
                        start: .zero,
                        end: duration,
                        displays: [ChapterDisplay(title: "Feature")],
                        children: [
                            MatroskaChapterAtom(
                                start: .zero,
                                end: MediaTime(nanoseconds: 5_000_000_000),
                                displays: [ChapterDisplay(title: "First Half")]
                            ),
                            MatroskaChapterAtom(
                                start: MediaTime(nanoseconds: 5_000_000_000),
                                end: duration,
                                displays: [ChapterDisplay(title: "Second Half")]
                            ),
                        ]
                    )
                ]
            )
        ])
        try MatroskaChapterXMLCodec().serialize(chapters).write(to: chapterURL)
        let setChapters = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .mkvpropedit),
                arguments: [
                    "--abort-on-warnings", sourceURL.path,
                    "--chapters", chapterURL.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(setChapters.exitCode, 0, setChapters.standardError.text)
        let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))

        let applicationSupport = fixtureRoot.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: false
        )
        let store = try AppHistoryLocation.makeStore(applicationSupportURL: applicationSupport)
        let model = AppModel(historyRecorderFactory: { store })
        await model.addFiles([sourceURL])
        let source = try XCTUnwrap(model.assets.first)
        let requested = MediaTrimRange(
            start: MediaTime(nanoseconds: 3_000_000_000),
            end: MediaTime(nanoseconds: 7_000_000_000)
        )
        let preview = try await model.previewTrim(
            in: source,
            request: TrimReviewRequest(mode: .fast, range: requested, exactChoice: nil),
            capabilities: .unavailable
        )
        XCTAssertEqual(preview.requestedRange, requested)
        XCTAssertEqual(
            preview.outputRange,
            MediaTrimRange(
                start: MediaTime(nanoseconds: 4_000_000_000),
                end: MediaTime(nanoseconds: 8_000_000_000)
            )
        )
        XCTAssertEqual(preview.videoEncodeCount, 0)

        let output = try await model.executeTrim(
            preview: preview,
            destinationURL: destinationURL
        )
        XCTAssertEqual(output.sourceURL, destinationURL)
        XCTAssertEqual(output.chapterEntryCount, 1)
        XCTAssertEqual(
            SHA256.hash(data: try Data(contentsOf: sourceURL)),
            sourceDigest
        )

        let records = try await store.load()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.workflowName, "Fast Trim")
        XCTAssertEqual(
            record.privacySafePlan,
            MediaJobPlanFacts(videoEncodeGenerations: 0, audioTracksEncoded: 0)
        )
        XCTAssertEqual(record.inputs.first?.privacySafeFacts?.container, .matroska)
        XCTAssertEqual(record.inputDisplayNames, ["Feature.mkv"])
        XCTAssertEqual(record.outputDisplayName, "Feature — Trimmed.mkv")
        XCTAssertEqual(
            record.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let serialized = record.events.compactMap(\.message).joined(separator: " ")
        XCTAssertTrue(serialized.contains("Zero encodes"))
        XCTAssertTrue(serialized.contains("00:00:04.000–00:00:08.000"))
        XCTAssertFalse(serialized.contains(fixtureRoot.path))
    }
}

private actor BenchmarkMemoryStore: EncodingBenchmarkPersisting {
    private var report: EncodingBenchmarkReport?

    init(report: EncodingBenchmarkReport?) {
        self.report = report
    }

    func load() async throws -> EncodingBenchmarkReport? { report }

    func save(_ report: EncodingBenchmarkReport) async throws {
        self.report = report
    }
}

extension MediaJobRecord {
    fileprivate var inputDisplayNames: [String] {
        inputs.map(\.displayName)
    }
}
