import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

private enum InspectedAssetRevisionError: Error, LocalizedError {
    case changedDuringInspection

    var errorDescription: String? {
        "The media file changed while it was being inspected. Inspect it again."
    }
}

@MainActor
final class AppModel {
    private struct HistoryExecution: Sendable {
        let recorder: any JobHistoryRecording
        let jobID: UUID
    }

    private struct QueueExecution: Sendable {
        let recorder: any JobQueueManaging
        let jobID: UUID
        let sourceDisposition: MediaQueueSourceDisposition
    }

    private enum VerifiedEdit {
        case metadata(MatroskaMetadataEdit, workflowID: UUID, workflowName: String)
        case trackRemoval(TrackRemoval, workflowID: UUID, workflowName: String)
        case saved(CompiledSavedWorkflow, ExternalSubtitleMuxPayload?)
        case externalSubtitle(ExternalSubtitleFilePreview, ExternalSubtitleTrackMetadata)
        case embeddedSubtitle(EmbeddedSubtitleCleanupPreview, restoringIDs: Set<Int>)
        case chapters(ChapterEditPreview, MatroskaChapterDocument)

        var workflowID: UUID {
            switch self {
            case .metadata(_, let workflowID, _): workflowID
            case .trackRemoval(_, let workflowID, _): workflowID
            case .saved(let workflow, _): workflow.workflowID
            case .externalSubtitle: BuiltInWorkflowCatalog.externalSubtitleMux
            case .embeddedSubtitle: BuiltInWorkflowCatalog.embeddedSubtitleCleanup
            case .chapters: BuiltInWorkflowCatalog.chapterEdit
            }
        }

        var workflowName: String {
            switch self {
            case .metadata(_, _, let workflowName): workflowName
            case .trackRemoval(_, _, let workflowName): workflowName
            case .saved(let workflow, _): workflow.workflowName
            case .externalSubtitle(let preview, _):
                "Add external \(preview.format.displayName) subtitle"
            case .embeddedSubtitle(let preview, _):
                "Clean embedded \(preview.format.displayName) subtitle"
            case .chapters: "Edit Matroska chapters"
            }
        }

        var planningMessage: String {
            switch self {
            case .metadata:
                return "Zero video encodes; mkvpropedit on a verified clone."
            case .trackRemoval:
                return "Zero video encodes; mkvmerge copies the retained streams."
            case .saved(let workflow, _):
                if workflow.createsUnchangedCopy {
                    return "Zero encodes; create and verify one unchanged output copy."
                }
                let audioCount = workflow.plan.impact.audioEncodeCount
                guard workflow.plan.impact.videoEncodeCount > 0 else {
                    if audioCount > 0 {
                        let noun = audioCount == 1 ? "track" : "tracks"
                        return
                            "Zero video encodes; encode \(audioCount) mismatched audio \(noun) once while packet-copying video, matching audio, and subtitles."
                    }
                    return
                        "Zero video encodes; all enabled steps share one verified output pipeline."
                }
                guard audioCount > 0 else {
                    return "All video-affecting steps are fused into one encode."
                }
                let noun = audioCount == 1 ? "track" : "tracks"
                return
                    "One video generation and \(audioCount) audio \(noun) are fused into one FFmpeg process."
            case .externalSubtitle(let preview, _):
                return
                    "Zero encodes; normalize one temporary \(preview.format.displayName) and remux it as the last MKV track."
            case .embeddedSubtitle(let preview, _):
                return
                    "Zero encodes; replace one reviewed embedded \(preview.format.displayName) track at its original position in one verified remux."
            case .chapters(_, let document):
                return
                    "Zero encodes; replace the chapter document with \(document.chapterCount) reviewed nested entries on a verified clone."
            }
        }

        var runningMessage: String {
            switch self {
            case .metadata: return "Editing a temporary clone."
            case .trackRemoval: return "Remuxing retained tracks to a temporary output."
            case .saved(let workflow, _):
                if workflow.videoConversionChoice != nil {
                    let audioCount = workflow.plan.impact.audioEncodeCount
                    let audioNoun = audioCount == 1 ? "track" : "tracks"
                    let encoding =
                        audioCount == 0
                        ? "encoding video once"
                        : "encoding video once and \(audioCount) mismatched audio \(audioNoun) once"
                    return workflow.hasDeterministicMediaOperations
                        ? "Preparing one verified private remux, then \(encoding)."
                        : "\(encoding.prefix(1).uppercased())\(encoding.dropFirst()) while copying every retained subtitle."
                } else if workflow.audioConversionPreset != nil {
                    let audioCount = workflow.plan.impact.audioEncodeCount
                    let noun = audioCount == 1 ? "track" : "tracks"
                    return workflow.hasDeterministicMediaOperations
                        ? "Preparing one verified private remux, then encoding \(audioCount) mismatched audio \(noun) once."
                        : "Encoding \(audioCount) mismatched audio \(noun) once while packet-copying video, matching audio, and subtitles."
                } else if workflow.createsUnchangedCopy {
                    return "Creating one unchanged temporary clone."
                } else if workflow.trackRemoval == nil && workflow.externalSubtitleInput == nil {
                    return "Editing one temporary clone."
                } else {
                    return "Applying all workflow steps to one temporary remux."
                }
            case .externalSubtitle:
                return "Adding one reviewed subtitle to a temporary MKV remux."
            case .embeddedSubtitle:
                return "Replacing one reviewed embedded subtitle in a temporary MKV remux."
            case .chapters:
                return "Replacing chapters in one temporary MKV clone."
            }
        }

        var privacySafePlan: MediaJobPlanFacts {
            switch self {
            case .saved(let workflow, _):
                MediaJobPlanFacts(
                    videoEncodeGenerations: UInt(max(0, workflow.plan.impact.videoEncodeCount)),
                    audioTracksEncoded: UInt(max(0, workflow.plan.impact.audioEncodeCount))
                )
            default:
                MediaJobPlanFacts(videoEncodeGenerations: 0, audioTracksEncoded: 0)
            }
        }

        var externalInputURLs: [URL] {
            switch self {
            case .saved(_, let preview): preview.map { [$0.sourceURL] } ?? []
            case .externalSubtitle(let preview, _): [preview.sourceURL]
            default: []
            }
        }
    }

    enum State: Equatable {
        case ready
        case discovering
        case inspecting(String)
        case executing(String)
        case completed(String)
        case completedWithWarnings(String)
        case failed(String)
    }

    private(set) var assets: [MediaAsset] = []
    private(set) var state: State = .ready
    private(set) var activeQueueJobID: UUID?
    private var inspectedAssetRevisions = [UUID: MediaFileRevision]()
    var didChange: (() -> Void)?
    var queueDidChange: (() -> Void)?
    private var cachedEncodingCapabilities: FFmpegEncodingCapabilities?
    private let historyRecorderFactory: @Sendable () throws -> any JobHistoryRecording
    private let workflowStoreFactory: @Sendable () throws -> any SavedWorkflowPersisting
    private let queueStoreFactory: @Sendable () throws -> any JobQueueManaging
    private let queueEnvironmentReader: any MediaQueueSchedulingEnvironmentReading
    private let trashSource: (URL) throws -> Void
    private var queueStore: (any JobQueueManaging)?
    private var queueAdmissionCoordinator: MediaQueueAdmissionCoordinator?
    private var queueRecoveryStarted = false
    private let encodingBenchmarkStoreFactory:
        @Sendable () throws -> any EncodingBenchmarkPersisting

    init(
        historyRecorderFactory: @escaping @Sendable () throws -> any JobHistoryRecording = {
            try AppHistoryLocation.makeStore()
        },
        workflowStoreFactory: @escaping @Sendable () throws -> any SavedWorkflowPersisting = {
            try AppHistoryLocation.makeWorkflowStore()
        },
        queueStoreFactory: @escaping @Sendable () throws -> any JobQueueManaging = {
            try AppHistoryLocation.makeQueueStore()
        },
        queueEnvironmentReader: any MediaQueueSchedulingEnvironmentReading =
            SystemMediaQueueSchedulingEnvironmentReader(),
        trashSource: @escaping (URL) throws -> Void = { sourceURL in
            _ = try FileManager.default.trashItem(at: sourceURL, resultingItemURL: nil)
        },
        encodingBenchmarkStoreFactory:
            @escaping @Sendable () throws -> any EncodingBenchmarkPersisting = {
                try AppHistoryLocation.makeEncodingBenchmarkStore()
            }
    ) {
        self.historyRecorderFactory = historyRecorderFactory
        self.workflowStoreFactory = workflowStoreFactory
        self.queueStoreFactory = queueStoreFactory
        self.queueEnvironmentReader = queueEnvironmentReader
        self.trashSource = trashSource
        self.encodingBenchmarkStoreFactory = encodingBenchmarkStoreFactory
    }

    func loadEncodingBenchmarkReport() async throws -> EncodingBenchmarkReport? {
        let catalog = try makeToolCatalog()
        let environment = try encodingBenchmarkEnvironment(catalog: catalog)
        let report: EncodingBenchmarkReport?
        do {
            report = try await encodingBenchmarkStoreFactory().load()
        } catch {
            // A stale or damaged optional recommendation must not block the user
            // from opening Encoding Test and replacing it with a valid report.
            return nil
        }
        guard let report,
            report.matches(environment)
        else {
            return nil
        }
        return report
    }

