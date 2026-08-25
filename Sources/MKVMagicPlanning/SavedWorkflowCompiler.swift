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
    case commonInputRequiresVideoConversion
    case commonInputCannotCombineWithMatroskaEdits
    case remuxCannotCombineWithOtherActions
    case unsupportedMKVRemux(MKVRemuxPlanningError)
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
    case unavailableMatroskaTagCounts
    case unavailableAttachmentIdentity
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
        case .unsupportedContainer:
            "This workflow cannot use the selected media container."
        case .commonInputRequiresVideoConversion:
            "MP4, M4V, MOV, and WebM workflow input currently requires one video-conversion step that applies to this file."
        case .commonInputCannotCombineWithMatroskaEdits:
            "For MP4, M4V, MOV, and WebM input, combine video conversion only with optional audio conversion and filename cleanup. Apply MKV track, subtitle, title, or chapter edits in a later workflow."
        case .remuxCannotCombineWithOtherActions:
            "Remux to MKV can currently be combined only with output filename cleanup. Disable the other media-changing steps."
        case .unsupportedMKVRemux(let error): error.localizedDescription
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
        case .unavailableMatroskaTagCounts:
            "Inspect the file again before removing its Matroska tags."
        case .unavailableAttachmentIdentity:
            "Inspect the file again before removing its image attachments."
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
    public let mkvRemuxPlan: ResolvedMKVRemuxPlan?

    public init(
        workflowID: UUID,
        workflowName: String,
        operations: [WorkflowOperation],
        plan: ExecutionPlan,
        summaries: [String],
        stepOutcomes: [SavedWorkflowStepOutcome] = [],
        externalSubtitleCleanupChangeCount: Int? = nil,
        suggestedOutputFilename: String? = nil,
        videoConversionChoice: ExactTrimChoice? = nil,
        mkvRemuxPlan: ResolvedMKVRemuxPlan? = nil
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
        self.mkvRemuxPlan = mkvRemuxPlan
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

    public var clearsAllTags: Bool {
        operations.contains(.clearAllTags)
    }

    public var attachmentRemoval: MatroskaAttachmentRemoval? {
        for operation in operations {
            if case .removeAttachments(let removal) = operation { return removal }
        }
        return nil
    }

    public var trackMetadataEdits: [TrackMetadataEdit] {
        operations.compactMap { operation in
            if case .editTrackMetadata(let edit) = operation { return edit }
            return nil
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
        operations.isEmpty && suggestedOutputFilename != nil && mkvRemuxPlan == nil
    }

    public var hasDeterministicMediaOperations: Bool {
        trackRemoval != nil || attachmentRemoval != nil || !trackMetadataEdits.isEmpty
            || removesSegmentTitle || clearsAllTags || externalSubtitleInput != nil
            || mkvRemuxPlan != nil
    }

    public var audioConversionPreset: AudioTranscodePreset? {
        for operation in operations {
            if case .transcodeAudio(let preset) = operation { return preset }
        }
        return videoConversionChoice?.audioPolicy.transcodePreset
    }

    /// These execution paths always emit Matroska regardless of the source
    /// filename. Keep Save-panel naming aligned with the reviewed command.
    public var requiresMKVOutputExtension: Bool {
        mkvRemuxPlan != nil || videoConversionChoice != nil || audioConversionPreset != nil
            || externalSubtitleInput != nil
    }
}

public struct SavedWorkflowCompiler: Sendable {
    public init() {}

    public func needsEncodingCapabilities(
        for workflow: SavedWorkflow,
        asset: MediaAsset
    ) -> Bool {
        if workflow.steps.contains(where: { $0.isEnabled && $0.action == .remuxToMKV }),
            MKVRemuxPlanner().canOffer(for: asset)
        {
            return false
        }
        let enabledActions = Set(workflow.steps.filter(\.isEnabled).map(\.action))
        if !MatroskaEditingPolicy.supports(asset) {
            guard ExactTrimPlanner().recognizesCompleteTranscodeContainer(asset) else {
                return false
            }
            let videoWillRun = workflow.steps.contains {
                $0.isEnabled && $0.action.videoConversionApplies(to: asset)
            }
            guard
                Self.commonInputCompositionError(
                    enabledActions: enabledActions,
                    videoConversionWillRun: videoWillRun
                ) == nil
            else { return false }
        }
        let videoWillRun = workflow.steps.contains {
            $0.isEnabled && $0.action.videoConversionApplies(to: asset)
        }
        if videoWillRun { return true }
        guard
            let preset = workflow.steps.first(where: {
                $0.isEnabled && $0.action.isStandaloneAudioConversion
            })?.action.audioTranscodePreset
        else { return false }
        return asset.tracks.contains {
            $0.kind == .audio && !preset.matches(sourceCodec: $0.codec)
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
        let enabledActions = Set(enabledSteps.map(\.action))
        let enabledVideoConversions = enabledSteps.filter { $0.action.isVideoConversion }
        guard enabledVideoConversions.count <= 1 else {
            throw SavedWorkflowCompilationError.multipleVideoConversions
        }
        let enabledAudioConversions = enabledSteps.filter { $0.action.isAudioConversion }
        guard enabledAudioConversions.count <= 1 else {
            throw SavedWorkflowCompilationError.multipleAudioConversions
        }
        guard
            enabledAudioConversions.first?.action.requiresVideoConversion != true
                || enabledVideoConversions.count == 1
        else {
            throw SavedWorkflowCompilationError.audioConversionRequiresVideoConversion
        }
        let videoConversionWillRun =
            enabledVideoConversions.first?.action
            .videoConversionApplies(to: asset) ?? false
        let mkvRemuxPlan: ResolvedMKVRemuxPlan?
        if enabledActions.contains(.remuxToMKV) {
            do {
                mkvRemuxPlan = try MKVRemuxPlanner().resolve(source: asset)
            } catch MKVRemuxPlanningError.alreadyMatroskaMKV {
                guard MatroskaEditingPolicy.supports(asset) else {
                    throw SavedWorkflowCompilationError.unsupportedContainer
                }
                mkvRemuxPlan = nil
            } catch let error as MKVRemuxPlanningError {
                throw SavedWorkflowCompilationError.unsupportedMKVRemux(error)
            }
        } else if MatroskaEditingPolicy.supports(asset) {
            mkvRemuxPlan = nil
        } else if ExactTrimPlanner().recognizesCompleteTranscodeContainer(asset) {
            if let error = Self.commonInputCompositionError(
                enabledActions: enabledActions,
                videoConversionWillRun: videoConversionWillRun
            ) {
                throw error
            }
            mkvRemuxPlan = nil
        } else {
            throw SavedWorkflowCompilationError.unsupportedContainer
        }
        if mkvRemuxPlan != nil {
            let compatibleActions: Set<SavedWorkflowAction> = [.remuxToMKV, .normalizeFilename]
            guard enabledActions.isSubset(of: compatibleActions) else {
                throw SavedWorkflowCompilationError.remuxCannotCombineWithOtherActions
            }
        }
        let clearsAllTagsWillRun: Bool
        if enabledActions.contains(.clearAllTags) {
            do {
                _ = try MatroskaTagPolicy.counts(in: asset)
                clearsAllTagsWillRun = true
            } catch MatroskaTagPolicyError.noTags {
                clearsAllTagsWillRun = false
            } catch MatroskaTagPolicyError.unavailableCounts {
                throw SavedWorkflowCompilationError.unavailableMatroskaTagCounts
            } catch {
                throw SavedWorkflowCompilationError.unsupportedContainer
            }
        } else {
            clearsAllTagsWillRun = false
        }
        let conversionPlanningAsset =
            clearsAllTagsWillRun ? assetWithClearedTagFacts(asset) : asset
        let imageAttachmentRemoval: MatroskaAttachmentRemoval?
        if enabledActions.contains(.removeImageAttachments) {
            do {
                imageAttachmentRemoval =
                    try MatroskaAttachmentRemovalPolicy.imageAttachmentRemoval(in: asset)
            } catch MatroskaAttachmentRemovalPolicyError.unstableAttachmentIdentity {
                throw SavedWorkflowCompilationError.unavailableAttachmentIdentity
            } catch {
                throw SavedWorkflowCompilationError.unsupportedContainer
            }
        } else {
            imageAttachmentRemoval = nil
        }
        let commentaryFlagEdits: [TrackMetadataEdit]
        if enabledActions.contains(.markCommentaryTracks) {
            do {
                commentaryFlagEdits = try CommentaryTrackPolicy.metadataEdits(in: asset)
            } catch TrackRolePolicyError.unstableTrackIdentity {
                throw SavedWorkflowCompilationError.unstableTrackIdentity
            }
        } else {
            commentaryFlagEdits = []
        }
        let commentaryNameEdits: [TrackMetadataEdit]
        if enabledActions.contains(.normalizeCommentaryNames) {
            do {
                commentaryNameEdits = try CommentaryNamePolicy.metadataEdits(in: asset)
            } catch TrackRolePolicyError.unstableTrackIdentity {
                throw SavedWorkflowCompilationError.unstableTrackIdentity
            }
        } else {
            commentaryNameEdits = []
        }
        let forcedSubtitleEdits: [TrackMetadataEdit]
        if enabledActions.contains(.markForcedSubtitles) {
            do {
                forcedSubtitleEdits = try ForcedSubtitlePolicy.metadataEdits(in: asset)
            } catch TrackRolePolicyError.unstableTrackIdentity {
                throw SavedWorkflowCompilationError.unstableTrackIdentity
            }
        } else {
            forcedSubtitleEdits = []
        }
        let roleMetadataEdits = mergedTrackRoleEdits(
            asset: asset,
            commentaryFlagEdits: commentaryFlagEdits,
            commentaryNameEdits: commentaryNameEdits,
            forcedSubtitleEdits: forcedSubtitleEdits
        )
        let roleOperationInsertionAction = enabledSteps.first { step in
            switch step.action {
            case .markCommentaryTracks: !commentaryFlagEdits.isEmpty
            case .normalizeCommentaryNames: !commentaryNameEdits.isEmpty
            case .markForcedSubtitles: !forcedSubtitleEdits.isEmpty
            default: false
            }
        }?.action
        let audioTracks = asset.tracks.filter { $0.kind == .audio }
        let audioTrackCount = audioTracks.count
        let selectedAudioPreset = enabledAudioConversions.first?.action.audioTranscodePreset
        let audioTracksToEncode =
            selectedAudioPreset.map { preset in
                audioTracks.filter { !preset.matches(sourceCodec: $0.codec) }
            } ?? []
        let audioEncodeCount = audioTracksToEncode.count
        let audioConversionWillRun =
            audioEncodeCount > 0
            && (enabledAudioConversions.first?.action.requiresVideoConversion != true
                || videoConversionWillRun)
        var audioPolicy = ExactTrimAudioPolicy.packetCopy
        if audioConversionWillRun,
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
            case .remuxToMKV:
                if let mkvRemuxPlan {
                    let trackNoun = mkvRemuxPlan.copiedTrackCount == 1 ? "track" : "tracks"
                    let chapterDetail =
                        mkvRemuxPlan.chapterCarrierTrackIDs.isEmpty
                        ? "preserve the reviewed chapter table"
                        : "translate the MP4 chapter carrier into nested Matroska chapters"
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail:
                                "Packet-copy \(mkvRemuxPlan.copiedTrackCount) media \(trackNoun) into MKV and \(chapterDetail)"
                        )
                    )
                } else {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail: "The source is already an MKV; keep its container unchanged."
                        )
                    )
                }
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
            case .clearAllTags:
                if clearsAllTagsWillRun {
                    operations.append(.clearAllTags)
                    let globalCount = asset.globalTagCount ?? 0
                    let trackCount = asset.trackTagCount ?? 0
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail:
                                "Remove \(globalCount) global and \(trackCount) track Matroska tags"
                        )
                    )
                } else {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail: "No global or track Matroska tags are present."
                        )
                    )
                }
            case .removeImageAttachments:
                if let imageAttachmentRemoval {
                    operations.append(.removeAttachments(imageAttachmentRemoval))
                    let count = imageAttachmentRemoval.attachmentUIDs.count
                    let noun = count == 1 ? "attachment" : "attachments"
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail: "Remove \(count) MIME-identified image \(noun)"
                        )
                    )
                } else {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail: "No MIME-identified image attachments are present."
                        )
                    )
                }
            case .markCommentaryTracks:
                if commentaryFlagEdits.isEmpty {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail: "No unmarked, clearly named commentary tracks are present."
                        )
                    )
                } else {
                    if roleOperationInsertionAction == step.action {
                        operations.append(
                            contentsOf: roleMetadataEdits.map(
                                WorkflowOperation.editTrackMetadata
                            )
                        )
                    }
                    let count = commentaryFlagEdits.count
                    let noun = count == 1 ? "track" : "tracks"
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail: "Mark \(count) clearly named commentary \(noun)"
                        )
                    )
                }
            case .normalizeCommentaryNames:
                if commentaryNameEdits.isEmpty {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail:
                                "Recognized commentary track names already follow the simple numbering convention."
                        )
                    )
                } else {
                    if roleOperationInsertionAction == step.action {
                        operations.append(
                            contentsOf: roleMetadataEdits.map(
                                WorkflowOperation.editTrackMetadata
                            )
                        )
                    }
                    let count = commentaryNameEdits.count
                    let noun = count == 1 ? "name" : "names"
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail: "Normalize \(count) commentary track \(noun)"
                        )
                    )
                }
            case .markForcedSubtitles:
                if forcedSubtitleEdits.isEmpty {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail: "No unmarked subtitle track contains the distinct word forced."
                        )
                    )
                } else {
                    if roleOperationInsertionAction == step.action {
                        operations.append(
                            contentsOf: roleMetadataEdits.map(
                                WorkflowOperation.editTrackMetadata
                            )
                        )
                    }
                    let count = forcedSubtitleEdits.count
                    let noun = count == 1 ? "subtitle" : "subtitles"
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail: "Mark \(count) clearly named forced \(noun)"
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
                    asset: conversionPlanningAsset,
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
                        detail: videoConversionDetail(
                            choice,
                            audioEncodeCount: audioEncodeCount,
                            copiedAudioCount: audioTrackCount - audioEncodeCount
                        )
                    )
                )
            case .convertAudioAAC, .convertAudioOpus, .convertAudioAC3,
                .convertAudioEAC3, .convertAudioFLAC, .transcodeAllAudioAAC,
                .transcodeAllAudioOpus, .transcodeAllAudioAC3,
                .transcodeAllAudioEAC3, .transcodeAllAudioFLAC:
                guard let preset = step.action.audioTranscodePreset else {
                    preconditionFailure("A non-audio action reached audio conversion review")
                }
                if step.action.requiresVideoConversion, !videoConversionWillRun {
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
                } else if audioEncodeCount == 0 {
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .skipped,
                            detail:
                                "Every audio track is already \(preset.displayName); keep each packet unchanged."
                        )
                    )
                } else {
                    operations.append(.transcodeAudio(preset))
                    let noun = audioEncodeCount == 1 ? "track" : "tracks"
                    let copiedAudioCount = audioTrackCount - audioEncodeCount
                    let copyDetail =
                        copiedAudioCount == 0
                        ? ""
                        : "; packet-copy \(copiedAudioCount) already-matching audio track\(copiedAudioCount == 1 ? "" : "s")"
                    stepOutcomes.append(
                        outcome(
                            for: step,
                            disposition: .applied,
                            detail:
                                "Encode \(audioEncodeCount) audio \(noun) once as \(preset.displayName), preserving each channel layout\(copyDetail)"
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
        guard !operations.isEmpty || suggestedOutputFilename != nil || mkvRemuxPlan != nil else {
            return SavedWorkflowCompilationPreview(
                workflowID: workflow.id,
                workflowName: workflow.name,
                stepOutcomes: stepOutcomes,
                compiledWorkflow: nil
            )
        }

        let plan: ExecutionPlan
        if let mkvRemuxPlan {
            let trackNoun = mkvRemuxPlan.copiedTrackCount == 1 ? "track" : "tracks"
            plan = ExecutionPlan(
                stages: [
                    PlanStage(
                        mechanism: .mkvMerge,
                        summary:
                            "Packet-copy \(mkvRemuxPlan.copiedTrackCount) compatible media \(trackNoun) into one MKV"
                    ),
                    PlanStage(
                        mechanism: .verify,
                        summary: "Verify copied packet payloads, tracks, and chapters"
                    ),
                    PlanStage(
                        mechanism: .commit,
                        summary: "Commit and reopen the verified MKV"
                    ),
                ],
                impact: PlanImpact(
                    videoEncodeCount: 0,
                    audioEncodeCount: 0,
                    copiesVideo: true
                )
            )
        } else if operations.isEmpty {
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
                audioConversionPreset: audioConversionWillRun
                    ? enabledAudioConversions.first?.action.audioTranscodePreset : nil,
                audioEncodeCount: audioEncodeCount
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
            videoConversionChoice: videoConversionChoice,
            mkvRemuxPlan: mkvRemuxPlan
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

    private static func commonInputCompositionError(
        enabledActions: Set<SavedWorkflowAction>,
        videoConversionWillRun: Bool
    ) -> SavedWorkflowCompilationError? {
        guard
            enabledActions.allSatisfy({ action in
                action.isVideoConversion || action.isAudioConversion
                    || action == .normalizeFilename
            })
        else {
            return .commonInputCannotCombineWithMatroskaEdits
        }
        return videoConversionWillRun ? nil : .commonInputRequiresVideoConversion
    }

    private func mergedTrackRoleEdits(
        asset: MediaAsset,
        commentaryFlagEdits: [TrackMetadataEdit],
        commentaryNameEdits: [TrackMetadataEdit],
        forcedSubtitleEdits: [TrackMetadataEdit]
    ) -> [TrackMetadataEdit] {
        let commentaryFlagsByUID = Dictionary(
            uniqueKeysWithValues: commentaryFlagEdits.map { ($0.trackUID, $0) }
        )
        let commentaryNamesByUID = Dictionary(
            uniqueKeysWithValues: commentaryNameEdits.map { ($0.trackUID, $0) }
        )
        let forcedSubtitlesByUID = Dictionary(
            uniqueKeysWithValues: forcedSubtitleEdits.map { ($0.trackUID, $0) }
        )
        return asset.tracks.compactMap { track in
            guard let uid = track.uid,
                let base = commentaryNamesByUID[uid] ?? commentaryFlagsByUID[uid]
                    ?? forcedSubtitlesByUID[uid]
            else {
                return nil
            }
            return TrackMetadataEdit(
                trackUID: uid,
                name: commentaryNamesByUID[uid]?.name ?? base.name,
                language: base.language,
                isDefault: base.isDefault,
                isForced: forcedSubtitlesByUID[uid]?.isForced ?? base.isForced,
                isEnabled: base.isEnabled,
                isCommentary: commentaryFlagsByUID[uid]?.isCommentary ?? base.isCommentary,
                isHearingImpaired: base.isHearingImpaired,
                isVisualImpaired: base.isVisualImpaired,
                isOriginal: base.isOriginal,
                isTextDescription: base.isTextDescription
            )
        }
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
        case .clearAllTags:
            "Remove all Matroska tags"
        case .removeImageAttachments:
            "Remove image attachments"
        case .markCommentaryTracks:
            "Mark clearly named commentary tracks"
        case .normalizeCommentaryNames:
            "Normalize commentary track names"
        case .markForcedSubtitles:
            "Mark clearly named forced subtitles"
        case .normalizeFilename:
            "Clean up the output filename"
        case .addExternalSubtitle:
            "Add one external subtitle"
        case .cleanExternalSubtitleText:
            "Clean the added subtitle text"
        case .remuxToMKV:
            "Remux compatible media to MKV"
        case .convertVideoIfNotAV1OrHEVC, .convertVideoRecommended, .convertVideoAV1,
            .convertVideoHEVC, .convertVideoH264, .convertVideoProRes:
            "Convert video once"
        case .convertAudioAAC, .convertAudioOpus, .convertAudioAC3,
            .convertAudioEAC3, .convertAudioFLAC:
            "Convert audio in the same pass"
        case .transcodeAllAudioAAC, .transcodeAllAudioOpus, .transcodeAllAudioAC3,
            .transcodeAllAudioEAC3, .transcodeAllAudioFLAC:
            "Convert every audio track once"
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
        case .clearAllTags:
            "No global or track Matroska tags are present."
        case .removeImageAttachments:
            "No MIME-identified image attachments are present."
        case .markCommentaryTracks:
            "No unmarked, clearly named commentary tracks are present."
        case .normalizeCommentaryNames:
            "Recognized commentary track names already follow the simple numbering convention."
        case .markForcedSubtitles:
            "No unmarked subtitle track contains the distinct word forced."
        case .normalizeFilename:
            "The filename is already simple."
        case .addExternalSubtitle:
            "No external subtitle was selected."
        case .cleanExternalSubtitleText:
            "No subtitle text cleanup changes were selected."
        case .remuxToMKV:
            "The source is already an MKV."
        case .convertVideoIfNotAV1OrHEVC, .convertVideoRecommended, .convertVideoAV1,
            .convertVideoHEVC, .convertVideoH264, .convertVideoProRes:
            "No video conversion was selected."
        case .convertAudioAAC, .convertAudioOpus, .convertAudioAC3,
            .convertAudioEAC3, .convertAudioFLAC, .transcodeAllAudioAAC,
            .transcodeAllAudioOpus, .transcodeAllAudioAC3,
            .transcodeAllAudioEAC3, .transcodeAllAudioFLAC:
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

    private func assetWithClearedTagFacts(_ asset: MediaAsset) -> MediaAsset {
        MediaAsset(
            id: asset.id,
            sourceURL: asset.sourceURL,
            container: asset.container,
            formatLongName: asset.formatLongName,
            duration: asset.duration,
            fileSize: asset.fileSize,
            bitrate: asset.bitrate,
            tracks: asset.tracks,
            chapters: asset.chapters,
            attachments: asset.attachments,
            metadata: asset.metadata,
            chapterEntryCount: asset.chapterEntryCount,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: asset.segmentUID,
            muxingApplication: asset.muxingApplication,
            writingApplication: asset.writingApplication,
            warnings: asset.warnings
        )
    }

    private func reviewedPlan(
        _ plan: ExecutionPlan,
        videoConversionChoice: ExactTrimChoice?,
        audioConversionPreset: AudioTranscodePreset?,
        audioEncodeCount: Int
    ) -> ExecutionPlan {
        guard videoConversionChoice != nil || audioConversionPreset != nil else { return plan }
        let audioPreset = audioConversionPreset
        let encodeSummary: String
        if let videoConversionChoice, let audioPreset {
            let noun = audioEncodeCount == 1 ? "track" : "tracks"
            encodeSummary =
                "Encode video once as \(videoConversionChoice.videoPreset.displayName) and \(audioEncodeCount) mismatched audio \(noun) once as \(audioPreset.displayName); packet-copy already-matching audio and subtitles"
        } else if let videoConversionChoice {
            encodeSummary =
                "Encode video once as \(videoConversionChoice.videoPreset.displayName) while packet-copying audio and subtitles"
        } else if let audioPreset {
            let noun = audioEncodeCount == 1 ? "track" : "tracks"
            encodeSummary =
                "Encode \(audioEncodeCount) mismatched audio \(noun) once as \(audioPreset.displayName) while packet-copying video, matching audio, and subtitles"
        } else {
            preconditionFailure("A reviewed encoding plan has no encoding policy")
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
            impact: plan.impact
        )
    }

    private func videoConversionDetail(
        _ choice: ExactTrimChoice,
        audioEncodeCount: Int,
        copiedAudioCount: Int
    ) -> String {
        guard let preset = choice.audioPolicy.transcodePreset else {
            return
                "Encode video once as \(choice.videoPreset.displayName); packet-copy every audio and subtitle track"
        }
        let noun = audioEncodeCount == 1 ? "track" : "tracks"
        let copiedNoun = copiedAudioCount == 1 ? "track" : "tracks"
        let copyDetail =
            copiedAudioCount == 0
            ? ""
            : "; packet-copy \(copiedAudioCount) already-matching audio \(copiedNoun)"
        return
            "Encode video once as \(choice.videoPreset.displayName) and \(audioEncodeCount) audio \(noun) once as \(preset.displayName)\(copyDetail); packet-copy subtitles"
    }
}
