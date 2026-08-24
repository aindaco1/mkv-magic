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
    case missingExternalSubtitleInput
    case invalidExternalSubtitleInput
    case externalSubtitleCleanupRequiresAddStep
    case missingExternalSubtitleCleanupReview
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
        case .missingExternalSubtitleInput:
            "Choose and confirm an external subtitle before previewing this workflow."
        case .invalidExternalSubtitleInput:
            "The external subtitle input does not match the reviewed workflow input."
        case .externalSubtitleCleanupRequiresAddStep:
            "Enable Add one external text subtitle before cleaning its text."
        case .missingExternalSubtitleCleanupReview:
            "Review the external subtitle cleanup suggestions before previewing this workflow."
        case .unstableTrackIdentity:
            "This file does not expose stable Matroska identifiers for every track."
        case .wouldRemoveAllTracks: "This workflow would remove every playable track."
        case .noApplicableChanges: "This file already satisfies the enabled workflow steps."
        }
    }
}

public struct SavedWorkflowExternalSubtitleInput: Equatable, Sendable {
    public let sourceURL: URL
    public let metadata: ExternalSubtitleTrackMetadata
    public let format: ExternalTextSubtitleFormat
    public let reviewedCleanupChangeCount: Int?

    public init(
        sourceURL: URL,
        metadata: ExternalSubtitleTrackMetadata,
        format: ExternalTextSubtitleFormat,
        reviewedCleanupChangeCount: Int? = nil
    ) {
        self.sourceURL = sourceURL
        self.metadata = metadata
        self.format = format
        self.reviewedCleanupChangeCount = reviewedCleanupChangeCount
    }
}

public struct SavedWorkflowResolvedInputs: Equatable, Sendable {
    public let externalSubtitle: SavedWorkflowExternalSubtitleInput?

    public init(externalSubtitle: SavedWorkflowExternalSubtitleInput? = nil) {
        self.externalSubtitle = externalSubtitle
    }
}

public enum SavedWorkflowStepDisposition: Equatable, Sendable {
    case applied
    case skipped
    case disabled
}

public struct SavedWorkflowStepOutcome: Equatable, Sendable {
    public let stepID: UUID
    public let action: SavedWorkflowAction
    public let disposition: SavedWorkflowStepDisposition
    public let detail: String

    public init(
        stepID: UUID,
        action: SavedWorkflowAction,
        disposition: SavedWorkflowStepDisposition,
        detail: String
    ) {
        self.stepID = stepID
        self.action = action
        self.disposition = disposition
        self.detail = detail
    }
}

public struct SavedWorkflowCompilationPreview: Equatable, Sendable {
    public let workflowID: UUID
    public let workflowName: String
    public let stepOutcomes: [SavedWorkflowStepOutcome]
    public let compiledWorkflow: CompiledSavedWorkflow?

    public init(
        workflowID: UUID,
        workflowName: String,
        stepOutcomes: [SavedWorkflowStepOutcome],
        compiledWorkflow: CompiledSavedWorkflow?
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.stepOutcomes = stepOutcomes
        self.compiledWorkflow = compiledWorkflow
    }
}

public struct CompiledSavedWorkflow: Equatable, Sendable {
    public let workflowID: UUID
    public let workflowName: String
    public let operations: [WorkflowOperation]
    public let plan: ExecutionPlan
    public let summaries: [String]
    public let stepOutcomes: [SavedWorkflowStepOutcome]
    public let externalSubtitleCleanupChangeCount: Int?
    public let suggestedOutputFilename: String?

    public init(
        workflowID: UUID,
        workflowName: String,
        operations: [WorkflowOperation],
        plan: ExecutionPlan,
        summaries: [String],
        stepOutcomes: [SavedWorkflowStepOutcome] = [],
        externalSubtitleCleanupChangeCount: Int? = nil,
        suggestedOutputFilename: String? = nil
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.operations = operations
        self.plan = plan
        self.summaries = summaries
        self.stepOutcomes = stepOutcomes
        self.externalSubtitleCleanupChangeCount = externalSubtitleCleanupChangeCount
        self.suggestedOutputFilename = suggestedOutputFilename
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

    public var externalSubtitleInput: SavedWorkflowExternalSubtitleInput? {
        for operation in operations {
            if case .addExternalSubtitle(let url, let metadata, let format) = operation {
                return SavedWorkflowExternalSubtitleInput(
                    sourceURL: url,
                    metadata: metadata,
                    format: format,
                    reviewedCleanupChangeCount: externalSubtitleCleanupChangeCount
                )
            }
        }
        return nil
    }

    public var createsUnchangedCopy: Bool {
        operations.isEmpty && suggestedOutputFilename != nil
    }
}

public struct SavedWorkflowCompiler: Sendable {
    public init() {}

