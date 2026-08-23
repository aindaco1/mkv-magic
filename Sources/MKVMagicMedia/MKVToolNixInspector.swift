import Foundation
import MKVMagicCore
import MKVMagicSystem

public struct MKVToolNixInspection: Equatable, Sendable {
    public let sourceURL: URL
    public let containerType: String
    public let recognized: Bool
    public let supported: Bool
    public let duration: MediaTime?
    public let title: String?
    public let segmentUID: String?
    public let muxingApplication: String?
    public let writingApplication: String?
    public let tracks: [MediaTrack]
    public let attachments: [MediaAttachment]
    public let chapterEntryCount: Int
    public let globalTagCount: Int
    public let trackTagCount: Int
    public let warnings: [String]
}

public struct MKVToolNixInspector<Runner: CommandRunning>: Sendable {
    private let mkvmergeURL: URL
    private let runner: Runner

    public init(mkvmergeURL: URL, runner: Runner) {
        self.mkvmergeURL = mkvmergeURL
        self.runner = runner
    }

    public func inspect(_ inputURL: URL) async throws -> MKVToolNixInspection {
        let input = try MediaInputValidator.validate(inputURL)
        let result = try await runner.run(
            CommandRequest(
                executableURL: mkvmergeURL,
                arguments: ["--identification-format", "json", "--identify", input.sourceURL.path],
                timeout: 120,
                outputLimit: 8_388_608
            )
        )
        guard result.exitCode == 0 else {
            throw MediaInspectionError.toolFailed(
                tool: "mkvmerge",
                exitCode: result.exitCode,
                message: result.standardError.text
            )
        }

        let document: MKVToolNixDocument
        do {
            document = try JSONDecoder().decode(
                MKVToolNixDocument.self, from: result.standardOutput.data)
        } catch {
            throw MediaInspectionError.malformedResponse(tool: "mkvmerge")
        }
        return document.inspection(sourceURL: input.sourceURL)
    }
}

private struct MKVToolNixDocument: Decodable {
    let attachments: [MKVAttachment]?
    let chapters: [MKVEntrySummary]?
    let container: MKVContainer
    let errors: [String]?
    let globalTags: [MKVEntrySummary]?
    let trackTags: [MKVEntrySummary]?
    let tracks: [MKVTrack]?
    let warnings: [String]?

    enum CodingKeys: String, CodingKey {
        case attachments
        case chapters
        case container
        case errors
        case globalTags = "global_tags"
        case trackTags = "track_tags"
        case tracks
        case warnings
    }

    func inspection(sourceURL: URL) -> MKVToolNixInspection {
        let properties = container.properties
        let allWarnings = ((errors ?? []).map { "Error: \($0)" } + (warnings ?? []))
            .filter { !$0.isEmpty }
        return MKVToolNixInspection(
            sourceURL: sourceURL,
            containerType: container.type,
            recognized: container.recognized,
            supported: container.supported,
            duration: properties?.duration.flatMap(MediaTime.safeNanoseconds),
            title: properties?.title,
            segmentUID: properties?.segmentUID,
            muxingApplication: properties?.muxingApplication,
            writingApplication: properties?.writingApplication,
            tracks: (tracks ?? []).map(\.track),
            attachments: (attachments ?? []).map(\.attachment),
            chapterEntryCount: (chapters ?? []).reduce(0) { $0 + $1.entryCount },
            globalTagCount: (globalTags ?? []).reduce(0) { $0 + $1.entryCount },
            trackTagCount: (trackTags ?? []).reduce(0) { $0 + $1.entryCount },
            warnings: allWarnings
        )
    }
}

private struct MKVContainer: Decodable {
    let properties: MKVContainerProperties?
    let recognized: Bool
    let supported: Bool
    let type: String
}

private struct MKVContainerProperties: Decodable {
    let duration: UInt64?
    let muxingApplication: String?
    let segmentUID: String?
    let title: String?
    let writingApplication: String?

    enum CodingKeys: String, CodingKey {
        case duration
        case muxingApplication = "muxing_application"
        case segmentUID = "segment_uid"
        case title
        case writingApplication = "writing_application"
    }
}

private struct MKVEntrySummary: Decodable {
    let entryCount: Int

