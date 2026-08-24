import Foundation
import MKVMagicCore

struct MatroskaAssetSnapshot: Equatable {
    let sourceURL: URL
    let container: String
    let formatLongName: String?
    let duration: MediaTime?
    let fileSize: Int64?
    let bitrate: Int64?
    let tracks: [MediaTrack]
    let chapters: [ChapterNode]
    let attachments: [MediaAttachment]
    let metadata: [String: String]
    let chapterEntryCount: Int?
    let globalTagCount: Int?
    let trackTagCount: Int?
    let segmentUID: String?
    let muxingApplication: String?
    let writingApplication: String?
    let warnings: [String]

    init(_ asset: MediaAsset) {
        sourceURL = asset.sourceURL
        container = asset.container
        formatLongName = asset.formatLongName
        duration = asset.duration
        fileSize = asset.fileSize
        bitrate = asset.bitrate
        tracks = asset.tracks
        chapters = asset.chapters
        attachments = asset.attachments
        metadata = asset.metadata
        chapterEntryCount = asset.chapterEntryCount
        globalTagCount = asset.globalTagCount
        trackTagCount = asset.trackTagCount
        segmentUID = asset.segmentUID
        muxingApplication = asset.muxingApplication
        writingApplication = asset.writingApplication
        warnings = asset.warnings
    }
}
