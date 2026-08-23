import Foundation

enum MediaSourceRevisionError: Error, Equatable, Sendable {
    case unsafeSource
}

public struct MediaSourceRevision: Equatable, Sendable {
    public let fileSize: Int64
    public let modificationDate: Date
    public let fileNumber: UInt64?
    public let systemNumber: UInt64?

    public init(
        fileSize: Int64,
        modificationDate: Date,
        fileNumber: UInt64? = nil,
        systemNumber: UInt64? = nil
    ) {
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.fileNumber = fileNumber
        self.systemNumber = systemNumber
    }

    static func read(_ rawURL: URL) throws -> Self {
        let url = rawURL.standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/"),
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true, values.isSymbolicLink != true
        else {
            throw MediaSourceRevisionError.unsafeSource
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw MediaSourceRevisionError.unsafeSource
        }
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            throw MediaSourceRevisionError.unsafeSource
        }
        return Self(
            fileSize: size,
            modificationDate: modificationDate,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            systemNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value
        )
    }
}

public typealias LosslessJoinSourceRevision = MediaSourceRevision
public typealias JoinNormalizationSourceRevision = MediaSourceRevision
