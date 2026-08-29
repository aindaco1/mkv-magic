import AppKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

@testable import MKVMagic

@MainActor
private final class CommonFlowUpdateChecker: UpdateChecking {
    private(set) var checkCount = 0

    func checkForUpdates() {
        checkCount += 1
    }
}

final class CommonUserFlowRegressionTests: XCTestCase {
    func testFlow01FileIntakeAndRemovalPreservesSource() async throws {
        let root = try makeTemporaryDirectory(prefix: "intake")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let ignoredURL = root.appendingPathComponent("Notes.txt")
        let sourceBytes = Data("user-owned media".utf8)
        try sourceBytes.write(to: sourceURL)
        try Data("ignore".utf8).write(to: ignoredURL)

        let discovered = try await LocalMediaFileDiscovery().discover([root])
        XCTAssertEqual(discovered, [sourceURL])

        await MainActor.run {
            let asset = MediaAsset(sourceURL: sourceURL, container: "matroska")
            let model = AppModel(initialAssets: [asset])
            model.removeAssets(withIDs: [asset.id])
            XCTAssertTrue(model.assets.isEmpty)
        }
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
    }

    func testFlow02MetadataAndTrackEditingRemainZeroEncode() throws {
        let asset = makeMediaAsset()
        let titlePlan = try WorkflowPlanner().plan(
            asset: asset,
            workflow: WorkflowDefinition(
                name: "Rename",
                operations: [.editSegmentTitle("Library Title")]
            )
        )
        let track = try XCTUnwrap(asset.tracks.first(where: { $0.kind == .audio }))
        let trackPlan = try WorkflowPlanner().plan(
            asset: asset,
            workflow: WorkflowDefinition(
                name: "Edit Track",
                operations: [.editTrackMetadata(try TrackMetadataEdit(track: track))]
            )
        )

        for plan in [titlePlan, trackPlan] {
            XCTAssertEqual(plan.stages.map(\.mechanism), [.mkvPropEdit, .verify, .commit])
            XCTAssertEqual(plan.impact.videoEncodeCount, 0)
            XCTAssertEqual(plan.impact.audioEncodeCount, 0)
            XCTAssertFalse(plan.impact.changesSourceBeforeVerification)
        }
    }

    func testFlow03SubtitleCleanupCreatesNewVerifiedCopy() async throws {
        let root = try makeTemporaryDirectory(prefix: "subtitle")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.en.srt")
        let outputURL = root.appendingPathComponent("Movie.en — Clean.srt")
        let sourceText =
            "1\n00:00:00,000 --> 00:00:01,000\nHello\n\n"
            + "2\n00:00:02,000 --> 00:00:03,000\nDownloaded from YTS.MX\n"
        let sourceBytes = Data(sourceText.utf8)
        try sourceBytes.write(to: sourceURL)
        let executor = SubtitleCleanupExecutor()
        let preview = try await executor.preview(sourceURL: sourceURL)

        let result = try await executor.execute(
            preview: preview,
            restoringCueIDs: [],
            destinationURL: outputURL
        )

        XCTAssertEqual(result.removedCueCount, 1)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        let cleanedText = String(
            decoding: try Data(contentsOf: outputURL),
            as: UTF8.self
        )
        XCTAssertFalse(cleanedText.contains("YTS.MX"))
    }

