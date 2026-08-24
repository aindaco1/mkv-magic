import Foundation
import MKVMagicCore

public enum MediaFileRevisionReaderError: Error, Equatable, Sendable {
    case unsafeFile
}

public struct MediaFileRevisionReader: Sendable {
    public init() {}

    public func read(_ rawURL: URL) throws -> MediaFileRevision {
        let url = rawURL.standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/"),
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true, values.isSymbolicLink != true
        else {
            throw MediaFileRevisionReaderError.unsafeFile
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw MediaFileRevisionReaderError.unsafeFile
        }
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            throw MediaFileRevisionReaderError.unsafeFile
        }
        return MediaFileRevision(
            fileSize: size,
            modificationDate: modificationDate,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            systemNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value
        )
    }
}
