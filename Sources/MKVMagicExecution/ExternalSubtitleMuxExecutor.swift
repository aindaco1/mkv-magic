import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum ExternalSubtitleMuxError: Error, Equatable, Sendable {
    case unsupportedSource
    case unsupportedDestination
    case invalidTrackName
    case sourceAndSubtitleAreSame
    case invalidCleanupReview
    case missingPropertyEditor
    case subtitleVerificationFailed
    case toolFailed(exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension ExternalSubtitleMuxError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "External subtitle muxing requires an inspected Matroska source."
        case .unsupportedDestination:
            "External subtitle muxing currently creates an MKV file."
        case .invalidTrackName:
            "The subtitle track name is too large or contains an unsupported null character."
        case .sourceAndSubtitleAreSame:
            "The external subtitle must be a different file from the video source."
        case .invalidCleanupReview:
            "The reviewed subtitle cleanup selection is no longer valid. Preview it again."
        case .missingPropertyEditor:
            "This combined workflow requires the bundled Matroska property editor."
        case .subtitleVerificationFailed:
            "The muxed subtitle did not pass its timing, text, and style audit."
        case .toolFailed(let exitCode, let message):
            "mkvmerge could not add the subtitle (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public typealias ExternalSubtitleMuxExecutionStage = VerifiedOutputExecutionStage

public enum ExternalSubtitleFilePreview: Equatable, Sendable {
    case subRip(SubtitleCleanupFilePreview)
    case advanced(AdvancedSubtitleCleanupFilePreview)

    public var sourceURL: URL {
        switch self {
        case .subRip(let preview): preview.sourceURL
        case .advanced(let preview): preview.sourceURL
        }
    }

    public var format: ExternalTextSubtitleFormat {
        switch self {
        case .subRip: .subRip
        case .advanced(let preview):
            preview.sourceURL.pathExtension.lowercased() == "ssa" ? .ssa : .ass
        }
    }

    public var sourceSHA256: Data {
        switch self {
        case .subRip(let preview): preview.sourceSHA256
        case .advanced(let preview): preview.sourceSHA256
        }
    }

    public var cleanupChangeCount: Int {
        switch self {
        case .subRip(let preview): preview.cleanup.changes.count
        case .advanced(let preview): preview.cleanup.changes.count
        }
    }

    public var subtitleEnd: SubRipTimestamp {
        switch self {
        case .subRip(let preview):
            preview.cleanup.original.cues.map(\.end).max()
                ?? SubRipTimestamp(milliseconds: 0)
        case .advanced(let preview):
            preview.cleanup.original.events.map(\.end).max()
                ?? SubRipTimestamp(milliseconds: 0)
        }
    }

    fileprivate var normalizedOriginalData: Data {
        switch self {
        case .subRip(let preview):
            Data(SubRipCodec().serialize(preview.cleanup.original).utf8)
        case .advanced(let preview):
            Data(
                AdvancedSubStationAlphaCodec().serialize(preview.cleanup.original).utf8
            )
        }
    }

    fileprivate func validateCurrent() throws {
        switch self {
        case .subRip(let preview):
            try SubtitleCleanupExecutor().validateCurrent(preview)
        case .advanced(let preview):
            try AdvancedSubtitleCleanupExecutor().validateCurrent(preview)
        }
    }
}

/// The per-run subtitle payload chosen by the user. Portable workflows persist only
/// the cleanup action; a queued reviewed run may privately retain its bounded choices.
public enum ExternalSubtitleMuxPayload: Equatable, Sendable {
    case original(ExternalSubtitleFilePreview)
    case reviewedCleanup(ExternalSubtitleFilePreview, restoringIDs: Set<Int>)

    public var preview: ExternalSubtitleFilePreview {
        switch self {
        case .original(let preview), .reviewedCleanup(let preview, _): preview
        }
    }

    public var sourceURL: URL { preview.sourceURL }
    public var format: ExternalTextSubtitleFormat { preview.format }

    public var appliedCleanupChangeCount: Int {
        switch self {
        case .original: return 0
        case .reviewedCleanup(let preview, let restoringIDs):
            return preview.cleanupChangeCount - restoringIDs.count
        }
    }

    public var reviewedCleanupChangeCount: Int? {
        switch self {
        case .original: nil
        case .reviewedCleanup: appliedCleanupChangeCount
        }
    }

    public func validateForReview() throws {
        try validateCurrent()
    }

    fileprivate var normalizedData: Data {
        switch self {
        case .original(let preview):
            return preview.normalizedOriginalData
        case .reviewedCleanup(.subRip(let preview), let restoringIDs):
            let desired = preview.cleanup.document(restoringCueIDs: restoringIDs)
            return Data(SubRipCodec().serialize(desired).utf8)
        case .reviewedCleanup(.advanced(let preview), let restoringIDs):
            let desired = preview.cleanup.document(restoringEventIDs: restoringIDs)
            return Data(AdvancedSubStationAlphaCodec().serialize(desired).utf8)
        }
    }

    fileprivate var subtitleEnd: SubRipTimestamp {
        switch self {
        case .original(let preview): return preview.subtitleEnd
        case .reviewedCleanup(.subRip(let preview), let restoringIDs):
            return preview.cleanup.document(restoringCueIDs: restoringIDs).cues.map(\.end).max()
                ?? SubRipTimestamp(milliseconds: 0)
        case .reviewedCleanup(.advanced(let preview), let restoringIDs):
            return preview.cleanup.document(restoringEventIDs: restoringIDs).events.map(\.end).max()
                ?? SubRipTimestamp(milliseconds: 0)
        }
    }

    fileprivate var subRipDocumentForAudit: SubRipDocument? {
        guard case .reviewedCleanup(.subRip(let preview), let restoringIDs) = self else {
            return nil
        }
        return preview.cleanup.document(restoringCueIDs: restoringIDs)
    }

    fileprivate var advancedDocumentForAudit: AdvancedSubStationAlphaDocument? {
        switch self {
        case .original(.advanced(let preview)):
            return preview.cleanup.original
        case .reviewedCleanup(.advanced(let preview), let restoringIDs):
            return preview.cleanup.document(restoringEventIDs: restoringIDs)
        case .original(.subRip), .reviewedCleanup(.subRip, _):
            return nil
        }
    }

    fileprivate func validateCurrent() throws {
        try preview.validateCurrent()
        guard case .reviewedCleanup(let preview, let restoringIDs) = self else { return }
        let validIDs: Set<Int>
        let hasRemainingText: Bool
        switch preview {
        case .subRip(let preview):
            validIDs = Set(preview.cleanup.changes.map(\.id))
            hasRemainingText = !preview.cleanup.document(restoringCueIDs: restoringIDs).cues.isEmpty
        case .advanced(let preview):
            validIDs = Set(preview.cleanup.changes.map(\.id))
            hasRemainingText =
                !preview.cleanup.document(restoringEventIDs: restoringIDs).events.isEmpty
        }
        guard restoringIDs.isSubset(of: validIDs), hasRemainingText else {
            throw ExternalSubtitleMuxError.invalidCleanupReview
        }
    }
}

public struct MKVExternalSubtitleMuxer<Runner: CommandRunning>: Sendable {
    private let executableURL: URL
    private let runner: Runner

    public init(executableURL: URL, runner: Runner) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public func mux(
        source: MediaAsset,
        subtitleURL: URL,
        metadata: ExternalSubtitleTrackMetadata,
        trackRemoval: TrackRemoval? = nil,
        attachmentRemoval: MatroskaAttachmentRemoval? = nil,
        outputURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in }
    ) async throws {
        let arguments = try Self.arguments(
            source: source,
            subtitleURL: subtitleURL,
            metadata: metadata,
            trackRemoval: trackRemoval,
            attachmentRemoval: attachmentRemoval,
            outputURL: outputURL
        )
        let result = try await runner.run(
            MKVToolNixProgress.request(
                executableURL: executableURL,
                arguments: arguments,
                timeout: 24 * 60 * 60,
                onProgress: onProgress
            )
        )
        guard result.exitCode == 0 else {
            throw ExternalSubtitleMuxError.toolFailed(
                exitCode: result.exitCode,
                message: result.conciseFailureMessage
            )
        }
    }

    public static func arguments(
        source: MediaAsset,
        subtitleURL: URL,
        metadata: ExternalSubtitleTrackMetadata,
        trackRemoval: TrackRemoval? = nil,
        attachmentRemoval: MatroskaAttachmentRemoval? = nil,
        outputURL: URL
    ) throws -> [String] {
        let language = try TrackLanguageTag.canonical(metadata.language)
        if let name = metadata.name {
            guard !name.contains("\0"), name.utf8.count <= 4_096 else {
                throw ExternalSubtitleMuxError.invalidTrackName
            }
        }
        var arguments = [
            "--output", outputURL.path,
            "--abort-on-warnings",
            "--normalize-language-ietf", "canonical",
            "--disable-track-statistics-tags",
        ]
        let retainedTracks: [MediaTrack]
        if let trackRemoval {
            let selection = try MKVTrackSelection(source: source, removal: trackRemoval)
            retainedTracks = selection.retainedTracks
            arguments.append(contentsOf: selection.selectorArguments)
        } else {
            retainedTracks = source.tracks.filter { $0.kind != .attachment }
        }
        if let attachmentRemoval {
            arguments.append(
                contentsOf: try MKVAttachmentSelection(
                    source: source,
                    removal: attachmentRemoval
                ).selectorArguments
            )
        }
        arguments.append(contentsOf: [
            source.sourceURL.path,
            "--language", "0:\(language)",
            "--default-track-flag", "0:\(metadata.isDefault ? "yes" : "no")",
            "--forced-display-flag", "0:\(metadata.isForced ? "yes" : "no")",
            "--hearing-impaired-flag", "0:\(metadata.isHearingImpaired ? "yes" : "no")",
        ])
        if let name = metadata.name {
            arguments.append(contentsOf: ["--track-name", "0:\(name)"])
        }
        arguments.append(subtitleURL.path)
        let trackOrder = (retainedTracks.map { "0:\($0.id)" } + ["1:0"]).joined(separator: ",")
        arguments.append(contentsOf: ["--track-order", trackOrder])
        return arguments
    }
}

public struct ExternalSubtitleMuxExecutor<Runner: CommandRunning, Inspector: MediaInspecting>:
    Sendable
{
    private let muxer: MKVExternalSubtitleMuxer<Runner>
    private let propertyEditor: MKVPropertyEditor<Runner>?
    private let mkvextractURL: URL?
    private let runner: Runner
    private let inspector: Inspector
    private let verifier = ExternalSubtitleMuxOutputVerifier()

    public init(
        mkvmergeURL: URL,
        mkvpropeditURL: URL? = nil,
        mkvextractURL: URL? = nil,
        runner: Runner,
        inspector: Inspector
    ) {
        muxer = MKVExternalSubtitleMuxer(executableURL: mkvmergeURL, runner: runner)
        propertyEditor = mkvpropeditURL.map {
            MKVPropertyEditor(executableURL: $0, runner: runner)
        }
        self.mkvextractURL = mkvextractURL
        self.runner = runner
        self.inspector = inspector
    }

    public func execute(
        source: MediaAsset,
        subtitlePreview: SubtitleCleanupFilePreview,
        metadata: ExternalSubtitleTrackMetadata,
        destinationURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (ExternalSubtitleMuxExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        try await execute(
            source: source,
            subtitlePreview: .subRip(subtitlePreview),
            metadata: metadata,
            destinationURL: destinationURL,
            onProgress: onProgress,
            onStage: onStage
        )
    }

    public func execute(
        source: MediaAsset,
        subtitlePreview: AdvancedSubtitleCleanupFilePreview,
        metadata: ExternalSubtitleTrackMetadata,
        destinationURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (ExternalSubtitleMuxExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        try await execute(
            source: source,
            subtitlePreview: .advanced(subtitlePreview),
            metadata: metadata,
            destinationURL: destinationURL,
            onProgress: onProgress,
            onStage: onStage
        )
    }

    public func execute(
        source: MediaAsset,
        subtitlePreview: ExternalSubtitleFilePreview,
        metadata: ExternalSubtitleTrackMetadata,
        trackRemoval: TrackRemoval? = nil,
        attachmentRemoval: MatroskaAttachmentRemoval? = nil,
        trackMetadataEdits: [TrackMetadataEdit] = [],
        removesSegmentTitle: Bool = false,
        clearsAllTags: Bool = false,
        destinationURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (ExternalSubtitleMuxExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        try await execute(
            source: source,
            subtitlePayload: .original(subtitlePreview),
            metadata: metadata,
            trackRemoval: trackRemoval,
            attachmentRemoval: attachmentRemoval,
            trackMetadataEdits: trackMetadataEdits,
            removesSegmentTitle: removesSegmentTitle,
            clearsAllTags: clearsAllTags,
            destinationURL: destinationURL,
            onProgress: onProgress,
            onStage: onStage
        )
    }

    public func execute(
        source: MediaAsset,
        subtitlePayload: ExternalSubtitleMuxPayload,
        metadata: ExternalSubtitleTrackMetadata,
        trackRemoval: TrackRemoval? = nil,
        attachmentRemoval: MatroskaAttachmentRemoval? = nil,
        trackMetadataEdits: [TrackMetadataEdit] = [],
        removesSegmentTitle: Bool = false,
        clearsAllTags: Bool = false,
        destinationURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (ExternalSubtitleMuxExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        guard MatroskaEditingPolicy.supports(source) else {
            throw ExternalSubtitleMuxError.unsupportedSource
        }
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw ExternalSubtitleMuxError.unsupportedDestination
        }
        guard
            source.sourceURL.standardizedFileURL
                != subtitlePayload.sourceURL.standardizedFileURL
        else {
            throw ExternalSubtitleMuxError.sourceAndSubtitleAreSame
        }
        try subtitlePayload.validateCurrent()
        if removesSegmentTitle || clearsAllTags || !trackMetadataEdits.isEmpty,
            propertyEditor == nil
        {
            throw ExternalSubtitleMuxError.missingPropertyEditor
        }
        let output = try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: source,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                let normalizedSubtitleURL = outputURL.deletingLastPathComponent()
                    .appendingPathComponent(
                        "external-subtitle.\(subtitlePayload.format.filenameExtension)"
                    )
                let normalizedSubtitle = subtitlePayload.normalizedData
                try normalizedSubtitle.write(
                    to: normalizedSubtitleURL, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: normalizedSubtitleURL) }
                try await muxer.mux(
                    source: source,
                    subtitleURL: normalizedSubtitleURL,
                    metadata: metadata,
                    trackRemoval: trackRemoval,
                    attachmentRemoval: attachmentRemoval,
                    outputURL: outputURL,
                    onProgress: onProgress
                )
                if removesSegmentTitle || clearsAllTags || !trackMetadataEdits.isEmpty {
                    guard let propertyEditor else {
                        throw ExternalSubtitleMuxError.missingPropertyEditor
                    }
                    if !trackMetadataEdits.isEmpty {
                        try await propertyEditor.editWorkflowProperties(
                            at: outputURL,
                            originalTracks: source.tracks,
                            edits: trackMetadataEdits,
                            removesSegmentTitle: removesSegmentTitle,
                            clearAllTags: clearsAllTags
                        )
                    } else if removesSegmentTitle {
                        try await propertyEditor.editSegmentTitle(
                            at: outputURL,
                            title: nil,
                            clearAllTags: clearsAllTags
                        )
                    } else {
                        try await propertyEditor.clearAllTags(at: outputURL)
                    }
                }
                try await verifySubtitlePayload(outputURL: outputURL, payload: subtitlePayload)
            },
            verify: { output in
                try verifier.verify(
                    original: source,
                    output: output,
                    expectedMetadata: metadata,
                    expectedFormat: subtitlePayload.format,
                    subtitleEnd: subtitlePayload.subtitleEnd,
                    trackRemoval: trackRemoval,
                    attachmentRemoval: attachmentRemoval,
                    trackMetadataEdits: trackMetadataEdits,
                    segmentTitle: removesSegmentTitle ? .set(nil) : .preserve,
                    tags: clearsAllTags ? .removeAll : .preserve
                )
            },
            committedAuditError: { outputURL, reason in
                ExternalSubtitleMuxError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
        do {
            try await verifySubtitlePayload(outputURL: output.sourceURL, payload: subtitlePayload)
        } catch {
            throw ExternalSubtitleMuxError.committedOutputAuditFailed(
                outputURL: output.sourceURL,
                reason: error.localizedDescription
            )
        }
        return output
    }

    private func verifySubtitlePayload(
        outputURL: URL,
        payload: ExternalSubtitleMuxPayload
    ) async throws {
        if let subRipDocument = payload.subRipDocumentForAudit {
            try await verifySubRipSubtitlePayload(
                outputURL: outputURL,
                intended: subRipDocument
            )
        }
        if let advancedDocument = payload.advancedDocumentForAudit {
            try await verifyAdvancedSubtitlePayload(
                outputURL: outputURL,
                original: advancedDocument
            )
        }
    }

    private func verifySubRipSubtitlePayload(
        outputURL: URL,
        intended: SubRipDocument
    ) async throws {
        guard let mkvextractURL else {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
        let auditURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("external-subtitle-audit.srt")
        let extractedData = try await extractAddedSubtitle(
            outputURL: outputURL,
            auditURL: auditURL,
            mkvextractURL: mkvextractURL,
            allowedExtensions: ["srt"]
        )
        let extracted: SubRipDocument
        do {
            extracted = try SubRipCodec().parse(
                SubtitleTextDecoder().decode(extractedData)
            ).document
        } catch {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
        guard SubRipMuxPayloadVerifier().verify(intended: intended, extracted: extracted) else {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
    }

    private func verifyAdvancedSubtitlePayload(
        outputURL: URL,
        original: AdvancedSubStationAlphaDocument
    ) async throws {
        guard let mkvextractURL else {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
        let auditURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("external-subtitle-audit.ass")
        let extractedData = try await extractAddedSubtitle(
            outputURL: outputURL,
            auditURL: auditURL,
            mkvextractURL: mkvextractURL,
            allowedExtensions: ["ass"]
        )
        let extracted: AdvancedSubStationAlphaDocument
        do {
            extracted = try AdvancedSubStationAlphaCodec().parse(
                SubtitleTextDecoder().decode(extractedData)
            ).document
        } catch {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
        guard
            AdvancedSubtitleMuxPayloadVerifier().verify(
                original: original,
                extracted: extracted
            )
        else {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
    }

    private func extractAddedSubtitle(
        outputURL: URL,
        auditURL: URL,
        mkvextractURL: URL,
        allowedExtensions: Set<String>
    ) async throws -> Data {
        let preliminaryOutput = try await inspector.inspect(outputURL)
        guard let addedTrack = preliminaryOutput.tracks.filter({ $0.kind != .attachment }).last,
            addedTrack.kind == .subtitle
        else {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
        defer { try? FileManager.default.removeItem(at: auditURL) }
        let result = try await runner.run(
            CommandRequest(
                executableURL: mkvextractURL,
                arguments: ["tracks", outputURL.path, "\(addedTrack.id):\(auditURL.path)"],
                timeout: 120,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0 else {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
        let extractedData: Data
        do {
            extractedData = try SafeSubtitleTextFile.read(
                auditURL,
                allowedExtensions: allowedExtensions,
                maximumInputBytes: AdvancedSubtitleCleanupExecutor.maximumInputBytes
            )
        } catch {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
        return extractedData
    }
}

struct SubRipMuxPayloadVerifier {
    func verify(intended: SubRipDocument, extracted: SubRipDocument) -> Bool {
        guard intended.cues.count == extracted.cues.count else { return false }
        return zip(intended.cues, extracted.cues).allSatisfy { intended, extracted in
            timestampsMatch(intended.start, extracted.start)
                && timestampsMatch(intended.end, extracted.end)
                && intended.lines == extracted.lines
        }
    }

    private func timestampsMatch(_ lhs: SubRipTimestamp, _ rhs: SubRipTimestamp) -> Bool {
        let difference = lhs.milliseconds.subtractingReportingOverflow(rhs.milliseconds)
        guard !difference.overflow, difference.partialValue != Int64.min else { return false }
        return abs(difference.partialValue) <= 1
    }
}

struct AdvancedSubtitleMuxPayloadVerifier {
    func verify(
        original: AdvancedSubStationAlphaDocument,
        extracted: AdvancedSubStationAlphaDocument
    ) -> Bool {
        guard headerLines(original) == headerLines(extracted),
            original.events.count == extracted.events.count
        else {
            return false
        }
        return zip(original.events, extracted.events).allSatisfy { original, extracted in
            timestampsMatch(original.start, extracted.start)
                && timestampsMatch(original.end, extracted.end)
                && original.structuralFields == extracted.structuralFields
                && original.text.trimmingCharacters(in: .whitespaces)
                    == extracted.text.trimmingCharacters(in: .whitespaces)
        }
    }

    private func headerLines(_ document: AdvancedSubStationAlphaDocument) -> [String] {
        var result = [String]()
        for line in document.lines {
            switch line {
            case .raw(let value): result.append(value)
            case .dialogue: return result
            }
        }
        return result
    }

    private func timestampsMatch(_ lhs: SubRipTimestamp, _ rhs: SubRipTimestamp) -> Bool {
        let difference = lhs.milliseconds.subtractingReportingOverflow(rhs.milliseconds)
        guard !difference.overflow, difference.partialValue != Int64.min else { return false }
        return abs(difference.partialValue) <= 10
    }
}
