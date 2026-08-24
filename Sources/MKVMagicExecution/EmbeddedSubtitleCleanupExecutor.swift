import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum EmbeddedSubtitleCleanupError: Error, Equatable, Sendable {
    case unsupportedSource
    case unsupportedDestination
    case trackNotFound
    case unstableTrackIdentity
    case unsupportedTrackFormat
    case staleSource
    case unsafeExtractedSubtitle
    case oversizedExtractedSubtitle
    case invalidExtractedTiming
    case invalidTrackMetadata
    case noCuesRemaining
    case noEventsRemaining
    case subtitleTimingVerificationFailed
    case subtitleVerificationFailed
    case toolFailed(tool: String, exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension EmbeddedSubtitleCleanupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Embedded subtitle cleanup requires an inspected Matroska source."
        case .unsupportedDestination:
            "Embedded subtitle cleanup currently creates an MKV file."
        case .trackNotFound:
            "The selected subtitle track is no longer present."
        case .unstableTrackIdentity:
            "The selected subtitle has no unique stable Matroska track UID."
        case .unsupportedTrackFormat:
            "This embedded subtitle is not editable text. SRT, ASS, and SSA are supported."
        case .staleSource:
            "The MKV or selected subtitle changed after the cleanup preview was created."
        case .unsafeExtractedSubtitle:
            "The extracted subtitle was not a safe regular file."
        case .oversizedExtractedSubtitle:
            "The extracted subtitle is larger than MKV Magic allows."
        case .invalidExtractedTiming:
            "The selected subtitle's original Matroska timing could not be preserved safely."
        case .invalidTrackMetadata:
            "The selected subtitle has invalid track metadata."
        case .noCuesRemaining:
            "Restore at least one cue before replacing this subtitle."
        case .noEventsRemaining:
            "Restore at least one dialogue event before replacing this subtitle."
        case .subtitleTimingVerificationFailed:
            "The replacement subtitle did not preserve its original Matroska packet timing."
        case .subtitleVerificationFailed:
            "The replacement subtitle did not pass its timing, text, and style audit."
        case .toolFailed(let tool, let exitCode, let message):
            "\(tool) could not clean the embedded subtitle (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct EmbeddedSubRipCleanupPreview: Equatable, Sendable {
    public let source: MediaAsset
    public let track: MediaTrack
    public let sourceRevision: EmbeddedSubtitleSourceRevision
    public let extractedSHA256: Data
    public let packetTimelineSHA256: Data
    public let encoding: SubtitleTextEncoding
    public let diagnostics: Set<SubRipDiagnostic>
    public let cleanup: SubtitleCleanupPreview
    public let appliesEnglishOCRRules: Bool

    public init(
        source: MediaAsset,
        track: MediaTrack,
        sourceRevision: EmbeddedSubtitleSourceRevision,
        extractedSHA256: Data,
        packetTimelineSHA256: Data,
        encoding: SubtitleTextEncoding,
        diagnostics: Set<SubRipDiagnostic>,
        cleanup: SubtitleCleanupPreview,
        appliesEnglishOCRRules: Bool
    ) {
        self.source = source
        self.track = track
        self.sourceRevision = sourceRevision
        self.extractedSHA256 = extractedSHA256
        self.packetTimelineSHA256 = packetTimelineSHA256
        self.encoding = encoding
        self.diagnostics = diagnostics
        self.cleanup = cleanup
        self.appliesEnglishOCRRules = appliesEnglishOCRRules
    }
}

public struct EmbeddedAdvancedSubtitleCleanupPreview: Equatable, Sendable {
    public let source: MediaAsset
    public let track: MediaTrack
    public let sourceRevision: EmbeddedSubtitleSourceRevision
    public let extractedSHA256: Data
    public let packetTimelineSHA256: Data
    public let encoding: SubtitleTextEncoding
    public let diagnostics: Set<AdvancedSubStationAlphaDiagnostic>
    public let cleanup: AdvancedSubStationAlphaCleanupPreview
    public let format: ExternalTextSubtitleFormat
    public let appliesEnglishOCRRules: Bool

    public init(
        source: MediaAsset,
        track: MediaTrack,
        sourceRevision: EmbeddedSubtitleSourceRevision,
        extractedSHA256: Data,
        packetTimelineSHA256: Data,
        encoding: SubtitleTextEncoding,
        diagnostics: Set<AdvancedSubStationAlphaDiagnostic>,
        cleanup: AdvancedSubStationAlphaCleanupPreview,
        format: ExternalTextSubtitleFormat,
        appliesEnglishOCRRules: Bool
    ) {
        self.source = source
        self.track = track
        self.sourceRevision = sourceRevision
        self.extractedSHA256 = extractedSHA256
        self.packetTimelineSHA256 = packetTimelineSHA256
        self.encoding = encoding
        self.diagnostics = diagnostics
        self.cleanup = cleanup
        self.format = format
        self.appliesEnglishOCRRules = appliesEnglishOCRRules
    }
}

public enum EmbeddedSubtitleCleanupPreview: Equatable, Sendable {
    case subRip(EmbeddedSubRipCleanupPreview)
    case advanced(EmbeddedAdvancedSubtitleCleanupPreview)

    public var source: MediaAsset {
        switch self {
        case .subRip(let preview): preview.source
        case .advanced(let preview): preview.source
        }
    }

    public var track: MediaTrack {
        switch self {
        case .subRip(let preview): preview.track
        case .advanced(let preview): preview.track
        }
    }

    public var format: ExternalTextSubtitleFormat {
        switch self {
        case .subRip: .subRip
        case .advanced(let preview): preview.format
        }
    }

    public var cleanupChangeCount: Int {
        switch self {
        case .subRip(let preview): preview.cleanup.changes.count
        case .advanced(let preview): preview.cleanup.changes.count
        }
    }

    public var itemCount: Int {
        switch self {
        case .subRip(let preview): preview.cleanup.original.cues.count
        case .advanced(let preview): preview.cleanup.original.events.count
        }
    }
}

public struct EmbeddedSubtitleSourceRevision: Equatable, Sendable {
    public let fileSize: Int64
    public let modificationDate: Date
    public let fileNumber: UInt64?
    public let systemNumber: UInt64?

    public init(
        fileSize: Int64,
        modificationDate: Date,
        fileNumber: UInt64? = nil,
        systemNumber: UInt64? = nil
    ) {
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.fileNumber = fileNumber
        self.systemNumber = systemNumber
    }

    fileprivate static func read(_ rawURL: URL) throws -> Self {
        let url = rawURL.standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/"),
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true, values.isSymbolicLink != true
        else {
            throw EmbeddedSubtitleCleanupError.unsupportedSource
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            throw EmbeddedSubtitleCleanupError.unsupportedSource
        }
        return Self(
            fileSize: size,
            modificationDate: modificationDate,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            systemNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value
        )
    }
}

public struct MKVEmbeddedSubtitleReplacer<Runner: CommandRunning>: Sendable {
    private let mkvmergeURL: URL
    private let mkvpropeditURL: URL
    private let runner: Runner

    public init(mkvmergeURL: URL, mkvpropeditURL: URL, runner: Runner) {
        self.mkvmergeURL = mkvmergeURL
        self.mkvpropeditURL = mkvpropeditURL
        self.runner = runner
    }

    public func replace(
        source: MediaAsset,
        trackUID: UInt64,
        cleanedSubtitleURL: URL,
        timestampsV2URL: URL?,
        outputURL: URL
    ) async throws {
        let muxArguments = try Self.muxArguments(
            source: source,
            trackUID: trackUID,
            cleanedSubtitleURL: cleanedSubtitleURL,
            timestampsV2URL: timestampsV2URL,
            outputURL: outputURL
        )
        try await run(tool: "mkvmerge", executableURL: mkvmergeURL, arguments: muxArguments)
        let propertyArguments = try Self.trackUIDArguments(
            source: source,
            trackUID: trackUID,
            outputURL: outputURL
        )
        try await run(
            tool: "mkvpropedit", executableURL: mkvpropeditURL, arguments: propertyArguments)
    }

    public static func muxArguments(
        source: MediaAsset,
        trackUID: UInt64,
        cleanedSubtitleURL: URL,
        timestampsV2URL: URL?,
        outputURL: URL
    ) throws -> [String] {
        let target = try selectedTrack(in: source, trackUID: trackUID)
        guard EmbeddedTextSubtitlePolicy.format(for: target) != nil else {
            throw EmbeddedSubtitleCleanupError.unsupportedTrackFormat
        }
        let language = try TrackLanguageTag.canonical(target.language ?? "und")
        if let title = target.title,
            title.contains("\0") || title.utf8.count > 4_096
        {
            throw EmbeddedSubtitleCleanupError.invalidTrackMetadata
        }
        let playableTracks = source.tracks.filter { $0.kind != .attachment }
        let retainedSubtitleIDs = playableTracks.filter {
            $0.kind == .subtitle && $0.uid != target.uid
        }.map(\.id)
        var arguments = [
            "--output", outputURL.path,
            "--abort-on-warnings",
            "--normalize-language-ietf", "canonical",
            "--disable-track-statistics-tags",
        ]
        if retainedSubtitleIDs.isEmpty {
            arguments.append("--no-subtitles")
        } else {
            arguments.append(contentsOf: [
                "--subtitle-tracks", retainedSubtitleIDs.map(String.init).joined(separator: ","),
            ])
        }
        arguments.append(source.sourceURL.path)
        arguments.append(contentsOf: [
            "--language", "0:\(language)",
            "--default-track-flag", "0:\(target.isDefault ? "yes" : "no")",
            "--forced-display-flag", "0:\(target.isForced ? "yes" : "no")",
            "--track-enabled-flag", "0:\(target.isEnabled ? "yes" : "no")",
            "--commentary-flag", "0:\(target.isCommentary ? "yes" : "no")",
            "--hearing-impaired-flag", "0:\(target.isHearingImpaired ? "yes" : "no")",
            "--visual-impaired-flag", "0:\(target.isVisualImpaired ? "yes" : "no")",
            "--original-flag", "0:\(target.isOriginal ? "yes" : "no")",
            "--text-descriptions-flag", "0:\(target.isTextDescription ? "yes" : "no")",
        ])
        if let title = target.title {
            arguments.append(contentsOf: ["--track-name", "0:\(title)"])
        }
        if let timestampsV2URL {
            arguments.append(contentsOf: ["--timestamps", "0:\(timestampsV2URL.path)"])
        }
        arguments.append(cleanedSubtitleURL.path)
        let trackOrder = playableTracks.map { track in
            track.uid == target.uid ? "1:0" : "0:\(track.id)"
        }.joined(separator: ",")
        arguments.append(contentsOf: ["--track-order", trackOrder])
        return arguments
    }

    public static func trackUIDArguments(
        source: MediaAsset,
        trackUID: UInt64,
        outputURL: URL
    ) throws -> [String] {
        let target = try selectedTrack(in: source, trackUID: trackUID)
        let subtitleOrdinal =
            source.tracks.prefix { $0.uid != target.uid }
            .filter { $0.kind == .subtitle }.count + 1
        return [
            outputURL.path,
            "--edit", "track:s\(subtitleOrdinal)",
            "--set", "track-uid=\(trackUID)",
        ]
    }

    private static func selectedTrack(in source: MediaAsset, trackUID: UInt64) throws -> MediaTrack
    {
        let matches = source.tracks.filter { $0.uid == trackUID }
        guard matches.count == 1 else {
            throw EmbeddedSubtitleCleanupError.unstableTrackIdentity
        }
        guard let target = matches.first, target.kind == .subtitle else {
            throw EmbeddedSubtitleCleanupError.trackNotFound
        }
        return target
    }

    private func run(tool: String, executableURL: URL, arguments: [String]) async throws {
        let result = try await runner.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: arguments,
                timeout: 24 * 60 * 60,
                outputLimit: 1_048_576
            ))
        guard result.exitCode == 0 else {
            let output =
                result.standardError.text.isEmpty
                ? result.standardOutput.text : result.standardError.text
            throw EmbeddedSubtitleCleanupError.toolFailed(
                tool: tool,
                exitCode: result.exitCode,
                message: String(output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
            )
        }
    }
}