    public func compile(
        _ workflow: SavedWorkflow,
        for asset: MediaAsset,
        inputs: SavedWorkflowResolvedInputs = SavedWorkflowResolvedInputs()
    ) throws -> CompiledSavedWorkflow {
        guard
            let compiled = try preview(
                workflow,
                for: asset,
                inputs: inputs
            ).compiledWorkflow
        else {
            throw SavedWorkflowCompilationError.noApplicableChanges
        }
        return compiled
    }

    public func preview(
        _ inputWorkflow: SavedWorkflow,
        for asset: MediaAsset,
        inputs: SavedWorkflowResolvedInputs = SavedWorkflowResolvedInputs()
    ) throws -> SavedWorkflowCompilationPreview {
        let workflow: SavedWorkflow
        do {
            workflow = try SavedWorkflowMigrator().migrate(inputWorkflow)
        } catch {
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
        let enabledActions = Set(enabledSteps.map(\.action))
        if enabledActions.contains(.cleanExternalSubtitleText),
            !enabledActions.contains(.addExternalSubtitle)
        {
            throw SavedWorkflowCompilationError.externalSubtitleCleanupRequiresAddStep
        }

        var operations = [WorkflowOperation]()
        var stepOutcomes = [SavedWorkflowStepOutcome]()
        var removalTrackUIDs = Set<UInt64>()
        var removalInsertionIndex: Int?
        var suggestedOutputFilename: String?
        for step in workflow.steps {
            guard step.isEnabled else {
                stepOutcomes.append(
                    outcome(for: step, disposition: .disabled, detail: "Not included in this run.")
                )
                continue
            }
            switch step.action {
            case .englishLibraryCleanup, .removeNonEnglishSubtitles,
                .removeRedundantEnglishSDH:
                let suggestions = cleanupSuggestions(for: step.action, asset: asset)
                let identifiers = Set(suggestions.map(\.trackUID))
                if !identifiers.isEmpty {
                    if removalInsertionIndex == nil { removalInsertionIndex = operations.count }
                    removalTrackUIDs.formUnion(identifiers)
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail: cleanupSummary(for: step.action, count: identifiers.count)
                        )
                    )
                } else {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail: skippedCleanupSummary(for: step.action)
                        )
                    )
                }
            case .removeSegmentTitle:
                if asset.metadata.keys.contains(where: {
                    $0.caseInsensitiveCompare("title") == .orderedSame
                }) {
                    operations.append(.editSegmentTitle(nil))
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail: "Remove the segment title"
                        )
                    )
                } else {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail: "No segment title is present."
                        )
                    )
                }
            case .normalizeFilename:
                if let suggestion = MediaFilenameNormalizationPolicy.suggestedFilename(
                    for: asset.sourceURL
                ) {
                    suggestedOutputFilename = suggestion
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail: "Suggest the output filename “\(suggestion)”"
                        )
                    )
                } else {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail:
                                "The filename is already simple; keep the normal output suggestion."
                        )
                    )
                }
            case .addExternalSubtitle:
                guard let input = inputs.externalSubtitle else {
                    throw SavedWorkflowCompilationError.missingExternalSubtitleInput
                }
                guard input.sourceURL.standardizedFileURL != asset.sourceURL.standardizedFileURL,
                    input.sourceURL.pathExtension.lowercased()
                        == input.format.filenameExtension
                else {
                    throw SavedWorkflowCompilationError.invalidExternalSubtitleInput
                }
                operations.append(
                    .addExternalSubtitle(
                        url: input.sourceURL,
                        metadata: input.metadata,
                        format: input.format
                    )
                )
                stepOutcomes.append(
                    outcome(
                        for: step,
                        disposition: .applied,
                        detail:
                            "Add one reviewed \(input.format.displayName) subtitle as the last track"
                    )
                )
            case .cleanExternalSubtitleText:
                guard let input = inputs.externalSubtitle,
                    let reviewedChangeCount = input.reviewedCleanupChangeCount
                else {
                    throw SavedWorkflowCompilationError.missingExternalSubtitleCleanupReview
                }
                guard reviewedChangeCount >= 0 else {
                    throw SavedWorkflowCompilationError.invalidExternalSubtitleInput
                }
                if reviewedChangeCount > 0 {
                    let noun = reviewedChangeCount == 1 ? "change" : "changes"
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail:
                                "Apply \(reviewedChangeCount) reviewed subtitle text \(noun) inside the same remux"
                        )
                    )
                } else {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail: "No subtitle text cleanup changes were selected."
                        )
                    )
                }
            }
        }
        if !removalTrackUIDs.isEmpty {
            let playableTracks = asset.tracks.filter { $0.kind != .attachment }
            guard playableTracks.allSatisfy({ $0.uid != nil }),
                Set(playableTracks.compactMap(\.uid)).count == playableTracks.count
            else {
                throw SavedWorkflowCompilationError.unstableTrackIdentity
            }
            guard
                playableTracks.contains(where: { track in
                    track.uid.map { !removalTrackUIDs.contains($0) } ?? false
                })
            else {
                throw SavedWorkflowCompilationError.wouldRemoveAllTracks
            }
            operations.insert(
                .removeTracksByUID(TrackRemoval(trackUIDs: removalTrackUIDs)),
                at: removalInsertionIndex ?? operations.endIndex
            )
        }
        guard !operations.isEmpty || suggestedOutputFilename != nil else {
            return SavedWorkflowCompilationPreview(
                workflowID: workflow.id,
                workflowName: workflow.name,
                stepOutcomes: stepOutcomes,
                compiledWorkflow: nil
            )
        }

        let plan: ExecutionPlan
        if operations.isEmpty {
            plan = ExecutionPlan(
                stages: [
                    PlanStage(
                        mechanism: .verify,
                        summary: "Verify an unchanged output copy"
                    ),
                    PlanStage(
                        mechanism: .commit,
                        summary: "Commit the verified result"
                    ),
                ],
                impact: PlanImpact(
                    videoEncodeCount: 0,
                    audioEncodeCount: 0,
                    copiesVideo: true
                )
            )
        } else {
            let resolved = WorkflowDefinition(
                id: workflow.id,
                name: workflow.name,
                operations: operations
            )
            plan = try WorkflowPlanner().plan(asset: asset, workflow: resolved)
        }
        let compiled = CompiledSavedWorkflow(
            workflowID: workflow.id,
            workflowName: workflow.name,
            operations: operations,
            plan: plan,
            summaries: stepOutcomes.filter { $0.disposition == .applied }.map(\.detail),
            stepOutcomes: stepOutcomes,
            externalSubtitleCleanupChangeCount: enabledActions.contains(
                .cleanExternalSubtitleText
            ) ? inputs.externalSubtitle?.reviewedCleanupChangeCount : nil,
            suggestedOutputFilename: suggestedOutputFilename
        )
        return SavedWorkflowCompilationPreview(
            workflowID: workflow.id,
            workflowName: workflow.name,
            stepOutcomes: stepOutcomes,
            compiledWorkflow: compiled
        )
    }

    private func outcome(
        for step: SavedWorkflowStep,
        disposition: SavedWorkflowStepDisposition,
        detail: String
    ) -> SavedWorkflowStepOutcome {
        SavedWorkflowStepOutcome(
            stepID: step.id,
            action: step.action,
            disposition: disposition,
            detail: detail
        )
    }

    private func cleanupSuggestions(
        for action: SavedWorkflowAction,
        asset: MediaAsset
    ) -> [CleanMKVTrackSuggestion] {
        EnglishLibraryCleanupPolicy.trackSuggestions(for: asset).filter { suggestion in
            switch (action, suggestion.reason) {
            case (.englishLibraryCleanup, _),
                (.removeNonEnglishSubtitles, .nonEnglishSubtitle(_)),
                (.removeRedundantEnglishSDH, .redundantSDH):
                true
            default:
                false
            }
        }
    }

    private func cleanupSummary(for action: SavedWorkflowAction, count: Int) -> String {
        let noun = count == 1 ? "track" : "tracks"
        return switch action {
        case .englishLibraryCleanup:
            "Remove \(count) suggested subtitle \(noun)"
        case .removeNonEnglishSubtitles:
            "Remove \(count) explicitly non-English subtitle \(noun)"
        case .removeRedundantEnglishSDH:
            "Remove \(count) redundant English SDH subtitle \(noun)"
        case .removeSegmentTitle:
            "Remove the segment title"
        case .normalizeFilename:
            "Clean up the output filename"
        case .addExternalSubtitle:
            "Add one external subtitle"
        case .cleanExternalSubtitleText:
            "Clean the added subtitle text"
        }
    }

    private func skippedCleanupSummary(for action: SavedWorkflowAction) -> String {
        switch action {
        case .englishLibraryCleanup:
            "No suggested subtitle tracks were found."
        case .removeNonEnglishSubtitles:
            "No explicitly non-English subtitle tracks were found."
        case .removeRedundantEnglishSDH:
            "No redundant English SDH subtitle tracks were found."
        case .removeSegmentTitle:
            "No segment title is present."
        case .normalizeFilename:
            "The filename is already simple."
        case .addExternalSubtitle:
            "No external subtitle was selected."
        case .cleanExternalSubtitleText:
            "No subtitle text cleanup changes were selected."
        }
    }
}
