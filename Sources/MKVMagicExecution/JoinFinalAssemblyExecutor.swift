import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

public enum JoinFinalAssemblyExecutionError: Error, Equatable, Sendable {
    case insufficientSources
    case unsupportedDestination
    case invalidChapterTimeline
    case invalidInputPath
    case staleInput
    case inconsistentCommand
    case toolFailed(exitCode: Int32, message: String)
    case unsafeChapterOutput
    case chapterVerificationFailed
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension JoinFinalAssemblyExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .insufficientSources:
            "Final join assembly needs at least two inspected sources."
        case .unsupportedDestination:
            "Final join assembly currently creates one Matroska MKV output."
        case .invalidChapterTimeline:
            "The reviewed nested chapters do not match the complete joined timeline."
        case .invalidInputPath:
            "Every original and normalized join input must be a safe regular file."
        case .staleInput:
            "An original or normalized stream bundle changed after final review."
        case .inconsistentCommand:
            "The final mux command no longer matches the reviewed lane plan."
        case .toolFailed(let exitCode, let message):
            "mkvmerge could not assemble the final MKV (code \(exitCode)): \(message)"
        case .unsafeChapterOutput:
            "mkvextract did not create a safe, bounded chapter document."
        case .chapterVerificationFailed:
            "The final MKV chapters do not exactly match the reviewed nested tree."
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct JoinFinalAssemblyPreview: Equatable, Sendable {
    public let sources: [MediaAsset]
    public let resolvedPlan: ResolvedJoinNormalizationPlan
    public let normalizedBundle: MediaAsset
    public let chapters: JoinedChapterComposition
    public let commandLanes: [JoinFinalLaneInput]
    public let retainedAttachmentIDsBySource: [Int: Set<Int>]
    public let sourceRevisions: [MediaSourceRevision]
    public let normalizedBundleRevision: MediaSourceRevision

    init(
        sources: [MediaAsset],
        resolvedPlan: ResolvedJoinNormalizationPlan,
        normalizedBundle: MediaAsset,
        chapters: JoinedChapterComposition,
        commandLanes: [JoinFinalLaneInput],
        retainedAttachmentIDsBySource: [Int: Set<Int>],
        sourceRevisions: [MediaSourceRevision],
        normalizedBundleRevision: MediaSourceRevision
    ) {
        self.sources = sources
        self.resolvedPlan = resolvedPlan
        self.normalizedBundle = normalizedBundle
        self.chapters = chapters
        self.commandLanes = commandLanes
        self.retainedAttachmentIDsBySource = retainedAttachmentIDsBySource
        self.sourceRevisions = sourceRevisions
        self.normalizedBundleRevision = normalizedBundleRevision
    }
}

public struct JoinFinalAssemblyExecutor<Runner: CommandRunning, Inspector: MediaInspecting>:
    Sendable
{
    private let mkvmergeURL: URL
    private let runner: Runner
    private let inspector: Inspector
    private let commandBuilder = JoinFinalAssemblyCommandBuilder()
    private let verifier = JoinFinalAssemblyOutputVerifier()
    private let chapterAuditor: MatroskaChapterOutputAuditor<Runner>

    public init(
        mkvmergeURL: URL,
        mkvextractURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        self.mkvmergeURL = mkvmergeURL
        self.runner = runner
        self.inspector = inspector
        chapterAuditor = MatroskaChapterOutputAuditor(
            mkvextractURL: mkvextractURL,
            runner: runner
        )
    }

    public func preview(
        sources: [MediaAsset],
        resolvedPlan: ResolvedJoinNormalizationPlan,
        normalizedBundle: MediaAsset,
        chapters: JoinedChapterComposition
    ) async throws -> JoinFinalAssemblyPreview {
        guard sources.count >= 2 else {
            throw JoinFinalAssemblyExecutionError.insufficientSources
        }
        try validate(chapters: chapters, sources: sources)
        let sourceRevisions: [MediaSourceRevision]
        let normalizedRevision: MediaSourceRevision
        do {
            sourceRevisions = try sources.map { try MediaSourceRevision.read($0.sourceURL) }
            normalizedRevision = try MediaSourceRevision.read(normalizedBundle.sourceURL)
        } catch {
            throw JoinFinalAssemblyExecutionError.invalidInputPath
        }
        guard
            zip(sources, sourceRevisions).allSatisfy({ source, revision in
                source.fileSize == nil || source.fileSize == revision.fileSize
            }),
            normalizedBundle.fileSize == nil
                || normalizedBundle.fileSize == normalizedRevision.fileSize
        else {
            throw JoinFinalAssemblyExecutionError.staleInput
        }

        let command = try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-final-preview"
        ) { directory in
            let chaptersURL = directory.appendingPathComponent("chapters.xml")
            try MatroskaChapterXMLCodec().serialize(chapters.document).write(
                to: chaptersURL,
                options: .atomic
            )
            return try commandBuilder.build(
                sources: sources,
                resolvedPlan: resolvedPlan,
                normalizedBundle: normalizedBundle,
                chapters: chapters,
                chaptersURL: chaptersURL,
                outputURL: directory.appendingPathComponent("preview-output.mkv")
            )
        }
        let preview = JoinFinalAssemblyPreview(
            sources: sources,
            resolvedPlan: resolvedPlan,
            normalizedBundle: normalizedBundle,
            chapters: chapters,
            commandLanes: command.lanes,
            retainedAttachmentIDsBySource: command.retainedAttachmentIDsBySource,
            sourceRevisions: sourceRevisions,
            normalizedBundleRevision: normalizedRevision
        )
        try validateCurrent(preview)
        return preview
    }