public struct EmbeddedSubtitleCleanupExecutor<Runner: CommandRunning, Inspector: MediaInspecting>:
    Sendable
{
    private let ffprobeURL: URL
    private let runner: Runner
    private let inspector: Inspector
    private let replacer: MKVEmbeddedSubtitleReplacer<Runner>
    private let subtitleExtractor: MatroskaTextSubtitleExtractor<Runner>
    private let verifier = EmbeddedSubtitleReplacementOutputVerifier()

    public init(
        mkvmergeURL: URL,
        mkvpropeditURL: URL,
        mkvextractURL: URL,
        ffprobeURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        self.ffprobeURL = ffprobeURL
        self.runner = runner
        self.inspector = inspector
        replacer = MKVEmbeddedSubtitleReplacer(
            mkvmergeURL: mkvmergeURL,
            mkvpropeditURL: mkvpropeditURL,
            runner: runner
        )
        subtitleExtractor = MatroskaTextSubtitleExtractor(
            mkvextractURL: mkvextractURL,
            runner: runner
        )
    }

    public func preview(
        source: MediaAsset,
        trackUID: UInt64
    ) async throws -> EmbeddedSubtitleCleanupPreview {
        guard MatroskaEditingPolicy.supports(source) else {
            throw EmbeddedSubtitleCleanupError.unsupportedSource
        }
        let current = try await inspector.inspect(source.sourceURL)
        guard MatroskaSubtitleAssetSnapshot(current) == MatroskaSubtitleAssetSnapshot(source) else {
            throw EmbeddedSubtitleCleanupError.staleSource
        }
        let track = try Self.selectedTrack(in: current, trackUID: trackUID)
        guard let format = EmbeddedTextSubtitlePolicy.format(for: track) else {
            throw EmbeddedSubtitleCleanupError.unsupportedTrackFormat
        }
        let revisionBefore = try EmbeddedSubtitleSourceRevision.read(current.sourceURL)
        let extractedData = try await extract(
            sourceURL: current.sourceURL,
            trackID: track.id,
            format: format
        )
        let packetTimeline = try await probePacketTimeline(
            sourceURL: current.sourceURL,
            subtitleOrdinal: try Self.subtitleOrdinal(in: current, trackUID: trackUID)
        )
        let revisionAfter = try EmbeddedSubtitleSourceRevision.read(current.sourceURL)
        guard revisionBefore == revisionAfter else {
            throw EmbeddedSubtitleCleanupError.staleSource
        }
        return try Self.makePreview(
            source: current,
            track: track,
            sourceRevision: revisionAfter,
            data: extractedData,
            packetTimeline: packetTimeline,
            format: format
        )
    }

    public func execute(
        preview: EmbeddedSubtitleCleanupPreview,
        restoringIDs: Set<Int>,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw EmbeddedSubtitleCleanupError.unsupportedDestination
        }
        let current = try await inspector.inspect(preview.source.sourceURL)
        guard
            MatroskaSubtitleAssetSnapshot(current) == MatroskaSubtitleAssetSnapshot(preview.source),
            try EmbeddedSubtitleSourceRevision.read(current.sourceURL)
                == Self.sourceRevision(in: preview)
        else {
            throw EmbeddedSubtitleCleanupError.staleSource
        }
        let currentTrack = try Self.selectedTrack(
            in: current,
            trackUID: try Self.trackUID(in: preview)
        )
        guard currentTrack == preview.track,
            EmbeddedTextSubtitlePolicy.format(for: currentTrack) == preview.format
        else {
            throw EmbeddedSubtitleCleanupError.staleSource
        }
        let extractedData = try await extract(
            sourceURL: current.sourceURL,
            trackID: currentTrack.id,
            format: preview.format
        )
        let packetTimeline = try await probePacketTimeline(
            sourceURL: current.sourceURL,
            subtitleOrdinal: try Self.subtitleOrdinal(
                in: current,
                trackUID: try Self.trackUID(in: preview)
            )
        )
        guard
            packetTimeline.digest == Self.packetTimelineSHA256(in: preview),
            packetTimeline.packets.count == preview.itemCount
        else {
            throw EmbeddedSubtitleCleanupError.staleSource
        }
        let desired = try Self.serializedDesired(
            preview: preview,
            currentData: extractedData,
            restoringIDs: restoringIDs
        )
        let exactTimingPlan = ExactSubtitleTimingPlan(
            source: packetTimeline,
            retainedItemIDs: desired.retainedItemIDs
        )
        guard
            try EmbeddedSubtitleSourceRevision.read(current.sourceURL)
                == Self.sourceRevision(in: preview)
        else {
            throw EmbeddedSubtitleCleanupError.staleSource
        }
        let output = try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: current,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                let cleanedURL = outputURL.deletingLastPathComponent()
                    .appendingPathComponent("embedded-subtitle.\(preview.format.filenameExtension)")
                try desired.data.write(to: cleanedURL, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: cleanedURL) }
                let timestampsV2URL = try exactTimingPlan.map { plan in
                    let url = outputURL.deletingLastPathComponent()
                        .appendingPathComponent("embedded-subtitle-timestamps.txt")
                    try plan.timestampsV2Data.write(to: url, options: .withoutOverwriting)
                    return url
                }
                defer {
                    if let timestampsV2URL {
                        try? FileManager.default.removeItem(at: timestampsV2URL)
                    }
                }
                try await replacer.replace(
                    source: current,
                    trackUID: try Self.trackUID(in: preview),
                    cleanedSubtitleURL: cleanedURL,
                    timestampsV2URL: timestampsV2URL,
                    outputURL: outputURL
                )
                try await verifyPayload(
                    outputURL: outputURL,
                    preview: preview,
                    data: desired.data,
                    exactTimingPlan: exactTimingPlan
                )
            },
            verify: { output in
                try verifier.verify(
                    original: current,
                    output: output,
                    replacedTrackUID: try Self.trackUID(in: preview),
                    expectedFormat: preview.format
                )
            },
            committedAuditError: { outputURL, reason in
                EmbeddedSubtitleCleanupError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
        do {
            try await verifyPayload(
                outputURL: output.sourceURL,
                preview: preview,
                data: desired.data,
                exactTimingPlan: exactTimingPlan
            )
        } catch {
            throw EmbeddedSubtitleCleanupError.committedOutputAuditFailed(
                outputURL: output.sourceURL,
                reason: error.localizedDescription
            )
        }
        return output
    }

    private static func makePreview(
        source: MediaAsset,
        track: MediaTrack,
        sourceRevision: EmbeddedSubtitleSourceRevision,
        data: Data,
        packetTimeline: EmbeddedSubtitlePacketTimeline,
        format: ExternalTextSubtitleFormat
    ) throws -> EmbeddedSubtitleCleanupPreview {
        let decoded = try SubtitleTextDecoder().decode(data)
        let digest = Data(SHA256.hash(data: data))
        let appliesEnglishOCRRules = EmbeddedTextSubtitlePolicy.appliesEnglishOCRRules(to: track)
        switch format {
        case .subRip:
            let parsed = try SubRipCodec().parse(decoded)
            guard packetTimeline.packets.count == parsed.document.cues.count else {
                throw EmbeddedSubtitleCleanupError.invalidExtractedTiming
            }
            return .subRip(
                EmbeddedSubRipCleanupPreview(
                    source: source,
                    track: track,
                    sourceRevision: sourceRevision,
                    extractedSHA256: digest,
                    packetTimelineSHA256: packetTimeline.digest,
                    encoding: decoded.encoding,
                    diagnostics: parsed.diagnostics,
                    cleanup: SubtitleCleanupPolicy(
                        appliesEnglishOCRRules: appliesEnglishOCRRules
                    ).preview(parsed.document),
                    appliesEnglishOCRRules: appliesEnglishOCRRules
                ))
        case .ass, .ssa:
            let parsed = try AdvancedSubStationAlphaCodec().parse(decoded)
            guard packetTimeline.packets.count == parsed.document.events.count else {
                throw EmbeddedSubtitleCleanupError.invalidExtractedTiming
            }
            return .advanced(
                EmbeddedAdvancedSubtitleCleanupPreview(
                    source: source,
                    track: track,
                    sourceRevision: sourceRevision,
                    extractedSHA256: digest,
                    packetTimelineSHA256: packetTimeline.digest,
                    encoding: decoded.encoding,
                    diagnostics: parsed.diagnostics,
                    cleanup: AdvancedSubStationAlphaCleanupPolicy(
                        appliesEnglishOCRRules: appliesEnglishOCRRules
                    ).preview(parsed.document),
                    format: format,
                    appliesEnglishOCRRules: appliesEnglishOCRRules
                ))
        }
    }

    private static func serializedDesired(
        preview: EmbeddedSubtitleCleanupPreview,
        currentData: Data,
        restoringIDs: Set<Int>
    ) throws -> EmbeddedSubtitleDesiredPayload {
        let currentDigest = Data(SHA256.hash(data: currentData))
        switch preview {
        case .subRip(let preview):
            let current = try SubRipCodec().parse(SubtitleTextDecoder().decode(currentData))
                .document
            guard currentDigest == preview.extractedSHA256,
                current == preview.cleanup.original,
                SubtitleCleanupPolicy(
                    appliesEnglishOCRRules: preview.appliesEnglishOCRRules
                ).preview(current) == preview.cleanup
            else {
                throw EmbeddedSubtitleCleanupError.staleSource
            }
            let desired = preview.cleanup.document(restoringCueIDs: restoringIDs)
            guard !desired.cues.isEmpty else {
                throw EmbeddedSubtitleCleanupError.noCuesRemaining
            }
            return EmbeddedSubtitleDesiredPayload(
                data: Data(SubRipCodec().serialize(desired).utf8),
                retainedItemIDs: desired.cues.map(\.id)
            )
        case .advanced(let preview):
            let current = try AdvancedSubStationAlphaCodec().parse(
                SubtitleTextDecoder().decode(currentData)
            ).document
            guard currentDigest == preview.extractedSHA256,
                current == preview.cleanup.original,
                AdvancedSubStationAlphaCleanupPolicy(
                    appliesEnglishOCRRules: preview.appliesEnglishOCRRules
                ).preview(current) == preview.cleanup
            else {
                throw EmbeddedSubtitleCleanupError.staleSource
            }
            let desired = preview.cleanup.document(restoringEventIDs: restoringIDs)
            guard !desired.events.isEmpty else {
                throw EmbeddedSubtitleCleanupError.noEventsRemaining
            }
            return EmbeddedSubtitleDesiredPayload(
                data: Data(AdvancedSubStationAlphaCodec().serialize(desired).utf8),
                retainedItemIDs: desired.events.map(\.id)
            )
        }
    }

    private func verifyPayload(
        outputURL: URL,
        preview: EmbeddedSubtitleCleanupPreview,
        data: Data,
        exactTimingPlan: ExactSubtitleTimingPlan?
    ) async throws {
        let output = try await inspector.inspect(outputURL)
        let trackUID = try Self.trackUID(in: preview)
        guard let track = output.tracks.first(where: { $0.uid == trackUID }),
            EmbeddedTextSubtitlePolicy.format(for: track) == preview.format
        else {
            throw EmbeddedSubtitleCleanupError.subtitleVerificationFailed
        }
        let extracted = try await extract(
            sourceURL: outputURL,
            trackID: track.id,
            format: preview.format
        )
        if let exactTimingPlan {
            let outputTimeline = try await probePacketTimeline(
                sourceURL: outputURL,
                subtitleOrdinal: try Self.subtitleOrdinal(in: output, trackUID: trackUID)
            )
            guard outputTimeline.packets == exactTimingPlan.expectedPackets else {
                throw EmbeddedSubtitleCleanupError.subtitleTimingVerificationFailed
            }
        }
        switch preview {
        case .subRip:
            let desired = try SubRipCodec().parse(SubtitleTextDecoder().decode(data)).document
            let reopened = try SubRipCodec().parse(
                SubtitleTextDecoder().decode(extracted)
            ).document
            guard EmbeddedSubRipPayloadVerifier().verify(desired: desired, extracted: reopened)
            else {
                throw EmbeddedSubtitleCleanupError.subtitleVerificationFailed
            }
        case .advanced:
            let desired = try AdvancedSubStationAlphaCodec().parse(
                SubtitleTextDecoder().decode(data)
            ).document
            let reopened = try AdvancedSubStationAlphaCodec().parse(
                SubtitleTextDecoder().decode(extracted)
            ).document
            guard
                AdvancedSubtitleMuxPayloadVerifier().verify(
                    original: desired,
                    extracted: reopened
                )
            else {
                throw EmbeddedSubtitleCleanupError.subtitleVerificationFailed
            }
        }
    }

    private func extract(
        sourceURL: URL,
        trackID: Int,
        format: ExternalTextSubtitleFormat
    ) async throws -> Data {
        do {
            return try await subtitleExtractor.extract(
                sourceURL: sourceURL,
                trackID: trackID,
                format: format
            )
        } catch let error as MatroskaTextSubtitleExtractorError {
            switch error {
            case .oversizedExtractedSubtitle:
                throw EmbeddedSubtitleCleanupError.oversizedExtractedSubtitle
            case .unsafeRequest, .unsafeExtractedSubtitle:
                throw EmbeddedSubtitleCleanupError.unsafeExtractedSubtitle
            case .toolFailed(let exitCode, let message):
                throw EmbeddedSubtitleCleanupError.toolFailed(
                    tool: "mkvextract",
                    exitCode: exitCode,
                    message: message
                )
            }
        }
    }

    private func probePacketTimeline(
        sourceURL: URL,
        subtitleOrdinal: Int
    ) async throws -> EmbeddedSubtitlePacketTimeline {
        let result = try await runner.run(
            CommandRequest(
                executableURL: ffprobeURL,
                arguments: [
                    "-v", "error",
                    "-select_streams", "s:\(subtitleOrdinal)",
                    "-show_packets",
                    "-show_streams",
                    "-show_entries", "stream=time_base:packet=pts,duration",
                    "-of", "json",
                    sourceURL.path,
                ],
                timeout: 120,
                outputLimit: SubtitleCleanupExecutor.maximumInputBytes
            ))
        guard result.exitCode == 0 else {
            let output =
                result.standardError.text.isEmpty
                ? result.standardOutput.text : result.standardError.text
            throw EmbeddedSubtitleCleanupError.toolFailed(
                tool: "ffprobe",
                exitCode: result.exitCode,
                message: String(output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
            )
        }
        guard !result.standardOutput.wasTruncated,
            let timeline = try? EmbeddedSubtitlePacketTimeline(
                ffprobeData: result.standardOutput.data)
        else {
            throw EmbeddedSubtitleCleanupError.invalidExtractedTiming
        }
        return timeline
    }

    private static func selectedTrack(in source: MediaAsset, trackUID: UInt64) throws -> MediaTrack
    {
        let matches = source.tracks.filter { $0.uid == trackUID }
        guard matches.count == 1 else {
            throw EmbeddedSubtitleCleanupError.unstableTrackIdentity
        }
        guard let track = matches.first, track.kind == .subtitle else {
            throw EmbeddedSubtitleCleanupError.trackNotFound
        }
        return track
    }

    private static func trackUID(in preview: EmbeddedSubtitleCleanupPreview) throws -> UInt64 {
        guard let trackUID = preview.track.uid else {
            throw EmbeddedSubtitleCleanupError.unstableTrackIdentity
        }
        return trackUID
    }

    private static func subtitleOrdinal(in source: MediaAsset, trackUID: UInt64) throws -> Int {
        let target = try selectedTrack(in: source, trackUID: trackUID)
        return source.tracks.prefix { $0.uid != target.uid }
            .filter { $0.kind == .subtitle }.count
    }

    private static func sourceRevision(
        in preview: EmbeddedSubtitleCleanupPreview
    ) -> EmbeddedSubtitleSourceRevision {
        switch preview {
        case .subRip(let preview): preview.sourceRevision
        case .advanced(let preview): preview.sourceRevision
        }
    }

    private static func packetTimelineSHA256(
        in preview: EmbeddedSubtitleCleanupPreview
    ) -> Data {
        switch preview {
        case .subRip(let preview): preview.packetTimelineSHA256
        case .advanced(let preview): preview.packetTimelineSHA256
        }
    }
}