    func runEncodingBenchmark() async throws -> EncodingBenchmarkReport {
        let capabilities = await probeEncodingCapabilities()
        state = .executing(
            "Testing bundled AV1 and HEVC with a private synthetic clip…"
        )
        didChange?()
        do {
            let catalog = try makeToolCatalog()
            let report = try await FFmpegEncodingBenchmark(
                ffmpegURL: try catalog.url(for: .ffmpeg),
                runner: FoundationCommandRunner()
            ).run(
                capabilities: capabilities,
                environment: try encodingBenchmarkEnvironment(catalog: catalog)
            )
            try await encodingBenchmarkStoreFactory().save(report)
            cachedEncodingCapabilities = capabilities.preferring(report.recommendedPreset)
            state = .completed(
                "Encoding test complete; \(report.recommendedPreset.displayName) is recommended."
            )
            didChange?()
            return report
        } catch let error as CommandRunnerError where error == .cancelled {
            state = .ready
            didChange?()
            throw error
        } catch is CancellationError {
            state = .ready
            didChange?()
            throw CancellationError()
        } catch {
            state = .failed(
                UserFacingErrorPresentation.message(
                    failure: "Could not complete the encoding test.",
                    recovery: "The previous recommendation is unchanged; try the test again.",
                    error: error
                )
            )
            didChange?()
            throw error
        }
    }

    func loadHistory() async throws -> [MediaJobRecord] {
        try await historyRecorderFactory().load()
    }

    func loadQueue() async throws -> MediaQueueSnapshot {
        let recorder = try queueRecorder()
        if queueRecoveryStarted {
            return await recoverPendingSourceDispositions(in: try await recorder.load())
        }
        queueRecoveryStarted = true
        do {
            let snapshot = try await recorder.recoverInterruptedJobs(at: Date())
            return await recoverPendingSourceDispositions(in: snapshot)
        } catch {
            queueRecoveryStarted = false
            throw error
        }
    }

    func setQueuePaused(_ paused: Bool) async throws -> MediaQueueSnapshot {
        let snapshot = try await queueRecorder().setPaused(paused, at: Date())
        queueDidChange?()
        if !paused {
            Task { [weak self] in
                await self?.runAutomaticQueueCycleIfEligible()
            }
        }
        return snapshot
    }

    func transitionQueueJob(
        _ jobID: UUID,
        to state: MediaQueueJobState,
        reason: MediaQueueEventReason? = .userAction
    ) async throws -> MediaQueueSnapshot {
        let snapshot = try await queueRecorder().transition(
            jobID: jobID,
            to: state,
            at: Date(),
            reason: reason
        )
        queueDidChange?()
        return snapshot
    }

    func reorderPendingQueueJobs(_ orderedIDs: [UUID]) async throws -> MediaQueueSnapshot {
        let snapshot = try await queueRecorder().reorderPending(orderedIDs, at: Date())
        queueDidChange?()
        return snapshot
    }

    func resolvePrimaryQueueInput(_ job: MediaQueueJob) throws -> URL {
        guard let input = job.inputs.first else {
            throw JobQueueStoreError.malformedQueue
        }
        let access: SecurityScopedBookmarkAccess =
            job.sourceDisposition == .trashAfterVerifiedSuccess
            ? .readWriteFile : .readOnlyFile
        return try SecurityScopedBookmarkCodec().resolve(input, access: access)
    }

    func runAutomaticQueueCycle() async throws -> MediaQueueSnapshot {
        _ = try await loadQueue()
        let coordinator = try automaticQueueCoordinator()
        let report = try await coordinator.runCycle(
            environment: queueEnvironmentReader.read(),
            supports: MediaQueueAutomaticWorkflowPolicy.supports,
            execute: { [weak self] admission in
                guard let self else { throw CancellationError() }
                return try await self.executeAutomaticQueueAdmission(admission)
            }
        )
        let recovered = await recoverPendingSourceDispositions(in: report.snapshot)
        queueDidChange?()
        return recovered
    }

    func runAutomaticQueueCycleIfEligible() async {
        do {
            _ = try await runAutomaticQueueCycle()
        } catch MediaQueueAdmissionCoordinatorError.cycleAlreadyRunning {
            return
        } catch {
            state = .completedWithWarnings(
                UserFacingErrorPresentation.message(
                    failure: "Could not start eligible queued work.",
                    recovery:
                        "The queue remains saved; reopen or resume it, or add another job, to retry.",
                    error: error
                )
            )
            didChange?()
        }
    }

    func cancelAutomaticQueueJob(_ jobID: UUID) async {
        await queueAdmissionCoordinator?.cancel(jobID: jobID)
    }

    func exportPrivacySafeSupportReport(
        records: [MediaJobRecord],
        to destinationURL: URL
    ) async throws {
        let toolRootURL = try resolveToolRootURL()
        let applicationVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "development"
        let applicationBuild =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "development"
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        try await Task.detached(priority: .utility) {
            let catalog = try ToolCatalog(rootURL: toolRootURL)
            let report = PrivacySafeSupportReport.make(
                applicationVersion: applicationVersion,
                applicationBuild: applicationBuild,
                operatingSystem: operatingSystem,
                catalog: catalog,
                records: records
            )
            try PrivacySafeSupportReportWriter.write(report, to: destinationURL)
        }.value
    }

    func loadWorkflows() async throws -> [SavedWorkflow] {
        try await workflowStoreFactory().load()
    }

    func saveWorkflows(_ workflows: [SavedWorkflow]) async throws {
        try await workflowStoreFactory().save(workflows)
    }

    func reviewedSourceRevision(for asset: MediaAsset) -> MediaFileRevision? {
        guard let revision = inspectedAssetRevisions[asset.id],
            (try? MediaFileRevisionReader().read(asset.sourceURL)) == revision
        else {
            return nil
        }
        return revision
    }

    func previewSubtitleCleanup(at sourceURL: URL) async throws -> SubtitleCleanupFilePreview {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        return try await SubtitleCleanupExecutor().preview(sourceURL: sourceURL)
    }

    func previewAdvancedSubtitleCleanup(
        at sourceURL: URL
    ) async throws -> AdvancedSubtitleCleanupFilePreview {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        return try await AdvancedSubtitleCleanupExecutor().preview(sourceURL: sourceURL)
    }

