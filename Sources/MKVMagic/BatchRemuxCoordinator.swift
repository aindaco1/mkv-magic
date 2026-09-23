import AppKit
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import MKVMagicSystem

/// Batch authoring only: processing still belongs to the normal durable queue.
@MainActor
final class BatchRemuxCoordinator {
    private let model: AppModel
    private weak var parent: NSWindow?
    private let onFinish: (String) -> Void
    private var videos = [MediaAsset]()
    private var sidecars = [MediaAsset]()
    private var unsupported = [MediaAsset]()
    private var previews = [UUID: ExternalSubtitleFilePreview]()
    private var choices = [UUID: BatchRemuxOptions]()
    private var associations = [ExternalSubtitleAssociation]()
    private var explicitlyReviewed = Set<UUID>()
    private var readFailures = [UUID: String]()
    private var sourceRevisions = [UUID: MediaFileRevision]()
    private var review: BatchReviewWindowController?
    private var editor: BatchRemuxOptionsWindowController?
    private var retryingJob: MediaQueueJob?

    init(model: AppModel, parent: NSWindow, onFinish: @escaping (String) -> Void) {
        self.model = model
        self.parent = parent
        self.onFinish = onFinish
    }

    static func canOffer(_ assets: [MediaAsset]) -> Bool {
        assets.count > 1 && assets.contains { MKVRemuxPlanner().canOffer(for: $0) }
    }

    func begin(assets: [MediaAsset], retrying job: MediaQueueJob? = nil) {
        guard assets.count <= ExternalSubtitleBatchMatcher.maximumInputCount else {
            onFinish(
                "Choose at most \(ExternalSubtitleBatchMatcher.maximumInputCount) files per remux batch."
            )
            return
        }
        retryingJob = job
        videos = assets.filter { MKVRemuxPlanner().canOffer(for: $0) }
        sidecars = assets.filter {
            ["srt", "ass", "ssa"].contains($0.sourceURL.pathExtension.lowercased())
        }
        let supportedIDs = Set((videos + sidecars).map(\.id))
        unsupported = assets.filter { !supportedIDs.contains($0.id) }
        guard let first = videos.first else {
            onFinish("No compatible videos selected for packet-copy MKV remux.")
            return
        }
        for video in videos { sourceRevisions[video.id] = model.reviewedSourceRevision(for: video) }
        let mediaSnapshot = videos, subtitleSnapshot = sidecars
        guard let parent else {
            onFinish("Batch review cancelled.")
            return
        }
        let progress = VerifiedOutputProgressWindowController.batch(
            title: "Preparing Remux Batch",
            initialMessage: "Matching filenames locally…", itemCount: sidecars.count + 1)
        progress.beginSheet(for: parent)
        let task = Task {
            associations = await Task.detached {
                ExternalSubtitleBatchMatcher.associate(
                    media: mediaSnapshot, subtitles: subtitleSnapshot)
            }.value
            progress.update(completedUnitCount: 1)
            var totalBytes: Int64 = 0
            for (index, sidecar) in sidecars.enumerated() {
                if Task.isCancelled { break }
                progress.update(
                    completedUnitCount: index + 1,
                    message:
                        "Reading subtitle \(index + 1) of \(sidecars.count): \(sidecar.sourceURL.lastPathComponent)"
                )
                do {
                    let size =
                        try sidecar.sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    totalBytes += Int64(size)
                    guard totalBytes <= 64 * 1_024 * 1_024 else {
                        readFailures[sidecar.id] =
                            "Batch subtitle review exceeds 64 MB; choose fewer files."
                        continue
                    }
                    previews[sidecar.id] = try await model.previewExternalSubtitle(
                        in: first, at: sidecar.sourceURL
                    ).preview
                } catch {
                    readFailures[sidecar.id] = UserFacingErrorPresentation.shortReason(error)
                }
                progress.update(completedUnitCount: index + 2)
            }
            progress.finish()
            guard !Task.isCancelled else {
                onFinish("Remux batch cancelled; nothing queued.")
                return
            }
            for video in videos {
                var subtitles = [UUID: ExternalSubtitleTrackMetadata]()
                for association in associations where association.suggestedMediaID == video.id {
                    guard let preview = previews[association.subtitleID] else { continue }
                    subtitles[association.subtitleID] = match(video, preview).suggestedMetadata
                }
                choices[video.id] = BatchRemuxOptions(
                    subtitles: subtitles,
                    audioLanguages: CommonMediaSubtitleRemuxPresentation.defaultAudioLanguages(
                        for: video))
            }
            if let job, videos.count == 1 {
                // Retry the same job and keep its reviewed metadata. Hash/revision
                // checks are renewed by preview and queue admission, never waived.
                let reviews = job.workflow.externalSubtitleReviews
                let orderedSidecars = sidecars
                if orderedSidecars.count == reviews.count {
                    choices[first.id] = BatchRemuxOptions(
                        subtitles: Dictionary(
                            uniqueKeysWithValues: zip(orderedSidecars, reviews).map {
                                ($0.0.id, $0.1.metadata)
                            }),
                        audioLanguages: job.workflow.sourceTrackLanguageOverrides)
                }
            }
            showReview()
        }
        progress.onCancel = { task.cancel() }
    }