private struct EmbeddedSubRipPayloadVerifier {
    func verify(desired: SubRipDocument, extracted: SubRipDocument) -> Bool {
        guard desired.cues.count == extracted.cues.count else { return false }
        return zip(desired.cues, extracted.cues).allSatisfy { desired, extracted in
            timestampsMatch(desired.start, extracted.start)
                && timestampsMatch(desired.end, extracted.end)
                && desired.lines == extracted.lines
        }
    }

    private func timestampsMatch(_ lhs: SubRipTimestamp, _ rhs: SubRipTimestamp) -> Bool {
        let difference = lhs.milliseconds.subtractingReportingOverflow(rhs.milliseconds)
        guard !difference.overflow, difference.partialValue != Int64.min else { return false }
        return abs(difference.partialValue) <= 1
    }
}

private struct EmbeddedSubtitleDesiredPayload {
    let data: Data
    let retainedItemIDs: [Int]
}

private struct EmbeddedSubtitlePacket: Equatable, Sendable {
    let presentationNanoseconds: Int64
    let durationNanoseconds: Int64

    var endNanoseconds: Int64? {
        let result = presentationNanoseconds.addingReportingOverflow(durationNanoseconds)
        return result.overflow ? nil : result.partialValue
    }
}

private struct EmbeddedSubtitlePacketTimeline: Sendable {
    let packets: [EmbeddedSubtitlePacket]
    let digest: Data

