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
    public let appliesEnglishOCRRules: Bool

    public init(
        sourceURL: URL,
        sourceSHA256: Data,
        encoding: SubtitleTextEncoding,
        diagnostics: Set<SubRipDiagnostic>,
        cleanup: SubtitleCleanupPreview,
        normalizationNeeded: Bool,
        appliesEnglishOCRRules: Bool = true
    ) {
        self.sourceURL = sourceURL
        self.sourceSHA256 = sourceSHA256
        self.encoding = encoding
        self.diagnostics = diagnostics
        self.cleanup = cleanup
        self.normalizationNeeded = normalizationNeeded
        self.appliesEnglishOCRRules = appliesEnglishOCRRules
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
            let appliesEnglishOCRRules = EnglishSubtitleFilenamePolicy.shouldApplyOCRRules(
                to: sourceURL
            )
            return SubtitleCleanupFilePreview(
                sourceURL: sourceURL.standardizedFileURL,
                sourceSHA256: Data(SHA256.hash(data: sourceData)),
                encoding: decoded.encoding,
                diagnostics: parsed.diagnostics,
                cleanup: SubtitleCleanupPolicy(
                    appliesEnglishOCRRules: appliesEnglishOCRRules
                ).preview(parsed.document),
                normalizationNeeded: decoded.encoding != .utf8 || sourceData != normalizedOriginal,
                appliesEnglishOCRRules: appliesEnglishOCRRules
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
        try validateCurrent(filePreview)
        let desired = filePreview.cleanup.document(restoringCueIDs: restoringCueIDs)
        guard !desired.cues.isEmpty else {
            throw SubtitleCleanupExecutionError.noCuesRemaining
        }
        let serialized = Data(SubRipCodec().serialize(desired).utf8)
        let committedURL = try await VerifiedSubtitleTextOutputWriter.execute(
            sourceURL: filePreview.sourceURL,
            destinationURL: destinationURL,
            data: serialized,
            onStage: onStage,
            verify: { outputURL in
                try Self.verify(fileURL: outputURL, expectedData: serialized, desired: desired)
            },
            committedAuditError: { outputURL, reason in
                SubtitleCleanupExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            }
        )
        let acceptedChanges = filePreview.cleanup.changes.filter {
            !restoringCueIDs.contains($0.id)
        }
        return SubtitleCleanupResult(
            outputURL: committedURL,
            document: desired,
            removedCueCount: acceptedChanges.filter { $0.after == nil }.count,
            changedCueCount: acceptedChanges.filter { $0.after != nil }.count
        )
    }

    public func validateCurrent(_ filePreview: SubtitleCleanupFilePreview) throws {
        let sourceData = try Self.readInput(filePreview.sourceURL)
        guard Data(SHA256.hash(data: sourceData)) == filePreview.sourceSHA256 else {
            throw SubtitleCleanupExecutionError.stalePreview
        }
        let current = try SubRipCodec().parse(SubtitleTextDecoder().decode(sourceData)).document
        guard current == filePreview.cleanup.original,
            SubtitleCleanupPolicy(
                appliesEnglishOCRRules: filePreview.appliesEnglishOCRRules
            ).preview(current) == filePreview.cleanup
        else {
            throw SubtitleCleanupExecutionError.stalePreview
        }
    }

    private static func readInput(_ rawURL: URL) throws -> Data {
        do {
            return try SafeSubtitleTextFile.read(
                rawURL,
                allowedExtensions: ["srt"],
                maximumInputBytes: maximumInputBytes
            )
        } catch let error as SafeSubtitleTextFileError {
            switch error {
            case .unsupportedExtension:
                throw SubtitleCleanupExecutionError.unsupportedFormat
            case .unsafeInput:
                throw SubtitleCleanupExecutionError.unsafeInput
            case .oversizedInput:
                throw SubtitleCleanupExecutionError.oversizedInput
            }
        }
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
