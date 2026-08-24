import Foundation
import MKVMagicCore
import MKVMagicPlanning

public enum CompleteAudioConversionCommandError: Error, Equatable, Sendable {
    case inconsistentPlan
    case invalidPath
    case existingOutput
    case unavailableAudioPreset(AudioTranscodePreset)
    case commandTooLarge
}

extension CompleteAudioConversionCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .inconsistentPlan:
            "The audio command no longer matches its reviewed conversion plan."
        case .invalidPath:
            "Audio conversion needs safe absolute MKV source and output paths."
        case .existingOutput:
            "Audio conversion refuses to overwrite an existing output."
        case .unavailableAudioPreset(let preset):
            "The bundled \(preset.displayName) encoder did not pass the active local probe."
        case .commandTooLarge:
            "The bounded audio conversion command is too large."
        }
    }
}

public struct CompleteAudioConversionFFmpegCommand: Equatable, Sendable {
    public let arguments: [String]
    public let outputURL: URL
    public let encodedAudioTrackIDs: [Int]
    public let copiedTrackIDs: [Int]

    public init(
        arguments: [String],
        outputURL: URL,
        encodedAudioTrackIDs: [Int],
        copiedTrackIDs: [Int]
    ) {
        self.arguments = arguments
        self.outputURL = outputURL
        self.encodedAudioTrackIDs = encodedAudioTrackIDs
        self.copiedTrackIDs = copiedTrackIDs
    }
}

public struct CompleteAudioConversionCommandBuilder: Sendable {
    public init() {}

    public func build(
        resolvedPlan: ResolvedCompleteAudioConversionPlan,
        capabilities: FFmpegEncodingCapabilities,
        outputURL rawOutputURL: URL
    ) throws -> CompleteAudioConversionFFmpegCommand {
        let source = resolvedPlan.source
        let sourceURL = source.sourceURL.standardizedFileURL
        let outputURL = rawOutputURL.standardizedFileURL
        guard safeAbsolutePath(sourceURL), safeAbsolutePath(outputURL),
            sourceURL != outputURL,
            sourceURL.pathExtension.lowercased() == "mkv",
            outputURL.pathExtension.lowercased() == "mkv"
        else {
            throw CompleteAudioConversionCommandError.invalidPath
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompleteAudioConversionCommandError.existingOutput
        }
        guard
            let encoder = capabilities.verifiedAudioEncoder(for: resolvedPlan.preset)
        else {
            throw CompleteAudioConversionCommandError.unavailableAudioPreset(
                resolvedPlan.preset
            )
        }
        let current: ResolvedCompleteAudioConversionPlan
        do {
            current = try CompleteAudioConversionPlanner().resolve(
                source: source,
                preset: resolvedPlan.preset,
                availableAudioPresets: Set(capabilities.availableAudioPresets)
            )
        } catch {
            throw CompleteAudioConversionCommandError.inconsistentPlan
        }
        guard current == resolvedPlan else {
            throw CompleteAudioConversionCommandError.inconsistentPlan
        }

        var arguments = [
            "-hide_banner", "-nostdin", "-loglevel", "error",
            "-i", sourceURL.path,
        ]
        for trackID in resolvedPlan.trackIDsInOutputOrder {
            arguments.append(contentsOf: ["-map", "0:\(trackID)"])
        }
        if !source.attachments.isEmpty {
            arguments.append(contentsOf: ["-map", "0:t?"])
        }
        arguments.append(contentsOf: ["-c", "copy"])
        for (outputIndex, trackID) in resolvedPlan.audioTrackIDs.enumerated() {
            guard let track = source.tracks.first(where: { $0.id == trackID }),
                let channels = track.channels,
                let sampleRate = track.sampleRate,
                let channelLayout = track.channelLayout
            else {
                throw CompleteAudioConversionCommandError.inconsistentPlan
            }
            do {
                arguments.append(
                    contentsOf: try FFmpegAudioEncoderArguments().make(
                        outputIndex: outputIndex,
                        encoder: encoder,
                        preset: resolvedPlan.preset,
                        channels: channels,
                        channelLayout: channelLayout,
                        inputSampleRate: sampleRate
                    )
                )
            } catch {
                throw CompleteAudioConversionCommandError.inconsistentPlan
            }
        }
        arguments.append(contentsOf: [
            "-map_metadata", "0",
            "-map_chapters", "-1",
            "-max_muxing_queue_size", "4096",
            "-f", "matroska",
            outputURL.path,
        ])
        let bytes = arguments.reduce(0) { $0 + $1.utf8.count + 1 }
        guard arguments.count <= 10_000, bytes <= 1_048_576 else {
            throw CompleteAudioConversionCommandError.commandTooLarge
        }
        return CompleteAudioConversionFFmpegCommand(
            arguments: arguments,
            outputURL: outputURL,
            encodedAudioTrackIDs: resolvedPlan.audioTrackIDs,
            copiedTrackIDs: resolvedPlan.copiedTrackIDs
        )
    }

    private func safeAbsolutePath(_ url: URL) -> Bool {
        url.isFileURL && url.path.hasPrefix("/") && !url.path.contains("\0")
            && (1...4_096).contains(url.path.utf8.count)
    }
}