    private func match(_ video: MediaAsset, _ preview: ExternalSubtitleFilePreview)
        -> ExternalSubtitleMatch
    {
        ExternalSubtitleMatcher().match(
            media: video, subtitleURL: preview.sourceURL, subtitleEnd: preview.subtitleEnd)
    }

    private func presentation(_ video: MediaAsset) -> BatchReviewItemPresentation {
        let selected = choices[video.id]?.subtitles ?? [:]
        let ambiguous =
            associations.contains {
                $0.suggestedMediaID == nil && $0.candidateMediaIDs.contains(video.id)
            } && !explicitlyReviewed.contains(video.id)
        let failedSidecars = associations.contains {
            ($0.suggestedMediaID == video.id || $0.candidateMediaIDs.contains(video.id))
                && readFailures[$0.subtitleID] != nil
        }
        let blocked =
            ambiguous || failedSidecars || sourceRevisions[video.id] == nil
            || selected.count > ExternalSubtitleBatchPolicy.maximumSubtitlesPerVideo
        let audio = (choices[video.id]?.audioLanguages ?? [:]).sorted { $0.key < $1.key }.map {
            "audio #\($0.key): \($0.value)"
        }
        let subtitleSummary = sidecars.compactMap { sidecar -> String? in
            guard let metadata = selected[sidecar.id] else { return nil }
            return
                "\(sidecar.sourceURL.lastPathComponent) [\(metadata.language)\(metadata.isForced ? ", forced" : "")\(metadata.isHearingImpaired ? ", SDH" : "")]"
        }
        var detail =
            "No encoding • "
            + (subtitleSummary.isEmpty
                ? "video only; no subtitles selected" : subtitleSummary.joined(separator: "; "))
        if !audio.isEmpty { detail += " • " + audio.joined(separator: "; ") }
        for sidecar in sidecars where selected[sidecar.id] != nil {
            guard let preview = previews[sidecar.id] else { continue }
            let warnings = ExternalSubtitleMuxPresentation.warnings(
                preview: preview, match: match(video, preview))
            if !warnings.isEmpty {
                detail +=
                    " • \(sidecar.sourceURL.lastPathComponent): " + warnings.joined(separator: " ")
            }
        }
        if ambiguous {
            detail =
                "Ambiguous subtitle matches: use Edit Selected to include or exclude them. "
                + detail
        }
        if failedSidecars {
            detail =
                "A matching subtitle could not be read; fix it or remove it from this batch. "
                + detail
        }
        if sourceRevisions[video.id] == nil { detail = "Inspect this video again before queueing." }
        if selected.count > ExternalSubtitleBatchPolicy.maximumSubtitlesPerVideo {
            detail = "Select at most 32 subtitles using Edit Selected."
        }
        return BatchReviewItemPresentation(
            id: video.id, inputName: video.sourceURL.lastPathComponent,
            outputName: OutputNamingPolicy.remuxedFilename(for: video.sourceURL),
            status: blocked ? .blocked : .ready, detail: detail, sourceURL: video.sourceURL,
            isEditable: true)
    }

