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
    case multipleVideoConversions
    case multipleAudioConversions
    case audioConversionRequiresVideoConversion
    case noAvailableVideoEncoder
    case unavailableVideoPreset(VideoPreset)
    case unavailableAudioPreset(AudioTranscodePreset)
    case unsupportedMediaConversion(ExactTrimPlanningError)
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
        case .multipleVideoConversions:
            "A saved workflow can contain only one enabled video-conversion step."
        case .multipleAudioConversions:
            "A saved workflow can contain only one enabled audio-conversion step."
        case .audioConversionRequiresVideoConversion:
            "Add and enable one video-conversion step before converting audio in the same pass."
        case .noAvailableVideoEncoder:
            "No bundled video encoder passed the local capability check on this Mac."
        case .unavailableVideoPreset(let preset):
            "The selected \(preset.displayName) encoder did not pass the local capability check on this Mac."
        case .unavailableAudioPreset(let preset):
            "The selected \(preset.displayName) audio encoder did not pass the local capability check on this Mac."
        case .unsupportedMediaConversion(let error):
            error.localizedDescription
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
    /// Ordered by the active local recommendation. Paths and probe details never
    /// enter the portable recipe.
    public let availableVideoPresets: [VideoPreset]
    public let availableAudioPresets: [AudioTranscodePreset]

    public init(
        externalSubtitle: SavedWorkflowExternalSubtitleInput? = nil,
        availableVideoPresets: [VideoPreset] = [],
        availableAudioPresets: [AudioTranscodePreset] = []
    ) {
        self.externalSubtitle = externalSubtitle
        self.availableVideoPresets = availableVideoPresets
        self.availableAudioPresets = availableAudioPresets
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
    public let videoConversionChoice: ExactTrimChoice?

    public init(
        workflowID: UUID,
        workflowName: String,
        operations: [WorkflowOperation],
        plan: ExecutionPlan,
        summaries: [String],
        stepOutcomes: [SavedWorkflowStepOutcome] = [],
        externalSubtitleCleanupChangeCount: Int? = nil,
        suggestedOutputFilename: String? = nil,
        videoConversionChoice: ExactTrimChoice? = nil
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.operations = operations
        self.plan = plan
        self.summaries = summaries
        self.stepOutcomes = stepOutcomes
        self.externalSubtitleCleanupChangeCount = externalSubtitleCleanupChangeCount
        self.suggestedOutputFilename = suggestedOutputFilename
        self.videoConversionChoice = videoConversionChoice
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

    public var hasDeterministicMediaOperations: Bool {
        trackRemoval != nil || removesSegmentTitle || externalSubtitleInput != nil
    }

    public var audioConversionPreset: AudioTranscodePreset? {
        videoConversionChoice?.audioPolicy.transcodePreset
    }
}

public struct SavedWorkflowCompiler: Sendable {
    public init() {}

    public func needsEncodingCapabilities(
        for workflow: SavedWorkflow,
        asset: MediaAsset
    ) -> Bool {
        workflow.steps.contains {
            $0.isEnabled && $0.action.videoConversionApplies(to: asset)
        }
    }

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
        let enabledVideoConversions = enabledSteps.filter { $0.action.isVideoConversion }
        guard enabledVideoConversions.count <= 1 else {
            throw SavedWorkflowCompilationError.multipleVideoConversions
        }
        let enabledAudioConversions = enabledSteps.filter { $0.action.isAudioConversion }
        guard enabledAudioConversions.count <= 1 else {
            throw SavedWorkflowCompilationError.multipleAudioConversions
        }
        guard enabledAudioConversions.isEmpty || enabledVideoConversions.count == 1 else {
            throw SavedWorkflowCompilationError.audioConversionRequiresVideoConversion
        }
        let videoConversionWillRun =
            enabledVideoConversions.first?.action
            .videoConversionApplies(to: asset) ?? false
        let audioTrackCount = asset.tracks.count { $0.kind == .audio }
        var audioPolicy = ExactTrimAudioPolicy.packetCopy
        if videoConversionWillRun, audioTrackCount > 0,
            let preset = enabledAudioConversions.first?.action.audioTranscodePreset
        {
            guard inputs.availableAudioPresets.contains(preset) else {
                throw SavedWorkflowCompilationError.unavailableAudioPreset(preset)
            }
            audioPolicy = ExactTrimAudioPolicy(preset: preset)
        }
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
        var videoConversionChoice: ExactTrimChoice?
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
            case .convertVideoIfNotAV1OrHEVC, .convertVideoRecommended, .convertVideoAV1,
                .convertVideoHEVC, .convertVideoH264, .convertVideoProRes:
                guard step.action.videoConversionApplies(to: asset) else {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail: "The video is already AV1 or HEVC; keep it unchanged."
                        )
                    )
                    continue
                }
                let choice = try resolveVideoConversionChoice(
                    for: step.action,
                    asset: asset,
                    audioPolicy: audioPolicy,
                    availableVideoPresets: inputs.availableVideoPresets,
                    availableAudioPresets: inputs.availableAudioPresets
                )
                videoConversionChoice = choice
                operations.append(.transcodeVideo(choice.videoPreset))
                stepOutcomes.append(
                    outcome(
                        for: step,
                        disposition: .applied,
                        detail: videoConversionDetail(choice, audioTrackCount: audioTrackCount)
                    )
                )
            case .convertAudioAAC, .convertAudioOpus, .convertAudioAC3,
                .convertAudioEAC3, .convertAudioFLAC:
                guard let preset = step.action.audioTranscodePreset else {
                    preconditionFailure("A non-audio action reached audio conversion review")
                }
                if !videoConversionWillRun {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail:
                                "Video conversion is not needed; keep every audio track unchanged."
                        )
                    )
                } else if audioTrackCount == 0 {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail: "No audio tracks are present."
                        )
                    )
                } else {
                    let noun = audioTrackCount == 1 ? "track" : "tracks"
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail:
                                "Encode \(audioTrackCount) audio \(noun) once as \(preset.displayName), preserving each channel layout"
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
            plan = reviewedPlan(
                try WorkflowPlanner().plan(asset: asset, workflow: resolved),
                videoConversionChoice: videoConversionChoice,
                audioTrackCount: audioTrackCount
            )
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
            suggestedOutputFilename: suggestedOutputFilename,
            videoConversionChoice: videoConversionChoice
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
        case .convertVideoIfNotAV1OrHEVC, .convertVideoRecommended, .convertVideoAV1,
            .convertVideoHEVC, .convertVideoH264, .convertVideoProRes:
            "Convert video once"
        case .convertAudioAAC, .convertAudioOpus, .convertAudioAC3,
            .convertAudioEAC3, .convertAudioFLAC:
            "Convert audio in the same pass"
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
        case .convertVideoIfNotAV1OrHEVC, .convertVideoRecommended, .convertVideoAV1,
            .convertVideoHEVC, .convertVideoH264, .convertVideoProRes:
            "No video conversion was selected."
        case .convertAudioAAC, .convertAudioOpus, .convertAudioAC3,
            .convertAudioEAC3, .convertAudioFLAC:
            "No audio conversion was selected."
        }
    }

    private func resolveVideoConversionChoice(
        for action: SavedWorkflowAction,
        asset: MediaAsset,
        audioPolicy: ExactTrimAudioPolicy,
        availableVideoPresets: [VideoPreset],
        availableAudioPresets: [AudioTranscodePreset]
    ) throws -> ExactTrimChoice {
        let orderedPresets = availableVideoPresets.reduce(into: [VideoPreset]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        guard !orderedPresets.isEmpty else {
            throw SavedWorkflowCompilationError.noAvailableVideoEncoder
        }
        let candidatePresets: [VideoPreset]
        switch action {
        case .convertVideoIfNotAV1OrHEVC:
            candidatePresets = orderedPresets
        case .convertVideoRecommended:
            candidatePresets = orderedPresets
        case .convertVideoAV1:
            candidatePresets = [.av1Quality]
        case .convertVideoHEVC:
            candidatePresets = [.hevcCompatibility]
        case .convertVideoH264:
            candidatePresets = [.h264Compatibility]
        case .convertVideoProRes:
            candidatePresets = [.proRes]
        default:
            preconditionFailure("A non-conversion action reached conversion resolution")
        }
        if action != .convertVideoRecommended, action != .convertVideoIfNotAV1OrHEVC,
            let requestedPreset = candidatePresets.first,
            !orderedPresets.contains(requestedPreset)
        {
            throw SavedWorkflowCompilationError.unavailableVideoPreset(requestedPreset)
        }
        let planner = ExactTrimPlanner()
        guard let duration = asset.duration else {
            throw SavedWorkflowCompilationError.unsupportedMediaConversion(.invalidDuration)
        }
        guard asset.tracks.contains(where: { $0.kind == .video }) else {
            throw SavedWorkflowCompilationError.unsupportedMediaConversion(.unsupportedTracks)
        }
        guard
            let recommended = planner.recommendedChoice(
                for: asset,
                availableVideoPresets: candidatePresets
            )
        else {
            throw SavedWorkflowCompilationError.unsupportedMediaConversion(
                .unsupportedDynamicRange
            )
        }
        let choice = ExactTrimChoice(
            videoPreset: recommended.videoPreset,
            videoRateControl: recommended.videoRateControl,
            encoderTuning: recommended.encoderTuning,
            audioPolicy: audioPolicy
        )
        do {
            _ = try planner.resolve(
                source: asset,
                range: MediaTrimRange(start: .zero, end: duration),
                choice: choice,
                operation: .transcode,
                availableVideoPresets: Set(orderedPresets),
                aacAvailable: availableAudioPresets.contains(.aacCompatibility),
                availableAudioPresets: Set(availableAudioPresets)
            )
        } catch let error as ExactTrimPlanningError {
            throw SavedWorkflowCompilationError.unsupportedMediaConversion(error)
        }
        return choice
    }

    private func reviewedPlan(
        _ plan: ExecutionPlan,
        videoConversionChoice: ExactTrimChoice?,
        audioTrackCount: Int
    ) -> ExecutionPlan {
        guard let videoConversionChoice else { return plan }
        let audioPreset = videoConversionChoice.audioPolicy.transcodePreset
        let encodeSummary: String
        if let audioPreset {
            let noun = audioTrackCount == 1 ? "track" : "tracks"
            encodeSummary =
                "Encode video once as \(videoConversionChoice.videoPreset.displayName) and \(audioTrackCount) audio \(noun) once as \(audioPreset.displayName); packet-copy subtitles"
        } else {
            encodeSummary =
                "Encode video once as \(videoConversionChoice.videoPreset.displayName) while packet-copying audio and subtitles"
        }
        let encode = plan.stages.filter { $0.mechanism == .ffmpegEncode }.map {
            PlanStage(
                id: $0.id,
                mechanism: $0.mechanism,
                summary: encodeSummary
            )
        }
        let preparation = plan.stages.filter {
            $0.mechanism != .ffmpegEncode && $0.mechanism != .verify && $0.mechanism != .commit
        }
        let completion = plan.stages.filter {
            $0.mechanism == .verify || $0.mechanism == .commit
        }
        return ExecutionPlan(
            stages: preparation + encode + completion,
            impact: PlanImpact(
                videoEncodeCount: plan.impact.videoEncodeCount,
                audioEncodeCount: audioPreset == nil ? 0 : audioTrackCount,
                copiesVideo: plan.impact.copiesVideo,
                changesSourceBeforeVerification: plan.impact.changesSourceBeforeVerification,
                warnings: plan.impact.warnings
            )
        )
    }

    private func videoConversionDetail(
        _ choice: ExactTrimChoice,
        audioTrackCount: Int
    ) -> String {
        guard let preset = choice.audioPolicy.transcodePreset else {
            return
                "Encode video once as \(choice.videoPreset.displayName); packet-copy every audio and subtitle track"
        }
        let noun = audioTrackCount == 1 ? "track" : "tracks"
        return
            "Encode video once as \(choice.videoPreset.displayName) and \(audioTrackCount) audio \(noun) once as \(preset.displayName); packet-copy subtitles"
    }
}
