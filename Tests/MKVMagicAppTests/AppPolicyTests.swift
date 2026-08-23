import AppKit
import CryptoKit
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

@testable import MKVMagic

@MainActor
private final class FakeUpdateChecker: UpdateChecking {
    private(set) var checks = 0

    func checkForUpdates() {
        checks += 1
    }
}

final class AppPolicyTests: XCTestCase {
    @MainActor
    func testAppDelegateAcceptsNarrowUpdateAdapter() {
        let checker = FakeUpdateChecker()
        _ = AppDelegate(updateController: checker)
        XCTAssertEqual(checker.checks, 0)
    }

    func testBundledToolVerificationUsesOnlyVersionArguments() {
        XCTAssertEqual(
            BundledToolVerification.arguments(for: .ffmpeg),
            ["-hide_banner", "-version"]
        )
        XCTAssertEqual(BundledToolVerification.arguments(for: .mkvmerge), ["--version"])
    }

    func testFirstInspectedAssetIsSelectedAutomatically() {
        XCTAssertEqual(AssetSelectionPolicy.rowToSelect(currentRow: -1, assetCount: 1), 0)
        XCTAssertNil(AssetSelectionPolicy.rowToSelect(currentRow: 0, assetCount: 2))
        XCTAssertNil(AssetSelectionPolicy.rowToSelect(currentRow: -1, assetCount: 0))
    }

    func testEditedOutputNamePreservesContainerExtension() {
        XCTAssertEqual(
            OutputNamingPolicy.suggestedFilename(
                for: URL(fileURLWithPath: "/Media/Movie.mkv")),
            "Movie — Edited.mkv"
        )
        XCTAssertEqual(
            OutputNamingPolicy.suggestedFilename(
                for: URL(fileURLWithPath: "/Media/Untitled")),
            "Untitled — Edited.mkv"
        )
    }

    func testCleanedSubtitleOutputNameUsesSRT() {
        XCTAssertEqual(
            OutputNamingPolicy.cleanedSubtitleFilename(
                for: URL(fileURLWithPath: "/Media/Movie.en.SRT")),
            "Movie.en — Clean.srt"
        )
    }

    func testInspectorSeparatesAttachmentsAndAvoidsDecodedAudioBitDepth() {
        let audio = MediaTrack(id: 0, kind: .audio, codec: "aac", bitDepth: 32)
        let attachment = MediaTrack(id: 1, kind: .attachment, codec: "unknown")
        let video = MediaTrack(id: 2, kind: .video, codec: "av1", bitDepth: 10)

        XCTAssertEqual(
            InspectorPresentationPolicy.playableTracks(in: [audio, attachment, video]),
            [audio, video]
        )
        XCTAssertNil(InspectorPresentationPolicy.displayedBitDepth(for: audio))
        XCTAssertEqual(InspectorPresentationPolicy.displayedBitDepth(for: video), 10)
    }

    func testTrackEditorUsesHumanReadableOneBasedTrackLabels() {
        let track = MediaTrack(
            id: 0,
            kind: .audio,
            codec: "aac",
            uid: 42,
            language: "en",
            title: "Main Audio"
        )
        XCTAssertEqual(
            TrackEditorPresentation.label(track),
            "#1 Audio — AAC — en — Main Audio"
        )
    }

    func testTrackEditorTreatsLegacyAndCanonicalLanguageCodesAsEquivalent() throws {
        let track = MediaTrack(
            id: 0,
            kind: .audio,
            codec: "aac",
            uid: 42,
            language: "eng",
            title: "Main Audio"
        )

        XCTAssertEqual(try TrackEditorPresentation.normalizedEdit(for: track).language, "en")
    }

