import Foundation
import MKVMagicCore
import MKVMagicSystem

public struct FFprobeInspector<Runner: CommandRunning>: MediaInspecting {
    private let ffprobeURL: URL
    private let runner: Runner

    public init(ffprobeURL: URL, runner: Runner) {
        self.ffprobeURL = ffprobeURL
        self.runner = runner
    }

    public func inspect(_ inputURL: URL) async throws -> MediaAsset {
        let input = try MediaInputValidator.validate(inputURL)
        let source = input.sourceURL

        let result = try await runner.run(
            CommandRequest(
                executableURL: ffprobeURL,
                arguments: [
                    "-v", "error",
                    "-print_format", "json",
                    "-show_format",
                    "-show_streams",
                    "-show_chapters",
                    source.path,
                ],
                timeout: 120,
                outputLimit: 8_388_608
            )
        )
        guard result.exitCode == 0 else {
            throw MediaInspectionError.toolFailed(
                tool: "ffprobe",
                exitCode: result.exitCode,
                message: result.standardError.text
            )
        }

        let document: FFprobeDocument
        do {
            document = try JSONDecoder().decode(
                FFprobeDocument.self, from: result.standardOutput.data)
        } catch {
            throw MediaInspectionError.malformedResponse(tool: "ffprobe")
        }
        return document.asset(sourceURL: source, fallbackSize: input.fileSize)
    }
}

private struct FFprobeDocument: Decodable {
    let streams: [FFprobeStream]?
    let chapters: [FFprobeChapter]?
    let format: FFprobeFormat?

    func asset(sourceURL: URL, fallbackSize: Int64?) -> MediaAsset {
        let formatNames = format?.formatName?.split(separator: ",") ?? []
        let normalizedTracks = (streams ?? []).map { $0.track }
        let normalizedChapters = (chapters ?? []).enumerated().map {
            $0.element.chapter(sourceURL: sourceURL, ordinal: $0.offset)
        }
        return MediaAsset(
            id: MediaStableIdentifier.make(scope: "asset", value: sourceURL.path),
            sourceURL: sourceURL,
            container: formatNames.first.map(String.init) ?? sourceURL.pathExtension.lowercased(),
            formatLongName: format?.formatLongName,
            duration: format?.duration.flatMap(Double.init).flatMap(MediaTime.init(seconds:)),
            fileSize: format?.size.flatMap(Int64.init) ?? fallbackSize,
            bitrate: format?.bitRate.flatMap(Int64.init),
            tracks: normalizedTracks,
            chapters: normalizedChapters,
            metadata: format?.tags ?? [:]
        )
    }
}

private struct FFprobeFormat: Decodable {
    let formatName: String?
    let formatLongName: String?
    let duration: String?
    let size: String?
    let bitRate: String?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case formatName = "format_name"
        case formatLongName = "format_long_name"
        case duration
        case size
        case bitRate = "bit_rate"
        case tags
    }
}

