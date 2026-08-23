import Foundation
import MKVMagicCore
import MKVMagicSystem

public enum MediaInspectionError: Error, Equatable, Sendable {
    case unsafeInput
    case toolFailed(exitCode: Int32, message: String)
    case malformedResponse
}

public protocol MediaInspecting: Sendable {
    func inspect(_ inputURL: URL) async throws -> MediaAsset
}

public struct FFprobeInspector<Runner: CommandRunning>: MediaInspecting {
    private let ffprobeURL: URL
    private let runner: Runner

    public init(ffprobeURL: URL, runner: Runner) {
        self.ffprobeURL = ffprobeURL
        self.runner = runner
    }

    public func inspect(_ inputURL: URL) async throws -> MediaAsset {
        let source = inputURL.standardizedFileURL
        guard source.isFileURL,
            source.path.hasPrefix("/"),
            let values = try? source.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw MediaInspectionError.unsafeInput
        }

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
                exitCode: result.exitCode,
                message: result.standardError.text
            )
        }

        let document: FFprobeDocument
        do {
            document = try JSONDecoder().decode(
                FFprobeDocument.self, from: result.standardOutput.data)
        } catch {
            throw MediaInspectionError.malformedResponse
        }
        return document.asset(sourceURL: source, fallbackSize: values.fileSize.map(Int64.init))
    }
}

private struct FFprobeDocument: Decodable {
    let streams: [FFprobeStream]?
    let chapters: [FFprobeChapter]?
    let format: FFprobeFormat?

    func asset(sourceURL: URL, fallbackSize: Int64?) -> MediaAsset {
        let formatNames = format?.formatName?.split(separator: ",") ?? []
        let normalizedTracks = (streams ?? []).map { $0.track }
        let normalizedChapters = (chapters ?? []).map { $0.chapter }
        return MediaAsset(
            sourceURL: sourceURL,
            container: formatNames.first.map(String.init) ?? sourceURL.pathExtension.lowercased(),
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
    let duration: String?
    let size: String?
    let bitRate: String?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case formatName = "format_name"
        case duration
        case size
        case bitRate = "bit_rate"
        case tags
    }
}

private struct FFprobeStream: Decodable {
    let index: Int
    let codecName: String?
    let codecType: String?
    let profile: String?
    let width: Int?
    let height: Int?
    let pixelFormat: String?
    let bitsPerRawSample: String?
    let sampleRate: String?
    let channels: Int?
    let channelLayout: String?
    let averageFrameRate: String?
    let disposition: [String: Int]?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case index
        case codecName = "codec_name"
        case codecType = "codec_type"
        case profile
        case width
        case height
        case pixelFormat = "pix_fmt"
        case bitsPerRawSample = "bits_per_raw_sample"
        case sampleRate = "sample_rate"
        case channels
        case channelLayout = "channel_layout"
        case averageFrameRate = "avg_frame_rate"
        case disposition
        case tags
    }

    var track: MediaTrack {
        let kind = MediaTrackKind(rawValue: codecType ?? "") ?? .unknown
        let dimensions = width.flatMap { resolvedWidth in
            height.map { MediaDimensions(width: resolvedWidth, height: $0) }
        }
        return MediaTrack(
            id: index,
            kind: kind,
            codec: codecName ?? "unknown",
            profile: profile,
            language: tags?["language"],
            title: tags?["title"],
            isDefault: disposition?["default"] == 1,
            isForced: disposition?["forced"] == 1,
            channels: channels,
            channelLayout: channelLayout,
            sampleRate: sampleRate.flatMap(Int.init),
            dimensions: dimensions,
            pixelFormat: pixelFormat,
            bitDepth: bitsPerRawSample.flatMap(Int.init),
            frameRate: averageFrameRate,
            tags: tags ?? [:]
        )
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

    var chapter: ChapterNode {
        ChapterNode(
            title: tags?["title"] ?? id.map { "Chapter \($0 + 1)" } ?? "Chapter",
            start: startTime.flatMap(Double.init).flatMap(MediaTime.init(seconds:)) ?? .zero,
            end: endTime.flatMap(Double.init).flatMap(MediaTime.init(seconds:)),
            language: tags?["language"]
        )
    }
}