    func testTrackRemovalPresentationUsesStableUIDsAndKeepsOneTrack() throws {
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 42)
        let audio = MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 84)

        XCTAssertTrue(TrackRemovalPresentation.canOfferRemoval(for: [video, audio]))
        XCTAssertEqual(
            try TrackRemovalPresentation.removal(
                tracks: [video, audio],
                selectedIndexes: [1]
            ).trackUIDs,
            [84]
        )
        XCTAssertThrowsError(
            try TrackRemovalPresentation.removal(
                tracks: [video, audio],
                selectedIndexes: [0, 1]
            )
        ) { error in
            XCTAssertEqual(error as? TrackRemovalPresentationError, .allTracksRemoved)
        }
        XCTAssertFalse(TrackRemovalPresentation.canOfferRemoval(for: [video]))
    }

    func testHistoryLocationCreatesPrivateAppSupportDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-history-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try AppHistoryLocation.makeStore(applicationSupportURL: root)
        try await store.save([])

        let appDirectory = root.appendingPathComponent("com.dustwave.mkvmagic")
        let attributes = try FileManager.default.attributesOfItem(atPath: appDirectory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appDirectory.appendingPathComponent("job-history.json").path
            )
        )
    }

    func testWorkflowLocationSharesPrivateAppSupportDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-workflows-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try AppHistoryLocation.makeWorkflowStore(applicationSupportURL: root)
        try await store.save([WorkflowEditorPolicy.newWorkflow()])

        let appDirectory = root.appendingPathComponent("com.dustwave.mkvmagic")
        let attributes = try FileManager.default.attributesOfItem(atPath: appDirectory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appDirectory.appendingPathComponent("workflows.json").path
            )
        )
    }

    func testHistoryLocationRejectsSymlinkedAppDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-history-\(UUID().uuidString)",
            isDirectory: true
        )
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-history-target-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("com.dustwave.mkvmagic"),
            withDestinationURL: target
        )

        XCTAssertThrowsError(
            try AppHistoryLocation.makeStore(applicationSupportURL: root)
        ) {
            XCTAssertEqual(
                $0 as? AppHistoryLocationError,
                .unsafeApplicationSupport
            )
        }
    }

    func testHistoryPresentationSortsNewestAndShowsSanitizedLifecycle() throws {
        let older = try makeHistoryRecord(
            id: UUID(uuidString: "1A0DBEF0-4AF6-4B92-B813-D683D26CB18F")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = try makeHistoryRecord(
            id: UUID(uuidString: "A3E910BC-636E-45EF-BC1A-D865966E2A37")!,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(HistoryPresentation.sorted([older, newer]).map(\.id), [newer.id, older.id])
        XCTAssertEqual(
            HistoryPresentation.columnValue(identifier: "state", record: newer),
            "Succeeded"
        )
        let detail = HistoryPresentation.detail(for: newer)
        XCTAssertTrue(detail.contains("Input: Movie.mkv"))
        XCTAssertTrue(detail.contains("Output: Movie — Edited.mkv"))
        XCTAssertTrue(detail.contains("Verified output committed and reopened."))
        XCTAssertFalse(detail.contains(newer.id.uuidString))
    }

    @MainActor
    func testHistoryWindowUsesCompactNativeLayout() throws {
        let controller = HistoryWindowController(records: [])
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(window.contentViewController is HistoryViewController)
        XCTAssertEqual(contentView.frame.size.width, 760, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 560, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 620)
        XCTAssertEqual(window.minSize.height, 420)
    }

    @MainActor
    func testTrackEditorWindowUsesCompactNativeLayout() throws {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Movie.mkv"),
            container: "matroska",
            tracks: [MediaTrack(id: 0, kind: .audio, codec: "aac", uid: 42)]
        )
        let controller = TrackEditorWindowController(asset: asset)
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(window.contentViewController is TrackEditorViewController)
        XCTAssertEqual(contentView.frame.size.width, 560, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 510, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 520)
        XCTAssertEqual(window.minSize.height, 480)
    }

    @MainActor
    func testTrackRemovalWindowUsesCompactNativeLayout() throws {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Movie.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1", uid: 42),
                MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 84),
            ]
        )
        let controller = TrackRemovalWindowController(asset: asset)
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(window.contentViewController is TrackRemovalViewController)
        XCTAssertEqual(contentView.frame.size.width, 620, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 480, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 540)
        XCTAssertEqual(window.minSize.height, 420)
    }

    @MainActor
    func testWorkflowWindowUsesCompactNativeLayout() throws {
        let controller = WorkflowWindowController(
            workflows: [WorkflowEditorPolicy.newWorkflow()],
            hasSelectedAsset: true,
            onSave: { _ in },
            onUse: { _ in }
        )
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(window.contentViewController is WorkflowLibraryViewController)
        XCTAssertEqual(contentView.frame.size.width, 780, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 560, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 680)
        XCTAssertEqual(window.minSize.height, 480)
    }

    func testWorkflowEditorDuplicatesPortableIntentWithFreshIdentifiers() {
        let original = WorkflowEditorPolicy.newWorkflow()
        let copy = WorkflowEditorPolicy.duplicate(original)

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.name, "New Workflow Copy")
        XCTAssertEqual(copy.steps.map(\.action), original.steps.map(\.action))
        XCTAssertEqual(copy.steps.map(\.isEnabled), original.steps.map(\.isEnabled))
        XCTAssertTrue(Set(copy.steps.map(\.id)).isDisjoint(with: original.steps.map(\.id)))
        XCTAssertEqual(
            WorkflowEditorPolicy.exportFilename(
                for: SavedWorkflow(name: "TV/Film: Clean", steps: original.steps)),
            "TV-Film- Clean.mkvmagic-workflow"
        )
    }

    func testSubtitleCleanupPresentationKeepsOneCueAndFormatsTiming() {
        let advertisement = SubRipCue(
            id: 0,
            start: SubRipTimestamp(milliseconds: 90_061_007),
            end: SubRipTimestamp(milliseconds: 90_062_008),
            lines: ["Downloaded from", "YTS.MX"]
        )
        let document = SubRipDocument(cues: [advertisement])
        let cleanup = SubtitleCleanupPolicy().preview(document)
        let preview = SubtitleCleanupFilePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.srt"),
            sourceSHA256: Data(SHA256.hash(data: Data())),
            encoding: .utf8,
            diagnostics: [],
            cleanup: cleanup,
            normalizationNeeded: false
        )

        XCTAssertFalse(
            SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: [advertisement.id]
            )
        )
        XCTAssertTrue(
            SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: []
            )
        )
        XCTAssertEqual(
            SubtitleCleanupPresentation.time(advertisement.start),
            "25:01:01,007"
        )
    }

    @MainActor
    func testSubtitleCleanupWindowUsesCompactNativeLayout() throws {
        let document = SubRipDocument(
            cues: [
                SubRipCue(
                    id: 0,
                    start: SubRipTimestamp(milliseconds: 0),
                    end: SubRipTimestamp(milliseconds: 1_000),
                    lines: [" Text "]
                )
            ]
        )
        let controller = SubtitleCleanupWindowController(
            preview: SubtitleCleanupFilePreview(
                sourceURL: URL(fileURLWithPath: "/Media/Movie.srt"),
                sourceSHA256: Data(SHA256.hash(data: Data())),
                encoding: .utf8,
                diagnostics: [],
                cleanup: SubtitleCleanupPolicy().preview(document),
                normalizationNeeded: true
            )
        )
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(window.contentViewController is SubtitleCleanupViewController)
        XCTAssertEqual(contentView.frame.size.width, 740, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 560, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 640)
        XCTAssertEqual(window.minSize.height, 480)
    }

    @MainActor
    func testSubtitleCleanupPersistsSanitizedVerifiedLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-subtitle-history-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.en.srt")
        let output = root.appendingPathComponent("Movie.en — Clean.srt")
        let sourceData = Data(
            ("1\r\n00:00:00,000 --> 00:00:01,000\r\nDownloaded from\r\nYTS.MX\r\n\r\n"
                + "2\r\n00:00:01,000 --> 00:00:02,000\r\n  Dialogue  \r\n").utf8
        )
        try sourceData.write(to: source)
        let applicationSupport = root.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: false
        )
        let store = try AppHistoryLocation.makeStore(applicationSupportURL: applicationSupport)
        let model = AppModel(historyRecorderFactory: { store })

        let preview = try await model.previewSubtitleCleanup(at: source)
        let result = try await model.cleanSubtitle(
            preview: preview,
            restoringCueIDs: [],
            destinationURL: output
        )

        XCTAssertEqual(result.removedCueCount, 1)
        XCTAssertEqual(result.changedCueCount, 1)
        XCTAssertEqual(try Data(contentsOf: source), sourceData)
        XCTAssertEqual(
            String(decoding: try Data(contentsOf: output), as: UTF8.self),
            "1\n00:00:01,000 --> 00:00:02,000\nDialogue\n"
        )
        XCTAssertEqual(
            model.state,
            .completed("Created Movie.en — Clean.srt; original unchanged.")
        )
        let records = try await store.load()
        let record = try XCTUnwrap(records.only)
        XCTAssertEqual(record.workflowName, "Clean SRT subtitle")
        XCTAssertEqual(record.inputs.map(\.displayName), ["Movie.en.srt"])
        XCTAssertEqual(record.outputDisplayName, "Movie.en — Clean.srt")
        XCTAssertEqual(
            record.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let historyText = record.events.compactMap(\.message).joined(separator: " ")
        XCTAssertFalse(historyText.contains(root.path))
        XCTAssertFalse(historyText.contains("Dialogue"))
        XCTAssertFalse(historyText.contains("YTS.MX"))
    }

    @MainActor
    func testMainWindowContentKeepsUsableWidthAfterLayout() throws {
        let controller = MainViewController(model: AppModel())
        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_080, height: 680)
        controller.view.layoutSubtreeIfNeeded()

        let splitView = try XCTUnwrap(
            controller.view.subviews.compactMap { $0 as? NSSplitView }.first)
        let footer = try XCTUnwrap(
            controller.view.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        XCTAssertGreaterThan(splitView.frame.width, 1_000)
        XCTAssertGreaterThan(splitView.frame.height, 600)
        XCTAssertGreaterThan(footer.frame.width, 1_000)
        XCTAssertEqual(footer.frame.height, 52, accuracy: 0.5)
        XCTAssertEqual(splitView.arrangedSubviews.count, 3)
        XCTAssertTrue(splitView.arrangedSubviews.allSatisfy { $0.frame.width > 0 })
    }

    private func makeHistoryRecord(id: UUID, createdAt: Date) throws -> MediaJobRecord {
        var record = MediaJobRecord(
            id: id,
            createdAt: createdAt,
            workflowID: UUID(uuidString: "6A2D7635-AB6D-4C7A-AE02-1561631121F0")!,
            workflowName: "Edit segment title",
            inputs: [MediaJobInput(displayName: "Movie.mkv")],
            outputDisplayName: "Movie — Edited.mkv"
        )
        for state in [
            MediaJobState.inspecting, .planned, .ready, .running, .verifying, .committing,
            .succeeded,
        ] {
            try record.transition(
                to: state,
                at: createdAt,
                message: state == .succeeded ? "Verified output committed and reopened." : nil
            )
        }
        return record
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? first : nil }
}