    enum CodingKeys: String, CodingKey {
        case entryCount = "num_entries"
    }
}

private struct MKVTrack: Decodable {
    let codec: String
    let id: Int
    let properties: MKVTrackProperties
    let type: String

    var track: MediaTrack {
        let kind: MediaTrackKind =
            switch type {
            case "video": .video
            case "audio": .audio
            case "subtitles": .subtitle
            case "buttons": .data
            default: .unknown
            }
        return MediaTrack(
            id: id,
            kind: kind,
            codec: codec,
            codecID: properties.codecID,
            uid: properties.uid,
            language: properties.languageIETF ?? properties.language,
            title: properties.trackName,
            isDefault: properties.defaultTrack ?? false,
            isForced: properties.forcedTrack ?? false,
            isEnabled: properties.enabledTrack ?? true,
            isCommentary: properties.commentaryTrack ?? false,
            isHearingImpaired: properties.hearingImpairedTrack ?? false,
            isVisualImpaired: properties.visualImpairedTrack ?? false,
            isOriginal: properties.originalTrack ?? false,
            isTextDescription: properties.textDescriptionTrack ?? false,
            channels: properties.audioChannels,
            sampleRate: properties.audioSamplingFrequency.map { Int($0.rounded()) },
            dimensions: Self.dimensions(properties.pixelDimensions),
            displayDimensions: Self.dimensions(properties.displayDimensions),
            bitDepth: properties.audioBitsPerSample ?? properties.videoBitsPerColour
        )
    }

    private static func dimensions(_ value: String?) -> MediaDimensions? {
        guard let value else { return nil }
        let parts = value.lowercased().split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
            let width = Int(parts[0]),
            let height = Int(parts[1]),
            width > 0,
            height > 0
        else {
            return nil
        }
        return MediaDimensions(width: width, height: height)
    }
}

private struct MKVTrackProperties: Decodable {
    let audioBitsPerSample: Int?
    let audioChannels: Int?
    let audioSamplingFrequency: Double?
    let codecID: String?
    let commentaryTrack: Bool?
    let defaultTrack: Bool?
    let displayDimensions: String?
    let enabledTrack: Bool?
    let forcedTrack: Bool?
    let hearingImpairedTrack: Bool?
    let language: String?
    let languageIETF: String?
    let originalTrack: Bool?
    let pixelDimensions: String?
    let textDescriptionTrack: Bool?
    let trackName: String?
    let uid: UInt64?
    let videoBitsPerColour: Int?
    let visualImpairedTrack: Bool?

    enum CodingKeys: String, CodingKey {
        case audioBitsPerSample = "audio_bits_per_sample"
        case audioChannels = "audio_channels"
        case audioSamplingFrequency = "audio_sampling_frequency"
        case codecID = "codec_id"
        case commentaryTrack = "flag_commentary"
        case defaultTrack = "default_track"
        case displayDimensions = "display_dimensions"
        case enabledTrack = "enabled_track"
        case forcedTrack = "forced_track"
        case hearingImpairedTrack = "flag_hearing_impaired"
        case language
        case languageIETF = "language_ietf"
        case originalTrack = "flag_original"
        case pixelDimensions = "pixel_dimensions"
        case textDescriptionTrack = "flag_text_descriptions"
        case trackName = "track_name"
        case uid
        case videoBitsPerColour = "video_bits_per_colour"
        case visualImpairedTrack = "flag_visual_impaired"
    }
}

private struct MKVAttachment: Decodable {
    let contentType: String?
    let description: String?
    let filename: String
    let id: Int
    let properties: MKVAttachmentProperties?
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case description
        case filename = "file_name"
        case id
        case properties
        case size
    }

    var attachment: MediaAttachment {
        MediaAttachment(
            id: id,
            filename: filename,
            mimeType: contentType,
            size: size,
            description: description,
            uid: properties?.uid
        )
    }
}

private struct MKVAttachmentProperties: Decodable {
    let uid: UInt64?
}

extension MediaTime {
    fileprivate static func safeNanoseconds(_ value: UInt64) -> MediaTime? {
        guard value <= UInt64(Int64.max) else { return nil }
        return MediaTime(nanoseconds: Int64(value))
    }
}
