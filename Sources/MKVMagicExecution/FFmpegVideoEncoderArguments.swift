import Foundation
import MKVMagicCore
import MKVMagicPlanning

enum FFmpegVideoEncoderArgumentError: Error, Equatable, Sendable {
    case invalidChoice
}

/// Shared one-generation encoder and color-signal arguments. Join
/// normalization and Exact Trim deliberately compile through one policy.
struct FFmpegVideoEncoderArguments: Sendable {
    func make(
        outputIndex: Int,
        encoder: String,
        preset: VideoPreset,
        rateControl: JoinVideoRateControl,
        dynamicRange: JoinVideoDynamicRangeTarget = .sdr,
        hdr10Signal: MediaHDR10Signal? = nil
    ) throws -> [String] {
        switch (dynamicRange, hdr10Signal) {
        case (.sdr, nil):
            break
        case (.hdr10, .some):
            guard preset == .av1Quality || preset == .hevcCompatibility else {
                throw FFmpegVideoEncoderArgumentError.invalidChoice
            }
        default:
            throw FFmpegVideoEncoderArgumentError.invalidChoice
        }

        var arguments = ["-c:v:\(outputIndex)", encoder]
        switch (preset, rateControl) {
        case (.av1Quality, .constantQuality(let quality)):
            guard (0...63).contains(quality) else {
                throw FFmpegVideoEncoderArgumentError.invalidChoice
            }
            // Pin SVT's balanced default so an upstream default change cannot
            // silently alter the reviewed speed/quality impact of a workflow.
            if encoder == "libsvtav1" {
                arguments.append(contentsOf: ["-preset:v:\(outputIndex)", "8"])
            }
            arguments.append(contentsOf: [
                "-crf:v:\(outputIndex)", String(quality),
                "-b:v:\(outputIndex)", "0",
                "-pix_fmt:v:\(outputIndex)", "yuv420p10le",
            ])
        case (.hevcCompatibility, .averageBitrate(let bitrate)):
            guard (100_000...200_000_000).contains(bitrate) else {
                throw FFmpegVideoEncoderArgumentError.invalidChoice
            }
            arguments.append(contentsOf: [
                "-profile:v:\(outputIndex)", "main10",
                "-b:v:\(outputIndex)", String(bitrate),
                "-pix_fmt:v:\(outputIndex)", "p010le",
            ])
        case (.h264Compatibility, .averageBitrate(let bitrate)):
            guard (100_000...200_000_000).contains(bitrate) else {
                throw FFmpegVideoEncoderArgumentError.invalidChoice
            }
            arguments.append(contentsOf: [
                "-profile:v:\(outputIndex)", "high",
                "-b:v:\(outputIndex)", String(bitrate),
                "-pix_fmt:v:\(outputIndex)", "yuv420p",
            ])
        case (.proRes, .codecDefault):
            arguments.append(contentsOf: [
                "-profile:v:\(outputIndex)", "3",
                "-pix_fmt:v:\(outputIndex)", "yuv422p10le",
            ])
        default:
            throw FFmpegVideoEncoderArgumentError.invalidChoice
        }

        arguments.append(contentsOf: ["-fps_mode:v:\(outputIndex)", "passthrough"])
        switch dynamicRange {
        case .sdr:
            arguments.append(contentsOf: [
                "-color_primaries:v:\(outputIndex)", "bt709",
                "-color_trc:v:\(outputIndex)", "bt709",
                "-colorspace:v:\(outputIndex)", "bt709",
                "-color_range:v:\(outputIndex)", "tv",
            ])
        case .hdr10:
            arguments.append(contentsOf: [
                "-color_primaries:v:\(outputIndex)", "9",
                "-color_trc:v:\(outputIndex)", "16",
                "-colorspace:v:\(outputIndex)", "9",
                "-color_range:v:\(outputIndex)", "1",
            ])
            if encoder == "libsvtav1" {
                arguments.append(contentsOf: [
                    "-svtav1-params:v:\(outputIndex)",
                    "color-primaries=bt2020:transfer-characteristics=smpte2084:"
                        + "matrix-coefficients=bt2020-ncl:color-range=studio",
                ])
            }
        }
        return arguments
    }

    func filterPixelFormat(for preset: VideoPreset) -> String {
        switch preset {
        case .av1Quality: "yuv420p10le"
        case .hevcCompatibility: "p010le"
        case .h264Compatibility: "yuv420p"
        case .proRes: "yuv422p10le"
        }
    }

    func setParamsFilter(for dynamicRange: JoinVideoDynamicRangeTarget) -> String {
        switch dynamicRange {
        case .sdr:
            "setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709"
        case .hdr10:
            "setparams=range=limited:color_primaries=bt2020:color_trc=smpte2084:"
                + "colorspace=bt2020nc"
        }
    }

    func inputMetadataArguments(
        _ signal: MediaHDR10Signal,
        streamSpecifier: String
    ) -> [String] {
        var arguments = [String]()
        if let metadata = signal.masteringDisplayMetadata {
            arguments.append(contentsOf: [
                "-mastering_display:\(streamSpecifier)",
                "G(\(metadata.greenX),\(metadata.greenY))"
                    + "B(\(metadata.blueX),\(metadata.blueY))"
                    + "R(\(metadata.redX),\(metadata.redY))"
                    + "WP(\(metadata.whitePointX),\(metadata.whitePointY))"
                    + "L(\(metadata.maxLuminance),\(metadata.minLuminance))",
            ])
        }
        if let metadata = signal.contentLightLevelMetadata {
            arguments.append(contentsOf: [
                "-content_light:\(streamSpecifier)",
                "\(metadata.maxContentLightLevel),\(metadata.maxFrameAverageLightLevel)",
            ])
        }
        return arguments
    }
}
