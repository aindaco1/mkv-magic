import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum ExternalSubtitleMuxError: Error, Equatable, Sendable {
    case unsupportedSource
    case unsupportedDestination
    case invalidTrackName
    case sourceAndSubtitleAreSame
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

    fileprivate var advancedDocument: AdvancedSubStationAlphaDocument? {
        guard case .advanced(let preview) = self else { return nil }
        return preview.cleanup.original
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
        outputURL: URL
    ) async throws {
        let arguments = try Self.arguments(
            source: source,
            subtitleURL: subtitleURL,
            metadata: metadata,
            trackRemoval: trackRemoval,
            outputURL: outputURL
        )
        let result = try await runner.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: arguments,
                timeout: 24 * 60 * 60,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0 else {
            let combined =
                [result.standardError.text, result.standardOutput.text]
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                ?? "Unknown tool error"
            throw ExternalSubtitleMuxError.toolFailed(
                exitCode: result.exitCode,
                message: String(
                    combined.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
            )
        }
    }

    public static func arguments(
        source: MediaAsset,
        subtitleURL: URL,
        metadata: ExternalSubtitleTrackMetadata,
        trackRemoval: TrackRemoval? = nil,
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
        onStage: @escaping @Sendable (ExternalSubtitleMuxExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        try await execute(
            source: source,
            subtitlePreview: .subRip(subtitlePreview),
            metadata: metadata,
            destinationURL: destinationURL,
            onStage: onStage
        )
    }

    public func execute(
        source: MediaAsset,
        subtitlePreview: AdvancedSubtitleCleanupFilePreview,
        metadata: ExternalSubtitleTrackMetadata,
        destinationURL: URL,
        onStage: @escaping @Sendable (ExternalSubtitleMuxExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        try await execute(
            source: source,
            subtitlePreview: .advanced(subtitlePreview),
            metadata: metadata,
            destinationURL: destinationURL,
            onStage: onStage
        )
    }

    public func execute(
        source: MediaAsset,
        subtitlePreview: ExternalSubtitleFilePreview,
        metadata: ExternalSubtitleTrackMetadata,
        trackRemoval: TrackRemoval? = nil,
        removesSegmentTitle: Bool = false,
        destinationURL: URL,
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
                != subtitlePreview.sourceURL.standardizedFileURL
        else {
            throw ExternalSubtitleMuxError.sourceAndSubtitleAreSame
        }
        try subtitlePreview.validateCurrent()
        if removesSegmentTitle, propertyEditor == nil {
            throw ExternalSubtitleMuxError.missingPropertyEditor
        }
        let output = try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: source,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                let normalizedSubtitleURL = outputURL.deletingLastPathComponent()
                    .appendingPathComponent(
                        "external-subtitle.\(subtitlePreview.format.filenameExtension)"
                    )
                let normalizedSubtitle = subtitlePreview.normalizedOriginalData
                try normalizedSubtitle.write(
                    to: normalizedSubtitleURL, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: normalizedSubtitleURL) }
                try await muxer.mux(
                    source: source,
                    subtitleURL: normalizedSubtitleURL,
                    metadata: metadata,
                    trackRemoval: trackRemoval,
                    outputURL: outputURL
                )
                if removesSegmentTitle {
                    guard let propertyEditor else {
                        throw ExternalSubtitleMuxError.missingPropertyEditor
                    }
                    try await propertyEditor.editSegmentTitle(at: outputURL, title: nil)
                }
                if let advancedDocument = subtitlePreview.advancedDocument {
                    try await verifyAdvancedSubtitlePayload(
                        outputURL: outputURL,
                        original: advancedDocument
                    )
                }
            },
            verify: { output in
                try verifier.verify(
                    original: source,
                    output: output,
                    expectedMetadata: metadata,
                    expectedFormat: subtitlePreview.format,
                    subtitleEnd: subtitlePreview.subtitleEnd,
                    trackRemoval: trackRemoval,
                    segmentTitle: removesSegmentTitle ? .set(nil) : .preserve
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
        if let advancedDocument = subtitlePreview.advancedDocument {
            do {
                try await verifyAdvancedSubtitlePayload(
                    outputURL: output.sourceURL,
                    original: advancedDocument
                )
            } catch {
                throw ExternalSubtitleMuxError.committedOutputAuditFailed(
                    outputURL: output.sourceURL,
                    reason: error.localizedDescription
                )
            }
        }
        return output
    }

    private func verifyAdvancedSubtitlePayload(
        outputURL: URL,
        original: AdvancedSubStationAlphaDocument
    ) async throws {
        guard let mkvextractURL else {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
        let preliminaryOutput = try await inspector.inspect(outputURL)
        guard let addedTrack = preliminaryOutput.tracks.filter({ $0.kind != .attachment }).last,
            addedTrack.kind == .subtitle
        else {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
        let auditURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("external-subtitle-audit.ass")
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
                allowedExtensions: ["ass"],
                maximumInputBytes: AdvancedSubtitleCleanupExecutor.maximumInputBytes
            )
        } catch {
            throw ExternalSubtitleMuxError.subtitleVerificationFailed
        }
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
