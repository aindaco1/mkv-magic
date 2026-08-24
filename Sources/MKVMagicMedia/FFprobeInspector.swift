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
            // ISO Base Media stores the user-visible per-track name under
            // `name`; Matroska exposes the same concept as `title`.
            title: tags?["title"] ?? tags?["name"],
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
            masteringDisplayMetadata: normalizedMasteringDisplayMetadata,
            contentLightLevelMetadata: normalizedContentLightLevelMetadata,
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
        if types.contains(where: {
            $0.localizedCaseInsensitiveContains("HDR Dynamic Metadata SMPTE2094-40")
                || $0.localizedCaseInsensitiveContains("HDR10+")
        }) {
            formats.insert("HDR10+")
        }
        return formats.sorted()
    }

    private var normalizedMasteringDisplayMetadata: MediaMasteringDisplayMetadata? {
        guard
            let data = sideData?.first(where: {
                $0.type.localizedCaseInsensitiveContains("Mastering display")
            }),
            let redX = data.redX.scaledInteger(denominator: 50_000),
            let redY = data.redY.scaledInteger(denominator: 50_000),
            let greenX = data.greenX.scaledInteger(denominator: 50_000),
            let greenY = data.greenY.scaledInteger(denominator: 50_000),
            let blueX = data.blueX.scaledInteger(denominator: 50_000),
            let blueY = data.blueY.scaledInteger(denominator: 50_000),
            let whitePointX = data.whitePointX.scaledInteger(denominator: 50_000),
            let whitePointY = data.whitePointY.scaledInteger(denominator: 50_000),
            let maxLuminance = data.maxLuminance.scaledInteger(denominator: 10_000),
            let minLuminance = data.minLuminance.scaledInteger(denominator: 10_000),
            [redX, redY, greenX, greenY, blueX, blueY, whitePointX, whitePointY]
                .allSatisfy({ (0...50_000).contains($0) }),
            (1...1_000_000_000).contains(maxLuminance),
            (0...maxLuminance).contains(minLuminance)
        else {
            return nil
        }
        return MediaMasteringDisplayMetadata(
            redX: redX,
            redY: redY,
            greenX: greenX,
            greenY: greenY,
            blueX: blueX,
            blueY: blueY,
            whitePointX: whitePointX,
            whitePointY: whitePointY,
            maxLuminance: maxLuminance,
            minLuminance: minLuminance
        )
    }

    private var normalizedContentLightLevelMetadata: MediaContentLightLevelMetadata? {
        guard
            let data = sideData?.first(where: {
                $0.type.localizedCaseInsensitiveContains("Content light level")
            }),
            let maxContent = data.maxContent,
            let maxAverage = data.maxAverage,
            (0...65_535).contains(maxContent),
            (0...65_535).contains(maxAverage)
        else {
            return nil
        }
        return MediaContentLightLevelMetadata(
            maxContentLightLevel: maxContent,
            maxFrameAverageLightLevel: maxAverage
        )
    }
}

private struct FFprobeSideData: Decodable {
    let type: String
    let redX: String?
    let redY: String?
    let greenX: String?
    let greenY: String?
    let blueX: String?
    let blueY: String?
    let whitePointX: String?
    let whitePointY: String?
    let minLuminance: String?
    let maxLuminance: String?
    let maxContent: Int?
    let maxAverage: Int?

    enum CodingKeys: String, CodingKey {
        case type = "side_data_type"
        case redX = "red_x"
        case redY = "red_y"
        case greenX = "green_x"
        case greenY = "green_y"
        case blueX = "blue_x"
        case blueY = "blue_y"
        case whitePointX = "white_point_x"
        case whitePointY = "white_point_y"
        case minLuminance = "min_luminance"
        case maxLuminance = "max_luminance"
        case maxContent = "max_content"
        case maxAverage = "max_average"
    }
}

extension Optional where Wrapped == String {
    fileprivate func scaledInteger(denominator targetDenominator: Int64) -> Int64? {
        guard let value = self else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        let numerator: Int64
        let denominator: Int64
        if parts.count == 1 {
            guard let parsed = Int64(parts[0]) else { return nil }
            numerator = parsed
            denominator = 1
        } else if parts.count == 2,
            let parsedNumerator = Int64(parts[0]),
            let parsedDenominator = Int64(parts[1])
        {
            numerator = parsedNumerator
            denominator = parsedDenominator
        } else {
            return nil
        }
        guard numerator >= 0, denominator > 0, targetDenominator > 0 else { return nil }
        let product = numerator.multipliedReportingOverflow(by: targetDenominator)
        guard !product.overflow else { return nil }
        let quotient = product.partialValue / denominator
        let remainder = product.partialValue % denominator
        let doubledRemainder = remainder.multipliedReportingOverflow(by: 2)
        guard !doubledRemainder.overflow else { return nil }
        if doubledRemainder.partialValue >= denominator {
            let rounded = quotient.addingReportingOverflow(1)
            return rounded.overflow ? nil : rounded.partialValue
        }
        return quotient
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
