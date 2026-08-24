import Foundation
import MKVMagicCore

public enum SecurityScopedBookmarkAccess: Equatable, Sendable {
    case readOnlyFile
    case readWriteFile
    case readWriteDirectory
}

public enum SecurityScopedBookmarkError: Error, Equatable, Sendable {
    case unsafeURL
    case wrongResourceType
    case stale
}

public struct SecurityScopedBookmarkCodec: Sendable {
    public init() {}

    public func makeReference(
        for url: URL,
        access: SecurityScopedBookmarkAccess
    ) throws -> MediaQueueFileReference {
        let safeURL = try validated(url, access: access)
        let options: URL.BookmarkCreationOptions =
            access == .readOnlyFile
            ? [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
            : [.withSecurityScope]
        let bookmark = try safeURL.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return MediaQueueFileReference(
            displayName: safeURL.lastPathComponent,
            securityScopedBookmark: bookmark
        )
    }

    public func resolve(
        _ reference: MediaQueueFileReference,
        access: SecurityScopedBookmarkAccess
    ) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: reference.securityScopedBookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else { throw SecurityScopedBookmarkError.stale }
        return try validated(url, access: access)
    }

    private func validated(
        _ url: URL,
        access: SecurityScopedBookmarkAccess
    ) throws -> URL {
        let standardized = url.standardizedFileURL
        guard standardized.isFileURL,
            standardized.path.hasPrefix("/"),
            !isSymbolicLink(standardized)
        else {
            throw SecurityScopedBookmarkError.unsafeURL
        }
        let values = try standardized.resourceValues(forKeys: [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard values.isSymbolicLink != true else {
            throw SecurityScopedBookmarkError.unsafeURL
        }
        switch access {
        case .readOnlyFile, .readWriteFile:
            guard values.isRegularFile == true else {
                throw SecurityScopedBookmarkError.wrongResourceType
            }
        case .readWriteDirectory:
            guard values.isDirectory == true else {
                throw SecurityScopedBookmarkError.wrongResourceType
            }
        }
        return standardized
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}
