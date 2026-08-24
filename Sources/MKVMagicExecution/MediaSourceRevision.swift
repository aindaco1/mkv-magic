import Foundation
import MKVMagicCore
import MKVMagicSystem

enum MediaSourceRevisionError: Error, Equatable, Sendable {
    case unsafeSource
}

public typealias MediaSourceRevision = MediaFileRevision

extension MediaFileRevision {
    static func read(_ rawURL: URL) throws -> Self {
        do {
            return try MediaFileRevisionReader().read(rawURL)
        } catch {
            throw MediaSourceRevisionError.unsafeSource
        }
    }
}

public typealias LosslessJoinSourceRevision = MediaSourceRevision
public typealias JoinNormalizationSourceRevision = MediaSourceRevision