    init(ffprobeData: Data) throws {
        let document = try JSONDecoder().decode(
            FFprobePacketTimelineDocument.self, from: ffprobeData)
        guard let streams = document.streams,
            streams.count == 1,
            let stream = streams.first,
            let timeBase = ExactTimeBase(stream.timeBase)
        else {
            throw EmbeddedSubtitleCleanupError.invalidExtractedTiming
        }
        packets = try (document.packets ?? []).map { packet in
            guard let presentation = packet.presentation,
                let duration = packet.duration,
                let presentationNanoseconds = timeBase.nanoseconds(for: presentation),
                let durationNanoseconds = timeBase.nanoseconds(for: duration),
                presentationNanoseconds >= 0,
                durationNanoseconds >= 0
            else {
                throw EmbeddedSubtitleCleanupError.invalidExtractedTiming
            }
            return EmbeddedSubtitlePacket(
                presentationNanoseconds: presentationNanoseconds,
                durationNanoseconds: durationNanoseconds
            )
        }
        let canonical = packets.map {
            "\($0.presentationNanoseconds):\($0.durationNanoseconds)"
        }.joined(separator: "\n")
        digest = Data(SHA256.hash(data: Data(canonical.utf8)))
    }
}

private struct FFprobePacketTimelineDocument: Decodable {
    let packets: [Packet]?
    let streams: [Stream]?

