import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

@MainActor
final class AppModel {
    private struct HistoryExecution: Sendable {
        let recorder: any JobHistoryRecording
        let jobID: UUID
    }

    private enum VerifiedEdit {
        case metadata(MatroskaMetadataEdit, workflowID: UUID, workflowName: String)
        case trackRemoval(TrackRemoval, workflowID: UUID, workflowName: String)
        case saved(CompiledSavedWorkflow)
        case externalSubtitle(ExternalSubtitleFilePreview, ExternalSubtitleTrackMetadata)
        case embeddedSubtitle(EmbeddedSubtitleCleanupPreview, restoringIDs: Set<Int>)
        case chapters(ChapterEditPreview, MatroskaChapterDocument)

        var workflowID: UUID {
            switch self {
            case .metadata(_, let workflowID, _): workflowID
            case .trackRemoval(_, let workflowID, _): workflowID
            case .saved(let workflow): workflow.workflowID
            case .externalSubtitle: AppModel.externalSubtitleMuxWorkflowID
            case .embeddedSubtitle: AppModel.embeddedSubtitleCleanupWorkflowID
            case .chapters: AppModel.chapterEditWorkflowID
            }
        }

        var workflowName: String {
            switch self {
            case .metadata(_, _, let workflowName): workflowName
            case .trackRemoval(_, _, let workflowName): workflowName
            case .saved(let workflow): workflow.workflowName
            case .externalSubtitle(let preview, _):
                "Add external \(preview.format.displayName) subtitle"
            case .embeddedSubtitle(let preview, _):
                "Clean embedded \(preview.format.displayName) subtitle"
            case .chapters: "Edit Matroska chapters"
            }
        }

        var planningMessage: String {
            switch self {
            case .metadata: "Zero video encodes; mkvpropedit on a verified clone."
            case .trackRemoval: "Zero video encodes; mkvmerge copies the retained streams."
            case .saved(let workflow):
                workflow.plan.impact.videoEncodeCount == 0
                    ? "Zero video encodes; all enabled steps share one verified output pipeline."
                    : "All video-affecting steps are fused into one encode."
            case .externalSubtitle(let preview, _):
                "Zero encodes; normalize one temporary \(preview.format.displayName) and remux it as the last MKV track."
            case .embeddedSubtitle(let preview, _):
                "Zero encodes; replace one reviewed embedded \(preview.format.displayName) track at its original position in one verified remux."
            case .chapters(_, let document):
                "Zero encodes; replace the chapter document with \(document.chapterCount) reviewed nested entries on a verified clone."
            }
        }

        var runningMessage: String {
            switch self {
            case .metadata: "Editing a temporary clone."
            case .trackRemoval: "Remuxing retained tracks to a temporary output."
            case .saved(let workflow):
                workflow.trackRemoval == nil
                    ? "Editing one temporary clone."
                    : "Applying all workflow steps to one temporary remux."
            case .externalSubtitle:
                "Adding one reviewed subtitle to a temporary MKV remux."
            case .embeddedSubtitle:
                "Replacing one reviewed embedded subtitle in a temporary MKV remux."
            case .chapters:
                "Replacing chapters in one temporary MKV clone."
            }
        }

