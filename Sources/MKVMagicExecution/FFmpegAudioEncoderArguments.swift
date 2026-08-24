import Foundation
import MKVMagicCore

enum FFmpegAudioEncoderArgumentsError: Error, Equatable, Sendable {
    case unsupportedTarget
}

struct FFmpegAudioEncoderArguments: Sendable {
    func make(
        outputIndex: Int,
        encoder: String,
        preset: AudioTranscodePreset,
        channels: Int,
        channelLayout: String,
        inputSampleRate: Int
    ) throws -> [String] {
        guard outputIndex >= 0,
            !encoder.isEmpty,
            encoder.utf8.count <= 64,
            encoder.utf8.allSatisfy({ $0.isSafeEncoderByte }),
            preset.preserves(channelLayout: channelLayout, channels: channels),
            let outputSampleRate = preset.outputSampleRate(forInput: inputSampleRate)
        else {
            throw FFmpegAudioEncoderArgumentsError.unsupportedTarget
        }
        var arguments = [
            "-c:a:\(outputIndex)", encoder,
            "-ar:a:\(outputIndex)", String(outputSampleRate),
            "-ac:a:\(outputIndex)", String(channels),
            "-channel_layout:a:\(outputIndex)", channelLayout,
        ]
        if let bitrate = preset.recommendedBitrate(channels: channels) {
            arguments += ["-b:a:\(outputIndex)", String(bitrate)]
        }
        if preset == .opusQuality {
            arguments += ["-application:a:\(outputIndex)", "audio"]
            if channels > 2 {
                arguments += ["-mapping_family:a:\(outputIndex)", "1"]
            }
        }
        return arguments
    }
}

extension UInt8 {
    fileprivate var isSafeEncoderByte: Bool {
        (48...57).contains(self) || (65...90).contains(self) || (97...122).contains(self)
            || self == 95 || self == 45
    }
}
