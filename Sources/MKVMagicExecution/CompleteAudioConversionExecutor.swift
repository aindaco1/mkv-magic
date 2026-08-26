import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

public enum CompleteAudioConversionExecutionError: Error, Equatable, Sendable {
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

extension CompleteAudioConversionExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedDestination:
            "Audio conversion currently creates one Matroska MKV output."
        case .unsafeSource:
            "Audio conversion needs a safe regular source file."
        case .staleSource:
            "The source or its chapters changed after review."
        case .inconsistentCommand:
            "The audio command no longer matches its reviewed encode/copy plan."
        case .copiedTrackVerificationFailed(let reason):
            "A packet-copied media track did not match the reviewed source: \(reason)"
        case .unsafeChapterOutput:
            "mkvextract did not create a safe, bounded chapter document."
        case .chapterVerificationFailed:
            "The output nested chapters do not match the reviewed tree."
        case .toolFailed(let tool, let exitCode, let message):
            "\(tool) could not complete audio conversion (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct CompleteAudioConversionPreview: Equatable, Sendable {
    public let resolvedPlan: ResolvedCompleteAudioConversionPlan
    public let capabilities: FFmpegEncodingCapabilities
    public let chapters: MatroskaChapterDocument
    public let sourceRevision: MediaSourceRevision
    public let sourceChapterSHA256: Data
    public let encodedAudioTrackIDs: [Int]
    public let copiedTrackIDs: [Int]

    init(
        resolvedPlan: ResolvedCompleteAudioConversionPlan,
        capabilities: FFmpegEncodingCapabilities,
        chapters: MatroskaChapterDocument,
        sourceRevision: MediaSourceRevision,
        sourceChapterSHA256: Data,
        encodedAudioTrackIDs: [Int],
        copiedTrackIDs: [Int]
    ) {
        self.resolvedPlan = resolvedPlan
        self.capabilities = capabilities
        self.chapters = chapters
        self.sourceRevision = sourceRevision
        self.sourceChapterSHA256 = sourceChapterSHA256
        self.encodedAudioTrackIDs = encodedAudioTrackIDs
        self.copiedTrackIDs = copiedTrackIDs
    }
}

