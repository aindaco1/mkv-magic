import Foundation

public enum MediaTrackKind: String, Codable, CaseIterable, Hashable, Sendable {
    case video
    case audio
    case subtitle
    case data
    case attachment
    case unknown
}

public struct MediaDimensions: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct MediaTrack: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let kind: MediaTrackKind
    public let codec: String
    public let profile: String?
    public let language: String?
    public let title: String?
    public let isDefault: Bool
    public let isForced: Bool
    public let channels: Int?
    public let channelLayout: String?
    public let sampleRate: Int?
    public let dimensions: MediaDimensions?
    public let pixelFormat: String?
    public let bitDepth: Int?
    public let frameRate: String?
    public let tags: [String: String]

    public init(
        id: Int,
        kind: MediaTrackKind,
        codec: String,
        profile: String? = nil,
        language: String? = nil,
        title: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        channels: Int? = nil,
        channelLayout: String? = nil,
        sampleRate: Int? = nil,
        dimensions: MediaDimensions? = nil,
        pixelFormat: String? = nil,
        bitDepth: Int? = nil,
        frameRate: String? = nil,
        tags: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.codec = codec
        self.profile = profile
        self.language = language
        self.title = title
        self.isDefault = isDefault
        self.isForced = isForced
        self.channels = channels
        self.channelLayout = channelLayout
        self.sampleRate = sampleRate
        self.dimensions = dimensions
        self.pixelFormat = pixelFormat
        self.bitDepth = bitDepth
        self.frameRate = frameRate
        self.tags = tags
    }
}

public struct ChapterNode: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var start: MediaTime
    public var end: MediaTime?
    public var language: String?
    public var children: [ChapterNode]

    public init(
        id: UUID = UUID(),
        title: String,
        start: MediaTime,
        end: MediaTime? = nil,
        language: String? = nil,
        children: [ChapterNode] = []
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.language = language
        self.children = children
    }
}

public struct MediaAttachment: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let filename: String
    public let mimeType: String?
    public let size: Int64?

    public init(id: Int, filename: String, mimeType: String? = nil, size: Int64? = nil) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
    }
}

public struct MediaAsset: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let container: String
    public let duration: MediaTime?
    public let fileSize: Int64?
    public let bitrate: Int64?
    public let tracks: [MediaTrack]
    public let chapters: [ChapterNode]
    public let attachments: [MediaAttachment]
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        container: String,
        duration: MediaTime? = nil,
        fileSize: Int64? = nil,
        bitrate: Int64? = nil,
        tracks: [MediaTrack] = [],
        chapters: [ChapterNode] = [],
        attachments: [MediaAttachment] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.container = container
        self.duration = duration
        self.fileSize = fileSize
        self.bitrate = bitrate
        self.tracks = tracks
        self.chapters = chapters
        self.attachments = attachments
        self.metadata = metadata
    }
}
