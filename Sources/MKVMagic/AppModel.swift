import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

@MainActor
final class AppModel {
    private enum VerifiedEdit {
        case metadata(MatroskaMetadataEdit, workflowID: UUID, workflowName: String)
        case trackRemoval(TrackRemoval, workflowID: UUID, workflowName: String)
        case saved(CompiledSavedWorkflow)

        var workflowID: UUID {
            switch self {
            case .metadata(_, let workflowID, _): workflowID
            case .trackRemoval(_, let workflowID, _): workflowID
            case .saved(let workflow): workflow.workflowID
            }
        }

        var workflowName: String {
            switch self {
            case .metadata(_, _, let workflowName): workflowName
            case .trackRemoval(_, _, let workflowName): workflowName
            case .saved(let workflow): workflow.workflowName
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

    private func executeVerifiedEdit(
        in asset: MediaAsset,
        destinationURL: URL,
        edit: VerifiedEdit
    ) async throws -> MediaAsset {
        let scopedURLs = [asset.sourceURL, destinationURL].map {
            ($0, $0.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, accessed) in scopedURLs where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        state = .executing("Creating and verifying \(destinationURL.lastPathComponent)…")
        didChange?()
        var historyRecorder: (any JobHistoryRecording)?
        var historyJobID: UUID?
        do {
            let recorder = try historyRecorderFactory()
            historyRecorder = recorder
            var historyJob = makeReadyEditJob(
                asset: asset,
                destinationURL: destinationURL,
                workflowID: edit.workflowID,
                workflowName: edit.workflowName
            )
            try historyJob.transition(
                to: .inspecting,
                at: historyJob.createdAt,
                message: "Using the completed media inspection."
            )
            try historyJob.transition(
                to: .planned,
                at: historyJob.createdAt,
                message: edit.planningMessage
            )
            try historyJob.transition(
                to: .ready,
                at: historyJob.createdAt,
                message: "User selected a new output location."
            )
            try await recorder.create(historyJob)
            let executingJobID = historyJob.id
            historyJobID = executingJobID
            try await recorder.transition(
                jobID: executingJobID,
                to: .running,
                at: Date(),
                message: edit.runningMessage
            )

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
                        try await Self.record(stage, jobID: executingJobID, using: recorder)
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
                        try await Self.record(stage, jobID: executingJobID, using: recorder)
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
                        try await Self.record(stage, jobID: executingJobID, using: recorder)
                    }
                )
            }
            if let existing = assets.firstIndex(where: { $0.sourceURL == output.sourceURL }) {
                assets[existing] = output
            } else {
                assets.append(output)
            }
            do {
                try await recorder.transition(
                    jobID: executingJobID,
                    to: .succeeded,
                    at: Date(),
                    message: "Verified output committed and reopened."
                )
                state = .completed(
                    "Created \(destinationURL.lastPathComponent); original unchanged."
                )
            } catch {
                _ = try? await recorder.transition(
                    jobID: executingJobID,
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
            return output
        } catch {
            if let historyRecorder, let historyJobID {
                _ = try? await historyRecorder.transition(
                    jobID: historyJobID,
                    to: .failed,
                    at: Date(),
                    message: Self.sanitizedFailureMessage(for: error)
                )
            }
            state = .failed("Original unchanged. \(error.localizedDescription)")
            didChange?()
            throw error
        }
    }

    private func makeReadyEditJob(
        asset: MediaAsset,
        destinationURL: URL,
        workflowID: UUID,
        workflowName: String
    ) -> MediaJobRecord {
        MediaJobRecord(
            createdAt: Date(),
            workflowID: workflowID,
            workflowName: workflowName,
            inputs: [MediaJobInput(displayName: asset.sourceURL.lastPathComponent)],
            outputDisplayName: destinationURL.lastPathComponent
        )
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
