import CryptoKit
import Foundation
import MKVMagicCore
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
        let source = fixtureRoot.appendingPathComponent("source.mkv")
        let output = fixtureRoot.appendingPathComponent("source — Edited.mkv")
        let trackOutput = fixtureRoot.appendingPathComponent("source — Track Edited.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)

        let createResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-c:a", "aac",
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
        XCTAssertEqual(editedTrack.language, "en")
        XCTAssertTrue(editedTrack.isForced)
        XCTAssertTrue(editedTrack.isCommentary)
        XCTAssertTrue(editedTrack.isOriginal)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), sourceDigest)

        let records = try await store.load()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 2)
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
