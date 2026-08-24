import Foundation
import MKVMagicCore
import MKVMagicPlanning

public enum ExactTrimCommandError: Error, Equatable, Sendable {
    case inconsistentPlan
    case invalidPath
    case existingOutput
    case unavailableEncoder(VideoPreset)
    case unavailableAAC
    case commandTooLarge
}

extension ExactTrimCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .inconsistentPlan: "The Exact Trim command no longer matches its reviewed plan."
        case .invalidPath: "Exact Trim needs safe absolute MKV source and output paths."
        case .existingOutput: "Exact Trim refuses to overwrite an existing output."
        case .unavailableEncoder(let preset):
            "The selected \(preset.rawValue) encoder did not pass the active local probe."
        case .unavailableAAC: "The bundled AAC encoder did not pass the active local probe."
        case .commandTooLarge: "The bounded Exact Trim command is too large."
        }
    }
}

public struct ExactTrimFFmpegCommand: Equatable, Sendable {
    public let arguments: [String]
    public let outputURL: URL
    public let encodedVideoTrackID: Int
    public let encodedAudioTrackIDs: [Int]
    public let copiedAudioTrackIDs: [Int]

    public init(
        arguments: [String],
        outputURL: URL,
        encodedVideoTrackID: Int,
        encodedAudioTrackIDs: [Int],
        copiedAudioTrackIDs: [Int]
    ) {
        self.arguments = arguments
        self.outputURL = outputURL
        self.encodedVideoTrackID = encodedVideoTrackID
        self.encodedAudioTrackIDs = encodedAudioTrackIDs
        self.copiedAudioTrackIDs = copiedAudioTrackIDs
    }
}

public struct ExactTrimCommandBuilder: Sendable {
    public init() {}