    private func showReview() {
        guard let parent else {
            onFinish("Batch review cancelled.")
            return
        }
        var items = videos.map(presentation)
        items += unsupported.map {
            BatchReviewItemPresentation(
                id: $0.id, inputName: $0.sourceURL.lastPathComponent,
                outputName: "—", status: .noChanges,
                detail:
                    "Not supported by this common-container remux batch; this file is left unchanged."
            )
        }
        for sidecar in sidecars {
            let association = associations.first { $0.subtitleID == sidecar.id }
            if let error = readFailures[sidecar.id] {
                items.append(
                    BatchReviewItemPresentation(
                        id: sidecar.id, inputName: sidecar.sourceURL.lastPathComponent,
                        outputName: "—", status: .blocked, detail: error))
            } else if association?.candidateMediaIDs.isEmpty != false {
                items.append(unmatchedPresentation(sidecar))
            }
        }
        let preferences = OutputDestinationPreferences()
        do {
            let directory =
                preferences.mode == .chosenFolder ? try preferences.resolveChosenFolder() : nil
            let access = directory.flatMap { OutputDirectorySecurityScope(directoryURL: $0) }
            let controller = BatchReviewWindowController(
                title: "Review MKV Remux Batch",
                explanation:
                    "One independent MKV per video. All confident subtitle matches are preselected; ambiguous matches need Edit Selected. Review the languages and flags, uncheck any output you do not want, then add the included jobs to the queue. Originals are kept.",
                items: items, actionTitle: "Add Included Jobs to Queue",
                offersSourceDisposition: false,
                initialDestinationDirectory: directory, initialDirectoryAccess: access)
            review = controller
            controller.onEditItem = { [weak self] id in self?.edit(id) }
            controller.beginSheet(for: parent) { [weak self] decision in
                guard let self else { return }
                self.review = nil
                guard let decision else {
                    self.onFinish("Remux batch cancelled; nothing queued.")
                    return
                }
                self.enqueue(decision)
            }
        } catch {
            onFinish(
                "Could not review the batch: \(UserFacingErrorPresentation.shortReason(error))")
        }
    }

    private func unmatchedPresentation(_ sidecar: MediaAsset) -> BatchReviewItemPresentation {
        let assigned = videos.first { choices[$0.id]?.subtitles[sidecar.id] != nil }
        return BatchReviewItemPresentation(
            id: sidecar.id, inputName: sidecar.sourceURL.lastPathComponent,
            outputName: "—", status: .noChanges,
            detail: assigned.map { "Included with \($0.sourceURL.lastPathComponent)." }
                ?? "Unmatched subtitle. Edit a video row to associate it manually, or leave it unchanged."
        )
    }

    private func edit(_ id: UUID) {
        guard let video = videos.first(where: { $0.id == id }), let parent = review?.window,
            let options = choices[id]
        else { return }
        let usedElsewhere = Set(choices.filter { $0.key != id }.flatMap { $0.value.subtitles.keys })
        let rows = sidecars.compactMap { sidecar -> BatchRemuxTrackChoice? in
            guard !usedElsewhere.contains(sidecar.id), let preview = previews[sidecar.id] else {
                return nil
            }
            let match = match(video, preview)
            return BatchRemuxTrackChoice(
                id: sidecar.id, filename: sidecar.sourceURL.lastPathComponent,
                metadata: options.subtitles[sidecar.id] ?? match.suggestedMetadata,
                included: options.subtitles[sidecar.id] != nil,
                explanation: ([ExternalSubtitleMuxPresentation.matchSummary(match)]
                    + ExternalSubtitleMuxPresentation.warnings(preview: preview, match: match))
                    .joined(separator: "\n"))
        }
        let editor = BatchRemuxOptionsWindowController(
            media: video, choices: rows, audioLanguages: options.audioLanguages)
        self.editor = editor
        editor.beginSheet(for: parent) { [weak self] result in
            guard let self else { return }
            self.editor = nil
            if let result {
                self.choices[id] = result
                self.explicitlyReviewed.insert(id)
                self.review?.update(self.presentation(video))
                for sidecar in self.sidecars where self.readFailures[sidecar.id] == nil {
                    self.review?.update(self.unmatchedPresentation(sidecar))
                }
            }
        }
    }

