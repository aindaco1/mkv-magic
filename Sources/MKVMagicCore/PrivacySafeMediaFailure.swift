import Foundation

public enum PrivacySafeMediaFailureCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case sourceChanged
    case toolFailed
    case emptyOutput
    case containerMismatch
    case durationMismatch
    case trackMismatch
    case trackMetadataMismatch
    case chapterMismatch
    case titleMismatch
    case attachmentMismatch
    case segmentIdentityMismatch
    case packetCopyMismatch
    case joinBoundaryDecodeFailed
    case committedOutputAuditFailed
    case destinationUnavailable
    case destinationExists
    case commitPermissionDenied
    case commitUnsupported
    case commitFailed
    case historyWriteFailed
    case verificationFailed
    case executionFailed
}

/// A deliberately coarse failure descriptor that is safe to persist and export.
/// It never stores paths, filenames, workflow names, subtitle text, or raw tool output.
public struct PrivacySafeMediaFailure: Codable, Equatable, Hashable, Sendable {
    public let category: PrivacySafeMediaFailureCategory
    public let lastActiveStage: MediaJobState
    public let joinBoundaryNumber: Int?

    public init(
        category: PrivacySafeMediaFailureCategory,
        lastActiveStage: MediaJobState,
        joinBoundaryNumber: Int? = nil
    ) {
        self.category = category
        self.lastActiveStage = lastActiveStage
        self.joinBoundaryNumber = joinBoundaryNumber
    }

    public static func executionFailed(
        at stage: MediaJobState = .running
    ) -> Self {
        Self(category: .executionFailed, lastActiveStage: stage)
    }

    public func hasCanonicalStructure(inputCount: Int) -> Bool {
        guard inputCount > 0,
            !lastActiveStage.isTerminal,
            lastActiveStage != .queued
        else { return false }
        switch category {
        case .joinBoundaryDecodeFailed:
            guard let joinBoundaryNumber else { return false }
            return joinBoundaryNumber > 0 && joinBoundaryNumber < inputCount
        default:
            return joinBoundaryNumber == nil
        }
    }
}

/// Centralizes classification for both private History and persistent queue failures.
/// Callers must pass only an already-sanitized diagnostic message.
public enum PrivacySafeMediaFailureClassifier {
    public static func classify(
        sanitizedMessage rawMessage: String,
        lastActiveStage: MediaJobState,
        inputCount: Int
    ) -> PrivacySafeMediaFailure {
        let message = rawMessage.lowercased()
        let boundaryNumber = joinBoundaryNumber(in: message, inputCount: inputCount)
        let category: PrivacySafeMediaFailureCategory
        if boundaryNumber != nil {
            category = .joinBoundaryDecodeFailed
        } else if message.contains("source changed") {
            category = .sourceChanged
        } else if message.contains("tool could not") || message.contains("mkvmerge could not") {
            category = .toolFailed
        } else if message.contains("output was empty") || message.contains("mkv was empty")
            || message.contains("mkv is empty")
        {
            category = .emptyOutput
        } else if message.contains("container did not match")
            || message.contains("did not create a matroska")
        {
            category = .containerMismatch
        } else if message.contains("duration did not match") {
            category = .durationMismatch
        } else if message.contains("track metadata did not match") {
            category = .trackMetadataMismatch
        } else if message.contains("track structure did not match") {
            category = .trackMismatch
        } else if message.contains("chapter timing or titles did not match") {
            category = .chapterMismatch
        } else if message.contains("segment title did not match") {
            category = .titleMismatch
        } else if message.contains("attachment set did not match") {
            category = .attachmentMismatch
        } else if message.contains("segment identity was invalid") {
            category = .segmentIdentityMismatch
        } else if message.contains("packet-copy audit did not match") {
            category = .packetCopyMismatch
        } else if message.contains("final reopen audit failed") {
            category = .committedOutputAuditFailed
        } else if message.contains("output location was unavailable or unsafe") {
            category = .destinationUnavailable
        } else if message.contains("already existed at the output location") {
            category = .destinationExists
        } else if message.contains("output commit permission was denied") {
            category = .commitPermissionDenied
        } else if message.contains("output filesystem did not support") {
            category = .commitUnsupported
        } else if message.contains("verified output could not be committed") {
            category = .commitFailed
        } else if message.contains("history could not be updated")
            || message.contains("history finalization failed")
        {
            category = .historyWriteFailed
        } else if lastActiveStage == .verifying {
            category = .verificationFailed
        } else {
            category = .executionFailed
        }
        return PrivacySafeMediaFailure(
            category: category,
            lastActiveStage: lastActiveStage,
            joinBoundaryNumber: boundaryNumber
        )
    }

    private static func joinBoundaryNumber(in message: String, inputCount: Int) -> Int? {
        let prefix = "the joined output did not decode cleanly across boundary "
        guard inputCount >= 2, let range = message.range(of: prefix) else { return nil }
        let suffix = message[range.upperBound...]
        let digits = suffix.prefix(while: { $0.isNumber })
        guard !digits.isEmpty,
            suffix.dropFirst(digits.count).first == ".",
            let boundaryNumber = Int(digits),
            boundaryNumber > 0,
            boundaryNumber < inputCount
        else {
            return nil
        }
        return boundaryNumber
    }
}