    public func build(
        resolvedPlan: ResolvedExactTrimPlan,
        capabilities: FFmpegEncodingCapabilities,
        outputURL rawOutputURL: URL
    ) throws -> ExactTrimFFmpegCommand {
        let source = resolvedPlan.source
        let outputURL = rawOutputURL.standardizedFileURL
        let sourceURL = source.sourceURL.standardizedFileURL
        guard safeAbsolutePath(sourceURL), safeAbsolutePath(outputURL),
            sourceURL != outputURL,
            sourceURL.pathExtension.lowercased() == "mkv",
            outputURL.pathExtension.lowercased() == "mkv"
        else {
            throw ExactTrimCommandError.invalidPath
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ExactTrimCommandError.existingOutput
        }
        guard
            let encoder = capabilities.verifiedEncoder(
                for: resolvedPlan.choice.videoPreset
            )
        else {
            throw ExactTrimCommandError.unavailableEncoder(
                resolvedPlan.choice.videoPreset
            )
        }
        if resolvedPlan.choice.audioPolicy == .aacPreserveLayout,
            capabilities.aac != .verified || capabilities.aacEncoder == nil
        {
            throw ExactTrimCommandError.unavailableAAC
        }
        let current: ResolvedExactTrimPlan
        do {
            current = try ExactTrimPlanner().resolve(
                source: source,
                range: resolvedPlan.range,
                choice: resolvedPlan.choice,
                availableVideoPresets: Set(capabilities.availableVideoPresets),
                aacAvailable: capabilities.aac == .verified
            )
        } catch {
            throw ExactTrimCommandError.inconsistentPlan
        }
        guard current == resolvedPlan else {
            throw ExactTrimCommandError.inconsistentPlan
        }
        let duration = resolvedPlan.range.end.nanoseconds.subtractingReportingOverflow(
            resolvedPlan.range.start.nanoseconds
        )
        guard !duration.overflow, duration.partialValue > 0 else {
            throw ExactTrimCommandError.inconsistentPlan
        }

        let videoArguments = FFmpegVideoEncoderArguments()
        var arguments = ["-hide_banner", "-nostdin", "-loglevel", "error"]
        if let hdr10Signal = resolvedPlan.hdr10Signal {
            arguments.append(
                contentsOf: videoArguments.inputMetadataArguments(
                    hdr10Signal,
                    streamSpecifier: "v:0"
                )
            )
        }
        arguments.append(contentsOf: [
            "-i", sourceURL.path,
            // Output-side seeking discards every stream before the reviewed in-point.
            // Input-side accurate seeking cannot discard early packets on copied audio.
            "-ss", decimalSeconds(resolvedPlan.range.start),
        ])
        for trackID in resolvedPlan.trackIDsInOutputOrder {
            arguments.append(contentsOf: ["-map", "0:\(trackID)"])
        }
        if !source.attachments.isEmpty {
            arguments.append(contentsOf: ["-map", "0:t?"])
        }
        arguments.append(contentsOf: ["-c", "copy"])
        if resolvedPlan.videoDynamicRange == .hdr10 {
            arguments.append(contentsOf: [
                "-filter:v:0",
                videoArguments.setParamsFilter(for: .hdr10),
            ])
        }
        do {
            arguments.append(
                contentsOf: try videoArguments.make(
                    outputIndex: 0,
                    encoder: encoder,
                    preset: resolvedPlan.choice.videoPreset,
                    rateControl: resolvedPlan.choice.videoRateControl,
                    dynamicRange: resolvedPlan.videoDynamicRange,
                    hdr10Signal: resolvedPlan.hdr10Signal
                )
            )
        } catch {
            throw ExactTrimCommandError.inconsistentPlan
        }

        var encodedAudioTrackIDs = [Int]()
        var copiedAudioTrackIDs = [Int]()
        switch resolvedPlan.choice.audioPolicy {
        case .packetCopy:
            copiedAudioTrackIDs = resolvedPlan.audioTrackIDs
        case .aacPreserveLayout:
            guard capabilities.aac == .verified, let aacEncoder = capabilities.aacEncoder else {
                throw ExactTrimCommandError.unavailableAAC
            }
            encodedAudioTrackIDs = resolvedPlan.audioTrackIDs
            for (outputIndex, trackID) in resolvedPlan.audioTrackIDs.enumerated() {
                guard let track = source.tracks.first(where: { $0.id == trackID }),
                    let channels = track.channels,
                    let sampleRate = track.sampleRate
                else {
                    throw ExactTrimCommandError.inconsistentPlan
                }
                arguments.append(contentsOf: [
                    "-c:a:\(outputIndex)", aacEncoder,
                    "-b:a:\(outputIndex)", String(aacBitrate(channels: channels)),
                    "-ar:a:\(outputIndex)", String(sampleRate),
                    "-ac:a:\(outputIndex)", String(channels),
                ])
            }
        }
        arguments.append(contentsOf: [
            "-map_metadata", "0",
            "-map_chapters", "-1",
            "-t", decimalSeconds(MediaTime(nanoseconds: duration.partialValue)),
            "-avoid_negative_ts", "make_zero",
            "-max_muxing_queue_size", "4096",
            "-f", "matroska",
            outputURL.path,
        ])
        let bytes = arguments.reduce(0) { $0 + $1.utf8.count + 1 }
        guard arguments.count <= 10_000, bytes <= 1_048_576 else {
            throw ExactTrimCommandError.commandTooLarge
        }
        return ExactTrimFFmpegCommand(
            arguments: arguments,
            outputURL: outputURL,
            encodedVideoTrackID: resolvedPlan.videoTrackID,
            encodedAudioTrackIDs: encodedAudioTrackIDs,
            copiedAudioTrackIDs: copiedAudioTrackIDs
        )
    }

    private func aacBitrate(channels: Int) -> Int {
        switch channels {
        case 1: 128_000
        case 2: 192_000
        case 3...6: 640_000
        default: 768_000
        }
    }

    private func decimalSeconds(_ time: MediaTime) -> String {
        let whole = time.nanoseconds / 1_000_000_000
        let fraction = time.nanoseconds % 1_000_000_000
        return "\(whole).\(String(format: "%09lld", fraction))"
    }

    private func safeAbsolutePath(_ url: URL) -> Bool {
        url.isFileURL && url.path.hasPrefix("/") && !url.path.contains("\0")
            && (1...4_096).contains(url.path.utf8.count)
    }
}