    public func execute(
        preview: JoinFinalAssemblyPreview,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw JoinFinalAssemblyExecutionError.unsupportedDestination
        }
        guard let firstSource = preview.sources.first else {
            throw JoinFinalAssemblyExecutionError.insufficientSources
        }
        try validate(chapters: preview.chapters, sources: preview.sources)
        try Task.checkCancellation()
        try validateCurrent(preview)
        let expectedChapters = try MatroskaChapterXMLCodec().serialize(
            preview.chapters.document
        )

        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: firstSource,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                try Task.checkCancellation()
                try validateCurrent(preview)
                try await PrivateTemporaryDirectory.withDirectory(
                    prefix: "mkv-magic-final-assembly"
                ) { directory in
                    let chaptersURL = directory.appendingPathComponent("chapters.xml")
                    try expectedChapters.write(to: chaptersURL, options: .atomic)
                    let command = try commandBuilder.build(
                        sources: preview.sources,
                        resolvedPlan: preview.resolvedPlan,
                        normalizedBundle: preview.normalizedBundle,
                        chapters: preview.chapters,
                        chaptersURL: chaptersURL,
                        outputURL: outputURL
                    )
                    guard command.lanes == preview.commandLanes,
                        command.retainedAttachmentIDsBySource
                            == preview.retainedAttachmentIDsBySource
                    else {
                        throw JoinFinalAssemblyExecutionError.inconsistentCommand
                    }
                    let result = try await runner.run(
                        CommandRequest(
                            executableURL: mkvmergeURL,
                            arguments: command.arguments,
                            timeout: 24 * 60 * 60,
                            outputLimit: 1_048_576
                        )
                    )
                    guard result.exitCode == 0 else {
                        throw JoinFinalAssemblyExecutionError.toolFailed(
                            exitCode: result.exitCode,
                            message: conciseMessage(result)
                        )
                    }
                }
                try Task.checkCancellation()
                try validateCurrent(preview)
            },
            verify: { output in
                try Task.checkCancellation()
                try validateCurrent(preview)
                try verifier.verify(
                    sources: preview.sources,
                    normalizedBundle: preview.normalizedBundle,
                    commandLanes: preview.commandLanes,
                    retainedAttachmentIDsBySource: preview.retainedAttachmentIDsBySource,
                    chapters: preview.chapters,
                    output: output
                )
                try await verifyChapters(
                    in: output.sourceURL,
                    expectedCanonical: expectedChapters
                )
                try validateCurrent(preview)
            },
            committedAuditError: { outputURL, reason in
                JoinFinalAssemblyExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }

    public func validateCurrent(_ preview: JoinFinalAssemblyPreview) throws {
        guard preview.sources.count == preview.sourceRevisions.count else {
            throw JoinFinalAssemblyExecutionError.staleInput
        }
        for (source, expected) in zip(preview.sources, preview.sourceRevisions) {
            guard (try? MediaSourceRevision.read(source.sourceURL)) == expected else {
                throw JoinFinalAssemblyExecutionError.staleInput
            }
        }
        guard
            (try? MediaSourceRevision.read(preview.normalizedBundle.sourceURL))
                == preview.normalizedBundleRevision
        else {
            throw JoinFinalAssemblyExecutionError.staleInput
        }
    }

    private func validate(
        chapters: JoinedChapterComposition,
        sources: [MediaAsset]
    ) throws {
        var duration: Int64 = 0
        for source in sources {
            guard let sourceDuration = source.duration, sourceDuration.nanoseconds > 0 else {
                throw JoinFinalAssemblyExecutionError.invalidChapterTimeline
            }
            let addition = duration.addingReportingOverflow(sourceDuration.nanoseconds)
            guard !addition.overflow else {
                throw JoinFinalAssemblyExecutionError.invalidChapterTimeline
            }
            duration = addition.partialValue
        }
        guard chapters.duration.nanoseconds == duration else {
            throw JoinFinalAssemblyExecutionError.invalidChapterTimeline
        }
        do {
            _ = try chapters.document.validated(mediaDuration: chapters.duration)
        } catch {
            throw JoinFinalAssemblyExecutionError.invalidChapterTimeline
        }
    }

    private func verifyChapters(
        in fileURL: URL,
        expectedCanonical: Data
    ) async throws {
        do {
            try await chapterAuditor.verify(
                fileURL: fileURL,
                expectedCanonical: expectedCanonical
            )
        } catch let error as MatroskaChapterOutputAuditError {
            switch error {
            case .toolFailed(let exitCode, let message):
                throw JoinFinalAssemblyExecutionError.toolFailed(
                    exitCode: exitCode,
                    message: message
                )
            case .unsafeExtractedDocument:
                throw JoinFinalAssemblyExecutionError.unsafeChapterOutput
            case .mismatch:
                throw JoinFinalAssemblyExecutionError.chapterVerificationFailed
            }
        }
    }

    private func conciseMessage(_ result: CommandResult) -> String {
        let message =
            [result.standardError.text, result.standardOutput.text]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Unknown tool error"
        return String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }
}