    private func enqueue(_ decision: BatchReviewDecision) {
        let included = videos.filter { decision.includes($0.id) }
        guard !included.isEmpty, let parent else {
            onFinish("Nothing queued.")
            return
        }
        let progress = VerifiedOutputProgressWindowController.batch(
            title: "Adding Remux Batch",
            initialMessage: "Preparing independent queue jobs…", itemCount: included.count)
        progress.beginSheet(for: parent)
        let task = Task {
            var reserved = Set<String>(), failures = [String]()
            var queued = 0
            for (index, video) in included.enumerated() {
                if Task.isCancelled { break }
                progress.update(
                    completedUnitCount: index,
                    message:
                        "Queueing \(index + 1) of \(included.count): \(video.sourceURL.lastPathComponent)"
                )
                let diagnostic = model.makeDiagnosticContext(.addToQueue)
                await diagnostic?.record(.queueAdmission, .started)
                do {
                    guard let options = choices[video.id], let revision = sourceRevisions[video.id]
                    else {
                        throw SavedWorkflowExecutionError.sourceChangedSinceReview
                    }
                    let selected = sidecars.filter { options.subtitles[$0.id] != nil }
                    let payloads = try selected.map { sidecar -> ExternalSubtitleMuxPayload in
                        guard let preview = previews[sidecar.id] else {
                            throw ExternalSubtitleMuxError.subtitleVerificationFailed
                        }
                        return .original(preview)
                    }
                    let inputs = selected.enumerated().map { index, sidecar in
                        SavedWorkflowExternalSubtitleInput(
                            sourceURL: sidecar.sourceURL,
                            metadata: options.subtitles[sidecar.id]!, format: payloads[index].format
                        )
                    }
                    let recipe = Self.recipe(hasSubtitles: !inputs.isEmpty)
                    let compiled = try SavedWorkflowCompiler().compile(
                        recipe, for: video,
                        inputs: SavedWorkflowResolvedInputs(
                            externalSubtitle: inputs.first,
                            sourceTrackLanguageOverrides: options.audioLanguages,
                            additionalExternalSubtitles: Array(inputs.dropFirst())))
                    let destination = try decision.destination(
                        for: video.id,
                        filename: OutputNamingPolicy.remuxedFilename(for: video.sourceURL),
                        reservedPaths: reserved)
                    reserved.insert(destination.path)
                    _ = try await model.enqueueSavedWorkflow(
                        compiled, recipe: recipe,
                        externalSubtitlePayload: payloads.first,
                        additionalExternalSubtitlePayloads: Array(payloads.dropFirst()),
                        retryingQueueJobID: retryingJob?.id, expectedSourceRevision: revision,
                        in: video, destinationURL: destination)
                    queued += 1
                    await diagnostic?.record(.finished, .succeeded)
                } catch is CancellationError {
                    await diagnostic?.record(.finished, .cancelled)
                    break
                } catch {
                    failures.append(
                        "\(video.sourceURL.lastPathComponent): \(UserFacingErrorPresentation.shortReason(error))"
                    )
                    await diagnostic?.record(
                        (error as? DiagnosticPreparationError)?.stage ?? .queueAdmission,
                        .failed, failure: .classify(error))
                }
                progress.update(completedUnitCount: index + 1)
            }
            progress.finish()
            _ = decision.directoryAccess
            let summary =
                "Remux batch: \(queued) queued, \(failures.count) need attention."
                + (Task.isCancelled
                    ? " Remaining items cancelled; already queued jobs are kept." : "")
            if !failures.isEmpty {
                let alert = NSAlert()
                alert.messageText = summary
                alert.informativeText = failures.prefix(20).joined(separator: "\n")
                alert.beginSheetModal(for: parent, completionHandler: nil)
            }
            onFinish(summary)
            let queuedModel = model
            Task { await queuedModel.runAutomaticQueueCycleIfEligible() }
        }
        progress.onCancel = { task.cancel() }
    }

    static func recipe(hasSubtitles: Bool) -> SavedWorkflow {
        let paired = CommonMediaSubtitleRemuxPresentation.reviewedWorkflowRecipe
        return SavedWorkflow(
            id: paired.id, name: hasSubtitles ? paired.name : "Remux videos to MKV",
            steps: hasSubtitles ? paired.steps : paired.steps.filter { $0.action == .remuxToMKV })
    }
}
