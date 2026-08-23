import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem

@MainActor
final class AppModel {
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

    init(
        historyRecorderFactory: @escaping @Sendable () throws -> any JobHistoryRecording = {
            try AppHistoryLocation.makeStore()
        }
    ) {
        self.historyRecorderFactory = historyRecorderFactory
    }

    func loadHistory() async throws -> [MediaJobRecord] {
        try await historyRecorderFactory().load()
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
            var historyJob = makeReadySegmentTitleJob(
                asset: asset,
                destinationURL: destinationURL
            )
            try historyJob.transition(
                to: .inspecting,
                at: historyJob.createdAt,
                message: "Using the completed media inspection."
            )
            try historyJob.transition(
                to: .planned,
                at: historyJob.createdAt,
                message: "Zero video encodes; mkvpropedit on a verified clone."
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
                message: "Editing a temporary clone."
            )

            let catalog = try makeToolCatalog()
            let runner = FoundationCommandRunner()
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let executor = SegmentTitleEditExecutor(
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            let output = try await executor.execute(
                source: asset,
                title: title,
                destinationURL: destinationURL,
                onStage: { stage in
                    switch stage {
                    case .verifying:
                        try await recorder.transition(
                            jobID: executingJobID,
                            to: .verifying,
                            at: Date(),
                            message: "Re-inspecting output and comparing preserved structure."
                        )
                    case .committing:
                        try await recorder.transition(
                            jobID: executingJobID,
                            to: .committing,
                            at: Date(),
                            message: "Verification passed; committing the new output."
                        )
                    }
                }
            )
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

    private func makeReadySegmentTitleJob(
        asset: MediaAsset,
        destinationURL: URL
    ) -> MediaJobRecord {
        MediaJobRecord(
            createdAt: Date(),
            workflowID: Self.segmentTitleWorkflowID,
            workflowName: "Edit segment title",
            inputs: [MediaJobInput(displayName: asset.sourceURL.lastPathComponent)],
            outputDisplayName: destinationURL.lastPathComponent
        )
    }

    private static func sanitizedFailureMessage(for error: Error) -> String {
        if let executionError = error as? SegmentTitleExecutionError,
            case .committedOutputAuditFailed = executionError
        {
            return "Output committed, but its final reopen audit failed."
        }
        return "Edit stopped before a verified commit."
    }

    private static let segmentTitleWorkflowID = UUID(
        uuidString: "6A2D7635-AB6D-4C7A-AE02-1561631121F0"
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