    func previewEmbeddedSubtitleCleanup(
        in source: MediaAsset,
        trackUID: UInt64
    ) async throws -> EmbeddedSubtitleCleanupPreview {
        let accessed = source.sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.sourceURL.stopAccessingSecurityScopedResource() }
        }
        let catalog = try makeToolCatalog()
        let runner = FoundationCommandRunner()
        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        return try await EmbeddedSubtitleCleanupExecutor(
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            mkvextractURL: try catalog.url(for: .mkvextract),
            ffprobeURL: try catalog.url(for: .ffprobe),
            runner: runner,
            inspector: inspector
        ).preview(source: source, trackUID: trackUID)
    }

    func previewChapters(in source: MediaAsset) async throws -> ChapterEditPreview {
        let accessed = source.sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.sourceURL.stopAccessingSecurityScopedResource() }
        }
        let catalog = try makeToolCatalog()
        let runner = FoundationCommandRunner()
        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        return try await ChapterEditExecutor(
            mkvextractURL: try catalog.url(for: .mkvextract),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        ).preview(source: source)
    }

    func loadLosslessJoinSourceOptions(
        _ sources: [MediaAsset]
    ) async throws -> [LosslessJoinSourceOption] {
        guard sources.count >= 2 else { throw JoinTrackMappingError.invalidSourceCount }
        let scopedURLs = sources.map {
            ($0.sourceURL, $0.sourceURL.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, accessed) in scopedURLs where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        state = .executing("Reading exact nested chapters for the join review…")
        didChange?()
        do {
            let catalog = try makeToolCatalog()
            let runner = FoundationCommandRunner()
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let executor = ChapterEditExecutor(
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            var options = [LosslessJoinSourceOption]()
            options.reserveCapacity(sources.count)
            for source in sources {
                state = .executing(
                    "Reading chapters from \(source.sourceURL.lastPathComponent)…"
                )
                didChange?()
                options.append(
                    LosslessJoinSourceOption(
                        chapterPreview: try await executor.preview(source: source)
                    )
                )
            }
            state = .ready
            didChange?()
            return options
        } catch {
            state = .failed(
                UserFacingErrorPresentation.message(
                    failure: "Could not prepare the join review.",
                    recovery: "No output was created; review the selected files and try again.",
                    error: error
                )
            )
            didChange?()
            throw error
        }
    }

    func probeEncodingCapabilities() async -> FFmpegEncodingCapabilities {
        if let cachedEncodingCapabilities { return cachedEncodingCapabilities }
        state = .executing("Checking which bundled encoders work on this Mac…")
        didChange?()
        do {
            let catalog = try makeToolCatalog()
            var capabilities = try await FFmpegCapabilityProbe(
                ffmpegURL: try catalog.url(for: .ffmpeg),
                runner: FoundationCommandRunner()
            ).probe()
            if let report = try? await encodingBenchmarkStoreFactory().load(),
                report.matches(try encodingBenchmarkEnvironment(catalog: catalog))
            {
                capabilities = capabilities.preferring(report.recommendedPreset)
            }
            cachedEncodingCapabilities = capabilities
            state = .ready
            didChange?()
            return capabilities
        } catch {
            state = .ready
            didChange?()
            return .unavailable
        }
    }

    func previewLosslessJoin(
        _ candidate: LosslessJoinCandidate
    ) async throws -> LosslessJoinPreview {
        let scopedURLs = candidate.sources.map {
            ($0.sourceURL, $0.sourceURL.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, accessed) in scopedURLs where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        state = .executing("Confirming that every reviewed source is unchanged…")
        didChange?()
        do {
            guard candidate.sources.count == candidate.chapterPreviews.count else {
                throw LosslessJoinExecutionError.staleSource
            }
            let currentReport = try JoinCompatibilityAnalyzer().analyze(
                sources: candidate.sources,
                mapping: candidate.mapping
            )
            guard currentReport == candidate.report,
                currentReport.disposition == .losslessCandidate
            else {
                throw LosslessJoinExecutionError.requiresReview(currentReport.disposition)
            }

            let catalog = try makeToolCatalog()
            let runner = FoundationCommandRunner()
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let chapterExecutor = ChapterEditExecutor(
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            for preview in candidate.chapterPreviews {
                try await chapterExecutor.validateCurrent(preview)
            }
            let executor = LosslessJoinExecutor(
                ffmpegURL: try catalog.url(for: .ffmpeg),
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                mkvextractURL: try catalog.url(for: .mkvextract),
                runner: runner,
                inspector: inspector
            )
            let preview = try executor.preview(
                sources: candidate.sources,
                mapping: candidate.mapping,
                chapters: candidate.chapters
            )
            for (joinRevision, chapterPreview) in zip(
                preview.sourceRevisions,
                candidate.chapterPreviews
            ) {
                let chapterRevision = chapterPreview.sourceRevision
                guard joinRevision.fileSize == chapterRevision.fileSize,
                    joinRevision.modificationDate == chapterRevision.modificationDate,
                    joinRevision.fileNumber == chapterRevision.fileNumber,
                    joinRevision.systemNumber == chapterRevision.systemNumber
                else {
                    throw LosslessJoinExecutionError.staleSource
                }
            }
            state = .ready
            didChange?()
            return preview
        } catch {
            state = .failed(
                UserFacingErrorPresentation.message(
                    failure: "Could not confirm the lossless join.",
                    recovery: "No output was created; reopen Join and review every source again.",
                    error: error
                )
            )
            didChange?()
            throw error
        }
    }

    func previewCommonFormatJoin(
        _ candidate: CommonFormatJoinCandidate,
        resolvedPlan: ResolvedJoinNormalizationPlan
    ) async throws -> CommonFormatJoinPreview {
        let scopedURLs = candidate.sources.map {
            ($0.sourceURL, $0.sourceURL.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, accessed) in scopedURLs where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        state = .executing("Binding every approved common-format choice to unchanged files…")
        didChange?()
        do {
            guard candidate.sources.count == candidate.chapterPreviews.count,
                resolvedPlan.proposal == candidate.proposal
            else {
                throw JoinNormalizationChoiceError.reportChanged
            }
            let currentReport = try JoinCompatibilityAnalyzer().analyze(
                sources: candidate.sources,
                mapping: candidate.mapping
            )
            guard currentReport == candidate.report,
                currentReport.disposition == .normalizationRequired
            else {
                throw JoinNormalizationChoiceError.reportChanged
            }

            let resolved = try JoinNormalizationChoiceResolver().resolve(
                sources: candidate.sources,
                proposal: candidate.proposal,
                choices: resolvedPlan.choices,
                availableVideoPresets: Set(candidate.capabilities.availableVideoPresets),
                aacAvailable: candidate.capabilities.aac == .verified,
                availableAudioPresets: Set(candidate.capabilities.availableAudioPresets)
            )
            let catalog = try makeToolCatalog()
            let runner = FoundationCommandRunner()
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let chapterExecutor = ChapterEditExecutor(
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            for preview in candidate.chapterPreviews {
                try await chapterExecutor.validateCurrent(preview)
            }
            let normalizationPreview = try JoinNormalizationExecutor(
                ffmpegURL: try catalog.url(for: .ffmpeg),
                runner: runner,
                inspector: inspector
            ).preview(
                sources: candidate.sources,
                resolvedPlan: resolved,
                capabilities: candidate.capabilities
            )
            state = .ready
            didChange?()
            return CommonFormatJoinPreview(
                candidate: candidate,
                resolvedPlan: resolved,
                normalizationPreview: normalizationPreview
            )
        } catch {
            state = .failed(
                UserFacingErrorPresentation.message(
                    failure: "Could not confirm the common-format join.",
                    recovery: "No output was created; reopen Join and review every choice again.",
                    error: error
                )
            )
            didChange?()
            throw error
        }
    }

    @discardableResult
    func executeCommonFormatJoin(
        preview: CommonFormatJoinPreview,
        destinationURL: URL,
        onStage: @escaping @MainActor @Sendable (CommonFormatJoinExecutionStage) -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        let sources = preview.candidate.sources
        let scopedURLs = (sources.map(\.sourceURL) + [destinationURL]).map {
            ($0, $0.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, accessed) in scopedURLs where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        state = .executing("Normalizing only the incompatible lanes once…")
        didChange?()
        var historyExecution: HistoryExecution?
        do {
            let proposal = preview.resolvedPlan.proposal
            let execution = try await beginHistory(
                inputs: sources.map(Self.historyInput),
                outputDisplayName: destinationURL.lastPathComponent,
                workflowID: BuiltInWorkflowCatalog.commonFormatJoin,
                workflowName: "Join MKV files with one normalization pass",
                privacySafePlan: MediaJobPlanFacts(
                    videoEncodeGenerations: UInt(max(0, proposal.impact.videoEncodeCount)),
                    audioTracksEncoded: UInt(max(0, proposal.impact.audioEncodeCount))
                ),
                inspectionMessage:
                    "Used completed inspections and exact extracted nested chapter documents.",
                planningMessage:
                    "Normalize \(proposal.impact.videoEncodeCount) video generation and \(proposal.impact.audioEncodeCount) audio lane(s) once; packet-copy compatible lanes.",
                runningMessage:
                    "Creating one private verified normalized stream bundle before final assembly."
            )
            historyExecution = execution
            let catalog = try makeToolCatalog()
            let runner = FoundationCommandRunner()
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let output = try await CommonFormatJoinExecutor(
                ffmpegURL: try catalog.url(for: .ffmpeg),
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                mkvextractURL: try catalog.url(for: .mkvextract),
                runner: runner,
                inspector: inspector
            ).execute(
                normalizationPreview: preview.normalizationPreview,
                resolvedPlan: preview.resolvedPlan,
                chapters: preview.candidate.chapters,
                destinationURL: destinationURL,
                onStage: { stage in
                    await onStage(stage)
                    if stage == .assembling {
                        await MainActor.run {
                            self.state = .executing(
                                "Assembling normalized and packet-copy lanes into the final MKV…"
                            )
                            self.didChange?()
                        }
                    }
                    switch stage {
                    case .verifying:
                        try await Self.record(
                            .verifying,
                            jobID: execution.jobID,
                            using: execution.recorder
                        )
                    case .committing:
                        try await Self.record(
                            .committing,
                            jobID: execution.jobID,
                            using: execution.recorder
                        )
                    case .normalizing, .assembling:
                        break
                    }
                }
            )
            registerInspectedAsset(output)
            await finishHistory(
                execution,
                destinationURL: destinationURL,
                successMessage:
                    "Verified the one-pass normalized lanes, exact copied packet payloads, every join boundary, metadata, attachments, and nested chapters; committed and reopened output."
            )
            return output
        } catch {
            if Self.isCancellation(error) {
                await cancelHistory(historyExecution)
            } else {
                await failHistory(historyExecution, error: error)
            }
            throw error
        }
    }

    @discardableResult
    func executeLosslessJoin(
        preview: LosslessJoinPreview,
        destinationURL: URL,
        onStage: @escaping @MainActor @Sendable (VerifiedOutputExecutionStage) -> Void = { _ in }
    ) async throws -> MediaAsset {
        let scopedURLs = (preview.sources.map(\.sourceURL) + [destinationURL]).map {
            ($0, $0.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, accessed) in scopedURLs where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        state = .executing("Joining complete files without re-encoding…")
        didChange?()
        var historyExecution: HistoryExecution?
        do {
            let execution = try await beginHistory(
                inputs: preview.sources.map(Self.historyInput),
                outputDisplayName: destinationURL.lastPathComponent,
                workflowID: BuiltInWorkflowCatalog.losslessJoin,
                workflowName: "Join MKV files losslessly",
                privacySafePlan: MediaJobPlanFacts(
                    videoEncodeGenerations: 0,
                    audioTracksEncoded: 0
                ),
                inspectionMessage:
                    "Used exact completed inspections and extracted nested chapter documents.",
                planningMessage:
                    "Zero encodes; every complete source track maps to one reviewed append lane.",
                runningMessage:
                    "Appending complete MKV files to one temporary output with reviewed chapters."
            )
            historyExecution = execution
            let catalog = try makeToolCatalog()
            let runner = FoundationCommandRunner()
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let executor = LosslessJoinExecutor(
                ffmpegURL: try catalog.url(for: .ffmpeg),
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                mkvextractURL: try catalog.url(for: .mkvextract),
                runner: runner,
                inspector: inspector
            )
            let output = try await executor.execute(
                preview: preview,
                destinationURL: destinationURL,
                onStage: { [weak self] stage in
                    await onStage(stage)
                    await MainActor.run {
                        guard let self else { return }
                        switch stage {
                        case .verifying:
                            self.state = .executing(
                                "Verifying copied packet payloads, every join boundary, tracks, and chapters…"
                            )
                        case .committing:
                            self.state = .executing(
                                "Saving and reopening the verified joined MKV…"
                            )
                        }
                        self.didChange?()
                    }
                    try await Self.record(
                        stage,
                        jobID: execution.jobID,
                        using: execution.recorder
                    )
                }
            )
            registerInspectedAsset(output)
            await finishHistory(
                execution,
                destinationURL: destinationURL,
                successMessage:
                    "Verified exact copied packet payloads, every join boundary, tracks, and nested chapters; committed and reopened output."
            )
            return output
        } catch {
            if Self.isCancellation(error) {
                await cancelHistory(historyExecution)
            } else {
                await failHistory(historyExecution, error: error)
            }
            throw error
        }
    }

    @discardableResult
    func executeTrim(
        preview: TrimExecutionPreview,
        destinationURL: URL,
        onStage: @escaping @MainActor @Sendable (VerifiedOutputExecutionStage) -> Void = { _ in }
    ) async throws -> MediaAsset {
        let source = preview.source
        let scopedURLs = [source.sourceURL, destinationURL].map {
            ($0, $0.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, accessed) in scopedURLs where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        state = .executing(
            preview.operation == .transcode
                ? "Converting the complete video with one video encode…"
                : preview.videoEncodeCount == 0
                    ? "Fast trimming without encoding…"
                    : "Exact trimming with one video encode…"
        )
        didChange?()
        var historyExecution: HistoryExecution?
        do {
            let planningMessage: String
            let runningMessage: String
            let workflowID: UUID
            let privacySafePlan: MediaJobPlanFacts
            switch preview {
            case .fast(let fast):
                workflowID = BuiltInWorkflowCatalog.fastTrim
                privacySafePlan = MediaJobPlanFacts(
                    videoEncodeGenerations: 0,
                    audioTracksEncoded: 0
                )
                planningMessage =
                    "Zero encodes; copy every stream at reviewed keyframes "
                    + "\(ChapterTimestamp.format(fast.plan.adjusted.start, digits: 3))–"
                    + ChapterTimestamp.format(fast.plan.adjusted.end, digits: 3) + "."
                runningMessage =
                    "Splitting one temporary MKV at reviewed keyframes and replacing chapters."
            case .exact(let exact):
                workflowID =
                    exact.resolvedPlan.operation == .transcode
                    ? BuiltInWorkflowCatalog.videoTranscode : BuiltInWorkflowCatalog.exactTrim
                privacySafePlan = MediaJobPlanFacts(
                    videoEncodeGenerations: UInt(max(0, preview.videoEncodeCount)),
                    audioTracksEncoded: UInt(exact.encodedAudioTrackIDs.count)
                )
                let audio =
                    exact.resolvedPlan.choice.audioPolicy.transcodePreset.map {
                        "encode \(exact.encodedAudioTrackIDs.count) audio track(s) once to \($0.displayName)"
                    } ?? "packet-copy every audio track"
                let video = TrimPresentationPolicy.presetName(
                    exact.resolvedPlan.choice.videoPreset
                )
                if exact.resolvedPlan.operation == .transcode {
                    planningMessage =
                        "One video encode using \(video); \(audio); preserve the complete "
                        + "duration and exact nested chapters."
                    runningMessage =
                        "Encoding the complete video once to one temporary MKV and preserving chapters."
                } else {
                    planningMessage =
                        "One video encode using \(video); \(audio); preserve the exact reviewed range."
                    runningMessage =
                        "Encoding video once to one temporary MKV and replacing exact chapters."
                }
            }
            let execution = try await beginHistory(
                inputs: [Self.historyInput(source)],
                outputDisplayName: destinationURL.lastPathComponent,
                workflowID: workflowID,
                workflowName: preview.workflowName,
                privacySafePlan: privacySafePlan,
                inspectionMessage:
                    "Used the completed inspection plus exact extracted nested chapters.",
                planningMessage: planningMessage,
                runningMessage: runningMessage
            )
            historyExecution = execution
            let catalog = try makeToolCatalog()
            let runner = FoundationCommandRunner()
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let output: MediaAsset
            switch preview {
            case .fast(let fast):
                output = try await FastTrimExecutor(
                    ffprobeURL: try catalog.url(for: .ffprobe),
                    mkvmergeURL: try catalog.url(for: .mkvmerge),
                    mkvextractURL: try catalog.url(for: .mkvextract),
                    mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                    runner: runner,
                    inspector: inspector
                ).execute(
                    preview: fast,
                    destinationURL: destinationURL,
                    onStage: { stage in
                        await onStage(stage)
                        try await Self.record(
                            stage,
                            jobID: execution.jobID,
                            using: execution.recorder
                        )
                    }
                )
            case .exact(let exact):
                output = try await ExactTrimExecutor(
                    ffmpegURL: try catalog.url(for: .ffmpeg),
                    ffprobeURL: try catalog.url(for: .ffprobe),
                    mkvextractURL: try catalog.url(for: .mkvextract),
                    mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                    runner: runner,
                    inspector: inspector
                ).execute(
                    preview: exact,
                    destinationURL: destinationURL,
                    onStage: { stage in
                        await onStage(stage)
                        try await Self.record(
                            stage,
                            jobID: execution.jobID,
                            using: execution.recorder
                        )
                    }
                )
            }
            registerInspectedAsset(output)
            await finishHistory(
                execution,
                destinationURL: destinationURL,
                successMessage:
                    preview.operation == .transcode
                    ? "Verified converted video, complete duration, streams, metadata, attachments, and unchanged nested chapters; committed and reopened output."
                    : "Verified trimmed range, streams, metadata, attachments, and exact nested chapters; committed and reopened output."
            )
            return output
        } catch {
            if Self.isCancellation(error) {
                await cancelHistory(historyExecution)
            } else {
                await failHistory(historyExecution, error: error)
            }
            throw error
        }
    }

    func suggestChapters(
        in source: MediaAsset,
        existingChapterStarts: [MediaTime],
        options: ChapterSuggestionOptions
    ) async throws -> [ChapterSuggestion] {
        let accessed = source.sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.sourceURL.stopAccessingSecurityScopedResource() }
        }
        let catalog = try makeToolCatalog()
        return try await FFmpegChapterSuggestionAnalyzer(
            ffmpegURL: try catalog.url(for: .ffmpeg),
            runner: FoundationCommandRunner()
        ).analyze(
            source: source,
            existingChapterStarts: existingChapterStarts,
            options: options
        )
    }

    func chapterThumbnails(
        in source: MediaAsset,
        at times: [MediaTime],
        expectedSourceRevision: ChapterSourceRevision? = nil
    ) async throws -> [ChapterThumbnail] {
        let accessed = source.sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.sourceURL.stopAccessingSecurityScopedResource() }
        }
        let catalog = try makeToolCatalog()
        return try await FFmpegChapterThumbnailGenerator(
            ffmpegURL: try catalog.url(for: .ffmpeg),
            runner: FoundationCommandRunner()
        ).generate(
            source: source,
            times: times,
            expectedSourceRevision: expectedSourceRevision
        )
    }

    func previewTrim(
        in source: MediaAsset,
        request: TrimReviewRequest,
        capabilities: FFmpegEncodingCapabilities
    ) async throws -> TrimExecutionPreview {
        let accessed = source.sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.sourceURL.stopAccessingSecurityScopedResource() }
        }
        state = .executing(
            request.operation == .transcode
                ? "Binding the complete file, encoder, streams, and nested chapters…"
                : request.mode == .fast
                    ? "Reading exact keyframes and nested chapters…"
                    : "Binding the exact range, encoder, streams, and nested chapters…"
        )
        didChange?()
        do {
            let catalog = try makeToolCatalog()
            let runner = FoundationCommandRunner()
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let preview: TrimExecutionPreview
            switch request.mode {
            case .fast:
                guard request.operation == .trim else {
                    throw ExactTrimPlanningError.invalidChoice
                }
                preview = .fast(
                    try await FastTrimExecutor(
                        ffprobeURL: try catalog.url(for: .ffprobe),
                        mkvmergeURL: try catalog.url(for: .mkvmerge),
                        mkvextractURL: try catalog.url(for: .mkvextract),
                        mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                        runner: runner,
                        inspector: inspector
                    ).preview(
                        source: source,
                        requestedRange: request.range
                    )
                )
            case .exact:
                guard let choice = request.exactChoice else {
                    throw ExactTrimPlanningError.invalidChoice
                }
                preview = .exact(
                    try await ExactTrimExecutor(
                        ffmpegURL: try catalog.url(for: .ffmpeg),
                        ffprobeURL: try catalog.url(for: .ffprobe),
                        mkvextractURL: try catalog.url(for: .mkvextract),
                        mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                        runner: runner,
                        inspector: inspector
                    ).preview(
                        source: source,
                        range: request.range,
                        choice: choice,
                        operation: request.operation,
                        capabilities: capabilities
                    )
                )
            }
            state = .ready
            didChange?()
            return preview
        } catch {
            state = .failed(
                UserFacingErrorPresentation.message(
                    failure:
                        request.operation == .transcode
                        ? "Could not prepare the conversion review."
                        : "Could not prepare the trim review.",
                    recovery:
                        request.operation == .transcode
                        ? "No output was created; reopen Convert Video and review the source and formats."
                        : "No output was created; reopen Trim and review the source and boundaries.",
                    error: error
                )
            )
            didChange?()
            throw error
        }
    }

    func addFiles(_ urls: [URL]) async {
        let uniqueRoots = Array(Set(urls.map(\.standardizedFileURL))).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        guard !uniqueRoots.isEmpty else { return }

        let scopedRoots = uniqueRoots.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer {
            for (url, accessed) in scopedRoots where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        state = .discovering
        didChange?()
        let inputURLs: [URL]
        do {
            inputURLs = try await LocalMediaFileDiscovery().discover(uniqueRoots)
        } catch {
            state = .failed(
                UserFacingErrorPresentation.message(
                    failure: "Could not scan the selected files.",
                    recovery:
                        "Nothing was added; choose accessible files or folders and try again.",
                    error: error
                )
            )
            didChange?()
            return
        }
        guard !inputURLs.isEmpty else {
            state = .failed("No supported media or subtitle files were found.")
            didChange?()
            return
        }

        let inspector: UnifiedMediaInspector<FoundationCommandRunner>
        do {
            let catalog = try makeToolCatalog()
            inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: FoundationCommandRunner()
            )
        } catch {
            state = .failed(
                "This development build has no verified tool bundle. Package the app or set "
                    + "MKV_MAGIC_TOOL_ROOT to an explicit manifest-backed tool directory."
            )
            didChange?()
            return
        }

        var failures = [String]()
        for url in inputURLs {
            state = .inspecting(url.lastPathComponent)
            didChange?()
            do {
                let revision = try MediaFileRevisionReader().read(url)
                let asset = try await inspector.inspect(url)
                guard (try? MediaFileRevisionReader().read(url)) == revision,
                    asset.fileSize == nil || asset.fileSize == revision.fileSize
                else {
                    throw InspectedAssetRevisionError.changedDuringInspection
                }
                registerInspectedAsset(asset, revision: revision)
            } catch {
                let message = UserFacingErrorPresentation.message(
                    failure: "Could not inspect \(url.lastPathComponent).",
                    recovery:
                        "That file was skipped; select it again after checking access and format.",
                    error: error
                )
                failures.append(message)
                state = .failed(message)
                didChange?()
                continue
            }
        }
        if let lastFailure = failures.last {
            state = .completedWithWarnings(
                "Inspected \(inputURLs.count - failures.count) of \(inputURLs.count) files. "
                    + lastFailure
            )
        } else {
            state = .ready
        }
        didChange?()
    }

    @discardableResult
    func editSegmentTitle(
        in asset: MediaAsset,
        title: String?,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await executeVerifiedEdit(
            in: asset,
            destinationURL: destinationURL,
            edit: .metadata(
                .segmentTitle(title),
                workflowID: BuiltInWorkflowCatalog.segmentTitle,
                workflowName: "Edit segment title"
            )
        )
    }

    @discardableResult
    func editTrackMetadata(
        in asset: MediaAsset,
        edit: TrackMetadataEdit,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await executeVerifiedEdit(
            in: asset,
            destinationURL: destinationURL,
            edit: .metadata(
                .track(edit),
                workflowID: BuiltInWorkflowCatalog.trackMetadata,
                workflowName: "Edit track metadata"
            )
        )
    }

    @discardableResult
    func removeTracks(
        in asset: MediaAsset,
        removal: TrackRemoval,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await executeVerifiedEdit(
            in: asset,
            destinationURL: destinationURL,
            edit: .trackRemoval(
                removal,
                workflowID: BuiltInWorkflowCatalog.trackRemoval,
                workflowName: "Remove tracks"
            )
        )
    }

    @discardableResult
    func cleanEnglishLibrary(
        in asset: MediaAsset,
        removal: TrackRemoval,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await executeVerifiedEdit(
            in: asset,
            destinationURL: destinationURL,
            edit: .trackRemoval(
                removal,
                workflowID: BuiltInWorkflowCatalog.englishLibraryCleanup,
                workflowName: "English Library Cleanup"
            )
        )
    }

    @discardableResult
    func runSavedWorkflow(
        _ workflow: CompiledSavedWorkflow,
        externalSubtitlePreview: ExternalSubtitleFilePreview? = nil,
        in asset: MediaAsset,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await executeVerifiedEdit(
            in: asset,
            destinationURL: destinationURL,
            edit: .saved(workflow, externalSubtitlePreview.map(ExternalSubtitleMuxPayload.original))
        )
    }

    func enqueueSavedWorkflow(
        _ workflow: CompiledSavedWorkflow,
        recipe: SavedWorkflow,
        sourceDisposition: MediaQueueSourceDisposition = .keepOriginal,
        retryingQueueJobID: UUID? = nil,
        expectedSourceRevision: MediaFileRevision? = nil,
        in asset: MediaAsset,
        destinationURL: URL
    ) async throws -> MediaQueueSnapshot {
        guard workflow.externalSubtitleInput == nil else {
            throw JobQueueStoreError.malformedQueue
        }
        if let expectedSourceRevision,
            (try? MediaFileRevisionReader().read(asset.sourceURL)) != expectedSourceRevision
        {
            throw SavedWorkflowExecutionError.sourceChangedSinceReview
        }
        let execution = try await prepareQueueExecution(
            recipe: recipe,
            plan: workflow.plan,
            inputURLs: [asset.sourceURL],
            destinationURL: destinationURL,
            sourceDisposition: sourceDisposition,
            retryingJobID: retryingQueueJobID
        )
        queueDidChange?()
        return try await execution.recorder.load()
    }

    @discardableResult
    func runSavedWorkflow(
        _ workflow: CompiledSavedWorkflow,
        externalSubtitlePayload: ExternalSubtitleMuxPayload?,
        in asset: MediaAsset,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await executeVerifiedEdit(
            in: asset,
            destinationURL: destinationURL,
            edit: .saved(workflow, externalSubtitlePayload)
        )
    }

    @discardableResult
    func runSavedWorkflow(
        _ workflow: CompiledSavedWorkflow,
        recipe: SavedWorkflow,
        externalSubtitlePayload: ExternalSubtitleMuxPayload?,
        sourceDisposition: MediaQueueSourceDisposition = .keepOriginal,
        retryingQueueJobID: UUID? = nil,
        expectedSourceRevision: MediaFileRevision? = nil,
        in asset: MediaAsset,
        destinationURL: URL
    ) async throws -> MediaAsset {
        let externalURLs = externalSubtitlePayload.map { [$0.sourceURL] } ?? []
        let queueExecution = try await beginQueueExecution(
            recipe: recipe,
            plan: workflow.plan,
            inputURLs: [asset.sourceURL] + externalURLs,
            destinationURL: destinationURL,
            sourceDisposition: sourceDisposition,
            retryingJobID: retryingQueueJobID
        )
        return try await executeVerifiedEdit(
            in: asset,
            destinationURL: destinationURL,
            edit: .saved(workflow, externalSubtitlePayload),
            queueExecution: queueExecution,
            expectedSourceRevision: expectedSourceRevision
        )
    }

    @discardableResult
    func muxExternalSubtitle(
        in asset: MediaAsset,
        subtitlePreview: SubtitleCleanupFilePreview,
        metadata: ExternalSubtitleTrackMetadata,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await muxExternalSubtitle(
            in: asset,
            subtitlePreview: .subRip(subtitlePreview),
            metadata: metadata,
            destinationURL: destinationURL
        )
    }

    @discardableResult
    func muxExternalSubtitle(
        in asset: MediaAsset,
        subtitlePreview: AdvancedSubtitleCleanupFilePreview,
        metadata: ExternalSubtitleTrackMetadata,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await muxExternalSubtitle(
            in: asset,
            subtitlePreview: .advanced(subtitlePreview),
            metadata: metadata,
            destinationURL: destinationURL
        )
    }

    @discardableResult
    func muxExternalSubtitle(
        in asset: MediaAsset,
        subtitlePreview: ExternalSubtitleFilePreview,
        metadata: ExternalSubtitleTrackMetadata,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await executeVerifiedEdit(
            in: asset,
            destinationURL: destinationURL,
            edit: .externalSubtitle(subtitlePreview, metadata)
        )
    }

    @discardableResult
    func cleanEmbeddedSubtitle(
        preview: EmbeddedSubtitleCleanupPreview,
        restoringIDs: Set<Int>,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await executeVerifiedEdit(
            in: preview.source,
            destinationURL: destinationURL,
            edit: .embeddedSubtitle(preview, restoringIDs: restoringIDs)
        )
    }

    @discardableResult
    func editChapters(
        preview: ChapterEditPreview,
        desired: MatroskaChapterDocument,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await executeVerifiedEdit(
            in: preview.source,
            destinationURL: destinationURL,
            edit: .chapters(preview, desired)
        )
    }

    @discardableResult
    func cleanSubtitle(
        preview: SubtitleCleanupFilePreview,
        restoringCueIDs: Set<Int>,
        destinationURL: URL
    ) async throws -> SubtitleCleanupResult {
        try await executeTextSubtitleCleanup(
            sourceURL: preview.sourceURL,
            destinationURL: destinationURL,
            workflowID: BuiltInWorkflowCatalog.subtitleCleanup,
            workflowName: "Clean SRT subtitle",
            planningMessage: "Zero encodes; normalize text and apply only reviewed cue changes."
        ) { execution in
            try await SubtitleCleanupExecutor().execute(
                preview: preview,
                restoringCueIDs: restoringCueIDs,
                destinationURL: destinationURL,
                onStage: { stage in
                    try await Self.record(
                        stage,
                        jobID: execution.jobID,
                        using: execution.recorder
                    )
                }
            )
        }
    }

    @discardableResult
    func cleanAdvancedSubtitle(
        preview: AdvancedSubtitleCleanupFilePreview,
        restoringEventIDs: Set<Int>,
        destinationURL: URL
    ) async throws -> AdvancedSubtitleCleanupResult {
        try await executeTextSubtitleCleanup(
            sourceURL: preview.sourceURL,
            destinationURL: destinationURL,
            workflowID: BuiltInWorkflowCatalog.advancedSubtitleCleanup,
            workflowName: "Clean ASS/SSA subtitle",
            planningMessage:
                "Zero encodes; normalize text and apply only reviewed dialogue changes while preserving styles."
        ) { execution in
            try await AdvancedSubtitleCleanupExecutor().execute(
                preview: preview,
                restoringEventIDs: restoringEventIDs,
                destinationURL: destinationURL,
                onStage: { stage in
                    try await Self.record(
                        stage,
                        jobID: execution.jobID,
                        using: execution.recorder
                    )
                }
            )
        }
    }

    private func executeTextSubtitleCleanup<Result>(
        sourceURL: URL,
        destinationURL: URL,
        workflowID: UUID,
        workflowName: String,
        planningMessage: String,
        operation: (HistoryExecution) async throws -> Result
    ) async throws -> Result {
        let scopedURLs = [sourceURL, destinationURL].map {
            ($0, $0.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, accessed) in scopedURLs where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        state = .executing("Creating and verifying \(destinationURL.lastPathComponent)…")
        didChange?()
        var historyExecution: HistoryExecution?
        do {
            let execution = try await beginHistory(
                inputs: [Self.historyInput(textSubtitleURL: sourceURL)],
                outputDisplayName: destinationURL.lastPathComponent,
                workflowID: workflowID,
                workflowName: workflowName,
                privacySafePlan: MediaJobPlanFacts(
                    videoEncodeGenerations: 0,
                    audioTracksEncoded: 0
                ),
                inspectionMessage: "Parsed bounded subtitle text for a deterministic review.",
                planningMessage: planningMessage,
                runningMessage: "Writing one normalized UTF-8 temporary subtitle."
            )
            historyExecution = execution
            let result = try await operation(execution)
            await finishHistory(
                execution,
                destinationURL: destinationURL,
                successMessage: "Verified UTF-8 subtitle committed and reopened."
            )
            return result
        } catch {
            await failHistory(historyExecution, error: error)
            throw error
        }
    }

    private func executeVerifiedEdit(
        in asset: MediaAsset,
        destinationURL: URL,
        edit: VerifiedEdit,
        queueExecution: QueueExecution? = nil,
        expectedSourceRevision: MediaFileRevision? = nil
    ) async throws -> MediaAsset {
        if case .saved(let workflow, _) = edit,
            workflow.videoConversionChoice != nil || workflow.audioConversionPreset != nil,
            cachedEncodingCapabilities == nil
        {
            _ = await probeEncodingCapabilities()
        }
        let scopedURLs = ([asset.sourceURL, destinationURL] + edit.externalInputURLs).map {
            ($0, $0.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, accessed) in scopedURLs where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        state = .executing("Creating and verifying \(destinationURL.lastPathComponent)…")
        didChange?()
        var historyExecution: HistoryExecution?
        do {
            let execution = try await beginHistory(
                inputs: [Self.historyInput(asset)]
                    + edit.externalInputURLs.map { Self.historyInput(textSubtitleURL: $0) },
                outputDisplayName: destinationURL.lastPathComponent,
                workflowID: edit.workflowID,
                workflowName: edit.workflowName,
                privacySafePlan: edit.privacySafePlan,
                inspectionMessage: "Using the completed media inspection.",
                planningMessage: edit.planningMessage,
                runningMessage: edit.runningMessage
            )
            historyExecution = execution

            let catalog = try makeToolCatalog()
            let runner = FoundationCommandRunner()
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let output: MediaAsset
            switch edit {
            case .metadata(let metadataEdit, _, _):
                let executor = MatroskaMetadataEditExecutor(
                    mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                    runner: runner,
                    inspector: inspector
                )
                output = try await executor.execute(
                    source: asset,
                    edit: metadataEdit,
                    destinationURL: destinationURL,
                    onStage: { stage in
                        try await Self.record(
                            stage,
                            jobID: execution.jobID,
                            using: execution.recorder
                        )
                    }
                )
            case .trackRemoval(let removal, _, _):
                let executor = TrackRemovalExecutor(
                    mkvmergeURL: try catalog.url(for: .mkvmerge),
                    runner: runner,
                    inspector: inspector
                )
                output = try await executor.execute(
                    source: asset,
                    removal: removal,
                    destinationURL: destinationURL,
                    onStage: { stage in
                        try await Self.record(
                            stage,
                            jobID: execution.jobID,
                            using: execution.recorder
                        )
                    }
                )
            case .saved(let workflow, let externalSubtitlePayload):
                if workflow.videoConversionChoice != nil {
                    let executor = SavedWorkflowVideoConversionExecutor(
                        ffmpegURL: try catalog.url(for: .ffmpeg),
                        ffprobeURL: try catalog.url(for: .ffprobe),
                        mkvmergeURL: try catalog.url(for: .mkvmerge),
                        mkvextractURL: try catalog.url(for: .mkvextract),
                        mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                        runner: runner,
                        inspector: inspector
                    )
                    output = try await executor.execute(
                        source: asset,
                        workflow: workflow,
                        externalSubtitlePayload: externalSubtitlePayload,
                        capabilities: cachedEncodingCapabilities ?? .unavailable,
                        expectedSourceRevision: expectedSourceRevision,
                        destinationURL: destinationURL,
                        onStage: { stage in
                            try await Self.record(
                                stage,
                                jobID: execution.jobID,
                                using: execution.recorder
                            )
                        }
                    )
                } else if workflow.audioConversionPreset != nil {
                    let executor = SavedWorkflowAudioConversionExecutor(
                        ffmpegURL: try catalog.url(for: .ffmpeg),
                        ffprobeURL: try catalog.url(for: .ffprobe),
                        mkvmergeURL: try catalog.url(for: .mkvmerge),
                        mkvextractURL: try catalog.url(for: .mkvextract),
                        mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                        runner: runner,
                        inspector: inspector
                    )
                    output = try await executor.execute(
                        source: asset,
                        workflow: workflow,
                        externalSubtitlePayload: externalSubtitlePayload,
                        capabilities: cachedEncodingCapabilities ?? .unavailable,
                        expectedSourceRevision: expectedSourceRevision,
                        destinationURL: destinationURL,
                        onStage: { stage in
                            try await Self.record(
                                stage,
                                jobID: execution.jobID,
                                using: execution.recorder
                            )
                        }
                    )
                } else {
                    let executor = SavedWorkflowExecutor(
                        mkvmergeURL: try catalog.url(for: .mkvmerge),
                        mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                        mkvextractURL: try catalog.url(for: .mkvextract),
                        runner: runner,
                        inspector: inspector
                    )
                    output = try await executor.execute(
                        source: asset,
                        trackRemoval: workflow.trackRemoval,
                        removesSegmentTitle: workflow.removesSegmentTitle,
                        externalSubtitleInput: workflow.externalSubtitleInput,
                        externalSubtitlePayload: externalSubtitlePayload,
                        createsUnchangedCopy: workflow.createsUnchangedCopy,
                        expectedSourceRevision: expectedSourceRevision,
                        destinationURL: destinationURL,
                        onStage: { stage in
                            try await Self.record(
                                stage,
                                jobID: execution.jobID,
                                using: execution.recorder
                            )
                        }
                    )
                }
            case .externalSubtitle(let subtitlePreview, let metadata):
                let executor = ExternalSubtitleMuxExecutor(
                    mkvmergeURL: try catalog.url(for: .mkvmerge),
                    mkvextractURL: try catalog.url(for: .mkvextract),
                    runner: runner,
                    inspector: inspector
                )
                output = try await executor.execute(
                    source: asset,
                    subtitlePreview: subtitlePreview,
                    metadata: metadata,
                    destinationURL: destinationURL,
                    onStage: { stage in
                        try await Self.record(
                            stage,
                            jobID: execution.jobID,
                            using: execution.recorder
                        )
                    }
                )
            case .embeddedSubtitle(let preview, let restoringIDs):
                let executor = EmbeddedSubtitleCleanupExecutor(
                    mkvmergeURL: try catalog.url(for: .mkvmerge),
                    mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                    mkvextractURL: try catalog.url(for: .mkvextract),
                    ffprobeURL: try catalog.url(for: .ffprobe),
                    runner: runner,
                    inspector: inspector
                )
                output = try await executor.execute(
                    preview: preview,
                    restoringIDs: restoringIDs,
                    destinationURL: destinationURL,
                    onStage: { stage in
                        try await Self.record(
                            stage,
                            jobID: execution.jobID,
                            using: execution.recorder
                        )
                    }
                )
            case .chapters(let preview, let desired):
                let executor = ChapterEditExecutor(
                    mkvextractURL: try catalog.url(for: .mkvextract),
                    mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                    runner: runner,
                    inspector: inspector
                )
                output = try await executor.execute(
                    preview: preview,
                    desired: desired,
                    destinationURL: destinationURL,
                    onStage: { stage in
                        try await Self.record(
                            stage,
                            jobID: execution.jobID,
                            using: execution.recorder
                        )
                    }
                )
            }
            registerInspectedAsset(output)
            await finishHistory(
                execution,
                destinationURL: destinationURL,
                successMessage: "Verified output committed and reopened."
            )
            let queueRecorded = await finishQueue(
                queueExecution,
                destinationURL: destinationURL
            )
            if SourceDispositionCommitPolicy.shouldApply(
                queueExecution?.sourceDisposition ?? .keepOriginal,
                afterQueueRecordedSuccess: queueRecorded
            ) {
                await applySourceDisposition(
                    queueExecution,
                    sourceURL: asset.sourceURL,
                    destinationURL: destinationURL
                )
            }
            return output
        } catch {
            await failQueue(queueExecution, error: error)
            if Self.isCancellation(error) {
                await cancelHistory(historyExecution)
            } else {
                await failHistory(historyExecution, error: error)
            }
            throw error
        }
    }

    private func registerInspectedAsset(
        _ asset: MediaAsset,
        revision suppliedRevision: MediaFileRevision? = nil
    ) {
        if let existing = assets.firstIndex(where: { $0.sourceURL == asset.sourceURL }) {
            inspectedAssetRevisions.removeValue(forKey: assets[existing].id)
            assets[existing] = asset
        } else {
            assets.append(asset)
        }
        if let revision = suppliedRevision
            ?? (try? MediaFileRevisionReader().read(asset.sourceURL))
        {
            inspectedAssetRevisions[asset.id] = revision
        } else {
            inspectedAssetRevisions.removeValue(forKey: asset.id)
        }
    }

    private func beginQueueExecution(
        recipe: SavedWorkflow,
        plan: ExecutionPlan,
        inputURLs: [URL],
        destinationURL: URL,
        sourceDisposition: MediaQueueSourceDisposition,
        retryingJobID: UUID?
    ) async throws -> QueueExecution {
        let execution = try await prepareQueueExecution(
            recipe: recipe,
            plan: plan,
            inputURLs: inputURLs,
            destinationURL: destinationURL,
            sourceDisposition: sourceDisposition,
            retryingJobID: retryingJobID
        )
        _ = try await execution.recorder.transition(
            jobID: execution.jobID,
            to: .running,
            at: Date(),
            reason: nil
        )
        activeQueueJobID = execution.jobID
        queueDidChange?()
        return execution
    }

    private func prepareQueueExecution(
        recipe: SavedWorkflow,
        plan: ExecutionPlan,
        inputURLs: [URL],
        destinationURL: URL,
        sourceDisposition: MediaQueueSourceDisposition,
        retryingJobID: UUID?
    ) async throws -> QueueExecution {
        _ = try await loadQueue()
        let recorder = try queueRecorder()
        let codec = SecurityScopedBookmarkCodec()
        let inputs = try inputURLs.enumerated().map { index, inputURL in
            let access: SecurityScopedBookmarkAccess =
                index == 0 && sourceDisposition == .trashAfterVerifiedSuccess
                ? .readWriteFile : .readOnlyFile
            return try codec.makeReference(for: inputURL, access: access)
        }
        let destinationDirectory = try codec.makeReference(
            for: destinationURL.deletingLastPathComponent(),
            access: .readWriteDirectory
        )
        let timestamp = Date()
        let jobID: UUID
        if let retryingJobID {
            _ = try await recorder.approveReplan(
                jobID: retryingJobID,
                workflow: .saved(recipe),
                inputs: inputs,
                destinationDirectory: destinationDirectory,
                outputDisplayName: destinationURL.lastPathComponent,
                sourceDisposition: sourceDisposition,
                reviewedPlan: plan,
                at: timestamp
            )
            jobID = retryingJobID
        } else {
            let job = MediaQueueJob(
                createdAt: timestamp,
                workflow: .saved(recipe),
                inputs: inputs,
                destinationDirectory: destinationDirectory,
                outputDisplayName: destinationURL.lastPathComponent,
                sourceDisposition: sourceDisposition,
                reviewedPlan: plan
            )
            _ = try await recorder.append(job, at: timestamp)
            jobID = job.id
        }
        return QueueExecution(
            recorder: recorder,
            jobID: jobID,
            sourceDisposition: sourceDisposition
        )
    }

    private func finishQueue(_ execution: QueueExecution?, destinationURL: URL) async -> Bool {
        guard let execution else { return true }
        defer {
            if activeQueueJobID == execution.jobID { activeQueueJobID = nil }
            queueDidChange?()
        }
        do {
            _ = try await execution.recorder.transition(
                jobID: execution.jobID,
                to: .succeeded,
                at: Date(),
                reason: nil
            )
            return true
        } catch {
            state = .completedWithWarnings(
                "Created \(destinationURL.lastPathComponent); original unchanged, but the queue could not record completion."
            )
            didChange?()
            return false
        }
    }

    private func applySourceDisposition(
        _ execution: QueueExecution?,
        sourceURL: URL,
        destinationURL: URL
    ) async {
        guard let execution,
            execution.sourceDisposition == .trashAfterVerifiedSuccess
        else { return }
        let outcome = applyVerifiedTrash(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )
        do {
            _ = try await execution.recorder.recordSourceDisposition(
                jobID: execution.jobID,
                outcome: outcome,
                at: Date()
            )
        } catch {
            state = .completedWithWarnings(
                "Created \(destinationURL.lastPathComponent), but the queue could not record the Trash outcome. Check the original and Trash before continuing."
            )
            didChange?()
        }
    }

    @discardableResult
    func applyVerifiedTrash(
        sourceURL: URL,
        destinationURL: URL
    ) -> MediaQueueSourceDispositionOutcome {
        do {
            try trashSource(sourceURL)
            assets.removeAll { $0.sourceURL == sourceURL }
            state = .completed(
                "Created \(destinationURL.lastPathComponent); moved the original to Trash after verified success."
            )
            didChange?()
            return .applied
        } catch {
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                state = .completedWithWarnings(
                    "Created \(destinationURL.lastPathComponent) and recorded verified success, but could not move the original to Trash, so it remains unchanged."
                )
                didChange?()
                return .failed
            } else {
                state = .completedWithWarnings(
                    "Created \(destinationURL.lastPathComponent) and recorded verified success, but could not confirm where macOS moved the original. Check Trash before continuing."
                )
                didChange?()
                return .uncertain
            }
        }
    }

    private func recoverPendingSourceDispositions(
        in snapshot: MediaQueueSnapshot
    ) async -> MediaQueueSnapshot {
        var recovered = snapshot
        var outcomes = [MediaQueueSourceDispositionOutcome]()
        var couldNotRecordEveryOutcome = false
        let pending = snapshot.jobs.filter {
            $0.state == .succeeded
                && $0.sourceDisposition == .trashAfterVerifiedSuccess
                && $0.sourceDispositionResult == nil
        }
        for job in pending {
            let outcome: MediaQueueSourceDispositionOutcome
            do {
                outcome = try applyRecoveredSourceDisposition(job)
            } catch {
                outcome = .uncertain
            }
            outcomes.append(outcome)
            do {
                recovered = try await queueRecorder().recordSourceDisposition(
                    jobID: job.id,
                    outcome: outcome,
                    at: Date()
                )
            } catch {
                couldNotRecordEveryOutcome = true
            }
        }
        if !pending.isEmpty {
            let count = pending.count
            let followUps = count == 1 ? "follow-up" : "follow-ups"
            let uncertainCount = outcomes.filter { $0 == .uncertain }.count
            let failedCount = outcomes.filter { $0 == .failed }.count
            if couldNotRecordEveryOutcome {
                state = .completedWithWarnings(
                    "Checked \(count) pending Trash \(followUps), but could not record every outcome. Check the originals and Trash before continuing."
                )
            } else if uncertainCount > 0 {
                let sourceOutcomes = uncertainCount == 1 ? "source outcome" : "source outcomes"
                state = .completedWithWarnings(
                    "Checked \(count) pending Trash \(followUps); \(uncertainCount) \(sourceOutcomes) could not be confirmed. Check the original and Trash before continuing."
                )
            } else if failedCount > 0 {
                let unchangedOriginals =
                    failedCount == 1 ? "original remains" : "originals remain"
                let objectPronoun = failedCount == 1 ? "it" : "them"
                state = .completedWithWarnings(
                    "Checked \(count) pending Trash \(followUps); \(failedCount) \(unchangedOriginals) unchanged because macOS could not move \(objectPronoun) to Trash."
                )
            } else {
                state = .completed("Finished \(count) pending Trash \(followUps).")
            }
            didChange?()
            queueDidChange?()
        }
        return recovered
    }

    private func applyRecoveredSourceDisposition(
        _ job: MediaQueueJob
    ) throws -> MediaQueueSourceDispositionOutcome {
        let sourceURL = try resolvePrimaryQueueInput(job)
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        return applyVerifiedTrash(
            sourceURL: sourceURL,
            destinationURL: sourceURL.deletingLastPathComponent()
                .appendingPathComponent(job.outputDisplayName)
        )
    }

    private func failQueue(_ execution: QueueExecution?, error: Error) async {
        guard let execution else { return }
        defer {
            if activeQueueJobID == execution.jobID { activeQueueJobID = nil }
            queueDidChange?()
        }
        if Self.isCancellation(error) {
            guard
                let job = try? await execution.recorder.load().jobs.first(where: {
                    $0.id == execution.jobID
                })
            else { return }
            if job.state == .running {
                _ = try? await execution.recorder.transition(
                    jobID: execution.jobID,
                    to: .cancelling,
                    at: Date(),
                    reason: .userAction
                )
            }
            _ = try? await execution.recorder.transition(
                jobID: execution.jobID,
                to: .cancelled,
                at: Date(),
                reason: .userAction
            )
        } else {
            _ = try? await execution.recorder.transition(
                jobID: execution.jobID,
                to: .failed,
                at: Date(),
                reason: .executionFailed
            )
        }
    }

    private func queueRecorder() throws -> any JobQueueManaging {
        if let queueStore { return queueStore }
        let recorder = try queueStoreFactory()
        queueStore = recorder
        return recorder
    }

    private func automaticQueueCoordinator() throws -> MediaQueueAdmissionCoordinator {
        if let queueAdmissionCoordinator { return queueAdmissionCoordinator }
        let coordinator = MediaQueueAdmissionCoordinator(store: try queueRecorder())
        queueAdmissionCoordinator = coordinator
        return coordinator
    }

    private func executeAutomaticQueueAdmission(
        _ admission: MediaQueueAdmission
    ) async throws -> MediaQueueAutomaticExecutionOutcome {
        guard case .saved(let workflow) = admission.job.workflow,
            let sourceURL = admission.inputURLs.first,
            admission.inputURLs.count == 1,
            let reviewedRevision = admission.job.inputs.first?.reviewedRevision
        else {
            return .needsReview
        }
        let exactRevision: MediaFileRevision
        do {
            exactRevision = try MediaFileRevisionReader().read(sourceURL)
        } catch {
            return .needsReview
        }
        guard exactRevision.atMillisecondPrecision == reviewedRevision else {
            return .needsReview
        }

        let catalog = try makeToolCatalog()
        let runner = FoundationCommandRunner()
        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        let asset = try await inspector.inspect(sourceURL)
        let availableVideoPresets: [VideoPreset]
        let availableAudioPresets: [AudioTranscodePreset]
        if SavedWorkflowCompiler().needsEncodingCapabilities(for: workflow, asset: asset) {
            let capabilities = await probeEncodingCapabilities()
            availableVideoPresets = capabilities.availableVideoPresets
            availableAudioPresets = capabilities.availableAudioPresets
        } else {
            availableVideoPresets = []
            availableAudioPresets = []
        }
        let compiled: CompiledSavedWorkflow
        do {
            compiled = try SavedWorkflowCompiler().compile(
                workflow,
                for: asset,
                inputs: SavedWorkflowResolvedInputs(
                    availableVideoPresets: availableVideoPresets,
                    availableAudioPresets: availableAudioPresets
                )
            )
        } catch is SavedWorkflowCompilationError {
            return .needsReview
        }
        guard compiled.plan.hasSameReviewedWork(as: admission.job.reviewedPlan),
            (try? MediaFileRevisionReader().read(sourceURL)) == exactRevision
        else {
            return .needsReview
        }
        _ = try await executeVerifiedEdit(
            in: asset,
            destinationURL: admission.outputURL,
            edit: .saved(compiled, nil),
            expectedSourceRevision: exactRevision
        )
        return .verifiedSuccess
    }

    private func beginHistory(
        inputs: [MediaJobInput],
        outputDisplayName: String,
        workflowID: UUID,
        workflowName: String,
        privacySafePlan: MediaJobPlanFacts,
        inspectionMessage: String,
        planningMessage: String,
        runningMessage: String
    ) async throws -> HistoryExecution {
        let recorder = try historyRecorderFactory()
        var job = MediaJobRecord(
            createdAt: Date(),
            workflowID: workflowID,
            workflowName: workflowName,
            inputs: inputs,
            outputDisplayName: outputDisplayName,
            privacySafePlan: privacySafePlan
        )
        try job.transition(to: .inspecting, at: job.createdAt, message: inspectionMessage)
        try job.transition(to: .planned, at: job.createdAt, message: planningMessage)
        try job.transition(
            to: .ready,
            at: job.createdAt,
            message: "User selected a new output location."
        )
        try await recorder.create(job)
        do {
            try await recorder.transition(
                jobID: job.id,
                to: .running,
                at: Date(),
                message: runningMessage
            )
        } catch {
            _ = try? await recorder.transition(
                jobID: job.id,
                to: .cancelled,
                at: Date(),
                message: "Execution did not start because history could not be updated."
            )
            throw error
        }
        return HistoryExecution(recorder: recorder, jobID: job.id)
    }

    private func finishHistory(
        _ execution: HistoryExecution,
        destinationURL: URL,
        successMessage: String
    ) async {
        do {
            try await execution.recorder.transition(
                jobID: execution.jobID,
                to: .succeeded,
                at: Date(),
                message: successMessage
            )
            state = .completed(
                "Created \(destinationURL.lastPathComponent); original unchanged."
            )
        } catch {
            _ = try? await execution.recorder.transition(
                jobID: execution.jobID,
                to: .failed,
                at: Date(),
                message: "Output committed; history finalization failed."
            )
            state = .completedWithWarnings(
                "Created \(destinationURL.lastPathComponent); original unchanged, but "
                    + "history could not record success."
            )
        }
        didChange?()
    }

    private func failHistory(_ execution: HistoryExecution?, error: Error) async {
        if let execution {
            _ = try? await execution.recorder.transition(
                jobID: execution.jobID,
                to: .failed,
                at: Date(),
                message: Self.sanitizedFailureMessage(for: error)
            )
        }
        state = .failed(
            UserFacingErrorPresentation.message(
                failure: "Could not create a verified output.",
                recovery: "The original is unchanged; review the operation and try again.",
                error: error
            )
        )
        didChange?()
    }

    private func cancelHistory(_ execution: HistoryExecution?) async {
        if let execution {
            _ = try? await execution.recorder.transition(
                jobID: execution.jobID,
                to: .cancelled,
                at: Date(),
                message: "User cancelled; temporary output removed and originals unchanged."
            )
        }
        state = .failed("Cancelled. Temporary output removed; originals unchanged.")
        didChange?()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? CommandRunnerError) == .cancelled
    }

    private static func sanitizedFailureMessage(for error: Error) -> String {
        if let executionError = error as? MatroskaMetadataExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? TrackRemovalExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? SavedWorkflowExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? SubtitleCleanupExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? AdvancedSubtitleCleanupExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? ExternalSubtitleMuxError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? EmbeddedSubtitleCleanupError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? ChapterEditExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? LosslessJoinExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? JoinFinalAssemblyExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? FastTrimExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        if let executionError = error as? ExactTrimExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        return "Edit stopped before a verified commit."
    }

    private static func record(
        _ stage: VerifiedOutputExecutionStage,
        jobID: UUID,
        using recorder: any JobHistoryRecording
    ) async throws {
        switch stage {
        case .verifying:
            try await recorder.transition(
                jobID: jobID,
                to: .verifying,
                at: Date(),
                message: "Re-inspecting output and comparing preserved structure."
            )
        case .committing:
            try await recorder.transition(
                jobID: jobID,
                to: .committing,
                at: Date(),
                message: "Verification passed; committing the new output."
            )
        }
    }

    nonisolated private static func historyInput(_ asset: MediaAsset) -> MediaJobInput {
        MediaJobInput(
            displayName: asset.sourceURL.lastPathComponent,
            privacySafeFacts: MediaJobInputFacts(asset: asset)
        )
    }

    nonisolated private static func historyInput(textSubtitleURL: URL) -> MediaJobInput {
        let values = try? textSubtitleURL.resourceValues(forKeys: [.fileSizeKey])
        return MediaJobInput(
            displayName: textSubtitleURL.lastPathComponent,
            privacySafeFacts: .textSubtitle(
                fileSize: values?.fileSize.map(Int64.init),
                pathExtension: textSubtitleURL.pathExtension
            )
        )
    }

    private func makeToolCatalog() throws -> ToolCatalog {
        try ToolCatalog(rootURL: resolveToolRootURL())
    }

    private func encodingBenchmarkEnvironment(
        catalog: ToolCatalog
    ) throws -> EncodingBenchmarkEnvironment {
        guard let ffmpeg = catalog.manifest.tools.first(where: { $0.name == .ffmpeg }) else {
            throw ToolCatalogError.incompleteManifest
        }
        return EncodingBenchmarkEnvironment(
            ffmpegSHA256: ffmpeg.sha256,
            architecture: catalog.architecture.rawValue,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    private func resolveToolRootURL() throws -> URL {
        if let explicitRoot = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"],
            explicitRoot.hasPrefix("/")
        {
            return URL(fileURLWithPath: explicitRoot, isDirectory: true)
        }
        guard let resourceURL = Bundle.main.resourceURL else {
            throw ToolCatalogError.unsafeRoot
        }
        return resourceURL.appendingPathComponent("Tools", isDirectory: true)
    }
}

enum SourceDispositionCommitPolicy {
    static func shouldApply(
        _ disposition: MediaQueueSourceDisposition,
        afterQueueRecordedSuccess queueRecordedSuccess: Bool
    ) -> Bool {
        queueRecordedSuccess && disposition == .trashAfterVerifiedSuccess
    }
}
