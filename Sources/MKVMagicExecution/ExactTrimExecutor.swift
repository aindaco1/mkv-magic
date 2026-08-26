import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

public enum ExactTrimExecutionError: Error, Equatable, Sendable {
    case unsupportedDestination
    case unsafeSource
    case staleSource
    case inconsistentCommand
    case copiedTrackVerificationFailed(reason: String)
    case unsafeChapterOutput
    case chapterVerificationFailed
    case toolFailed(tool: String, exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension ExactTrimExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedDestination: "Video processing currently creates one Matroska MKV output."
        case .unsafeSource: "Video processing needs a safe regular source file."
        case .staleSource: "The source or its chapters changed after review."
        case .inconsistentCommand:
            "The video command no longer matches its reviewed encode/copy plan."
        case .copiedTrackVerificationFailed(let reason):
            "A packet-copied audio or subtitle track did not match the reviewed source: \(reason)"
        case .unsafeChapterOutput:
            "mkvextract did not create a safe, bounded chapter document."
        case .chapterVerificationFailed:
            "The output nested chapters do not match the reviewed tree."
        case .toolFailed(let tool, let exitCode, let message):
            "\(tool) could not complete video processing (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct ExactTrimPreview: Equatable, Sendable {
    public let resolvedPlan: ResolvedExactTrimPlan
    public let capabilities: FFmpegEncodingCapabilities
    public let originalChapters: MatroskaChapterDocument
    public let trimmedChapters: MatroskaChapterDocument
    public let sourceRevision: MediaSourceRevision
    public let sourceChapterSHA256: Data
    public let encodedVideoTrackID: Int
    public let encodedAudioTrackIDs: [Int]
    public let copiedAudioTrackIDs: [Int]
    public let copiedSubtitleTrackIDs: [Int]

    init(
        resolvedPlan: ResolvedExactTrimPlan,
        capabilities: FFmpegEncodingCapabilities,
        originalChapters: MatroskaChapterDocument,
        trimmedChapters: MatroskaChapterDocument,
        sourceRevision: MediaSourceRevision,
        sourceChapterSHA256: Data,
        encodedVideoTrackID: Int,
        encodedAudioTrackIDs: [Int],
        copiedAudioTrackIDs: [Int],
        copiedSubtitleTrackIDs: [Int]
    ) {
        self.resolvedPlan = resolvedPlan
        self.capabilities = capabilities
        self.originalChapters = originalChapters
        self.trimmedChapters = trimmedChapters
        self.sourceRevision = sourceRevision
        self.sourceChapterSHA256 = sourceChapterSHA256
        self.encodedVideoTrackID = encodedVideoTrackID
        self.encodedAudioTrackIDs = encodedAudioTrackIDs
        self.copiedAudioTrackIDs = copiedAudioTrackIDs
        self.copiedSubtitleTrackIDs = copiedSubtitleTrackIDs
    }
}

public struct ExactTrimExecutor<
    Runner: CommandRunning & CommandLineDigesting,
    Inspector: MediaInspecting
>: Sendable {
    private let ffmpegURL: URL
    private let ffprobeURL: URL
    private let mkvpropeditURL: URL
    private let runner: Runner
    private let inspector: Inspector
    private let chapterExtractor: MatroskaChapterDocumentExtractor<Runner>
    private let chapterAuditor: MatroskaChapterOutputAuditor<Runner>
    private let commandBuilder = ExactTrimCommandBuilder()
    private let verifier = ExactTrimOutputVerifier()
    private let chapterCodec = MatroskaChapterXMLCodec()

    public init(
        ffmpegURL: URL,
        ffprobeURL: URL,
        mkvextractURL: URL,
        mkvpropeditURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
        self.mkvpropeditURL = mkvpropeditURL
        self.runner = runner
        self.inspector = inspector
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
        range: MediaTrimRange,
        choice: ExactTrimChoice,
        operation: ExactVideoOperation = .trim,
        capabilities: FFmpegEncodingCapabilities
    ) async throws -> ExactTrimPreview {
        let resolved = try ExactTrimPlanner().resolve(
            source: source,
            range: range,
            choice: choice,
            operation: operation,
            availableVideoPresets: Set(capabilities.availableVideoPresets),
            aacAvailable: capabilities.aac == .verified,
            availableAudioPresets: Set(capabilities.availableAudioPresets)
        )
        let revision: MediaSourceRevision
        do {
            revision = try MediaSourceRevision.read(source.sourceURL)
        } catch {
            throw ExactTrimExecutionError.unsafeSource
        }
        guard source.fileSize == nil || source.fileSize == revision.fileSize else {
            throw ExactTrimExecutionError.staleSource
        }
        let extracted = try await reviewedChapters(for: resolved)
        guard (try? MediaSourceRevision.read(source.sourceURL)) == revision,
            let duration = source.duration
        else {
            throw ExactTrimExecutionError.staleSource
        }
        let outputChapters: MatroskaChapterDocument
        switch operation {
        case .trim:
            outputChapters = try MatroskaChapterTrimmer().trim(
                extracted.document,
                sourceDuration: duration,
                retainedRange: range
            )
        case .transcode:
            outputChapters = extracted.document
        }
        let command = try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-exact-trim-preview"
        ) { directory in
            try commandBuilder.build(
                resolvedPlan: resolved,
                capabilities: capabilities,
                outputURL: directory.appendingPathComponent("preview.mkv")
            )
        }
        return ExactTrimPreview(
            resolvedPlan: resolved,
            capabilities: capabilities,
            originalChapters: extracted.document,
            trimmedChapters: outputChapters,
            sourceRevision: revision,
            sourceChapterSHA256: digest(extracted.canonicalData),
            encodedVideoTrackID: command.encodedVideoTrackID,
            encodedAudioTrackIDs: command.encodedAudioTrackIDs,
            copiedAudioTrackIDs: command.copiedAudioTrackIDs,
            copiedSubtitleTrackIDs: command.copiedSubtitleTrackIDs
        )
    }

