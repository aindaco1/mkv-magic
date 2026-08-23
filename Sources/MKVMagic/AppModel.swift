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

        var workflowID: UUID {
            switch self {
            case .metadata(_, let workflowID, _): workflowID
            case .trackRemoval(_, let workflowID, _): workflowID
            case .saved(let workflow): workflow.workflowID
            case .externalSubtitle: AppModel.externalSubtitleMuxWorkflowID
            }
        }

        var workflowName: String {
            switch self {
            case .metadata(_, _, let workflowName): workflowName
            case .trackRemoval(_, _, let workflowName): workflowName
            case .saved(let workflow): workflow.workflowName
            case .externalSubtitle(let preview, _):
                "Add external \(preview.format.displayName) subtitle"
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
