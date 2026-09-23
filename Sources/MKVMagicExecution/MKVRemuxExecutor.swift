import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

public enum MKVRemuxExecutionError: Error, Equatable, Sendable {
    case unsupportedDestination
    case unsafeSource
    case staleSource
    case toolFailed(exitCode: Int32, message: String)
    case copiedTrackVerificationFailed(reason: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension MKVRemuxExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedDestination: "Remux to MKV creates one .mkv output."
        case .unsafeSource: "Remux to MKV needs a safe regular source file."
        case .staleSource: "The source changed after the zero-encode remux was reviewed."
        case .toolFailed(let exitCode, let message):
            "mkvmerge could not create the temporary MKV (code \(exitCode)): \(message)"
        case .copiedTrackVerificationFailed(let reason):
            "A copied media track did not match the reviewed source: \(reason)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen audit failed: \(reason)"
        }
    }
}

public struct MKVRemuxPreview: Hashable, Sendable {
    public let plan: ResolvedMKVRemuxPlan
    public let sourceRevision: MediaSourceRevision

    public init(plan: ResolvedMKVRemuxPlan, sourceRevision: MediaSourceRevision) {
        self.plan = plan
        self.sourceRevision = sourceRevision
    }

    public var source: MediaAsset { plan.source }
}

public struct MKVRemuxWithExternalSubtitlePreview: Equatable, Sendable {
    public let remux: MKVRemuxPreview
    public let subtitlePayload: ExternalSubtitleMuxPayload
    public let subtitleMetadata: ExternalSubtitleTrackMetadata
    public let trackLanguageOverrides: [Int: String]

    public init(
        remux: MKVRemuxPreview,
        subtitlePayload: ExternalSubtitleMuxPayload,
        subtitleMetadata: ExternalSubtitleTrackMetadata,
        trackLanguageOverrides: [Int: String]
    ) {
        self.remux = remux
        self.subtitlePayload = subtitlePayload
        self.subtitleMetadata = subtitleMetadata
        self.trackLanguageOverrides = trackLanguageOverrides
    }

    public var source: MediaAsset { remux.source }
}

public struct MKVRemuxExecutor<
    Runner: CommandRunning & CommandLineDigesting,
    Inspector: MediaInspecting