    public func execute(
        preview: ExactTrimPreview,
        destinationURL: URL,
        validateReviewedSource: @escaping @Sendable () throws -> Void = {},
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw ExactTrimExecutionError.unsupportedDestination
        }
        try Task.checkCancellation()
        try await validateCurrent(preview)
        let expectedChapters = try chapterCodec.serialize(preview.trimmedChapters)

        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: preview.resolvedPlan.source,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                try Task.checkCancellation()
                try await validateCurrent(preview)
                let command = try commandBuilder.build(
                    resolvedPlan: preview.resolvedPlan,
                    capabilities: preview.capabilities,
                    outputURL: outputURL
                )
                guard command.encodedVideoTrackID == preview.encodedVideoTrackID,
                    command.encodedAudioTrackIDs == preview.encodedAudioTrackIDs,
                    command.copiedAudioTrackIDs == preview.copiedAudioTrackIDs,
                    command.copiedSubtitleTrackIDs == preview.copiedSubtitleTrackIDs
                else {
                    throw ExactTrimExecutionError.inconsistentCommand
                }
                let encode = try await runner.run(
                    CommandRequest(
                        executableURL: ffmpegURL,
                        arguments: command.arguments,
                        timeout: 24 * 60 * 60,
                        outputLimit: 1_048_576
                    )
                )
                try requireSuccess(encode, tool: "ffmpeg")
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
                    resolvedPlan: preview.resolvedPlan,
                    chapters: preview.trimmedChapters,
                    output: output
                )
                try await verifyCompleteFilePacketCopies(preview: preview, output: output)
                try await verifyChapters(
                    in: output.sourceURL,
                    expectedCanonical: expectedChapters
                )
                try await validateCurrent(preview)
            },
            validateSource: validateReviewedSource,
            committedAuditError: { outputURL, reason in
                ExactTrimExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }

    public func validateCurrent(_ preview: ExactTrimPreview) async throws {
        let sourceURL = preview.resolvedPlan.source.sourceURL
        guard (try? MediaSourceRevision.read(sourceURL)) == preview.sourceRevision else {
            throw ExactTrimExecutionError.staleSource
        }
        guard preview.resolvedPlan.sourceKind.isMatroska else { return }
        let extracted = try await extractChapters(from: sourceURL)
        guard digest(extracted.canonicalData) == preview.sourceChapterSHA256,
            (try? MediaSourceRevision.read(sourceURL)) == preview.sourceRevision
        else {
            throw ExactTrimExecutionError.staleSource
        }
    }

    private func reviewedChapters(
        for plan: ResolvedExactTrimPlan
    ) async throws -> ExtractedMatroskaChapters {
        if plan.sourceKind.isMatroska {
            return try await extractChapters(from: plan.source.sourceURL)
        }
        guard let duration = plan.source.duration else {
            throw ExactTrimExecutionError.chapterVerificationFailed
        }
        let document = try MatroskaChapterDocument.importingInspectedChapters(
            plan.source.chapters,
            sourceID: plan.source.id,
            mediaDuration: duration
        )
        return ExtractedMatroskaChapters(
            document: document,
            canonicalData: try chapterCodec.serialize(document)
        )
    }

    private func extractChapters(from fileURL: URL) async throws -> ExtractedMatroskaChapters {
        do {
            return try await chapterExtractor.extract(from: fileURL)
        } catch let error as MatroskaChapterOutputAuditError {
            switch error {
            case .toolFailed(let exitCode, let message):
                throw ExactTrimExecutionError.toolFailed(
                    tool: "mkvextract",
                    exitCode: exitCode,
                    message: message
                )
            case .unsafeExtractedDocument:
                throw ExactTrimExecutionError.unsafeChapterOutput
            case .mismatch:
                throw ExactTrimExecutionError.chapterVerificationFailed
            }
        }
    }

    private func replaceChapters(
        in fileURL: URL,
        document: MatroskaChapterDocument,
        canonicalData: Data
    ) async throws {
        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-exact-trim-chapters"
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
                        // The reviewed source is tag-free. FFmpeg can synthesize
                        // Matroska statistics tags, so remove those in the same edit.
                        "--tags", "all:",
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
                throw ExactTrimExecutionError.toolFailed(
                    tool: "mkvextract",
                    exitCode: exitCode,
                    message: message
                )
            case .unsafeExtractedDocument:
                throw ExactTrimExecutionError.unsafeChapterOutput
            case .mismatch:
                throw ExactTrimExecutionError.chapterVerificationFailed
            }
        }
    }

    private func requireSuccess(_ result: CommandResult, tool: String) throws {
        guard result.exitCode == 0 else {
            throw ExactTrimExecutionError.toolFailed(
                tool: tool,
                exitCode: result.exitCode,
                message: result.conciseFailureMessage
            )
        }
    }

    private func verifyCompleteFilePacketCopies(
        preview: ExactTrimPreview,
        output: MediaAsset
    ) async throws {
        guard preview.resolvedPlan.operation == .transcode else { return }
        let source = preview.resolvedPlan.source
        let copiedTrackIDs = Set(
            preview.copiedAudioTrackIDs + preview.copiedSubtitleTrackIDs
        )
        guard !copiedTrackIDs.isEmpty else { return }
        let reviewedTrackIDs = Set(preview.resolvedPlan.trackIDsInOutputOrder)
        let sourceTracks = source.tracks.filter { reviewedTrackIDs.contains($0.id) }
        let outputTracks = output.tracks.filter { $0.kind != .attachment }
        guard sourceTracks.count == outputTracks.count else {
            throw ExactTrimExecutionError.copiedTrackVerificationFailed(
                reason: "the media-track count changed"
            )
        }
        let lanes = zip(sourceTracks, outputTracks).enumerated().compactMap {
            laneIndex, pair -> JoinPacketAuditLane? in
            guard copiedTrackIDs.contains(pair.0.id) else { return nil }
            return JoinPacketAuditLane(
                laneIndex: laneIndex,
                kind: pair.0.kind,
                outputTrackID: pair.1.id,
                expectedInputs: [
                    JoinPacketFingerprintInput(
                        fileURL: source.sourceURL,
                        trackID: pair.0.id
                    )
                ]
            )
        }
        guard lanes.count == copiedTrackIDs.count else {
            throw ExactTrimExecutionError.copiedTrackVerificationFailed(
                reason: "the copied-track map changed"
            )
        }
        do {
            try await JoinOutputAuditor(
                ffmpegURL: ffmpegURL,
                ffprobeURL: ffprobeURL,
                runner: runner
            ).auditPacketCopies(sources: [source], output: output, lanes: lanes)
        } catch {
            throw ExactTrimExecutionError.copiedTrackVerificationFailed(
                reason: packetCopyFailureReason(error)
            )
        }
    }

    private func packetCopyFailureReason(_ error: Error) -> String {
        guard let error = error as? JoinOutputAuditError else {
            return "packet verification failed"
        }
        switch error {
        case .invalidTimeline, .invalidLanePlan:
            return "the reviewed packet map changed"
        case .unsafeInput:
            return "a source or output file was no longer safe"
        case .decodeFailed, .truncatedDecodeDiagnostics:
            return "the output decode audit failed"
        case .packetFingerprintFailed, .packetFingerprintBatchFailed:
            return "the packet fingerprint command failed"
        case .packetCountChanged:
            return "the copied packet count changed"
        case .packetPayloadChanged:
            return "a copied packet payload changed"
        }
    }

    private func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
