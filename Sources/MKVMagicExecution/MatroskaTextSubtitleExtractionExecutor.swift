import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum MatroskaTextSubtitleExtractionError: Error, Equatable, Sendable {
    case unsupportedSource
    case trackNotFound
    case staleSource
    case unsupportedDestination
    case unsafeExtractedSubtitle
    case oversizedExtractedSubtitle
    case invalidExtractedSubtitle
    case extractionChanged
    case toolFailed(exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension MatroskaTextSubtitleExtractionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Subtitle extraction requires an inspected Matroska file with an embedded SRT, ASS, or SSA track."
        case .trackNotFound:
            "The selected embedded text subtitle is no longer available in this inspection."
        case .staleSource:
            "The MKV changed after its subtitle extraction was reviewed."
        case .unsupportedDestination:
            "The extracted subtitle must keep its original SRT, ASS, or SSA format."
        case .unsafeExtractedSubtitle:
            "mkvextract did not create a safe regular subtitle."
        case .oversizedExtractedSubtitle:
            "The extracted subtitle is larger than MKV Magic allows."
        case .invalidExtractedSubtitle:
            "The extracted subtitle did not pass its text, style, and timing audit."
        case .extractionChanged:
            "The extracted subtitle changed after review. Inspect the source again."
        case .toolFailed(let exitCode, let message):
            "mkvextract could not extract the selected subtitle (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified subtitle was saved as \(outputURL.lastPathComponent), but its final reopen audit failed: \(reason)"
        }
    }
}

private enum ExtractedTextSubtitleDocument: Equatable, Sendable {
    case subRip(SubRipDocument)
    case advanced(AdvancedSubStationAlphaDocument)

    var itemCount: Int {
        switch self {
        case .subRip(let document): document.cues.count
        case .advanced(let document): document.events.count
        }
    }
}

public struct MatroskaTextSubtitleExtractionPreview: Equatable, Sendable {
    public let source: MediaAsset
    public let track: MediaTrack
    public let format: ExternalTextSubtitleFormat
    public let sourceRevision: MediaSourceRevision
    fileprivate let data: Data
    fileprivate let document: ExtractedTextSubtitleDocument

    fileprivate init(
        source: MediaAsset,
        track: MediaTrack,
        format: ExternalTextSubtitleFormat,
        sourceRevision: MediaSourceRevision,
        data: Data,
        document: ExtractedTextSubtitleDocument
    ) {
        self.source = source
        self.track = track
        self.format = format
        self.sourceRevision = sourceRevision
        self.data = data
        self.document = document
    }

    public var itemCount: Int { document.itemCount }
    public var byteCount: Int { data.count }
}

public struct MatroskaTextSubtitleExtractionResult: Equatable, Sendable {
    public let outputURL: URL
    public let itemCount: Int

    public init(outputURL: URL, itemCount: Int) {
        self.outputURL = outputURL
        self.itemCount = itemCount
    }
}

public struct MatroskaTextSubtitleExtractionExecutor<
    Runner: CommandRunning, Inspector: MediaInspecting