    struct Packet: Decodable {
        let presentation: Int64?
        let duration: Int64?

        enum CodingKeys: String, CodingKey {
            case presentation = "pts"
            case duration
        }
    }

    struct Stream: Decodable {
        let timeBase: String

        enum CodingKeys: String, CodingKey {
            case timeBase = "time_base"
        }
    }
}

private struct ExactTimeBase {
    let numerator: Int64
    let denominator: Int64

    init?(_ rawValue: String) {
        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
            let numerator = Int64(components[0]),
            let denominator = Int64(components[1]),
            numerator > 0,
            denominator > 0
        else {
            return nil
        }
        self.numerator = numerator
        self.denominator = denominator
    }

    func nanoseconds(for ticks: Int64) -> Int64? {
        guard ticks >= 0 else { return nil }
        var reducedTicks = ticks
        var reducedNumerator = numerator
        var reducedScale: Int64 = 1_000_000_000
        var reducedDenominator = denominator

        let numeratorDivisor = greatestCommonDivisor(reducedNumerator, reducedDenominator)
        reducedNumerator /= numeratorDivisor
        reducedDenominator /= numeratorDivisor
        let scaleDivisor = greatestCommonDivisor(reducedScale, reducedDenominator)
        reducedScale /= scaleDivisor
        reducedDenominator /= scaleDivisor
        let tickDivisor = greatestCommonDivisor(reducedTicks, reducedDenominator)
        reducedTicks /= tickDivisor
        reducedDenominator /= tickDivisor
        guard reducedDenominator == 1 else { return nil }

        let first = reducedTicks.multipliedReportingOverflow(by: reducedNumerator)
        guard !first.overflow else { return nil }
        let second = first.partialValue.multipliedReportingOverflow(by: reducedScale)
        return second.overflow ? nil : second.partialValue
    }

