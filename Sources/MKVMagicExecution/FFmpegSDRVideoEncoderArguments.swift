import Foundation
import MKVMagicCore
import MKVMagicPlanning

enum FFmpegSDRVideoEncoderArgumentError: Error, Equatable, Sendable {
    case invalidChoice
}

/// Shared one-generation encoder arguments for reviewed BT.709 SDR output.
/// Join normalization and Exact Trim deliberately compile through one policy.
struct FFmpegSDRVideoEncoderArguments: Sendable {
    func make(
        outputIndex: Int,
        encoder: String,
        preset: VideoPreset,
        rateControl: JoinVideoRateControl
    ) throws -> [String] {
        var arguments = ["-c:v:\(outputIndex)", encoder]
        switch (preset, rateControl) {
        case (.av1Quality, .constantQuality(let quality)):
            guard (0...63).contains(quality) else {
                throw FFmpegSDRVideoEncoderArgumentError.invalidChoice
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
                throw FFmpegSDRVideoEncoderArgumentError.invalidChoice
            }
            arguments.append(contentsOf: [
                "-profile:v:\(outputIndex)", "main10",
                "-b:v:\(outputIndex)", String(bitrate),
                "-pix_fmt:v:\(outputIndex)", "p010le",
            ])
        case (.h264Compatibility, .averageBitrate(let bitrate)):
            guard (100_000...200_000_000).contains(bitrate) else {
                throw FFmpegSDRVideoEncoderArgumentError.invalidChoice
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
            throw FFmpegSDRVideoEncoderArgumentError.invalidChoice
        }
        arguments.append(contentsOf: [
            "-fps_mode:v:\(outputIndex)", "passthrough",
            "-color_primaries:v:\(outputIndex)", "bt709",
            "-color_trc:v:\(outputIndex)", "bt709",
            "-colorspace:v:\(outputIndex)", "bt709",
            "-color_range:v:\(outputIndex)", "tv",
        ])
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
}