>: Sendable {
    private let extractor: MatroskaTextSubtitleExtractor<Runner>
    private let inspector: Inspector

    public init(mkvextractURL: URL, runner: Runner, inspector: Inspector) {
        extractor = MatroskaTextSubtitleExtractor(
            mkvextractURL: mkvextractURL,
            runner: runner
        )
        self.inspector = inspector
    }

    public func preview(
        source: MediaAsset,
        trackUID: UInt64
    ) async throws -> MatroskaTextSubtitleExtractionPreview {
        let current = try await inspector.inspect(source.sourceURL)
        guard MatroskaAssetSnapshot(current) == MatroskaAssetSnapshot(source) else {
            throw MatroskaTextSubtitleExtractionError.staleSource
        }
        let track = try selectedTrack(in: current, trackUID: trackUID)
        let format = try format(for: track)
        let revision: MediaSourceRevision
        do {
            revision = try MediaSourceRevision.read(current.sourceURL)
        } catch {
            throw MatroskaTextSubtitleExtractionError.staleSource
        }
        let data = try await extract(
            sourceURL: current.sourceURL, trackID: track.id, format: format)
        let document = try Self.parse(data, format: format)
        guard (try? MediaSourceRevision.read(current.sourceURL)) == revision else {
            throw MatroskaTextSubtitleExtractionError.staleSource
        }
        return MatroskaTextSubtitleExtractionPreview(
            source: current,
            track: track,
            format: format,
            sourceRevision: revision,
            data: data,
            document: document
        )
    }

    public func execute(
        preview: MatroskaTextSubtitleExtractionPreview,
        destinationURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MatroskaTextSubtitleExtractionResult {
        guard destinationURL.pathExtension.lowercased() == preview.format.filenameExtension else {
            throw MatroskaTextSubtitleExtractionError.unsupportedDestination
        }
        let current = try await inspector.inspect(preview.source.sourceURL)
        guard
            MatroskaAssetSnapshot(current) == MatroskaAssetSnapshot(preview.source)
        else {
            throw MatroskaTextSubtitleExtractionError.staleSource
        }
        let track = try selectedTrack(in: current, trackUID: try trackUID(in: preview))
        guard track == preview.track, try format(for: track) == preview.format else {
            throw MatroskaTextSubtitleExtractionError.staleSource
        }
        let validateSource = try mediaFileRevisionValidator(
            sourceURL: current.sourceURL,
            expectedRevision: preview.sourceRevision,
            changedError: MatroskaTextSubtitleExtractionError.staleSource
        )
        try Task.checkCancellation()
        try validateSource()
        let data = try await extract(
            sourceURL: current.sourceURL,
            trackID: preview.track.id,
            format: preview.format,
            onProgress: onProgress
        )
        let document = try Self.parse(data, format: preview.format)
        try Task.checkCancellation()
        try validateSource()
        guard data == preview.data, document == preview.document else {
            throw MatroskaTextSubtitleExtractionError.extractionChanged
        }
        let committedURL = try await VerifiedSubtitleTextOutputWriter.execute(
            sourceURL: current.sourceURL,
            destinationURL: destinationURL,
            data: data,
            onStage: onStage,
            verify: { outputURL in
                try Self.verify(
                    outputURL: outputURL,
                    format: preview.format,
                    expectedData: data,
                    expectedDocument: document
                )
            },
            validateSource: validateSource,
            committedAuditError: { outputURL, reason in
                MatroskaTextSubtitleExtractionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            }
        )
        return MatroskaTextSubtitleExtractionResult(
            outputURL: committedURL,
            itemCount: document.itemCount
        )
    }

    private func selectedTrack(in source: MediaAsset, trackUID: UInt64) throws -> MediaTrack {
        guard MatroskaEditingPolicy.supports(source) else {
            throw MatroskaTextSubtitleExtractionError.unsupportedSource
        }
        guard
            let track = EmbeddedTextSubtitlePolicy.extractableTracks(in: source)
                .first(where: { $0.uid == trackUID })
        else {
            throw MatroskaTextSubtitleExtractionError.trackNotFound
        }
        return track
    }

    private func format(for track: MediaTrack) throws -> ExternalTextSubtitleFormat {
        guard let format = EmbeddedTextSubtitlePolicy.format(for: track) else {
            throw MatroskaTextSubtitleExtractionError.trackNotFound
        }
        return format
    }

    private func trackUID(in preview: MatroskaTextSubtitleExtractionPreview) throws -> UInt64 {
        guard let trackUID = preview.track.uid else {
            throw MatroskaTextSubtitleExtractionError.trackNotFound
        }
        return trackUID
    }

    private func extract(
        sourceURL: URL,
        trackID: Int,
        format: ExternalTextSubtitleFormat,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in }
    ) async throws -> Data {
        do {
            return try await extractor.extract(
                sourceURL: sourceURL,
                trackID: trackID,
                format: format,
                onProgress: onProgress
            )
        } catch let error as MatroskaTextSubtitleExtractorError {
            switch error {
            case .unsafeRequest, .unsafeExtractedSubtitle:
                throw MatroskaTextSubtitleExtractionError.unsafeExtractedSubtitle
            case .oversizedExtractedSubtitle:
                throw MatroskaTextSubtitleExtractionError.oversizedExtractedSubtitle
            case .toolFailed(let exitCode, let message):
                throw MatroskaTextSubtitleExtractionError.toolFailed(
                    exitCode: exitCode,
                    message: message
                )
            }
        }
    }

    private static func parse(
        _ data: Data,
        format: ExternalTextSubtitleFormat
    ) throws -> ExtractedTextSubtitleDocument {
        do {
            let decoded = try SubtitleTextDecoder().decode(data)
            return switch format {
            case .subRip: .subRip(try SubRipCodec().parse(decoded).document)
            case .ass, .ssa:
                .advanced(try AdvancedSubStationAlphaCodec().parse(decoded).document)
            }
        } catch {
            throw MatroskaTextSubtitleExtractionError.invalidExtractedSubtitle
        }
    }

    private static func verify(
        outputURL: URL,
        format: ExternalTextSubtitleFormat,
        expectedData: Data,
        expectedDocument: ExtractedTextSubtitleDocument
    ) throws {
        let data: Data
        do {
            data = try SafeSubtitleTextFile.read(
                outputURL,
                allowedExtensions: [format.filenameExtension],
                maximumInputBytes: SubtitleCleanupExecutor.maximumInputBytes
            )
        } catch {
            throw MatroskaTextSubtitleExtractionError.invalidExtractedSubtitle
        }
        guard data == expectedData,
            (try? parse(data, format: format)) == expectedDocument
        else {
            throw MatroskaTextSubtitleExtractionError.invalidExtractedSubtitle
        }
    }
}