        var externalInputURLs: [URL] {
            switch self {
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
    var didChange: (() -> Void)?
    private var cachedEncodingCapabilities: FFmpegEncodingCapabilities?
    private let historyRecorderFactory: @Sendable () throws -> any JobHistoryRecording
    private let workflowStoreFactory: @Sendable () throws -> any SavedWorkflowPersisting

    init(
        historyRecorderFactory: @escaping @Sendable () throws -> any JobHistoryRecording = {
            try AppHistoryLocation.makeStore()
        },
        workflowStoreFactory: @escaping @Sendable () throws -> any SavedWorkflowPersisting = {
            try AppHistoryLocation.makeWorkflowStore()
        }
    ) {
        self.historyRecorderFactory = historyRecorderFactory
        self.workflowStoreFactory = workflowStoreFactory
    }

    func loadHistory() async throws -> [MediaJobRecord] {
        try await historyRecorderFactory().load()
    }

    func loadWorkflows() async throws -> [SavedWorkflow] {
        try await workflowStoreFactory().load()
    }

    func saveWorkflows(_ workflows: [SavedWorkflow]) async throws {
        try await workflowStoreFactory().save(workflows)
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
            state = .failed("Could not prepare the join review: \(error.localizedDescription)")
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
            let capabilities = try await FFmpegCapabilityProbe(
                ffmpegURL: try catalog.url(for: .ffmpeg),
                runner: FoundationCommandRunner()
            ).probe()
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
            state = .failed("Join review is stale or incomplete: \(error.localizedDescription)")
            didChange?()
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
                inputDisplayNames: preview.sources.map { $0.sourceURL.lastPathComponent },
                outputDisplayName: destinationURL.lastPathComponent,
                workflowID: Self.losslessJoinWorkflowID,
                workflowName: "Join MKV files losslessly",
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
                                "Verifying joined tracks, duration, tags, and nested chapters…"
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
            if let existing = assets.firstIndex(where: { $0.sourceURL == output.sourceURL }) {
                assets[existing] = output
            } else {
                assets.append(output)
            }
            await finishHistory(
                execution,
                destinationURL: destinationURL,
                successMessage:
                    "Verified joined tracks and exact nested chapters; committed and reopened output."
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
            preview.videoEncodeCount == 0
                ? "Fast trimming without encoding…"
                : "Exact trimming with one video encode…"
        )
        didChange?()
        var historyExecution: HistoryExecution?
        do {
            let planningMessage: String
            let runningMessage: String
            let workflowID: UUID
            switch preview {
            case .fast(let fast):
                workflowID = Self.fastTrimWorkflowID
                planningMessage =
                    "Zero encodes; copy every stream at reviewed keyframes "
                    + "\(ChapterTimestamp.format(fast.plan.adjusted.start, digits: 3))–"
                    + ChapterTimestamp.format(fast.plan.adjusted.end, digits: 3) + "."
                runningMessage =
                    "Splitting one temporary MKV at reviewed keyframes and replacing chapters."
            case .exact(let exact):
                workflowID = Self.exactTrimWorkflowID
                let audio =
                    exact.resolvedPlan.choice.audioPolicy == .packetCopy
                    ? "packet-copy every audio track"
                    : "encode \(exact.encodedAudioTrackIDs.count) audio track(s) once to AAC"
                planningMessage =
                    "One video encode using "
                    + TrimPresentationPolicy.presetName(
                        exact.resolvedPlan.choice.videoPreset
                    )
                    + "; \(audio); preserve the exact reviewed range."
                runningMessage =
                    "Encoding video once to one temporary MKV and replacing exact chapters."
            }
            let execution = try await beginHistory(
                inputDisplayNames: [source.sourceURL.lastPathComponent],
                outputDisplayName: destinationURL.lastPathComponent,
                workflowID: workflowID,
                workflowName: preview.workflowName,
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
            if let existing = assets.firstIndex(where: { $0.sourceURL == output.sourceURL }) {
                assets[existing] = output
            } else {
                assets.append(output)
            }
            await finishHistory(
                execution,
                destinationURL: destinationURL,
                successMessage:
                    "Verified trimmed range, streams, metadata, attachments, and exact nested chapters; committed and reopened output."
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
            request.mode == .fast
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
                        mkvextractURL: try catalog.url(for: .mkvextract),
                        mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                        runner: runner,
                        inspector: inspector
                    ).preview(
                        source: source,
                        range: request.range,
                        choice: choice,
                        capabilities: capabilities
                    )
                )
            }
            state = .ready
            didChange?()
            return preview
        } catch {
            state = .failed("Trim review stopped: \(error.localizedDescription)")
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
            state = .failed("Could not scan the selected files: \(error.localizedDescription)")
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
                let asset = try await inspector.inspect(url)
                if let existing = assets.firstIndex(where: { $0.sourceURL == asset.sourceURL }) {
                    assets[existing] = asset
                } else {
                    assets.append(asset)
                }
            } catch {
                let message =
                    "Could not inspect \(url.lastPathComponent): \(error.localizedDescription)"
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
                workflowID: Self.segmentTitleWorkflowID,
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
                workflowID: Self.trackMetadataWorkflowID,
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
                workflowID: Self.trackRemovalWorkflowID,
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
                workflowID: Self.englishLibraryCleanupWorkflowID,
                workflowName: "English Library Cleanup"
            )
        )
    }

