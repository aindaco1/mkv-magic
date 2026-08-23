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

    @MainActor
    func testAppDelegateCreatesVisibleUsableMainWindow() throws {
        _ = NSApplication.shared
        let checker = FakeUpdateChecker()
        let delegate = AppDelegate(updateController: checker)

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "MKV Magic" })
        defer { window.close() }
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(contentView.frame.size.width, 1_080, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 680, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 820)
        XCTAssertEqual(window.minSize.height, 520)
        XCTAssertTrue(window.contentViewController is MainViewController)
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
        XCTAssertEqual(
            OutputNamingPolicy.cleanedSubtitleFilename(
                for: URL(fileURLWithPath: "/Media/Movie.en.ASS")),
            "Movie.en — Clean.ass"
        )
        XCTAssertEqual(
            OutputNamingPolicy.cleanedSubtitleFilename(
                for: URL(fileURLWithPath: "/Media/Legacy.SSA")),
            "Legacy — Clean.ssa"
        )
    }

    func testSubtitledOutputNameAlwaysUsesMKV() {
        XCTAssertEqual(
            OutputNamingPolicy.subtitledFilename(
                for: URL(fileURLWithPath: "/Media/Movie.WEBM")),
            "Movie — Subtitled.mkv"
        )
    }

    func testEmbeddedSubtitleCleanupOutputNameAlwaysUsesMKV() {
        XCTAssertEqual(
            OutputNamingPolicy.cleanedMKVFilename(
                for: URL(fileURLWithPath: "/Media/Movie.WEBM")),
            "Movie — Cleaned.mkv"
        )
    }

    func testJoinedOutputNameAlwaysUsesMKV() {
        XCTAssertEqual(
            OutputNamingPolicy.joinedFilename(
                for: URL(fileURLWithPath: "/Media/Part One.WEBM")),
            "Part One — Joined.mkv"
        )
    }

    func testLosslessJoinReviewBuildsStrictNestedPartPlan() throws {
        let first = losslessJoinOption(
            part: 1,
            duration: 10,
            chapters: [
                MatroskaChapterEdition(
                    chapters: [
                        MatroskaChapterAtom(
                            start: .zero,
                            displays: [ChapterDisplay(title: "Opening")]
                        )
                    ]
                )
            ]
        )
        let second = losslessJoinOption(part: 2, duration: 12)

        let snapshot = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(
                    option: first,
                    editionID: try XCTUnwrap(first.editions.first?.id)
                ),
                LosslessJoinSourceSelection(option: second, editionID: nil),
            ]
        )

        let candidate = try XCTUnwrap(snapshot.candidate)
        XCTAssertTrue(snapshot.blockerSummaries.isEmpty)
        XCTAssertTrue(snapshot.issueSummaries.isEmpty)
        XCTAssertEqual(
            snapshot.normalizationSummaries,
            ["Not needed; every reviewed lane remains a packet copy."]
        )
        XCTAssertEqual(snapshot.laneSummaries.count, 1)
        XCTAssertTrue(snapshot.laneSummaries[0].contains("Part 1: #0 AAC"))
        XCTAssertEqual(candidate.report.disposition, .losslessCandidate)
        XCTAssertEqual(candidate.chapters.duration, MediaTime(nanoseconds: 22_000_000_000))
        XCTAssertEqual(candidate.chapters.document.chapterCount, 4)
        let parents = try XCTUnwrap(candidate.chapters.document.editions.first).chapters
        XCTAssertEqual(parents.map(\.primaryTitle), ["Part 1 — Part 1", "Part 2 — Part 2"])
        XCTAssertEqual(parents[0].children.first?.primaryTitle, "Opening")
        XCTAssertEqual(parents[1].children.first?.primaryTitle, "Chapter 02")
    }

    func testLosslessJoinReviewBlocksOnePassNormalizationMismatch() throws {
        let first = losslessJoinOption(part: 1, duration: 10, sampleRate: 48_000)
        let second = losslessJoinOption(part: 2, duration: 10, sampleRate: 44_100)

        let snapshot = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(option: first, editionID: nil),
                LosslessJoinSourceSelection(option: second, editionID: nil),
            ]
        )

        XCTAssertNil(snapshot.candidate)
        XCTAssertTrue(snapshot.issueSummaries.contains { $0.contains("sample rate") })
        XCTAssertTrue(snapshot.blockerSummaries.contains { $0.contains("normalization") })
        XCTAssertTrue(snapshot.normalizationSummaries.contains { $0.contains("AAC once") })
        XCTAssertTrue(
            snapshot.normalizationSummaries.contains { $0.contains("0 video generation") }
        )
    }

    func testLosslessJoinReviewRequiresExplicitChoiceForMultipleEditions() throws {
        let option = losslessJoinOption(
            part: 1,
            duration: 10,
            chapters: [
                MatroskaChapterEdition(chapters: []),
                MatroskaChapterEdition(isDefault: false, chapters: []),
            ]
        )
        let second = losslessJoinOption(part: 2, duration: 10)
        let blocked = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(option: option, editionID: nil),
                LosslessJoinSourceSelection(option: second, editionID: nil),
            ]
        )
        XCTAssertNil(blocked.candidate)
        XCTAssertTrue(blocked.blockerSummaries.contains { $0.contains("Choose") })

        let reviewed = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(
                    option: option,
                    editionID: try XCTUnwrap(option.editions.last?.id)
                ),
                LosslessJoinSourceSelection(option: second, editionID: nil),
            ]
        )
        XCTAssertNotNil(reviewed.candidate)
    }

    @MainActor
    func testLosslessJoinWindowKeepsNativeReviewActionsVisibleAtMinimumSize() throws {
        let first = losslessJoinOption(part: 1, duration: 10)
        let second = losslessJoinOption(part: 2, duration: 10)
        let controller = LosslessJoinWindowController(options: [first, second])
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.title, "Join MKV Files")
        XCTAssertEqual(window.minSize, NSSize(width: 720, height: 560))
        let table = try XCTUnwrap(descendants(in: content).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.numberOfRows, 2)
        let controls = buttons(in: content)
        for title in ["Move Up", "Move Down", "Cancel", "Continue to Save…"] {
            XCTAssertTrue(controls.contains { $0.title == title }, "Missing join action \(title)")
        }
        XCTAssertTrue(
            try XCTUnwrap(controls.first { $0.title == "Continue to Save…" }).isEnabled
        )
        for button in controls where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }
        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_JOIN_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            controller.showWindow(nil)
            window.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            content.layoutSubtreeIfNeeded()
            let bounds = content.bounds
            let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
            content.cacheDisplay(in: bounds, to: representation)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
        }
    }

    @MainActor
    func testLosslessJoinWindowRendersCommonFormatPreviewWithoutEnablingSave() throws {
        let controller = LosslessJoinWindowController(options: [
            losslessJoinOption(part: 1, duration: 10, sampleRate: 48_000),
            losslessJoinOption(part: 2, duration: 10, sampleRate: 44_100),
        ])
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()

        let review = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextView }.first
        )
        XCTAssertTrue(review.string.contains("COMMON-FORMAT OPTION"))
        XCTAssertTrue(review.string.contains("AAC once"))
        XCTAssertTrue(review.string.contains("0 video generation"))
        XCTAssertTrue(review.string.contains("explicit approval"))
        let save = try XCTUnwrap(
            buttons(in: content).first { $0.title == "Continue to Save…" }
        )
        XCTAssertFalse(save.isEnabled)
    }

    func testExternalSubtitleMetadataIsCanonicalAndBounded() throws {
        XCTAssertEqual(
            try ExternalSubtitleMuxPresentation.metadata(
                language: " ENG ",
                name: "  English Forced  ",
                isDefault: false,
                isForced: true,
                isHearingImpaired: false
            ),
            ExternalSubtitleTrackMetadata(
                language: "en",
                name: "English Forced",
                isForced: true
            )
        )
        XCTAssertThrowsError(
            try ExternalSubtitleMuxPresentation.metadata(
                language: "en",
                name: "Bad\0Name",
                isDefault: false,
                isForced: false,
                isHearingImpaired: false
            )
        ) { error in
            XCTAssertEqual(error as? ExternalSubtitleMuxError, .invalidTrackName)
        }
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
        XCTAssertTrue(
            SubtitleCleanupPresentation.selectedByDefault(reasons: [.ocrHighConfidence])
        )
        XCTAssertFalse(
            SubtitleCleanupPresentation.selectedByDefault(reasons: [.spellingSuggestion])
        )
    }

    func testSubtitleCleanupPresentationDistinguishesOCRConfidenceAndLanguagePolicy() {
        let cue = SubRipCue(
            id: 0,
            start: SubRipTimestamp(milliseconds: 0),
            end: SubRipTimestamp(milliseconds: 1_000),
            lines: ["Tbe"]
        )
        let correctedCue = SubRipCue(
            id: cue.id,
            start: cue.start,
            end: cue.end,
            lines: ["The"]
        )
        let change = SubtitleCleanupChange(
            id: cue.id,
            reasons: [.spellingSuggestion],
            before: cue,
            after: correctedCue
        )
        let cleanup = SubtitleCleanupPreview(
            original: SubRipDocument(cues: [cue]),
            cleaned: SubRipDocument(cues: [correctedCue]),
            changes: [change]
        )
        let preview = SubtitleCleanupFilePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.fr.srt"),
            sourceSHA256: Data(),
            encoding: .utf8,
            diagnostics: [],
            cleanup: cleanup,
            normalizationNeeded: false,
            appliesEnglishOCRRules: false
        )

        XCTAssertTrue(SubtitleCleanupPresentation.title(change).contains("possible"))
        XCTAssertTrue(
            SubtitleCleanupPresentation.normalization(preview).contains("skipped")
        )
        XCTAssertTrue(SubtitleCleanupPresentation.summary(preview).contains("0 of 1"))
    }

    func testAdvancedSubtitleCleanupPresentationKeepsOneEventAndDescribesPreservation() throws {
        let preview = try advancedSubtitlePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.ass"),
            text:
                "[Events]\nFormat: Layer, Start, End, Style, Text\n"
                + "Dialogue: 0,0:00:01.00,0:00:02.00,Default,Downloaded from YTS.MX\n"
        )
        let eventID = try XCTUnwrap(preview.cleanup.original.events.first?.id)

        XCTAssertFalse(
            SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: [eventID]
            )
        )
        XCTAssertTrue(
            SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: []
            )
        )
        XCTAssertTrue(
            SubtitleCleanupPresentation.normalization(preview).contains(
                "script sections and styles preserved"
            )
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
    func testAdvancedSubtitleCleanupUsesSharedCompactReviewWindow() throws {
        let preview = try advancedSubtitlePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.ass"),
            text:
                "[Events]\nFormat: Layer, Start, End, Style, Text\n"
                + "Dialogue: 0,0:00:01.00,0:00:02.00,Default, Text \n"
        )
        let controller = SubtitleCleanupWindowController(preview: preview)
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertEqual(window.title, "Clean ASS/SSA Subtitle")
        XCTAssertTrue(window.contentViewController is SubtitleCleanupViewController)
        XCTAssertEqual(contentView.frame.size.width, 740, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 560, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 640)
        XCTAssertEqual(window.minSize.height, 480)
    }

    @MainActor
    func testEmbeddedSubtitlePickerUsesReadableTrackLabelsAndCompactLayout() throws {
        let tracks = [
            MediaTrack(
                id: 1,
                kind: .subtitle,
                codec: "subrip",
                codecID: "S_TEXT/UTF8",
                uid: 42,
                language: "en",
                title: "English SDH",
                isDefault: true,
                isHearingImpaired: true
            ),
            MediaTrack(
                id: 2,
                kind: .subtitle,
                codec: "PGS",
                codecID: "S_HDMV/PGS",
                uid: 43,
                language: "fr"
            ),
        ]
        XCTAssertEqual(
            EmbeddedSubtitleTrackPickerViewController.title(tracks[0]),
            "#2 • SRT • en • English SDH • default, SDH"
        )
        let controller = EmbeddedSubtitleTrackPickerWindowController(tracks: tracks)
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertEqual(window.title, "Choose Embedded Subtitle")
        XCTAssertTrue(
            window.contentViewController is EmbeddedSubtitleTrackPickerViewController)
        XCTAssertEqual(contentView.frame.size.width, 620, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 280, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 540)
        XCTAssertEqual(window.minSize.height, 260)
    }

    @MainActor
    func testEmbeddedSRTUsesSharedReviewWindowAndTrackLanguageExplanation() throws {
        let cue = SubRipCue(
            id: 0,
            start: SubRipTimestamp(milliseconds: 0),
            end: SubRipTimestamp(milliseconds: 1_000),
            lines: [" y0u "]
        )
        let track = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 42,
            language: "en",
            title: "English"
        )
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            tracks: [track]
        )
        let preview = EmbeddedSubtitleCleanupPreview.subRip(
            EmbeddedSubRipCleanupPreview(
                source: source,
                track: track,
                sourceRevision: EmbeddedSubtitleSourceRevision(
                    fileSize: 1,
                    modificationDate: Date(timeIntervalSince1970: 0)
                ),
                extractedSHA256: Data(),
                packetTimelineSHA256: Data(),
                encoding: .utf8,
                diagnostics: [],
                cleanup: SubtitleCleanupPolicy().preview(SubRipDocument(cues: [cue])),
                appliesEnglishOCRRules: true
            ))
        let controller = SubtitleCleanupWindowController(preview: preview)
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.title, "Clean Embedded SRT Subtitle")
        XCTAssertTrue(window.contentViewController is SubtitleCleanupViewController)
        XCTAssertTrue(
            SubtitleCleanupPresentation.embeddedNormalization(
                format: .subRip,
                track: track,
                appliesEnglishOCRRules: true,
                diagnosticCount: 0
            ).contains("same position")
        )
    }

    @MainActor
    func testExternalSubtitleMuxWindowUsesCompactNativeLayoutAndExplicitWarnings() throws {
        let cue = SubRipCue(
            id: 0,
            start: SubRipTimestamp(milliseconds: 0),
            end: SubRipTimestamp(milliseconds: 1_000),
            lines: [" Text "]
        )
        let document = SubRipDocument(cues: [cue])
        let preview = SubtitleCleanupFilePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Unrelated.srt"),
            sourceSHA256: Data(SHA256.hash(data: Data())),
            encoding: .utf8,
            diagnostics: [],
            cleanup: SubtitleCleanupPolicy().preview(document),
            normalizationNeeded: false
        )
        let match = ExternalSubtitleMatch(
            subtitleURL: preview.sourceURL,
            score: 0,
            confidence: .low,
            reasons: [],
            suggestedMetadata: ExternalSubtitleTrackMetadata(language: "und"),
            subtitleEnd: cue.end,
            durationDifferenceMilliseconds: -119_000,
            isDurationCompatible: false
        )
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 120),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
        let warnings = ExternalSubtitleMuxPresentation.warnings(
            preview: preview,
            match: match
        )
        XCTAssertEqual(warnings.count, 3)
        XCTAssertTrue(warnings[0].contains("weak match"))
        XCTAssertTrue(warnings[1].contains("shorter"))
        XCTAssertTrue(warnings[2].contains("will not be applied"))

        let controller = ExternalSubtitleMuxWindowController(
            media: media,
            preview: preview,
            match: match
        )
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertTrue(window.contentViewController is ExternalSubtitleMuxViewController)
        XCTAssertEqual(contentView.frame.size.width, 620, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 530, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 560)
        XCTAssertEqual(window.minSize.height, 500)
    }

    @MainActor
    func testExternalASSMuxUsesSharedConfirmationAndWarnsBeforeDiscardingCleanup() throws {
        let preview = try advancedSubtitlePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.en.ass"),
            text:
                "[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
                + "[Events]\nFormat: Layer, Start, End, Style, Text\n"
                + "Dialogue: 0,0:00:00.00,0:00:01.00,Default, Text \n"
        )
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 1),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
        let match = ExternalSubtitleMatcher().match(
            media: media,
            subtitleURL: preview.sourceURL,
            subtitle: preview.cleanup.original
        )

        let warnings = ExternalSubtitleMuxPresentation.warnings(
            preview: preview,
            match: match
        )
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("Clean Subtitle first"))

        let controller = ExternalSubtitleMuxWindowController(
            media: media,
            preview: preview,
            match: match
        )
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertEqual(window.title, "Add External Subtitle")
        XCTAssertTrue(window.contentViewController is ExternalSubtitleMuxViewController)
        XCTAssertEqual(contentView.frame.size.width, 620, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 530, accuracy: 1)
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
    func testAdvancedSubtitleCleanupPersistsSanitizedVerifiedLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-ass-history-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.en.ass")
        let output = root.appendingPathComponent("Movie.en — Clean.ass")
        let sourceText =
            "[Script Info]\r\nTitle: Movie\r\n"
            + "[V4+ Styles]\r\nFormat: Name, Fontname\r\nStyle: Default,Arial\r\n"
            + "[Events]\r\nFormat: Layer, Start, End, Style, Text\r\n"
            + "Dialogue: 0,0:00:00.00,0:00:01.00,Default,Downloaded from YTS.MX\r\n"
            + "Dialogue: 0,0:00:01.00,0:00:02.00,Default,  Dialogue  \r\n"
        let sourceData = Data(sourceText.utf8)
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

        let preview = try await model.previewAdvancedSubtitleCleanup(at: source)
        let result = try await model.cleanAdvancedSubtitle(
            preview: preview,
            restoringEventIDs: [],
            destinationURL: output
        )

        XCTAssertEqual(result.removedEventCount, 1)
        XCTAssertEqual(result.changedEventCount, 1)
        XCTAssertEqual(try Data(contentsOf: source), sourceData)
        let outputText = String(decoding: try Data(contentsOf: output), as: UTF8.self)
        XCTAssertTrue(outputText.contains("Style: Default,Arial"))
        XCTAssertTrue(outputText.contains("Default,Dialogue"))
        XCTAssertFalse(outputText.contains("YTS.MX"))
        XCTAssertEqual(
            model.state,
            .completed("Created Movie.en — Clean.ass; original unchanged.")
        )
        let records = try await store.load()
        let record = try XCTUnwrap(records.only)
        XCTAssertEqual(record.workflowName, "Clean ASS/SSA subtitle")
        XCTAssertEqual(record.inputs.map(\.displayName), ["Movie.en.ass"])
        XCTAssertEqual(record.outputDisplayName, "Movie.en — Clean.ass")
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

    @MainActor
    func testChapterStudioExposesNestedEditingAndExplicitFlatteningActions() throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/Movie.mkv")
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 60_000_000_000),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
        let original = MatroskaChapterDocument(
            editions: [
                MatroskaChapterEdition(
                    uid: 1,
                    chapters: [
                        MatroskaChapterAtom(
                            uid: 2,
                            start: .zero,
                            displays: [ChapterDisplay(title: "Opening")]
                        )
                    ]
                )
            ]
        )
        let controller = ChapterStudioWindowController(
            preview: ChapterEditPreview(
                source: source,
                original: original,
                sourceRevision: ChapterSourceRevision(
                    fileSize: 1,
                    modificationDate: Date(timeIntervalSince1970: 0)
                ),
                canonicalSHA256: Data(repeating: 0, count: 32)
            ),
            suggestionProvider: { _, _ in [] },
            thumbnailProvider: { _ in [] }
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        controller.window?.setContentSize(NSSize(width: 820, height: 580))
        content.layoutSubtreeIfNeeded()
        let titles = buttonTitles(in: content)

        for expected in [
            "Add Edition", "Add Chapter", "Add Child", "Duplicate", "Remove", "Nest",
            "Unnest", "Every…", "Suggest…", "Thumbnails…", "Flatten for Jellyfin", "Import…",
            "Export…", "Use Changes",
        ] {
            XCTAssertTrue(titles.contains(expected), "Missing Chapter Studio action \(expected)")
        }
        let chapterButtons = buttons(in: content)
        XCTAssertTrue(try XCTUnwrap(chapterButtons.first { $0.title == "Suggest…" }).isEnabled)
        XCTAssertTrue(try XCTUnwrap(chapterButtons.first { $0.title == "Thumbnails…" }).isEnabled)
        for button in chapterButtons where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }

        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_CHAPTER_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            controller.showWindow(nil)
            controller.window?.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            content.layoutSubtreeIfNeeded()
            let bounds = content.bounds
            let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
            content.cacheDisplay(in: bounds, to: representation)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
        }
    }

    @MainActor
    func testChapterThumbnailChooserShowsLocalFramesAndExactTimesAtMinimumSize() throws {
        let jpeg = try makeThumbnailJPEG()
        let controller = try XCTUnwrap(
            ChapterThumbnailWindowController(
                thumbnails: [
                    ChapterThumbnail(
                        time: MediaTime(nanoseconds: 5_000_000_000), imageData: jpeg),
                    ChapterThumbnail(
                        time: MediaTime(nanoseconds: 10_000_000_000), imageData: jpeg),
                    ChapterThumbnail(
                        time: MediaTime(nanoseconds: 15_000_000_000), imageData: jpeg),
                ],
                currentTime: MediaTime(nanoseconds: 10_000_000_000)
            )
        )
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(NSSize(width: 560, height: 300))
        content.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.title, "Chapter Start Preview")
        XCTAssertEqual(window.minSize, NSSize(width: 560, height: 300))
        let controls = buttons(in: content)
        XCTAssertEqual(controls.filter { $0.title == "Use This Time" }.count, 3)
        XCTAssertTrue(controls.contains { $0.title == "Cancel" })
        let labels = descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }
        for expected in [
            "Before", "Current", "After", "00:00:05.000", "00:00:10.000",
            "00:00:15.000",
        ] {
            XCTAssertTrue(labels.contains(expected), "Missing thumbnail label \(expected)")
        }
        XCTAssertEqual(descendants(in: content).compactMap { $0 as? NSImageView }.count, 3)
        for button in controls where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }

        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_THUMBNAIL_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            controller.showWindow(nil)
            window.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            content.layoutSubtreeIfNeeded()
            let bounds = content.bounds
            let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
            content.cacheDisplay(in: bounds, to: representation)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
        }
    }

    @MainActor
    func testChapterSuggestionReviewStartsSelectedAndExposesBulkControls() throws {
        let controller = ChapterSuggestionReviewWindowController(
            suggestions: [
                ChapterSuggestion(
                    time: MediaTime(nanoseconds: 10_000_000_000),
                    signals: [.sceneChange, .blackFrame]
                ),
                ChapterSuggestion(
                    time: MediaTime(nanoseconds: 30_000_000_000),
                    signals: [.silence]
                ),
            ]
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        controller.window?.setContentSize(NSSize(width: 560, height: 400))
        content.layoutSubtreeIfNeeded()
        let controls = buttons(in: content)
        XCTAssertTrue(controls.contains { $0.title == "Select All" })
        XCTAssertTrue(controls.contains { $0.title == "Select None" })
        XCTAssertTrue(controls.contains { $0.title == "Cancel" })
        XCTAssertTrue(try XCTUnwrap(controls.first { $0.title == "Add Selected" }).isEnabled)
        let table = try XCTUnwrap(descendants(in: content).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertGreaterThan(table.enclosingScrollView?.frame.height ?? 0, 150)
        for button in controls where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }

        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_SUGGESTION_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            controller.showWindow(nil)
            controller.window?.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            content.layoutSubtreeIfNeeded()
            let bounds = content.bounds
            let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
            content.cacheDisplay(in: bounds, to: representation)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
        }
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

    private func losslessJoinOption(
        part: Int,
        duration seconds: Int64,
        sampleRate: Int = 48_000,
        chapters: [MatroskaChapterEdition] = []
    ) -> LosslessJoinSourceOption {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Part \(part).mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: seconds * 1_000_000_000),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .audio,
                    codec: "aac",
                    codecID: "A_AAC",
                    profile: "LC",
                    uid: UInt64(part),
                    isDefault: true,
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: sampleRate
                )
            ]
        )
        return LosslessJoinSourceOption(
            chapterPreview: ChapterEditPreview(
                source: source,
                original: MatroskaChapterDocument(editions: chapters),
                sourceRevision: ChapterSourceRevision(
                    fileSize: 1,
                    modificationDate: Date(timeIntervalSince1970: 1)
                ),
                canonicalSHA256: Data(repeating: 0, count: 32)
            )
        )
    }

    private func advancedSubtitlePreview(
        sourceURL: URL,
        text: String
    ) throws -> AdvancedSubtitleCleanupFilePreview {
        let data = Data(text.utf8)
        let parsed = try AdvancedSubStationAlphaCodec().parse(
            DecodedSubtitleText(text: text, encoding: .utf8)
        )
        return AdvancedSubtitleCleanupFilePreview(
            sourceURL: sourceURL,
            sourceSHA256: Data(SHA256.hash(data: data)),
            encoding: .utf8,
            diagnostics: parsed.diagnostics,
            cleanup: AdvancedSubStationAlphaCleanupPolicy().preview(parsed.document),
            normalizationNeeded: false
        )
    }

    @MainActor
    private func buttonTitles(in view: NSView) -> [String] {
        buttons(in: view).map(\.title)
    }

    @MainActor
    private func buttons(in view: NSView) -> [NSButton] {
        descendants(in: view).compactMap { $0 as? NSButton }
    }

    @MainActor
    private func descendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor
    private func makeThumbnailJPEG() throws -> Data {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 160,
                pixelsHigh: 90,
                bitsPerSample: 8,
                samplesPerPixel: 3,
                hasAlpha: false,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        return try XCTUnwrap(
            bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]))
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? first : nil }
}
