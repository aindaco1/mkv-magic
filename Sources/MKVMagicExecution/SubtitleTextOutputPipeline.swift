import Foundation

enum SafeSubtitleTextFileError: Error, Equatable {
    case unsupportedExtension
    case unsafeInput
    case oversizedInput
}

struct SafeSubtitleTextFile {
    static func read(
        _ rawURL: URL,
        allowedExtensions: Set<String>,
        maximumInputBytes: Int
    ) throws -> Data {
        let url = rawURL.standardizedFileURL
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else {
            throw SafeSubtitleTextFileError.unsupportedExtension
        }
        guard url.isFileURL,
            url.path.hasPrefix("/"),
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw SafeSubtitleTextFileError.unsafeInput
        }
        guard values.fileSize ?? 0 <= maximumInputBytes else {
            throw SafeSubtitleTextFileError.oversizedInput
        }
        // Inputs are capped at 16 MiB. Taking an owned snapshot avoids an mmap observing a
        // concurrent in-place rewrite between digesting, parsing, and stale-preview checks.
        return try Data(contentsOf: url)
    }
}

struct VerifiedSubtitleTextOutputWriter {
    static func execute(
        sourceURL: URL,
        destinationURL: URL,
        data: Data,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void,
        verify: @escaping @Sendable (URL) throws -> Void,
        validateSource: @escaping @Sendable () throws -> Void = {},
        committedAuditError: @escaping @Sendable (URL, String) -> any Error
    ) async throws -> URL {
        try Task.checkCancellation()
        try validateSource()
        let transaction = VerifiedOutputTransaction(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )
        do {
            let temporaryURL = try await transaction.prepareEmptyOutput()
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            try Task.checkCancellation()
            try validateSource()
            try await onStage(.verifying)
            try Task.checkCancellation()
            try verify(temporaryURL)
            try Task.checkCancellation()
            try validateSource()
            try await transaction.markVerified()
            try await onStage(.committing)
            try Task.checkCancellation()
            try validateSource()
            let committedURL = try await transaction.commit()
            do {
                try verify(committedURL)
                try Task.checkCancellation()
                try validateSource()
            } catch {
                throw committedAuditError(committedURL, error.localizedDescription)
            }
            return committedURL
        } catch {
            await transaction.cancel()
            throw error
        }
    }
}
