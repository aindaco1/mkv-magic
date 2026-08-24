import Foundation
import MKVMagicCore
import MKVMagicSystem

public enum TimedTextSubtitleConversionError: Error, Equatable, Sendable {
    case unsupportedSource
    case trackNotFound
    case unsafeSource
    case staleSource
    case unsupportedDestination
    case unsafeConvertedSubtitle
    case oversizedConvertedSubtitle
    case invalidConvertedSubtitle
    case conversionChanged
    case toolFailed(exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension TimedTextSubtitleConversionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Timed-text conversion requires an inspected MP4, M4V, or MOV file with a TX3G subtitle."
        case .trackNotFound:
            "The selected TX3G subtitle track is no longer available in this inspection."
        case .unsafeSource:
            "Timed-text conversion needs a safe regular source file."
        case .staleSource:
            "The video changed after its TX3G subtitle conversion was reviewed."
        case .unsupportedDestination:
            "Timed-text conversion creates one editable .ass subtitle file."
        case .unsafeConvertedSubtitle:
            "FFmpeg did not create a safe regular ASS subtitle."
        case .oversizedConvertedSubtitle:
            "The converted ASS subtitle is larger than MKV Magic allows."
        case .invalidConvertedSubtitle:
            "The converted ASS subtitle did not pass its text, style, and timing audit."
        case .conversionChanged:
            "The TX3G-to-ASS result changed after review. Review the source again."
        case .toolFailed(let exitCode, let message):
            "FFmpeg could not convert the TX3G subtitle (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified subtitle was saved as \(outputURL.lastPathComponent), but its final reopen audit failed: \(reason)"
        }
    }
}

public struct TimedTextSubtitleConversionPreview: Equatable, Sendable {
    public let source: MediaAsset
    public let track: MediaTrack
    public let sourceRevision: MediaSourceRevision
    public let document: AdvancedSubStationAlphaDocument

    public init(
        source: MediaAsset,
        track: MediaTrack,
        sourceRevision: MediaSourceRevision,
        document: AdvancedSubStationAlphaDocument
    ) {
        self.source = source
        self.track = track
        self.sourceRevision = sourceRevision
        self.document = document
    }

    public var eventCount: Int { document.events.count }
}

public struct TimedTextSubtitleConversionResult: Equatable, Sendable {
    public let outputURL: URL
    public let document: AdvancedSubStationAlphaDocument

    public init(outputURL: URL, document: AdvancedSubStationAlphaDocument) {
        self.outputURL = outputURL
        self.document = document
    }
}

public struct TimedTextSubtitleConversionExecutor<Runner: CommandRunning>: Sendable {
    private let ffmpegURL: URL
    private let runner: Runner

    public init(ffmpegURL: URL, runner: Runner) {
        self.ffmpegURL = ffmpegURL
        self.runner = runner
    }

    public func preview(
        source: MediaAsset,
        trackID: Int
    ) async throws -> TimedTextSubtitleConversionPreview {
        let track = try selectedTrack(in: source, trackID: trackID)
        let revision: MediaSourceRevision
        do {
            revision = try MediaSourceRevision.read(source.sourceURL)
        } catch {
            throw TimedTextSubtitleConversionError.unsafeSource
        }
        let document = try await extract(sourceURL: source.sourceURL, trackID: trackID)
        guard (try? MediaSourceRevision.read(source.sourceURL)) == revision else {
            throw TimedTextSubtitleConversionError.staleSource
        }
        return TimedTextSubtitleConversionPreview(
            source: source,
            track: track,
            sourceRevision: revision,
            document: document
        )
    }

