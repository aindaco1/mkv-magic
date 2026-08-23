import CryptoKit
import Foundation
import MKVMagicCore

public enum MediaInspectionError: Error, Equatable, Sendable {
    case unsafeInput
    case toolFailed(tool: String, exitCode: Int32, message: String)
    case malformedResponse(tool: String)
}

extension MediaInspectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafeInput:
            "The selected item is not a safe regular file."
        case .toolFailed(let tool, let exitCode, let message):
            "\(tool) could not read this file (code \(exitCode)): \(message.conciseToolMessage)"
        case .malformedResponse(let tool):
            "\(tool) returned inspection data MKV Magic could not understand."
        }
    }
}

public protocol MediaInspecting: Sendable {
    func inspect(_ inputURL: URL) async throws -> MediaAsset
}

struct ValidatedMediaInput: Sendable {
    let sourceURL: URL
    let fileSize: Int64?
}

enum MediaInputValidator {
    static func validate(_ inputURL: URL) throws -> ValidatedMediaInput {
        let source = inputURL.standardizedFileURL
        guard source.isFileURL,
            source.path.hasPrefix("/"),
            let values = try? source.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw MediaInspectionError.unsafeInput
        }
        return ValidatedMediaInput(
            sourceURL: source,
            fileSize: values.fileSize.map(Int64.init)
        )
    }
}

enum MediaStableIdentifier {
    static func make(scope: String, value: String) -> UUID {
        let digest = SHA256.hash(data: Data((scope + "\u{0}" + value).utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}

extension String {
    fileprivate var conciseToolMessage: String {
        let normalized =
            trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "Unknown tool error"
        return String(normalized.prefix(240))
    }
}
