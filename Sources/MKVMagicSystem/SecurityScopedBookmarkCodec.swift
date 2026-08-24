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
    case changedSinceReview
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
            securityScopedBookmark: bookmark,
            reviewedRevision: access == .readWriteDirectory ? nil : try fileRevision(for: safeURL)
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

    public func resolveUnchangedFile(
        _ reference: MediaQueueFileReference,
        access: SecurityScopedBookmarkAccess
    ) throws -> URL {
        guard access != .readWriteDirectory,
            let reviewedRevision = reference.reviewedRevision
        else {
            throw SecurityScopedBookmarkError.changedSinceReview
        }
        let url = try resolve(reference, access: access)
        guard try fileRevision(for: url) == reviewedRevision else {
            throw SecurityScopedBookmarkError.changedSinceReview
        }
        return url
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

    private func fileRevision(for url: URL) throws -> MediaQueueFileRevision {
        do {
            return try MediaFileRevisionReader().read(url).atMillisecondPrecision
        } catch {
            throw SecurityScopedBookmarkError.unsafeURL
        }
    }
}