public struct CompleteAudioConversionExecutor<
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
    private let commandBuilder = CompleteAudioConversionCommandBuilder()
    private let verifier = CompleteAudioConversionOutputVerifier()
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
        preset: AudioTranscodePreset,
        capabilities: FFmpegEncodingCapabilities
    ) async throws -> CompleteAudioConversionPreview {
        let resolved = try CompleteAudioConversionPlanner().resolve(
            source: source,
            preset: preset,
            availableAudioPresets: Set(capabilities.availableAudioPresets)
        )
        let revision: MediaSourceRevision
        do {
            revision = try MediaSourceRevision.read(source.sourceURL)
        } catch {
            throw CompleteAudioConversionExecutionError.unsafeSource
        }
        guard source.fileSize == nil || source.fileSize == revision.fileSize else {
            throw CompleteAudioConversionExecutionError.staleSource
        }
        let extracted = try await extractChapters(from: source.sourceURL)
        guard (try? MediaSourceRevision.read(source.sourceURL)) == revision else {
            throw CompleteAudioConversionExecutionError.staleSource
        }
        let command = try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-audio-conversion-preview"
        ) { directory in
            try commandBuilder.build(
                resolvedPlan: resolved,
                capabilities: capabilities,
                outputURL: directory.appendingPathComponent("preview.mkv")
            )
        }
        return CompleteAudioConversionPreview(
            resolvedPlan: resolved,
            capabilities: capabilities,
            chapters: extracted.document,
            sourceRevision: revision,
            sourceChapterSHA256: digest(extracted.canonicalData),
            encodedAudioTrackIDs: command.encodedAudioTrackIDs,
            copiedTrackIDs: command.copiedTrackIDs
        )
    }

    public func execute(
        preview: CompleteAudioConversionPreview,
        destinationURL: URL,
        validateReviewedSource: @escaping @Sendable () throws -> Void = {},
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw CompleteAudioConversionExecutionError.unsupportedDestination
        }
        try Task.checkCancellation()
        try await validateCurrent(preview)
        let expectedChapters = try chapterCodec.serialize(preview.chapters)

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
                guard command.encodedAudioTrackIDs == preview.encodedAudioTrackIDs,
                    command.copiedTrackIDs == preview.copiedTrackIDs
                else {
                    throw CompleteAudioConversionExecutionError.inconsistentCommand
                }
                let result = try await runner.run(
                    CommandRequest(
                        executableURL: ffmpegURL,
                        arguments: command.arguments,
                        timeout: 24 * 60 * 60,
                        outputLimit: 1_048_576
                    )
                )
                try requireSuccess(result, tool: "ffmpeg")
                try Task.checkCancellation()
                try await validateCurrent(preview)
                try await replaceChapters(
                    in: outputURL,
                    document: preview.chapters,
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
                    chapters: preview.chapters,
                    output: output
                )
                try await verifyPacketCopies(preview: preview, output: output)
                try await verifyChapters(
                    in: output.sourceURL,
                    expectedCanonical: expectedChapters
                )
                try await validateCurrent(preview)
            },
            validateSource: validateReviewedSource,
            committedAuditError: { outputURL, reason in
                CompleteAudioConversionExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }

    public func validateCurrent(_ preview: CompleteAudioConversionPreview) async throws {
        let sourceURL = preview.resolvedPlan.source.sourceURL
        guard (try? MediaSourceRevision.read(sourceURL)) == preview.sourceRevision else {
            throw CompleteAudioConversionExecutionError.staleSource
        }
        let extracted = try await extractChapters(from: sourceURL)
        guard digest(extracted.canonicalData) == preview.sourceChapterSHA256,
            (try? MediaSourceRevision.read(sourceURL)) == preview.sourceRevision
        else {
            throw CompleteAudioConversionExecutionError.staleSource
        }
    }

    private func extractChapters(from fileURL: URL) async throws -> ExtractedMatroskaChapters {
        do {
            return try await chapterExtractor.extract(from: fileURL)
        } catch let error as MatroskaChapterOutputAuditError {
            switch error {
            case .toolFailed(let exitCode, let message):
                throw CompleteAudioConversionExecutionError.toolFailed(
                    tool: "mkvextract",
                    exitCode: exitCode,
                    message: message
                )
            case .unsafeExtractedDocument:
                throw CompleteAudioConversionExecutionError.unsafeChapterOutput
            case .mismatch:
                throw CompleteAudioConversionExecutionError.chapterVerificationFailed
            }
        }
    }

    private func replaceChapters(
        in fileURL: URL,
        document: MatroskaChapterDocument,
        canonicalData: Data
    ) async throws {
        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-audio-conversion-chapters"
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
                        "--chapters", document.editions.isEmpty ? "" : chapterURL.path,
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
                throw CompleteAudioConversionExecutionError.toolFailed(
                    tool: "mkvextract",
                    exitCode: exitCode,
                    message: message
                )
            case .unsafeExtractedDocument:
                throw CompleteAudioConversionExecutionError.unsafeChapterOutput
            case .mismatch:
                throw CompleteAudioConversionExecutionError.chapterVerificationFailed
            }
        }
    }

    private func verifyPacketCopies(
        preview: CompleteAudioConversionPreview,
        output: MediaAsset
    ) async throws {
        let source = preview.resolvedPlan.source
        let copiedTrackIDs = Set(preview.copiedTrackIDs)
        guard !copiedTrackIDs.isEmpty else { return }
        let sourceTracks = source.tracks.filter { $0.kind != .attachment }
        let outputTracks = output.tracks.filter { $0.kind != .attachment }
        guard sourceTracks.count == outputTracks.count else {
            throw CompleteAudioConversionExecutionError.copiedTrackVerificationFailed(
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
            throw CompleteAudioConversionExecutionError.copiedTrackVerificationFailed(
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
            throw CompleteAudioConversionExecutionError.copiedTrackVerificationFailed(
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

    private func requireSuccess(_ result: CommandResult, tool: String) throws {
        guard result.exitCode == 0 else {
            throw CompleteAudioConversionExecutionError.toolFailed(
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
