import CryptoKit
import Foundation
import MKVMagicCore

public enum SubtitleCleanupExecutionError: Error, Equatable, Sendable {
    case unsupportedFormat
    case unsafeInput
    case oversizedInput
    case stalePreview
    case noCuesRemaining
    case verificationFailed
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension SubtitleCleanupExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Subtitle cleanup currently supports SRT files."
        case .unsafeInput: "The subtitle input is not a safe regular file."
        case .oversizedInput: "The subtitle file is larger than MKV Magic allows."
        case .stalePreview: "The subtitle changed after the cleanup preview was created."
        case .noCuesRemaining: "Restore at least one cue before saving this subtitle."
        case .verificationFailed: "The cleaned subtitle did not pass its timing and text audit."
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified subtitle was saved as \(outputURL.lastPathComponent), but its final "
                + "reopen audit failed: \(reason)"
        }
    }
}

public struct SubtitleCleanupResult: Equatable, Sendable {
    public let outputURL: URL
    public let document: SubRipDocument
    public let removedCueCount: Int
    public let changedCueCount: Int

    public init(
        outputURL: URL,
        document: SubRipDocument,
        removedCueCount: Int,
        changedCueCount: Int
    ) {
        self.outputURL = outputURL
        self.document = document
        self.removedCueCount = removedCueCount
        self.changedCueCount = changedCueCount
    }
}

public struct SubtitleCleanupFilePreview: Equatable, Sendable {
    public let sourceURL: URL
    public let sourceSHA256: Data
    public let encoding: SubtitleTextEncoding
    public let diagnostics: Set<SubRipDiagnostic>
    public let cleanup: SubtitleCleanupPreview
    public let normalizationNeeded: Bool

    public init(
        sourceURL: URL,
        sourceSHA256: Data,
        encoding: SubtitleTextEncoding,
        diagnostics: Set<SubRipDiagnostic>,
        cleanup: SubtitleCleanupPreview,
        normalizationNeeded: Bool
    ) {
        self.sourceURL = sourceURL
        self.sourceSHA256 = sourceSHA256
        self.encoding = encoding
        self.diagnostics = diagnostics
        self.cleanup = cleanup
        self.normalizationNeeded = normalizationNeeded
    }
}

public struct SubtitleCleanupExecutor: Sendable {
    public static let maximumInputBytes = 16_777_216

    public init() {}

    public func preview(sourceURL: URL) async throws -> SubtitleCleanupFilePreview {
        try await Task.detached {
            let sourceData = try Self.readInput(sourceURL)
            let decoded = try SubtitleTextDecoder().decode(sourceData)
            let parsed = try SubRipCodec().parse(decoded)
            let normalizedOriginal = Data(SubRipCodec().serialize(parsed.document).utf8)
            return SubtitleCleanupFilePreview(
                sourceURL: sourceURL.standardizedFileURL,
                sourceSHA256: Data(SHA256.hash(data: sourceData)),
                encoding: decoded.encoding,
                diagnostics: parsed.diagnostics,
                cleanup: SubtitleCleanupPolicy().preview(parsed.document),
                normalizationNeeded: decoded.encoding != .utf8 || sourceData != normalizedOriginal
            )
        }.value
    }

    public func execute(
        preview filePreview: SubtitleCleanupFilePreview,
        restoringCueIDs: Set<Int>,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> SubtitleCleanupResult {
        guard destinationURL.pathExtension.lowercased() == "srt" else {
            throw SubtitleCleanupExecutionError.unsupportedFormat
        }
        let sourceURL = filePreview.sourceURL
        let sourceData = try Self.readInput(sourceURL)
        guard Data(SHA256.hash(data: sourceData)) == filePreview.sourceSHA256 else {
            throw SubtitleCleanupExecutionError.stalePreview
        }
        let current = try SubRipCodec().parse(SubtitleTextDecoder().decode(sourceData)).document
        guard current == filePreview.cleanup.original,
            SubtitleCleanupPolicy().preview(current) == filePreview.cleanup
        else {
            throw SubtitleCleanupExecutionError.stalePreview
        }
        let desired = filePreview.cleanup.document(restoringCueIDs: restoringCueIDs)
        guard !desired.cues.isEmpty else {
            throw SubtitleCleanupExecutionError.noCuesRemaining
        }
        let serialized = Data(SubRipCodec().serialize(desired).utf8)
        let transaction = VerifiedOutputTransaction(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )
        do {
            let temporaryURL = try await transaction.prepareEmptyOutput()
            try serialized.write(to: temporaryURL, options: .withoutOverwriting)
            try await onStage(.verifying)
            try Self.verify(fileURL: temporaryURL, expectedData: serialized, desired: desired)
            try await transaction.markVerified()
            try await onStage(.committing)
            let committedURL = try await transaction.commit()
            do {
                try Self.verify(fileURL: committedURL, expectedData: serialized, desired: desired)
            } catch {
                throw SubtitleCleanupExecutionError.committedOutputAuditFailed(
                    outputURL: committedURL,
                    reason: error.localizedDescription
                )
            }
            let acceptedChanges = filePreview.cleanup.changes.filter {
                !restoringCueIDs.contains($0.id)
            }
            return SubtitleCleanupResult(
                outputURL: committedURL,
                document: desired,
                removedCueCount: acceptedChanges.filter { $0.after == nil }.count,
                changedCueCount: acceptedChanges.filter { $0.after != nil }.count
            )
        } catch {
            await transaction.cancel()
            throw error
        }
    }

    private static func readInput(_ rawURL: URL) throws -> Data {
        let url = rawURL.standardizedFileURL
        guard url.isFileURL,
            url.path.hasPrefix("/"),
            url.pathExtension.lowercased() == "srt",
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            if url.pathExtension.lowercased() != "srt" {
                throw SubtitleCleanupExecutionError.unsupportedFormat
            }
            throw SubtitleCleanupExecutionError.unsafeInput
        }
        guard values.fileSize ?? 0 <= maximumInputBytes else {
            throw SubtitleCleanupExecutionError.oversizedInput
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func verify(
        fileURL: URL,
        expectedData: Data,
        desired: SubRipDocument
    ) throws {
        let data = try readInput(fileURL)
        guard data == expectedData else {
            throw SubtitleCleanupExecutionError.verificationFailed
        }
        let decoded = try SubtitleTextDecoder().decode(data)
        guard decoded.encoding == .utf8 else {
            throw SubtitleCleanupExecutionError.verificationFailed
        }
        let reopened = try SubRipCodec().parse(decoded).document
        guard reopened.cues.map(SemanticCue.init) == desired.cues.map(SemanticCue.init) else {
            throw SubtitleCleanupExecutionError.verificationFailed
        }
    }
}

private struct SemanticCue: Equatable {
    let start: SubRipTimestamp
    let end: SubRipTimestamp
    let settings: String?
    let lines: [String]

    init(_ cue: SubRipCue) {
        start = cue.start
        end = cue.end
        settings = cue.settings
        lines = cue.lines
    }
}