private struct FFprobeStream: Decodable {
    let index: Int
    let codecName: String?
    let codecLongName: String?
    let codecTagString: String?
    let codecType: String?
    let profile: String?
    let level: Int?
    let bitRate: String?
    let width: Int?
    let height: Int?
    let pixelFormat: String?
    let bitsPerRawSample: String?
    let sampleRate: String?
    let channels: Int?
    let channelLayout: String?
    let averageFrameRate: String?
    let colorRange: String?
    let colorSpace: String?
    let colorTransfer: String?
    let colorPrimaries: String?
    let disposition: [String: Int]?
    let sideData: [FFprobeSideData]?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case index
        case codecName = "codec_name"
        case codecLongName = "codec_long_name"
        case codecTagString = "codec_tag_string"
        case codecType = "codec_type"
        case profile
        case level
        case bitRate = "bit_rate"
        case width
        case height
        case pixelFormat = "pix_fmt"
        case bitsPerRawSample = "bits_per_raw_sample"
        case sampleRate = "sample_rate"
        case channels
        case channelLayout = "channel_layout"
        case averageFrameRate = "avg_frame_rate"
        case colorRange = "color_range"
        case colorSpace = "color_space"
        case colorTransfer = "color_transfer"
        case colorPrimaries = "color_primaries"
        case disposition
        case sideData = "side_data_list"
        case tags
    }

    var track: MediaTrack {
        let kind = MediaTrackKind(rawValue: codecType ?? "") ?? .unknown
        let dimensions = width.flatMap { resolvedWidth in
            height.map { MediaDimensions(width: resolvedWidth, height: $0) }
        }
        let colorInfo: MediaColorInfo? =
            if colorRange != nil || colorPrimaries != nil || colorTransfer != nil
                || colorSpace != nil
            {
                MediaColorInfo(
                    range: colorRange,
                    primaries: colorPrimaries,
                    transfer: colorTransfer,
                    matrix: colorSpace
                )
            } else {
                nil
            }
        return MediaTrack(
            id: index,
            kind: kind,
            codec: codecName ?? "unknown",
            codecLongName: codecLongName,
            codecID: codecTagString,
            profile: profile,
            level: level,
            language: tags?["language"],
            title: tags?["title"],
            isDefault: disposition?["default"] == 1,
            isForced: disposition?["forced"] == 1,
            isCommentary: disposition?["comment"] == 1,
            isHearingImpaired: disposition?["hearing_impaired"] == 1,
            isVisualImpaired: disposition?["visual_impaired"] == 1,
            isOriginal: disposition?["original"] == 1,
            isTextDescription: disposition?["descriptions"] == 1,
            bitrate: bitRate.flatMap(Int64.init),
            channels: channels,
            channelLayout: channelLayout,
            sampleRate: sampleRate.flatMap(Int.init),
            dimensions: dimensions,
            pixelFormat: pixelFormat,
            bitDepth: bitsPerRawSample.flatMap(Int.init) ?? inferredBitDepth,
            frameRate: averageFrameRate,
            colorInfo: colorInfo,
            hdrFormats: normalizedHDRFormats,
            tags: tags ?? [:]
        )
    }

    private var inferredBitDepth: Int? {
        guard let pixelFormat else { return nil }
        for value in [16, 14, 12, 10, 9] where pixelFormat.contains("p\(value)") {
            return value
        }
        return nil
    }

    private var normalizedHDRFormats: [String] {
        let types = (sideData ?? []).map(\.type)
        var formats = Set<String>()
        if types.contains(where: { $0.localizedCaseInsensitiveContains("DOVI") }) {
            formats.insert("Dolby Vision")
        }
        if types.contains(where: {
            $0.localizedCaseInsensitiveContains("Mastering display")
                || $0.localizedCaseInsensitiveContains("Content light level")
        }) {
            formats.insert("HDR10 metadata")
        }
        return formats.sorted()
    }
}

private struct FFprobeSideData: Decodable {
    let type: String

    enum CodingKeys: String, CodingKey {
        case type = "side_data_type"
    }
}

private struct FFprobeChapter: Decodable {
    let id: Int?
    let startTime: String?
    let endTime: String?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case tags
    }

    func chapter(sourceURL: URL, ordinal: Int) -> ChapterNode {
        let stableValue = [
            sourceURL.path,
            String(id ?? ordinal),
            startTime ?? "",
            endTime ?? "",
            tags?["title"] ?? "",
        ].joined(separator: "\u{0}")
        return ChapterNode(
            id: MediaStableIdentifier.make(scope: "chapter", value: stableValue),
            title: tags?["title"] ?? id.map { "Chapter \($0 + 1)" } ?? "Chapter",
            start: startTime.flatMap(Double.init).flatMap(MediaTime.init(seconds:)) ?? .zero,
            end: endTime.flatMap(Double.init).flatMap(MediaTime.init(seconds:)),
            language: tags?["language"]
        )
    }
}