    public func execute(
        preview: TimedTextSubtitleConversionPreview,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> TimedTextSubtitleConversionResult {
        guard destinationURL.pathExtension.lowercased() == "ass" else {
            throw TimedTextSubtitleConversionError.unsupportedDestination
        }
        _ = try selectedTrack(in: preview.source, trackID: preview.track.id)
        let validateSource = try mediaFileRevisionValidator(
            sourceURL: preview.source.sourceURL,
            expectedRevision: preview.sourceRevision,
            changedError: TimedTextSubtitleConversionError.staleSource
        )
        try Task.checkCancellation()
        try validateSource()
        let currentDocument = try await extract(
            sourceURL: preview.source.sourceURL,
            trackID: preview.track.id
        )
        try Task.checkCancellation()
        try validateSource()
        guard currentDocument == preview.document else {
            throw TimedTextSubtitleConversionError.conversionChanged
        }
        let outputData = Data(AdvancedSubStationAlphaCodec().serialize(currentDocument).utf8)
        let committedURL = try await VerifiedSubtitleTextOutputWriter.execute(
            sourceURL: preview.source.sourceURL,
            destinationURL: destinationURL,
            data: outputData,
            onStage: onStage,
            verify: { outputURL in
                try Self.verify(
                    outputURL: outputURL,
                    expectedData: outputData,
                    expectedDocument: currentDocument
                )
            },
            validateSource: validateSource,
            committedAuditError: { outputURL, reason in
                TimedTextSubtitleConversionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            }
        )
        return TimedTextSubtitleConversionResult(
            outputURL: committedURL,
            document: currentDocument
        )
    }

    public static func arguments(
        sourceURL: URL,
        trackID: Int,
        outputURL: URL
    ) throws -> [String] {
        guard trackID >= 0,
            safeAbsoluteFilePath(sourceURL),
            safeAbsoluteFilePath(outputURL),
            outputURL.pathExtension.lowercased() == "ass"
        else {
            throw TimedTextSubtitleConversionError.unsupportedSource
        }
        return [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-n",
            "-i", sourceURL.path,
            "-map", "0:\(trackID)",
            "-map_metadata", "-1", "-map_chapters", "-1",
            "-c:s", "ass", "-f", "ass",
            outputURL.path,
        ]
    }

    private func selectedTrack(in source: MediaAsset, trackID: Int) throws -> MediaTrack {
        guard TimedTextSubtitleConversionPolicy.canOffer(for: source) else {
            throw TimedTextSubtitleConversionError.unsupportedSource
        }
        guard
            let track = TimedTextSubtitleConversionPolicy.convertibleTracks(in: source)
                .first(where: { $0.id == trackID })
        else {
            throw TimedTextSubtitleConversionError.trackNotFound
        }
        return track
    }

    private func extract(
        sourceURL: URL,
        trackID: Int
    ) async throws -> AdvancedSubStationAlphaDocument {
        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-tx3g"
        ) { directory in
            let outputURL = directory.appendingPathComponent("converted.ass")
            let result = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: try Self.arguments(
                        sourceURL: sourceURL,
                        trackID: trackID,
                        outputURL: outputURL
                    ),
                    timeout: 120,
                    outputLimit: 1_048_576
                )
            )
            guard result.exitCode == 0,
                !result.standardOutput.wasTruncated,
                !result.standardError.wasTruncated
            else {
                let rawMessage =
                    result.standardError.text.isEmpty
                    ? result.standardOutput.text : result.standardError.text
                let message = String(
                    rawMessage.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240)
                )
                throw TimedTextSubtitleConversionError.toolFailed(
                    exitCode: result.exitCode,
                    message: message
                )
            }
            return try Self.readDocument(outputURL)
        }
    }

    private static func verify(
        outputURL: URL,
        expectedData: Data,
        expectedDocument: AdvancedSubStationAlphaDocument
    ) throws {
        let data: Data
        do {
            data = try SafeSubtitleTextFile.read(
                outputURL,
                allowedExtensions: ["ass"],
                maximumInputBytes: SubtitleCleanupExecutor.maximumInputBytes
            )
        } catch {
            throw TimedTextSubtitleConversionError.invalidConvertedSubtitle
        }
        guard data == expectedData,
            let decoded = try? SubtitleTextDecoder().decode(data),
            decoded.encoding == .utf8,
            let reopened = try? AdvancedSubStationAlphaCodec().parse(decoded).document,
            reopened == expectedDocument
        else {
            throw TimedTextSubtitleConversionError.invalidConvertedSubtitle
        }
    }

    private static func readDocument(_ outputURL: URL) throws -> AdvancedSubStationAlphaDocument {
        let data: Data
        do {
            data = try SafeSubtitleTextFile.read(
                outputURL,
                allowedExtensions: ["ass"],
                maximumInputBytes: SubtitleCleanupExecutor.maximumInputBytes
            )
        } catch let error as SafeSubtitleTextFileError {
            switch error {
            case .oversizedInput:
                throw TimedTextSubtitleConversionError.oversizedConvertedSubtitle
            case .unsupportedExtension, .unsafeInput:
                throw TimedTextSubtitleConversionError.unsafeConvertedSubtitle
            }
        }
        do {
            return try AdvancedSubStationAlphaCodec().parse(
                SubtitleTextDecoder().decode(data)
            ).document
        } catch {
            throw TimedTextSubtitleConversionError.invalidConvertedSubtitle
        }
    }

    private static func safeAbsoluteFilePath(_ url: URL) -> Bool {
        let path = url.path
        return url.isFileURL && path.hasPrefix("/") && !path.contains("\0")
            && (1...4_096).contains(path.utf8.count)
    }
}