    func testFlow04QuickActionOutputNamesAreDistinctAndSafe() {
        let sourceURL = URL(fileURLWithPath: "/Media/Movie.Final.mkv")
        let subtitle = MediaTrack(id: 2, kind: .subtitle, codec: "subrip")
        let attachment = MediaAttachment(
            id: 4,
            filename: "../Poster:Final.jpg",
            mimeType: "image/jpeg"
        )
        let names = [
            OutputNamingPolicy.cleanedMKVFilename(for: sourceURL),
            OutputNamingPolicy.subtitledFilename(for: sourceURL),
            OutputNamingPolicy.extractedSubtitleFilename(
                for: sourceURL,
                track: subtitle,
                format: .subRip,
                trackCount: 2
            ),
            OutputNamingPolicy.extractedAttachmentFilename(for: attachment),
            OutputNamingPolicy.extractedTagFilename(for: sourceURL),
            OutputNamingPolicy.tagsRemovedFilename(for: sourceURL),
            OutputNamingPolicy.trimmedFilename(for: sourceURL),
            OutputNamingPolicy.convertedFilename(for: sourceURL),
            OutputNamingPolicy.remuxedFilename(for: sourceURL),
        ]

        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { !$0.contains("/") && !$0.contains("\0") })
        XCTAssertTrue(names.filter { $0.hasSuffix(".mkv") }.count >= 5)
    }

    func testFlow05CompatibleJoinStaysLossless() throws {
        let sources = [
            makeMediaAsset(path: "/Media/Part 1.mkv", trackIDOffset: 0),
            makeMediaAsset(path: "/Media/Part 2.mkv", trackIDOffset: 10),
        ]
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
                JoinTrackLane(kind: .audio, trackIDsBySource: [1, 11]),
            ])
        )

        XCTAssertEqual(report.disposition, .losslessCandidate)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.requiresAuthoritativeMKVToolNixValidation)
    }

    func testFlow06ExactTrimAndConversionFuseToOneVideoGeneration() throws {
        let plan = try WorkflowPlanner().plan(
            asset: makeMediaAsset(),
            workflow: WorkflowDefinition(
                name: "Exact Trim and HEVC",
                operations: [
                    .trim(
                        start: MediaTime(nanoseconds: 1_000_000_000),
                        end: MediaTime(nanoseconds: 8_000_000_000),
                        exact: true
                    ),
                    .transcodeVideo(.hevcCompatibility),
                ]
            )
        )

        XCTAssertEqual(plan.impact.videoEncodeCount, 1)
        XCTAssertEqual(plan.stages.filter { $0.mechanism == .ffmpegEncode }.count, 1)
        XCTAssertFalse(plan.impact.changesSourceBeforeVerification)
    }

    func testFlow07SavedWorkflowPreviewIsPortableAndQueueEligible() throws {
        let preview = try SavedWorkflowCompiler().preview(
            SavedWorkflowPresetCatalog.cleanMKV,
            for: makeCleanupCandidate()
        )
        let compiled = try XCTUnwrap(preview.compiledWorkflow)

        XCTAssertEqual(compiled.plan.impact.videoEncodeCount, 0)
        XCTAssertEqual(compiled.plan.impact.audioEncodeCount, 0)
        XCTAssertFalse(compiled.plan.impact.changesSourceBeforeVerification)
        XCTAssertTrue(
            MediaQueueAutomaticWorkflowPolicy.supports(
                SavedWorkflowPresetCatalog.cleanMKV,
                inputCount: 1
            )
        )
        XCTAssertEqual(MediaQueueResourceClass(impact: compiled.plan.impact), .lightweight)
    }

    func testFlow08HistoryRecordsTheVerifiedLifecycleInOrder() throws {
        let started = Date(timeIntervalSince1970: 1_000)
        var record = MediaJobRecord(
            createdAt: started,
            workflowID: UUID(),
            workflowName: "Clean MKV",
            inputs: [MediaJobInput(displayName: "Movie.mkv")],
            outputDisplayName: "Movie — Cleaned.mkv"
        )
        for (index, state) in [
            MediaJobState.inspecting, .planned, .ready, .running, .verifying,
            .committing, .succeeded,
        ].enumerated() {
            try record.transition(
                to: state,
                at: started.addingTimeInterval(Double(index + 1)),
                message: state.rawValue
            )
        }

        XCTAssertEqual(
            record.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        XCTAssertTrue(HistoryPresentation.detail(for: record).contains("Succeeded"))
    }

    @MainActor
    func testFlow09AutomaticDestinationNeverOverwrites() throws {
        let root = try makeTemporaryDirectory(prefix: "destination")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("Movie — Cleaned.mkv"))

        let resolved = try OutputDestinationPolicy.availableOutputURL(
            filename: "Movie — Cleaned.mkv",
            directoryURL: root,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )

        XCTAssertEqual(resolved.lastPathComponent, "Movie — Cleaned 2.mkv")
    }

    @MainActor
    func testFlow10ProgressAndHelpRemainAccessibleAndLocal() throws {
        let progressController = VerifiedOutputProgressWindowController.videoTranscode()
        let content = try XCTUnwrap(progressController.window?.contentView)
        let progress = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSProgressIndicator }.first
        )
        XCTAssertFalse(progress.isIndeterminate)
        progressController.update(stage: VerifiedOutputExecutionStage.verifying)
        XCTAssertEqual(progress.doubleValue, 1)

        let updateChecker = CommonFlowUpdateChecker()
        _ = AppDelegate(updateController: updateChecker)
        XCTAssertEqual(updateChecker.checkCount, 0)
        let helpController = HelpWindowController()
        helpController.showWindow(nil)
        defer { helpController.close() }
        let helpText = try XCTUnwrap(
            descendants(in: try XCTUnwrap(helpController.window?.contentView))
                .compactMap { $0 as? NSTextView }.first
        ).string
        XCTAssertTrue(helpText.localizedCaseInsensitiveContains("originals remain unchanged"))
        XCTAssertTrue(helpText.localizedCaseInsensitiveContains("stay local"))
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-common-flow-\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makeMediaAsset(
        path: String = "/Media/Movie.mkv",
        trackIDOffset: Int = 0
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: path),
            container: "matroska",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            fileSize: 1_000_000,
            tracks: [
                MediaTrack(
                    id: trackIDOffset,
                    kind: .video,
                    codec: "h264",
                    codecID: "V_MPEG4/ISO/AVC",
                    profile: "High",
                    level: 41,
                    uid: UInt64(100 + trackIDOffset),
                    language: "und",
                    title: "Main Video",
                    isDefault: true,
                    dimensions: MediaDimensions(width: 1_920, height: 1_080),
                    displayDimensions: MediaDimensions(width: 1_920, height: 1_080),
                    pixelFormat: "yuv420p",
                    bitDepth: 8,
                    frameRate: "24000/1001",
                    colorInfo: MediaColorInfo(
                        range: "tv",
                        primaries: "bt709",
                        transfer: "bt709",
                        matrix: "bt709"
                    )
                ),
                MediaTrack(
                    id: trackIDOffset + 1,
                    kind: .audio,
                    codec: "aac",
                    codecID: "A_AAC",
                    profile: "LC",
                    uid: UInt64(101 + trackIDOffset),
                    language: "en",
                    title: "Main Audio",
                    isDefault: true,
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: 48_000
                ),
            ],
            segmentUID: "segment-\(trackIDOffset)"
        )
    }

    private func makeCleanupCandidate() -> MediaAsset {
        let base = makeMediaAsset(path: "/Media/Movie.2026.1080p.mkv")
        return MediaAsset(
            sourceURL: base.sourceURL,
            container: base.container,
            duration: base.duration,
            fileSize: base.fileSize,
            tracks: base.tracks + [
                MediaTrack(
                    id: 2,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 202,
                    language: "fr",
                    title: "French"
                ),
                MediaTrack(
                    id: 3,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 203,
                    language: "en",
                    title: "English SDH",
                    isHearingImpaired: true
                ),
            ],
            attachments: [
                MediaAttachment(
                    id: 1,
                    filename: "cover.jpg",
                    mimeType: "image/jpeg",
                    size: 100,
                    uid: 301
                )
            ],
            metadata: ["title": "Release Title"],
            globalTagCount: 1,
            trackTagCount: 1,
            segmentUID: base.segmentUID
        )
    }

    @MainActor
    private func descendants(in root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(descendants)
    }
}
