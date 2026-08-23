import Foundation
import MKVMagicCore

public enum SavedWorkflowCompilationError: Error, Equatable, Sendable {
    case unsupportedSchema
    case emptyName
    case emptyWorkflow
    case duplicateStepIdentifier
    case duplicateAction
    case noEnabledSteps
    case unsupportedContainer
    case unstableTrackIdentity
    case wouldRemoveAllTracks
    case noApplicableChanges
}

extension SavedWorkflowCompilationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "This workflow uses an unsupported schema version."
        case .emptyName: "Give the workflow a name."
        case .emptyWorkflow: "Add at least one workflow step."
        case .duplicateStepIdentifier: "The workflow contains a duplicate step identifier."
        case .duplicateAction: "Each workflow action can appear only once."
        case .noEnabledSteps: "Enable at least one workflow step."
        case .unsupportedContainer: "Saved workflows currently require a Matroska file."
        case .unstableTrackIdentity:
            "This file does not expose stable Matroska identifiers for every track."
        case .wouldRemoveAllTracks: "This workflow would remove every playable track."
        case .noApplicableChanges: "This file already satisfies the enabled workflow steps."
        }
    }
}

public struct CompiledSavedWorkflow: Equatable, Sendable {
    public let workflowID: UUID
    public let workflowName: String
    public let operations: [WorkflowOperation]
    public let plan: ExecutionPlan
    public let summaries: [String]

    public init(
        workflowID: UUID,
        workflowName: String,
        operations: [WorkflowOperation],
        plan: ExecutionPlan,
        summaries: [String]
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.operations = operations
        self.plan = plan
        self.summaries = summaries
    }

    public var trackRemoval: TrackRemoval? {
        for operation in operations {
            if case .removeTracksByUID(let removal) = operation { return removal }
        }
        return nil
    }

    public var removesSegmentTitle: Bool {
        operations.contains { operation in
            if case .editSegmentTitle(nil) = operation { return true }
            return false
        }
    }
}

public struct SavedWorkflowCompiler: Sendable {
    public init() {}

    public func compile(
        _ workflow: SavedWorkflow,
        for asset: MediaAsset
    ) throws -> CompiledSavedWorkflow {
        guard workflow.schemaVersion == SavedWorkflow.currentSchemaVersion else {
            throw SavedWorkflowCompilationError.unsupportedSchema
        }
        guard !workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SavedWorkflowCompilationError.emptyName
        }
        guard !workflow.steps.isEmpty else {
            throw SavedWorkflowCompilationError.emptyWorkflow
        }
        guard Set(workflow.steps.map(\.id)).count == workflow.steps.count else {
            throw SavedWorkflowCompilationError.duplicateStepIdentifier
        }
        guard Set(workflow.steps.map(\.action)).count == workflow.steps.count else {
            throw SavedWorkflowCompilationError.duplicateAction
        }
        let enabledSteps = workflow.steps.filter(\.isEnabled)
        guard !enabledSteps.isEmpty else {
            throw SavedWorkflowCompilationError.noEnabledSteps
        }
        guard MatroskaEditingPolicy.supports(asset) else {
            throw SavedWorkflowCompilationError.unsupportedContainer
        }

        var operations = [WorkflowOperation]()
        var summaries = [String]()
        for step in enabledSteps {
            switch step.action {
            case .englishLibraryCleanup:
                let suggestions = EnglishLibraryCleanupPolicy.trackSuggestions(for: asset)
                let identifiers = Set(suggestions.map(\.trackUID))
                if !identifiers.isEmpty {
                    let playableTracks = asset.tracks.filter { $0.kind != .attachment }
                    guard playableTracks.allSatisfy({ $0.uid != nil }),
                        Set(playableTracks.compactMap(\.uid)).count == playableTracks.count
                    else {
                        throw SavedWorkflowCompilationError.unstableTrackIdentity
                    }
                    guard
                        playableTracks.contains(where: { track in
                            track.uid.map { !identifiers.contains($0) } ?? false
                        })
                    else {
                        throw SavedWorkflowCompilationError.wouldRemoveAllTracks
                    }
                    operations.append(.removeTracksByUID(TrackRemoval(trackUIDs: identifiers)))
                    summaries.append(
                        "Remove \(identifiers.count) suggested subtitle track"
                            + (identifiers.count == 1 ? "" : "s")
                    )
                }
            case .removeSegmentTitle:
                if asset.metadata.keys.contains(where: {
                    $0.caseInsensitiveCompare("title") == .orderedSame
                }) {
                    operations.append(.editSegmentTitle(nil))
                    summaries.append("Remove the segment title")
                }
            }
        }
        guard !operations.isEmpty else {
            throw SavedWorkflowCompilationError.noApplicableChanges
        }

        let resolved = WorkflowDefinition(
            id: workflow.id,
            name: workflow.name,
            operations: operations
        )
        return CompiledSavedWorkflow(
            workflowID: workflow.id,
            workflowName: workflow.name,
            operations: operations,
            plan: try WorkflowPlanner().plan(asset: asset, workflow: resolved),
            summaries: summaries
        )
    }
}
