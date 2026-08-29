import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum FastTrimExecutionError: Error, Equatable, Sendable {
    case unsupportedSource
    case unsupportedDestination
    case staleSource
    case unsafeChapterOutput
    case chapterVerificationFailed
    case toolFailed(tool: String, exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension FastTrimExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Fast Trim currently needs one video track in an inspected Matroska MKV."
        case .unsupportedDestination: "Fast Trim currently creates one Matroska MKV output."
        case .staleSource: "The source or its chapters changed after the trim review."
        case .unsafeChapterOutput:
            "mkvextract did not create a safe, bounded chapter document."
        case .chapterVerificationFailed:
            "The saved nested chapters do not exactly match the reviewed trim."
        case .toolFailed(let tool, let exitCode, let message):
            "\(tool) could not complete Fast Trim (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct FastTrimPreview: Equatable, Sendable {
    public let source: MediaAsset
    public let plan: FastTrimPlan
    public let videoKeyframes: [MediaTime]
    public let originalChapters: MatroskaChapterDocument
    public let trimmedChapters: MatroskaChapterDocument
    public let sourceRevision: MediaSourceRevision
    public let sourceChapterSHA256: Data

    init(
        source: MediaAsset,
        plan: FastTrimPlan,
        videoKeyframes: [MediaTime],
        originalChapters: MatroskaChapterDocument,
        trimmedChapters: MatroskaChapterDocument,
        sourceRevision: MediaSourceRevision,
        sourceChapterSHA256: Data
    ) {
        self.source = source
        self.plan = plan
        self.videoKeyframes = videoKeyframes
        self.originalChapters = originalChapters
        self.trimmedChapters = trimmedChapters
        self.sourceRevision = sourceRevision
        self.sourceChapterSHA256 = sourceChapterSHA256
    }
}

public struct FastTrimExecutor<Runner: CommandRunning, Inspector: MediaInspecting>: Sendable {
    private let mkvmergeURL: URL
    private let mkvpropeditURL: URL
    private let runner: Runner
    private let inspector: Inspector
    private let keyframeProbe: VideoKeyframeProbe<Runner>
    private let chapterExtractor: MatroskaChapterDocumentExtractor<Runner>
    private let chapterAuditor: MatroskaChapterOutputAuditor<Runner>
    private let commandBuilder = FastTrimCommandBuilder()
    private let verifier = FastTrimOutputVerifier()
    private let chapterCodec = MatroskaChapterXMLCodec()

    public init(
        ffprobeURL: URL,
        mkvmergeURL: URL,
        mkvextractURL: URL,
        mkvpropeditURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        self.mkvmergeURL = mkvmergeURL
        self.mkvpropeditURL = mkvpropeditURL
        self.runner = runner
        self.inspector = inspector
        keyframeProbe = VideoKeyframeProbe(ffprobeURL: ffprobeURL, runner: runner)
        chapterExtractor = MatroskaChapterDocumentExtractor(
            mkvextractURL: mkvextractURL,
            runner: runner
        )
        chapterAuditor = MatroskaChapterOutputAuditor(
            mkvextractURL: mkvextractURL,
            runner: runner
        )
    }

    public func preview(
        source: MediaAsset,
        requestedRange: MediaTrimRange
    ) async throws -> FastTrimPreview {
        guard supports(source), let duration = source.duration else {
            throw FastTrimExecutionError.unsupportedSource
        }
        let before: MediaSourceRevision
        do {
            before = try MediaSourceRevision.read(source.sourceURL)
        } catch {
            throw FastTrimExecutionError.unsupportedSource
        }
        guard source.fileSize == nil || source.fileSize == before.fileSize else {
            throw FastTrimExecutionError.staleSource
        }

        async let keyframesTask = keyframeProbe.probe(sourceURL: source.sourceURL)
        async let chaptersTask = extractChapters(from: source.sourceURL)
        let (keyframes, extracted) = try await (keyframesTask, chaptersTask)
        guard (try? MediaSourceRevision.read(source.sourceURL)) == before else {
            throw FastTrimExecutionError.staleSource
        }
        let plan = try FastTrimPlanner().plan(
            requested: requestedRange,
            sourceDuration: duration,
            videoKeyframes: keyframes
        )
        let trimmed = try MatroskaChapterTrimmer().trim(
            extracted.document,
            sourceDuration: duration,
            retainedRange: plan.adjusted
        )
        return FastTrimPreview(
            source: source,
            plan: plan,
            videoKeyframes: keyframes,
            originalChapters: extracted.document,
            trimmedChapters: trimmed,
            sourceRevision: before,
            sourceChapterSHA256: digest(extracted.canonicalData)
        )
    }

    public func execute(
        preview: FastTrimPreview,
        destinationURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard supports(preview.source) else { throw FastTrimExecutionError.unsupportedSource }
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw FastTrimExecutionError.unsupportedDestination
        }
        try Task.checkCancellation()
        try await validateCurrent(preview)
        let expectedChapters = try chapterCodec.serialize(preview.trimmedChapters)

        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: preview.source,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                try Task.checkCancellation()
                try await validateCurrent(preview)
                let command = try commandBuilder.build(
                    sourceURL: preview.source.sourceURL,
                    plan: preview.plan,
                    outputURL: outputURL
                )
                let merge = try await runner.run(
                    MKVToolNixProgress.request(
                        executableURL: mkvmergeURL,
                        arguments: command.arguments,
                        timeout: 24 * 60 * 60,
                        onProgress: onProgress
                    )
                )
                try requireSuccess(merge, tool: "mkvmerge")
                try Task.checkCancellation()
                try await validateCurrent(preview)
                try await replaceChapters(
                    in: outputURL,
                    document: preview.trimmedChapters,
                    canonicalData: expectedChapters
                )
                try Task.checkCancellation()
                try await validateCurrent(preview)
            },
            verify: { output in
                try Task.checkCancellation()
                try await validateCurrent(preview)
                try verifier.verify(
                    original: preview.source,
                    plan: preview.plan,
                    chapters: preview.trimmedChapters,
                    output: output
                )
                try await verifyChapters(
                    in: output.sourceURL,
                    expectedCanonical: expectedChapters
                )
                try await validateCurrent(preview)
            },
            committedAuditError: { outputURL, reason in
                FastTrimExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }

    public func validateCurrent(_ preview: FastTrimPreview) async throws {
        guard
            (try? MediaSourceRevision.read(preview.source.sourceURL))
                == preview.sourceRevision
        else {
            throw FastTrimExecutionError.staleSource
        }
        let extracted = try await extractChapters(from: preview.source.sourceURL)
        guard digest(extracted.canonicalData) == preview.sourceChapterSHA256,
            (try? MediaSourceRevision.read(preview.source.sourceURL))
                == preview.sourceRevision
        else {
            throw FastTrimExecutionError.staleSource
        }
    }

    private func supports(_ source: MediaAsset) -> Bool {
        source.sourceURL.pathExtension.lowercased() == "mkv"
            && MatroskaEditingPolicy.supports(source)
            && source.tracks.filter { $0.kind == .video }.count == 1
            && source.duration?.nanoseconds ?? 0 > 0
    }

    private func extractChapters(from fileURL: URL) async throws -> ExtractedMatroskaChapters {
        do {
            return try await chapterExtractor.extract(from: fileURL)
        } catch let error as MatroskaChapterOutputAuditError {
            switch error {
            case .toolFailed(let exitCode, let message):
                throw FastTrimExecutionError.toolFailed(
                    tool: "mkvextract",
                    exitCode: exitCode,
                    message: message
                )
            case .unsafeExtractedDocument:
                throw FastTrimExecutionError.unsafeChapterOutput
            case .mismatch:
                throw FastTrimExecutionError.chapterVerificationFailed
            }
        }
    }

    private func replaceChapters(
        in fileURL: URL,
        document: MatroskaChapterDocument,
        canonicalData: Data
    ) async throws {
        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-fast-trim-chapters"
        ) { directory in
            let chapterURL = directory.appendingPathComponent("chapters.xml")
            if !document.editions.isEmpty {
                try canonicalData.write(to: chapterURL, options: .atomic)
            }
            let result = try await runner.run(
                CommandRequest(
                    executableURL: mkvpropeditURL,
                    arguments: [
                        "--abort-on-warnings",
                        fileURL.path,
                        "--chapters",
                        document.editions.isEmpty ? "" : chapterURL.path,
                    ],
                    timeout: 120,
                    outputLimit: 1_048_576
                )
            )
            try requireSuccess(result, tool: "mkvpropedit")
        }
    }

    private func verifyChapters(in fileURL: URL, expectedCanonical: Data) async throws {
        do {
            try await chapterAuditor.verify(
                fileURL: fileURL,
                expectedCanonical: expectedCanonical
            )
        } catch let error as MatroskaChapterOutputAuditError {
            switch error {
            case .toolFailed(let exitCode, let message):
                throw FastTrimExecutionError.toolFailed(
                    tool: "mkvextract",
                    exitCode: exitCode,
                    message: message
                )
            case .unsafeExtractedDocument:
                throw FastTrimExecutionError.unsafeChapterOutput
            case .mismatch:
                throw FastTrimExecutionError.chapterVerificationFailed
            }
        }
    }

    private func requireSuccess(_ result: CommandResult, tool: String) throws {
        guard result.exitCode == 0 else {
            throw FastTrimExecutionError.toolFailed(
                tool: tool,
                exitCode: result.exitCode,
                message: result.conciseFailureMessage
            )
        }
    }

    private func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
