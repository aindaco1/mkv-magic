import Foundation
import MKVMagicCore
import MKVMagicSystem

/// Binds a reviewed execution to one exact regular-file revision without
/// retaining any media content or file-specific facts in portable intent.
struct MediaFileRevisionGuard: Sendable {
    let sourceURL: URL
    let revision: MediaFileRevision

    init(sourceURL rawSourceURL: URL, expectedRevision: MediaFileRevision?) throws {
        let sourceURL = rawSourceURL.standardizedFileURL
        let revision = try MediaFileRevisionReader().read(sourceURL)
        guard expectedRevision == nil || expectedRevision == revision else {
            throw MediaFileRevisionGuardError.staleSource
        }
        self.sourceURL = sourceURL
        self.revision = revision
    }

    func isCurrent() -> Bool {
        (try? MediaFileRevisionReader().read(sourceURL)) == revision
    }
}

enum MediaFileRevisionGuardError: Error, Equatable, Sendable {
    case staleSource
}

func mediaFileRevisionValidator<Failure: Error & Sendable>(
    sourceURL: URL,
    expectedRevision: MediaFileRevision?,
    changedError: Failure
) throws -> @Sendable () throws -> Void {
    let guardValue: MediaFileRevisionGuard
    do {
        guardValue = try MediaFileRevisionGuard(
            sourceURL: sourceURL,
            expectedRevision: expectedRevision
        )
    } catch {
        throw changedError
    }
    return {
        guard guardValue.isCurrent() else { throw changedError }
    }
}
