import CryptoKit
import Foundation
import MKVMagicCore

public enum AdvancedSubtitleCleanupExecutionError: Error, Equatable, Sendable {
    case unsupportedFormat
    case unsafeInput
    case oversizedInput
    case stalePreview
    case noEventsRemaining
    case verificationFailed
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension AdvancedSubtitleCleanupExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Subtitle cleanup requires an ASS or SSA file."
        case .unsafeInput: "The subtitle input is not a safe regular file."
        case .oversizedInput: "The subtitle file is larger than MKV Magic allows."
        case .stalePreview: "The subtitle changed after the cleanup preview was created."
        case .noEventsRemaining: "Restore at least one dialogue event before saving."
        case .verificationFailed: "The cleaned subtitle did not pass its style and timing audit."
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified subtitle was saved as \(outputURL.lastPathComponent), but its final "
                + "reopen audit failed: \(reason)"
        }
    }
}

public struct AdvancedSubtitleCleanupResult: Equatable, Sendable {
    public let outputURL: URL
    public let document: AdvancedSubStationAlphaDocument
    public let removedEventCount: Int
    public let changedEventCount: Int

    public init(
        outputURL: URL,
        document: AdvancedSubStationAlphaDocument,
        removedEventCount: Int,
        changedEventCount: Int
    ) {
        self.outputURL = outputURL
        self.document = document
        self.removedEventCount = removedEventCount
        self.changedEventCount = changedEventCount
    }
}

public struct AdvancedSubtitleCleanupFilePreview: Equatable, Sendable {
    public let sourceURL: URL
    public let sourceSHA256: Data
    public let encoding: SubtitleTextEncoding
    public let diagnostics: Set<AdvancedSubStationAlphaDiagnostic>
    public let cleanup: AdvancedSubStationAlphaCleanupPreview
    public let normalizationNeeded: Bool

    public init(
        sourceURL: URL,
        sourceSHA256: Data,
        encoding: SubtitleTextEncoding,
        diagnostics: Set<AdvancedSubStationAlphaDiagnostic>,
        cleanup: AdvancedSubStationAlphaCleanupPreview,
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

public struct AdvancedSubtitleCleanupExecutor: Sendable {
    public static let maximumInputBytes = SubtitleCleanupExecutor.maximumInputBytes

    public init() {}

    public func preview(sourceURL: URL) async throws -> AdvancedSubtitleCleanupFilePreview {
        try await Task.detached {
            let sourceData = try Self.readInput(sourceURL)
            let decoded = try SubtitleTextDecoder().decode(sourceData)
            let parsed = try AdvancedSubStationAlphaCodec().parse(decoded)
            let normalizedOriginal = Data(
                AdvancedSubStationAlphaCodec().serialize(parsed.document).utf8
            )
            return AdvancedSubtitleCleanupFilePreview(
                sourceURL: sourceURL.standardizedFileURL,
                sourceSHA256: Data(SHA256.hash(data: sourceData)),
                encoding: decoded.encoding,
                diagnostics: parsed.diagnostics,
                cleanup: AdvancedSubStationAlphaCleanupPolicy().preview(parsed.document),
                normalizationNeeded: decoded.encoding != .utf8 || sourceData != normalizedOriginal
            )
        }.value
    }

    public func execute(
        preview filePreview: AdvancedSubtitleCleanupFilePreview,
        restoringEventIDs: Set<Int>,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> AdvancedSubtitleCleanupResult {
        guard
            destinationURL.pathExtension.lowercased()
                == filePreview.sourceURL.pathExtension.lowercased()
        else {
            throw AdvancedSubtitleCleanupExecutionError.unsupportedFormat
        }
        try validateCurrent(filePreview)
        let desired = filePreview.cleanup.document(restoringEventIDs: restoringEventIDs)
        guard !desired.events.isEmpty else {
            throw AdvancedSubtitleCleanupExecutionError.noEventsRemaining
        }
        let serialized = Data(AdvancedSubStationAlphaCodec().serialize(desired).utf8)
        let committedURL = try await VerifiedSubtitleTextOutputWriter.execute(
            sourceURL: filePreview.sourceURL,
            destinationURL: destinationURL,
            data: serialized,
            onStage: onStage,
            verify: { outputURL in
                try Self.verify(fileURL: outputURL, expectedData: serialized, desired: desired)
            },
            committedAuditError: { outputURL, reason in
                AdvancedSubtitleCleanupExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            }
        )
        let acceptedChanges = filePreview.cleanup.changes.filter {
            !restoringEventIDs.contains($0.id)
        }
        return AdvancedSubtitleCleanupResult(
            outputURL: committedURL,
            document: desired,
            removedEventCount: acceptedChanges.filter { $0.after == nil }.count,
            changedEventCount: acceptedChanges.filter { $0.after != nil }.count
        )
    }

    public func validateCurrent(_ filePreview: AdvancedSubtitleCleanupFilePreview) throws {
        let sourceData = try Self.readInput(filePreview.sourceURL)
        let currentDigest = Data(SHA256.hash(data: sourceData))
        guard currentDigest == filePreview.sourceSHA256 else {
            throw AdvancedSubtitleCleanupExecutionError.stalePreview
        }
        let current = try AdvancedSubStationAlphaCodec().parse(
            SubtitleTextDecoder().decode(sourceData)
        ).document
        guard current == filePreview.cleanup.original,
            AdvancedSubStationAlphaCleanupPolicy().preview(current) == filePreview.cleanup
        else {
            throw AdvancedSubtitleCleanupExecutionError.stalePreview
        }
    }

    private static func readInput(_ rawURL: URL) throws -> Data {
        do {
            return try SafeSubtitleTextFile.read(
                rawURL,
                allowedExtensions: ["ass", "ssa"],
                maximumInputBytes: maximumInputBytes
            )
        } catch let error as SafeSubtitleTextFileError {
            switch error {
            case .unsupportedExtension:
                throw AdvancedSubtitleCleanupExecutionError.unsupportedFormat
            case .unsafeInput:
                throw AdvancedSubtitleCleanupExecutionError.unsafeInput
            case .oversizedInput:
                throw AdvancedSubtitleCleanupExecutionError.oversizedInput
            }
        }
    }

    private static func verify(
        fileURL: URL,
        expectedData: Data,
        desired: AdvancedSubStationAlphaDocument
    ) throws {
        let data = try readInput(fileURL)
        guard data == expectedData else {
            throw AdvancedSubtitleCleanupExecutionError.verificationFailed
        }
        let decoded = try SubtitleTextDecoder().decode(data)
        guard decoded.encoding == .utf8 else {
            throw AdvancedSubtitleCleanupExecutionError.verificationFailed
        }
        let reopened = try AdvancedSubStationAlphaCodec().parse(decoded).document
        guard
            reopened.events.map(SemanticAdvancedSubtitleEvent.init)
                == desired.events.map(SemanticAdvancedSubtitleEvent.init)
        else {
            throw AdvancedSubtitleCleanupExecutionError.verificationFailed
        }
    }
}

private struct SemanticAdvancedSubtitleEvent: Equatable {
    let start: SubRipTimestamp
    let end: SubRipTimestamp
    let style: String?
    let text: String

    init(_ event: AdvancedSubStationAlphaEvent) {
        start = event.start
        end = event.end
        style = event.style
        text = event.text
    }
}
