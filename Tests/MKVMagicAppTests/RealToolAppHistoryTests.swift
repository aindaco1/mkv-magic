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
        let source = fixtureRoot.appendingPathComponent("source.mkv")
        let output = fixtureRoot.appendingPathComponent("source — Edited.mkv")
        let trackOutput = fixtureRoot.appendingPathComponent("source — Track Edited.mkv")
        let workflowOutput = fixtureRoot.appendingPathComponent("source — Workflow.mkv")
        let removalOutput = fixtureRoot.appendingPathComponent("source — Track Removed.mkv")
        let muxOutput = fixtureRoot.appendingPathComponent("source — Subtitled.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)
        try Data("1\n00:00:00,000 --> 00:00:00,500\nBonjour\n".utf8).write(to: subtitle)

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

        let records = try await store.load()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 5)
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

        let historyURL =
            applicationSupport
            .appendingPathComponent("com.dustwave.mkvmagic", isDirectory: true)
            .appendingPathComponent("job-history.json")
        let historyText = String(decoding: try Data(contentsOf: historyURL), as: UTF8.self)
        XCTAssertFalse(historyText.contains(fixtureRoot.path))
        XCTAssertFalse(historyText.contains(rawAudio.path))
    }
}

extension MediaJobRecord {
    fileprivate var inputDisplayNames: [String] {
        inputs.map(\.displayName)
    }
}
