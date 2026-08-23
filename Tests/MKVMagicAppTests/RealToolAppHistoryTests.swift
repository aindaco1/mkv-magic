import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

@testable import MKVMagic

final class RealToolAppHistoryTests: XCTestCase {
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
                SavedWorkflowStep(action: .englishLibraryCleanup),
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
        XCTAssertEqual(record.outputDisplayName, "Joined.mkv")
        XCTAssertEqual(
            record.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let serialized = record.events.compactMap(\.message).joined(separator: " ")
        XCTAssertFalse(serialized.contains(fixtureRoot.path))
        XCTAssertTrue(serialized.contains("Zero encodes"))
    }
}

extension MediaJobRecord {
    fileprivate var inputDisplayNames: [String] {
        inputs.map(\.displayName)
    }
}
