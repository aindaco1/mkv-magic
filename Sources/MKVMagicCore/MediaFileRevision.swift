import Foundation

public struct MediaFileRevision: Codable, Hashable, Sendable {
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

    public var atMillisecondPrecision: Self {
        let milliseconds = floor(modificationDate.timeIntervalSince1970 * 1_000) / 1_000
        return Self(
            fileSize: fileSize,
            modificationDate: Date(timeIntervalSince1970: milliseconds),
            fileNumber: fileNumber,
            systemNumber: systemNumber
        )
    }
}

public typealias MediaQueueFileRevision = MediaFileRevision