    @discardableResult
    func runSavedWorkflow(
        _ workflow: CompiledSavedWorkflow,
        in asset: MediaAsset,
        destinationURL: URL
    ) async throws -> MediaAsset {
        try await executeVerifiedEdit(
            in: asset,
            destinationURL: destinationURL,
            edit: .saved(workflow)
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
            workflowID: Self.subtitleCleanupWorkflowID,
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
            workflowID: Self.advancedSubtitleCleanupWorkflowID,
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
                inputDisplayNames: [sourceURL.lastPathComponent],
                outputDisplayName: destinationURL.lastPathComponent,
                workflowID: workflowID,
                workflowName: workflowName,
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
        edit: VerifiedEdit
    ) async throws -> MediaAsset {
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
                inputDisplayNames: [asset.sourceURL.lastPathComponent]
                    + edit.externalInputURLs.map(\.lastPathComponent),
                outputDisplayName: destinationURL.lastPathComponent,
                workflowID: edit.workflowID,
                workflowName: edit.workflowName,
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
            case .saved(let workflow):
                let executor = SavedWorkflowExecutor(
                    mkvmergeURL: try catalog.url(for: .mkvmerge),
                    mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                    runner: runner,
                    inspector: inspector
                )
                output = try await executor.execute(
                    source: asset,
                    trackRemoval: workflow.trackRemoval,
                    removesSegmentTitle: workflow.removesSegmentTitle,
                    destinationURL: destinationURL,
                    onStage: { stage in
                        try await Self.record(
                            stage,
                            jobID: execution.jobID,
                            using: execution.recorder
                        )
                    }
                )
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
            if let existing = assets.firstIndex(where: { $0.sourceURL == output.sourceURL }) {
                assets[existing] = output
            } else {
                assets.append(output)
            }
            await finishHistory(
                execution,
                destinationURL: destinationURL,
                successMessage: "Verified output committed and reopened."
            )
            return output
        } catch {
            await failHistory(historyExecution, error: error)
            throw error
        }
    }

    private func beginHistory(
        inputDisplayNames: [String],
        outputDisplayName: String,
        workflowID: UUID,
        workflowName: String,
        inspectionMessage: String,
        planningMessage: String,
        runningMessage: String
    ) async throws -> HistoryExecution {
        let recorder = try historyRecorderFactory()
        var job = MediaJobRecord(
            createdAt: Date(),
            workflowID: workflowID,
            workflowName: workflowName,
            inputs: inputDisplayNames.map { MediaJobInput(displayName: $0) },
            outputDisplayName: outputDisplayName
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
        state = .failed("Original unchanged. \(error.localizedDescription)")
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

    private static let segmentTitleWorkflowID = UUID(
        uuidString: "6A2D7635-AB6D-4C7A-AE02-1561631121F0"
    )!
    private static let trackMetadataWorkflowID = UUID(
        uuidString: "842C095A-A70A-4B81-BD33-E2857F9B87CD"
    )!
    private static let trackRemovalWorkflowID = UUID(
        uuidString: "6F67B5AB-BB34-45BF-B159-E98F0C26FA3E"
    )!
    private static let englishLibraryCleanupWorkflowID = UUID(
        uuidString: "853C0788-5994-491F-AC13-A0A47319CD0E"
    )!
    private static let subtitleCleanupWorkflowID = UUID(
        uuidString: "7062274D-C993-42BF-903E-3DD817424EBF"
    )!
    private static let advancedSubtitleCleanupWorkflowID = UUID(
        uuidString: "A15A085C-F68E-433F-A6D8-486EF1AB2F95"
    )!
    nonisolated private static let externalSubtitleMuxWorkflowID = UUID(
        uuidString: "5CB3529A-967E-4B11-81E2-E5D932F1B395"
    )!
    nonisolated private static let embeddedSubtitleCleanupWorkflowID = UUID(
        uuidString: "C3A2A7DD-8C17-4A91-A9BC-9750F35A9C6F"
    )!
    nonisolated private static let chapterEditWorkflowID = UUID(
        uuidString: "01898D29-C2C9-44C4-A87D-B72A3AB90FF8"
    )!
    nonisolated private static let losslessJoinWorkflowID = UUID(
        uuidString: "1329034D-8DA4-4D8F-82B6-C3BC42A4E4FA"
    )!
    nonisolated private static let fastTrimWorkflowID = UUID(
        uuidString: "7E551E9E-039C-46DB-A14D-E43E338A5E2A"
    )!
    nonisolated private static let exactTrimWorkflowID = UUID(
        uuidString: "CA62AB88-34D1-44E0-B410-FB9DAA2FE3ED"
    )!

    private func makeToolCatalog() throws -> ToolCatalog {
        if let explicitRoot = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"],
            explicitRoot.hasPrefix("/")
        {
            return try ToolCatalog(rootURL: URL(fileURLWithPath: explicitRoot, isDirectory: true))
        }
        guard let resourceURL = Bundle.main.resourceURL else {
            throw ToolCatalogError.unsafeRoot
        }
        return try ToolCatalog(
            rootURL: resourceURL.appendingPathComponent("Tools", isDirectory: true))
    }
}