>: Sendable {
    private let mkvmergeURL: URL
    private let ffmpegURL: URL
    private let ffprobeURL: URL
    private let mkvextractURL: URL?
    private let runner: Runner
    private let inspector: Inspector
    private let planner = MKVRemuxPlanner()
    private let commandBuilder = MKVRemuxCommandBuilder()
    private let verifier = MKVRemuxOutputVerifier()

    public init(
        mkvmergeURL: URL,
        ffmpegURL: URL,
        ffprobeURL: URL,
        mkvextractURL: URL? = nil,
        runner: Runner,
        inspector: Inspector
    ) {
        self.mkvmergeURL = mkvmergeURL
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
        self.mkvextractURL = mkvextractURL
        self.runner = runner
        self.inspector = inspector
    }

    public func preview(source: MediaAsset) throws -> MKVRemuxPreview {
        let plan = try planner.resolve(source: source)
        let revision: MediaSourceRevision
        do {
            revision = try MediaSourceRevision.read(source.sourceURL)
        } catch {
            throw MKVRemuxExecutionError.unsafeSource
        }
        return MKVRemuxPreview(plan: plan, sourceRevision: revision)
    }

    public func preview(
        source: MediaAsset,
        subtitlePayload: ExternalSubtitleMuxPayload,
        subtitleMetadata: ExternalSubtitleTrackMetadata,
        trackLanguageOverrides: [Int: String]
    ) throws -> MKVRemuxWithExternalSubtitlePreview {
        let remux = try preview(source: source)
        guard
            source.sourceURL.standardizedFileURL
                != subtitlePayload.sourceURL.standardizedFileURL
        else { throw ExternalSubtitleMuxError.sourceAndSubtitleAreSame }
        try subtitlePayload.validateForReview()
        let audioTrackIDs = Set(source.tracks.filter { $0.kind == .audio }.map(\.id))
        guard Set(trackLanguageOverrides.keys).isSubset(of: audioTrackIDs) else {
            throw MKVRemuxCommandError.inconsistentPlan
        }
        for language in trackLanguageOverrides.values {
            _ = try TrackLanguageTag.canonical(language)
        }
        _ = try TrackLanguageTag.canonical(subtitleMetadata.language)
        return MKVRemuxWithExternalSubtitlePreview(
            remux: remux,
            subtitlePayload: subtitlePayload,
            subtitleMetadata: subtitleMetadata,
            trackLanguageOverrides: trackLanguageOverrides
        )
    }

    public func execute(
        preview: MKVRemuxPreview,
        destinationURL: URL,
        trackLanguageOverrides: [Int: String] = [:],
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        try await execute(
            preview: preview,
            appendedSubtitles: [],
            destinationURL: destinationURL,
            sourceLanguageOverrides: trackLanguageOverrides,
            onProgress: onProgress,
            onStage: onStage
        )
    }

    public func execute(
        preview: MKVRemuxWithExternalSubtitlePreview,
        destinationURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        try await execute(
            preview: preview.remux,
            appendedSubtitles: [preview],
            destinationURL: destinationURL,
            onProgress: onProgress,
            onStage: onStage
        )
    }

    public func execute(
        previews: [MKVRemuxWithExternalSubtitlePreview],
        destinationURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard let first = previews.first else { throw MKVRemuxCommandError.inconsistentPlan }
        return try await execute(
            preview: first.remux, appendedSubtitles: previews,
            destinationURL: destinationURL, onProgress: onProgress, onStage: onStage)
    }

    private func execute(
        preview: MKVRemuxPreview,
        appendedSubtitles: [MKVRemuxWithExternalSubtitlePreview],
        destinationURL: URL,
        sourceLanguageOverrides: [Int: String] = [:],
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void
    ) async throws -> MediaAsset {
        guard appendedSubtitles.count <= ExternalSubtitleBatchPolicy.maximumSubtitlesPerVideo,
            Set(appendedSubtitles.map { $0.subtitlePayload.sourceURL.standardizedFileURL }).count
                == appendedSubtitles.count,
            appendedSubtitles.allSatisfy({
                $0.remux == preview
                    && $0.trackLanguageOverrides == appendedSubtitles.first?.trackLanguageOverrides
                    && $0.subtitlePayload.sourceURL.standardizedFileURL
                        != preview.source.sourceURL.standardizedFileURL
                    && $0.subtitlePayload.sourceURL.standardizedFileURL
                        != destinationURL.standardizedFileURL
            })
        else { throw MKVRemuxCommandError.inconsistentPlan }
        let languageOverrides =
            appendedSubtitles.first?.trackLanguageOverrides ?? sourceLanguageOverrides
        let expectations = appendedSubtitles.map {
            MKVRemuxAppendedSubtitleExpectation(
                metadata: $0.subtitleMetadata, format: $0.subtitlePayload.format,
                end: $0.subtitlePayload.subtitleEnd)
        }
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw MKVRemuxExecutionError.unsupportedDestination
        }
        let validateVideo = try mediaFileRevisionValidator(
            sourceURL: preview.source.sourceURL,
            expectedRevision: preview.sourceRevision,
            changedError: MKVRemuxExecutionError.staleSource
        )
        let validateSource: @Sendable () throws -> Void = {
            try validateVideo()
            for subtitle in appendedSubtitles {
                try subtitle.subtitlePayload.validateCurrent()
            }
        }
        let output = try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: preview.source,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                try Task.checkCancellation()
                try validateSource()
                let reviewedChaptersURL = try writeReviewedChapters(
                    for: preview.plan,
                    beside: outputURL
                )
                var normalizedSubtitleURLs = [URL]()
                defer {
                    if let reviewedChaptersURL {
                        try? FileManager.default.removeItem(at: reviewedChaptersURL)
                    }
                    for url in normalizedSubtitleURLs {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                for (index, appendedSubtitle) in appendedSubtitles.enumerated() {
                    let url = outputURL.deletingLastPathComponent().appendingPathComponent(
                        "external-subtitle-\(index).\(appendedSubtitle.subtitlePayload.format.filenameExtension)"
                    )
                    try appendedSubtitle.subtitlePayload.normalizedData.write(
                        to: url,
                        options: .withoutOverwriting
                    )
                    normalizedSubtitleURLs.append(url)
                }
                let subtitleArguments = zip(normalizedSubtitleURLs, appendedSubtitles).map {
                    (url: $0.0, metadata: $0.1.subtitleMetadata)
                }
                let arguments = try commandBuilder.build(
                    plan: preview.plan,
                    outputURL: outputURL,
                    reviewedChaptersURL: reviewedChaptersURL,
                    trackLanguageOverrides: languageOverrides,
                    externalSubtitle: subtitleArguments.first,
                    additionalExternalSubtitles: Array(subtitleArguments.dropFirst())
                )
                let result = try await runner.run(
                    MKVToolNixProgress.request(
                        executableURL: mkvmergeURL,
                        arguments: arguments,
                        timeout: 24 * 60 * 60,
                        onProgress: onProgress
                    )
                )
                guard result.exitCode == 0,
                    !result.standardError.wasTruncated,
                    !result.standardOutput.wasTruncated
                else {
                    let rawMessage =
                        result.standardError.text.isEmpty
                        ? result.standardOutput.text : result.standardError.text
                    throw MKVRemuxExecutionError.toolFailed(
                        exitCode: result.exitCode,
                        message: String(rawMessage.prefix(240))
                    )
                }
                for (index, appendedSubtitle) in appendedSubtitles.enumerated() {
                    try await ExternalSubtitlePayloadAuditor(
                        mkvextractURL: mkvextractURL,
                        runner: runner,
                        inspector: inspector
                    ).verify(
                        outputURL: outputURL,
                        payload: appendedSubtitle.subtitlePayload,
                        auditOriginalSubRip: true,
                        trackOffsetFromEnd: appendedSubtitles.count - 1 - index
                    )
                    try appendedSubtitle.subtitlePayload.validateCurrent()
                }
                try validateSource()
            },
            verify: { output in
                try verifier.verify(
                    plan: preview.plan,
                    output: output,
                    trackLanguageOverrides: languageOverrides,
                    appendedSubtitle: expectations.first,
                    additionalAppendedSubtitles: Array(expectations.dropFirst())
                )
                let copiedTrackIDs = Set(preview.plan.trackIDsInOutputOrder)
                let sourceTracks = preview.source.tracks.filter {
                    copiedTrackIDs.contains($0.id)
                }
                let outputTracks = output.tracks.filter { $0.kind != .attachment }
                let lanes = zip(sourceTracks, outputTracks).enumerated().map {
                    JoinPacketAuditLane(
                        laneIndex: $0.offset,
                        kind: $0.element.0.kind,
                        outputTrackID: $0.element.1.id,
                        expectedInputs: [
                            JoinPacketFingerprintInput(
                                fileURL: preview.source.sourceURL,
                                trackID: $0.element.0.id
                            )
                        ]
                    )
                }
                do {
                    try await JoinOutputAuditor(
                        ffmpegURL: ffmpegURL,
                        ffprobeURL: ffprobeURL,
                        runner: runner
                    ).auditPacketCopies(
                        sources: [preview.source],
                        output: output,
                        lanes: lanes
                    )
                } catch {
                    throw MKVRemuxExecutionError.copiedTrackVerificationFailed(
                        reason: String(error.localizedDescription.prefix(240))
                    )
                }
                try validateSource()
            },
            validateSource: validateSource,
            committedAuditError: { outputURL, reason in
                MKVRemuxExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
        for (index, appendedSubtitle) in appendedSubtitles.enumerated() {
            do {
                try await ExternalSubtitlePayloadAuditor(
                    mkvextractURL: mkvextractURL,
                    runner: runner,
                    inspector: inspector
                ).verify(
                    outputURL: output.sourceURL,
                    payload: appendedSubtitle.subtitlePayload,
                    auditOriginalSubRip: true,
                    trackOffsetFromEnd: appendedSubtitles.count - 1 - index
                )
            } catch {
                throw MKVRemuxExecutionError.committedOutputAuditFailed(
                    outputURL: output.sourceURL,
                    reason: error.localizedDescription
                )
            }
        }
        return output
    }

    private func writeReviewedChapters(
        for plan: ResolvedMKVRemuxPlan,
        beside outputURL: URL
    ) throws -> URL? {
        guard !plan.source.chapters.isEmpty else { return nil }
        guard let duration = plan.source.duration else {
            throw MKVRemuxCommandError.inconsistentPlan
        }
        let document = try MatroskaChapterDocument.importingInspectedChapters(
            plan.source.chapters,
            sourceID: plan.source.id,
            mediaDuration: duration
        )
        let url = outputURL.deletingLastPathComponent().appendingPathComponent(
            "reviewed-chapters.xml"
        )
        try MatroskaChapterXMLCodec().serialize(document).write(
            to: url,
            options: .withoutOverwriting
        )
        return url
    }
}
