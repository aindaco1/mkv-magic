import Foundation

public enum PrivateTemporaryDirectoryError: Error, Equatable, Sendable {
    case invalidPrefix
    case unsafeDirectory
}

extension PrivateTemporaryDirectoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPrefix: "The private workspace name is invalid."
        case .unsafeDirectory: "The private workspace could not be created safely."
        }
    }
}

public enum PrivateTemporaryDirectory {
    public static func withDirectory<T: Sendable>(
        prefix: String,
        _ operation: (URL) async throws -> T
    ) async throws -> T {
        guard (1...64).contains(prefix.utf8.count),
            prefix.utf8.allSatisfy({ byte in
                (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
                    || (byte >= 97 && byte <= 122) || byte == 45
            })
        else {
            throw PrivateTemporaryDirectoryError.invalidPrefix
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let values = try directory.resourceValues(forKeys: [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        let permissions =
            try FileManager.default.attributesOfItem(atPath: directory.path)[
                .posixPermissions
            ] as? NSNumber
        guard directory.isFileURL, directory.path.hasPrefix("/"), values.isDirectory == true,
            values.isRegularFile != true, values.isSymbolicLink != true,
            permissions?.intValue == 0o700
        else {
            throw PrivateTemporaryDirectoryError.unsafeDirectory
        }
        return try await operation(directory)
    }
}
