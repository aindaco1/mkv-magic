import AppKit
import CryptoKit
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
        try WorkflowEvidence.record(
            "metadata-plan",
            facts: [
                "no_video_encoding": titlePlan.impact.videoEncodeCount == 0,
                "no_audio_encoding": titlePlan.impact.audioEncodeCount == 0,
                "verified_clone_before_commit": titlePlan.stages.map(\.mechanism)
                    == [.mkvPropEdit, .verify, .commit],
            ], explanation: titlePlan.stages.map(\.summary).joined(separator: "\n"))
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
            OutputNamingPolicy.chaptersAddedFilename(for: sourceURL),
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

    func testFlow05CodecInitializationMismatchUsesOneGeneration() throws {
        let sources = [
            makeMediaAsset(
                path: "/Media/CAVLC.mkv",
                codecInitializationSHA256: String(repeating: "a", count: 64)
            ),
            makeMediaAsset(
                path: "/Media/CABAC.mkv",
                trackIDOffset: 10,
                codecInitializationSHA256: String(repeating: "b", count: 64)
            ),
        ]
        let mapping = JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
            JoinTrackLane(kind: .audio, trackIDsBySource: [1, 11]),
        ])

        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: mapping
        )
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping
        )

        XCTAssertEqual(report.disposition, .normalizationRequired)
        XCTAssertTrue(report.issues.contains { $0.reason == .codecInitialization })
        XCTAssertTrue(ReviewedMKVToolNixLosslessAppendPolicy.canOffer(for: report))
        XCTAssertTrue(proposal.blockers.isEmpty)
        XCTAssertEqual(proposal.impact.videoEncodeCount, 1)
        XCTAssertEqual(proposal.videoLanes[0].sourceActions, [.encodeOnce, .encodeOnce])
        XCTAssertEqual(proposal.impact.audioEncodeCount, 0)
    }

    func testFlow05UntaggedHDH264CanUseReviewedSDRCommonFormat() throws {
        let sources = [
            makeMediaAsset(
                path: "/Media/CAVLC.mkv",
                codecInitializationSHA256: String(repeating: "a", count: 64),
                colorInfo: nil
            ),
            makeMediaAsset(
                path: "/Media/CABAC.mkv",
                trackIDOffset: 10,
                codecInitializationSHA256: String(repeating: "b", count: 64),
                colorInfo: nil
            ),
        ]
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
                JoinTrackLane(kind: .audio, trackIDsBySource: [1, 11]),
            ]),
            preferredVideoPreset: .h264Compatibility
        )

        XCTAssertTrue(proposal.blockers.isEmpty, "\(proposal.blockers)")
        XCTAssertEqual(proposal.impact.videoEncodeCount, 1)
        XCTAssertEqual(proposal.videoLanes[0].recommendedDynamicRange, .sdr)
        XCTAssertTrue(proposal.decisions.contains { $0.kind == .untaggedSDR })
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
        try WorkflowEvidence.record(
            "fused-trim",
            facts: [
                "exact_trim_requested": true,
                "one_video_generation": plan.impact.videoEncodeCount == 1,
                "one_encode_stage": plan.stages.filter { $0.mechanism == .ffmpegEncode }.count == 1,
            ], explanation: plan.stages.map(\.summary).joined(separator: "\n"))
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
        try WorkflowEvidence.record(
            "cleanup-review",
            facts: [
                "no_video_encoding": compiled.plan.impact.videoEncodeCount == 0,
                "no_audio_encoding": compiled.plan.impact.audioEncodeCount == 0,
                "changes_await_approval": true,
            ],
            explanation: WorkflowPlanReviewPresentation.impactSummary(for: preview) + "\n"
                + preview.stepOutcomes.filter { $0.disposition == .applied }.map {
                    $0.action.displayName + " — "
                        + WorkflowPlanReviewPresentation.statusLabel(for: $0)
                }.joined(separator: "\n"))
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
    func testFlow09DestinationRequiresAccessAndNeverOverwrites() throws {
        let root = try makeTemporaryDirectory(prefix: "destination")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("Movie — Cleaned.mkv"))

        let resolved = try OutputDestinationPolicy.availableOutputURL(
            filename: "Movie — Cleaned.mkv",
            directoryURL: root,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )

        XCTAssertEqual(resolved.lastPathComponent, "Movie — Cleaned 2.mkv")

        let suite = "mkv-magic-flow-output-policy-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let resolution = try OutputDestinationPolicy.resolve(
            sourceURL: root.appendingPathComponent("Movie.mkv"),
            suggestedFilename: "Movie — Cleaned.mkv",
            preferences: OutputDestinationPreferences(defaults: defaults),
            directoryAccessProvider: { _ in nil }
        )
        guard case .askEveryTime = resolution else {
            return XCTFail("The save panel must obtain access before writing beside a source")
        }
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

    func testFlow11DraggedMP4AndSRTBecomeOneEditableZeroEncodeRemux() throws {
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.English.mp4"),
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            duration: MediaTime(seconds: 60),
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "h264"),
                MediaTrack(id: 1, kind: .audio, codec: "aac", language: "und"),
            ]
        )
        let subtitle = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.French.srt"),
            container: "srt"
        )
        let pair = try XCTUnwrap(
            CommonMediaSubtitleRemuxPresentation.pair(in: [media, subtitle])
        )
        XCTAssertEqual(pair.media, media)
        XCTAssertEqual(
            CommonMediaSubtitleRemuxPresentation.defaultAudioLanguages(for: media),
            [1: "en"]
        )
        let match = ExternalSubtitleMatcher().match(
            media: media,
            subtitleURL: subtitle.sourceURL,
            subtitle: SubRipDocument(cues: [
                SubRipCue(
                    id: 1,
                    start: SubRipTimestamp(milliseconds: 0),
                    end: SubRipTimestamp(milliseconds: 59_000),
                    lines: ["Bonjour"]
                )
            ])
        )
        XCTAssertEqual(match.suggestedMetadata.language, "fr")

        let arguments = try MKVRemuxCommandBuilder().build(
            plan: MKVRemuxPlanner().resolve(source: media),
            outputURL: URL(fileURLWithPath: "/private/Movie.mkv"),
            trackLanguageOverrides: [1: "en"],
            externalSubtitle: (subtitle.sourceURL, match.suggestedMetadata)
        )
        XCTAssertEqual(arguments.filter { $0 == "--output" }.count, 1)
        XCTAssertTrue(arguments.contains("0:0,0:1,1:0"))
        XCTAssertFalse(arguments.contains("-c:v"))
        XCTAssertFalse(arguments.contains("-c:a"))

        let reviewedWorkflow = try CommonMediaSubtitleRemuxPresentation.reviewedWorkflow(
            for: media,
            externalSubtitle: SavedWorkflowExternalSubtitleInput(
                sourceURL: subtitle.sourceURL,
                metadata: match.suggestedMetadata,
                format: .subRip
            ),
            sourceTrackLanguageOverrides: [1: "en"]
        )
        XCTAssertEqual(reviewedWorkflow.compiled.sourceTrackLanguageOverrides, [1: "en"])
        XCTAssertTrue(
            MediaQueueAutomaticWorkflowPolicy.supports(
                reviewedWorkflow.recipe,
                inputCount: 2
            )
        )
        XCTAssertEqual(
            reviewedWorkflow.compiled.plan.stages.map(\.mechanism),
            [.mkvMerge, .verify, .commit]
        )
        try WorkflowEvidence.record(
            "remux-review",
            facts: [
                "one_remux": reviewedWorkflow.compiled.plan.stages.filter {
                    $0.mechanism == .mkvMerge
                }.count == 1,
                "no_video_encoding": reviewedWorkflow.compiled.plan.impact.videoEncodeCount == 0,
                "no_audio_encoding": reviewedWorkflow.compiled.plan.impact.audioEncodeCount == 0,
            ],
            explanation: WorkflowPlanReviewPresentation.impactSummary(
                for: reviewedWorkflow.compiled))
    }

    @MainActor
    func testFlow12TwoReviewedMP4AndSRTJobsCanWaitTogether() async throws {
        let root = try makeTemporaryDirectory(prefix: "two-remux-jobs")
        defer { try? FileManager.default.removeItem(at: root) }
        let queueStore = try JSONJobQueueStore(
            fileURL: root.appendingPathComponent("job-queue.json")
        )
        let model = AppModel(queueStoreFactory: { queueStore })

        for (index, languages) in [(1, ("en", "fr")), (2, ("es", "de"))] {
            let mediaURL = root.appendingPathComponent("Movie\(index).\(languages.0).mp4")
            let subtitleURL = root.appendingPathComponent("Movie\(index).\(languages.1).srt")
            try Data("reviewed media \(index)".utf8).write(to: mediaURL)
            let subtitleData = Data(
                "1\n00:00:00,000 --> 00:00:01,000\nSubtitle \(index)\n".utf8
            )
            try subtitleData.write(to: subtitleURL)
            let media = MediaAsset(
                sourceURL: mediaURL,
                container: "mov,mp4,m4a,3gp,3g2,mj2",
                duration: MediaTime(seconds: 2),
                fileSize: Int64(try Data(contentsOf: mediaURL).count),
                tracks: [
                    MediaTrack(id: 0, kind: .video, codec: "h264"),
                    MediaTrack(id: 1, kind: .audio, codec: "aac", language: "und"),
                ],
                chapterEntryCount: 0
            )
            let decoded = try SubtitleTextDecoder().decode(subtitleData)
            let parsed = try SubRipCodec().parse(decoded)
            let payload = ExternalSubtitleMuxPayload.original(
                .subRip(
                    SubtitleCleanupFilePreview(
                        sourceURL: subtitleURL,
                        sourceSHA256: Data(SHA256.hash(data: subtitleData)),
                        encoding: decoded.encoding,
                        diagnostics: parsed.diagnostics,
                        cleanup: SubtitleCleanupPolicy().preview(parsed.document),
                        normalizationNeeded: false
                    )
                )
            )
            let reviewed = try CommonMediaSubtitleRemuxPresentation.reviewedWorkflow(
                for: media,
                externalSubtitle: SavedWorkflowExternalSubtitleInput(
                    sourceURL: subtitleURL,
                    metadata: ExternalSubtitleTrackMetadata(language: languages.1),
                    format: .subRip
                ),
                sourceTrackLanguageOverrides: [1: languages.0]
            )

            _ = try await model.enqueueSavedWorkflow(
                reviewed.compiled,
                recipe: reviewed.recipe,
                externalSubtitlePayload: payload,
                expectedSourceRevision: MediaFileRevisionReader().read(mediaURL),
                in: media,
                destinationURL: root.appendingPathComponent("Output\(index).mkv")
            )
        }

        let queued = try await model.loadQueue()
        XCTAssertEqual(queued.jobs.count, 2)
        XCTAssertEqual(queued.jobs.map(\.state), [.waiting, .waiting])
        XCTAssertEqual(
            queued.jobs.map { $0.workflow.externalSubtitleReview?.sourceTrackLanguageOverrides },
            [[1: "en"], [1: "es"]]
        )
        XCTAssertEqual(
            queued.jobs.map { $0.inputs.map(\.displayName) },
            [
                ["Movie1.en.mp4", "Movie1.fr.srt"],
                ["Movie2.es.mp4", "Movie2.de.srt"],
            ]
        )
        try WorkflowEvidence.record(
            "waiting-queue",
            facts: [
                "two_waiting_jobs": queued.jobs.map(\.state) == [.waiting, .waiting],
                "no_attempts_started": queued.jobs.allSatisfy { $0.attemptCount == 0 },
            ],
            explanation: QueuePresentation.summary(queued) + "\n"
                + queued.jobs.map { QueuePresentation.selectedJobDetail($0) }.joined(
                    separator: "\n"))
    }

    func testFlow13BatchChapterSuggestionsStayIndependentAndPreserveOriginals() throws {
        let firstSource = URL(fileURLWithPath: "/Media/Part One.mkv")
        let secondSource = URL(fileURLWithPath: "/Media/Part Two.mkv")
        let originals = [
            MatroskaChapterDocument(editions: [
                MatroskaChapterEdition(chapters: [
                    MatroskaChapterAtom(
                        start: .zero,
                        displays: [ChapterDisplay(title: "Chapter 1")]
                    )
                ])
            ]),
            MatroskaChapterDocument(),
        ]
        let selections = [
            [
                ChapterSuggestion(
                    time: MediaTime(nanoseconds: 10_000_000_000),
                    signals: [.sceneChange]
                )
            ],
            [
                ChapterSuggestion(
                    time: MediaTime(nanoseconds: 20_000_000_000),
                    signals: [.silence]
                )
            ],
        ]

        let results = try zip(originals, selections).map { original, suggestions in
            try ChapterSuggestionApplicator.apply(
                suggestions,
                to: original,
                mediaDuration: MediaTime(nanoseconds: 60_000_000_000)
            )
        }

        XCTAssertEqual(originals[0].chapterCount, 1)
        XCTAssertTrue(originals[1].editions.isEmpty)
        XCTAssertEqual(results.map(\.addedCount), [1, 1])
        XCTAssertEqual(results.map(\.document.chapterCount), [2, 1])
        XCTAssertEqual(
            results[0].document.editions[0].chapters.map(\.primaryTitle),
            ["Chapter 1", "Chapter 2"]
        )
        XCTAssertEqual(
            Set([
                OutputNamingPolicy.chaptersAddedFilename(for: firstSource),
                OutputNamingPolicy.chaptersAddedFilename(for: secondSource),
            ]).count,
            2
        )
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
        trackIDOffset: Int = 0,
        codecInitializationSHA256: String? = nil,
        colorInfo: MediaColorInfo? = MediaColorInfo(
            range: "tv",
            primaries: "bt709",
            transfer: "bt709",
            matrix: "bt709"
        )
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
                    codecInitializationDigest: codecInitializationSHA256.flatMap(
                        MediaCodecInitializationDigest.init(sha256:)
                    ),
                    uid: UInt64(100 + trackIDOffset),
                    language: "und",
                    title: "Main Video",
                    isDefault: true,
                    dimensions: MediaDimensions(width: 1_920, height: 1_080),
                    displayDimensions: MediaDimensions(width: 1_920, height: 1_080),
                    pixelFormat: "yuv420p",
                    bitDepth: 8,
                    frameRate: "24000/1001",
                    colorInfo: colorInfo
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
