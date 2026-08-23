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

public struct MediaColorInfo: Codable, Hashable, Sendable {
    public let range: String?
    public let primaries: String?
    public let transfer: String?
    public let matrix: String?

    public init(
        range: String? = nil,
        primaries: String? = nil,
        transfer: String? = nil,
        matrix: String? = nil
    ) {
        self.range = range
        self.primaries = primaries
        self.transfer = transfer
        self.matrix = matrix
    }
}

public struct MediaTrack: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let kind: MediaTrackKind
    public let codec: String
    public let codecLongName: String?
    public let codecID: String?
    public let profile: String?
    public let level: Int?
    public let uid: UInt64?
    public let language: String?
    public let title: String?
    public let isDefault: Bool
    public let isForced: Bool
    public let isEnabled: Bool
    public let isCommentary: Bool
    public let isHearingImpaired: Bool
    public let isVisualImpaired: Bool
    public let isOriginal: Bool
    public let isTextDescription: Bool
    public let bitrate: Int64?
    public let channels: Int?
    public let channelLayout: String?
    public let sampleRate: Int?
    public let dimensions: MediaDimensions?
    public let displayDimensions: MediaDimensions?
    public let pixelFormat: String?
    public let bitDepth: Int?
    public let frameRate: String?
    public let colorInfo: MediaColorInfo?
    public let hdrFormats: [String]
    public let tags: [String: String]

    public init(
        id: Int,
        kind: MediaTrackKind,
        codec: String,
        codecLongName: String? = nil,
        codecID: String? = nil,
        profile: String? = nil,
        level: Int? = nil,
        uid: UInt64? = nil,
        language: String? = nil,
        title: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isEnabled: Bool = true,
        isCommentary: Bool = false,
        isHearingImpaired: Bool = false,
        isVisualImpaired: Bool = false,
        isOriginal: Bool = false,
        isTextDescription: Bool = false,
        bitrate: Int64? = nil,
        channels: Int? = nil,
        channelLayout: String? = nil,
        sampleRate: Int? = nil,
        dimensions: MediaDimensions? = nil,
        displayDimensions: MediaDimensions? = nil,
        pixelFormat: String? = nil,
        bitDepth: Int? = nil,
        frameRate: String? = nil,
        colorInfo: MediaColorInfo? = nil,
        hdrFormats: [String] = [],
        tags: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.codec = codec
        self.codecLongName = codecLongName
        self.codecID = codecID
        self.profile = profile
        self.level = level
        self.uid = uid
        self.language = language
        self.title = title
        self.isDefault = isDefault
        self.isForced = isForced
        self.isEnabled = isEnabled
        self.isCommentary = isCommentary
        self.isHearingImpaired = isHearingImpaired
        self.isVisualImpaired = isVisualImpaired
        self.isOriginal = isOriginal
        self.isTextDescription = isTextDescription
        self.bitrate = bitrate
        self.channels = channels
        self.channelLayout = channelLayout
        self.sampleRate = sampleRate
        self.dimensions = dimensions
        self.displayDimensions = displayDimensions
        self.pixelFormat = pixelFormat
        self.bitDepth = bitDepth
        self.frameRate = frameRate
        self.colorInfo = colorInfo
        self.hdrFormats = hdrFormats
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
    public let description: String?
    public let uid: UInt64?

    public init(
        id: Int,
        filename: String,
        mimeType: String? = nil,
        size: Int64? = nil,
        description: String? = nil,
        uid: UInt64? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.description = description
        self.uid = uid
    }
}

public struct MediaAsset: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let container: String
    public let formatLongName: String?
    public let duration: MediaTime?
    public let fileSize: Int64?
    public let bitrate: Int64?
    public let tracks: [MediaTrack]
    public let chapters: [ChapterNode]
    public let attachments: [MediaAttachment]
    public let metadata: [String: String]
    public let chapterEntryCount: Int?
    public let globalTagCount: Int?
    public let trackTagCount: Int?
    public let segmentUID: String?
    public let muxingApplication: String?
    public let writingApplication: String?
    public let warnings: [String]

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        container: String,
        formatLongName: String? = nil,
        duration: MediaTime? = nil,
        fileSize: Int64? = nil,
        bitrate: Int64? = nil,
        tracks: [MediaTrack] = [],
        chapters: [ChapterNode] = [],
        attachments: [MediaAttachment] = [],
        metadata: [String: String] = [:],
        chapterEntryCount: Int? = nil,
        globalTagCount: Int? = nil,
        trackTagCount: Int? = nil,
        segmentUID: String? = nil,
        muxingApplication: String? = nil,
        writingApplication: String? = nil,
        warnings: [String] = []
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.container = container
        self.formatLongName = formatLongName
        self.duration = duration
        self.fileSize = fileSize
        self.bitrate = bitrate
        self.tracks = tracks
        self.chapters = chapters
        self.attachments = attachments
        self.metadata = metadata
        self.chapterEntryCount = chapterEntryCount
        self.globalTagCount = globalTagCount
        self.trackTagCount = trackTagCount
        self.segmentUID = segmentUID
        self.muxingApplication = muxingApplication
        self.writingApplication = writingApplication
        self.warnings = warnings
    }
}