    private func greatestCommonDivisor(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var a = lhs
        var b = rhs
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(a, 1)
    }
}

private struct ExactSubtitleTimingPlan {
    let expectedPackets: [EmbeddedSubtitlePacket]
    let timestampsV2Data: Data

    init?(source: EmbeddedSubtitlePacketTimeline, retainedItemIDs: [Int]) {
        guard !retainedItemIDs.isEmpty,
            retainedItemIDs == retainedItemIDs.sorted(),
            Set(retainedItemIDs).count == retainedItemIDs.count,
            retainedItemIDs.allSatisfy({ source.packets.indices.contains($0) })
        else {
            return nil
        }
        let retained = retainedItemIDs.map { source.packets[$0] }
        guard
            zip(retained, retained.dropFirst()).allSatisfy({ current, next in
                current.endNanoseconds == next.presentationNanoseconds
            }), let finalEnd = retained.last?.endNanoseconds
        else {
            return nil
        }
        expectedPackets = retained
        let timestamps = retained.map(\.presentationNanoseconds) + [finalEnd]
        let text =
            (["# timestamp format v2"] + timestamps.map(Self.milliseconds)).joined(
                separator: "\n") + "\n"
        timestampsV2Data = Data(text.utf8)
    }

    private static func milliseconds(_ nanoseconds: Int64) -> String {
        let whole = nanoseconds / 1_000_000
        let fraction = nanoseconds % 1_000_000
        guard fraction != 0 else { return String(whole) }
        var digits = String(fraction)
        digits = String(repeating: "0", count: 6 - digits.count) + digits
        while digits.last == "0" { digits.removeLast() }
        return "\(whole).\(digits)"
    }
}
