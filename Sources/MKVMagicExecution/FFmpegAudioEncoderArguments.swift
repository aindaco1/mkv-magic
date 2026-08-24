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
            let outputSampleRate = preset.outputSampleRate(forInput: inputSampleRate)
        else {
            throw FFmpegAudioEncoderArgumentsError.unsupportedTarget
        }
        let encoderLayout = try filterChannelLayout(
            encoder: encoder,
            preset: preset,
            channels: channels,
            outputChannelLayout: channelLayout
        )
        var arguments = [
            "-c:a:\(outputIndex)", encoder,
            "-ar:a:\(outputIndex)", String(outputSampleRate),
            "-ac:a:\(outputIndex)", String(channels),
            "-channel_layout:a:\(outputIndex)", encoderLayout,
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

    /// Some encoders name their input order differently from the layout that
    /// Matroska/FFprobe reports after reopening. Keep that adapter bounded and
    /// encoder-specific so the reviewed output layout remains stable.
    func filterChannelLayout(
        encoder: String,
        preset: AudioTranscodePreset,
        channels: Int,
        outputChannelLayout: String
    ) throws -> String {
        guard !encoder.isEmpty,
            encoder.utf8.count <= 64,
            encoder.utf8.allSatisfy({ $0.isSafeEncoderByte }),
            preset.preserves(channelLayout: outputChannelLayout, channels: channels)
        else {
            throw FFmpegAudioEncoderArgumentsError.unsupportedTarget
        }
        let layout = outputChannelLayout.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard preset == .aacCompatibility, encoder == "aac_at" else { return layout }
        switch layout {
        case "5.0": return "5.0(side)"
        case "5.1": return "5.1(side)"
        default: return layout
        }
    }
}

extension UInt8 {
    fileprivate var isSafeEncoderByte: Bool {
        (48...57).contains(self) || (65...90).contains(self) || (97...122).contains(self)
            || self == 95 || self == 45
    }
}
