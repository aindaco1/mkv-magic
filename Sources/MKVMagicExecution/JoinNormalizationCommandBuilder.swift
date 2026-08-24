import Foundation
import MKVMagicCore
import MKVMagicPlanning

public enum JoinNormalizationCommandError: Error, Equatable, Sendable {
    case reportChanged
    case invalidPath
    case existingOutput
    case noEncodedLanes
    case inconsistentPlan
    case unavailableEncoder(VideoPreset)
    case unavailableAAC
    case missingFilter(String)
    case unsupportedDynamicRange(laneIndex: Int)
    case unsupportedAudioLayout(laneIndex: Int)
    case unsupportedSourceDuration(sourceIndex: Int)
    case commandTooLarge
}

extension JoinNormalizationCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .reportChanged:
            "The inspected join facts changed before the FFmpeg preview was compiled."
        case .invalidPath:
            "Every normalization input and output needs a safe absolute file path."
        case .existingOutput:
            "The normalization preview refuses to overwrite an existing output."
        case .noEncodedLanes:
            "This joined group has no video or audio lane that needs FFmpeg encoding."
        case .inconsistentPlan:
            "The resolved common-format choices do not match the inspected lane plan."
        case .unavailableEncoder(let preset):
            "The selected \(preset.rawValue) encoder did not pass the active local probe."
        case .unavailableAAC:
            "The bundled AAC encoder did not pass the active local probe."
        case .missingFilter(let filter):
            "Bundled FFmpeg did not report the required \(filter) filter."
        case .unsupportedDynamicRange(let laneIndex):
            "Video lane \(laneIndex + 1) needs HDR/color conversion that is not executable yet."
        case .unsupportedAudioLayout(let laneIndex):
            "Audio lane \(laneIndex + 1) uses a channel layout that is not supported safely yet."
        case .unsupportedSourceDuration(let sourceIndex):
            "Part \(sourceIndex + 1) needs a known positive duration before its normalized timeline can be compiled."
        case .commandTooLarge:
            "The fused FFmpeg preview exceeds the bounded command size."
        }
    }
}

public struct JoinNormalizationFFmpegCommand: Equatable, Sendable {
    public let arguments: [String]
    public let outputURL: URL
    public let encodedVideoLaneIndices: [Int]
    public let encodedAudioLaneIndices: [Int]

    public init(
        arguments: [String],
        outputURL: URL,
        encodedVideoLaneIndices: [Int],
        encodedAudioLaneIndices: [Int]
    ) {
        self.arguments = arguments
        self.outputURL = outputURL
        self.encodedVideoLaneIndices = encodedVideoLaneIndices
        self.encodedAudioLaneIndices = encodedAudioLaneIndices
    }
}

/// Compiles every affected video and audio lane into one FFmpeg invocation.
/// Compatible packet-copy lanes, subtitles, attachments, metadata, chapters,
/// final MKV assembly, execution, and verification remain separate stages.
public struct JoinNormalizationCommandBuilder: Sendable {
    public init() {}

    public func build(
        sources: [MediaAsset],
        resolvedPlan: ResolvedJoinNormalizationPlan,
        capabilities: FFmpegEncodingCapabilities,
        outputURL rawOutputURL: URL
    ) throws -> JoinNormalizationFFmpegCommand {
        let proposal = resolvedPlan.proposal
        let mapping = proposal.report.mapping
        let currentReport = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: mapping
        )
        guard JoinCompatibilityReportSnapshot(currentReport, sources: sources) == proposal.report
        else {
            throw JoinNormalizationCommandError.reportChanged
        }
        guard proposal.blockers.isEmpty else {
            throw JoinNormalizationCommandError.inconsistentPlan
        }
        let outputURL = rawOutputURL.standardizedFileURL
        guard safeAbsolutePath(outputURL), outputURL.pathExtension.lowercased() == "mkv",
            sources.allSatisfy({ safeAbsolutePath($0.sourceURL.standardizedFileURL) }),
            !sources.contains(where: { $0.sourceURL.standardizedFileURL == outputURL })
        else {
            throw JoinNormalizationCommandError.invalidPath
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw JoinNormalizationCommandError.existingOutput
        }
        if let missing = capabilities.missingJoinFilters.first {
            throw JoinNormalizationCommandError.missingFilter(missing)
        }

        let indexedTracks = sources.map {
            Dictionary(uniqueKeysWithValues: $0.tracks.map { ($0.id, $0) })
        }
        let videoLanes = proposal.videoLanes.filter(\.encodesVideo).sorted {
            $0.laneIndex < $1.laneIndex
        }
        let audioLanes = proposal.audioLanes.filter(\.encodesAudio).sorted {
            $0.laneIndex < $1.laneIndex
        }
        guard !videoLanes.isEmpty || !audioLanes.isEmpty else {
            throw JoinNormalizationCommandError.noEncodedLanes
        }

        let videoArguments = FFmpegVideoEncoderArguments()
        var graphParts = [String]()
        var videoOutputs = [
            (
                laneIndex: Int,
                label: String,
                choice: JoinVideoTargetChoice,
                hdr10Signal: MediaHDR10Signal?
            )
        ]()
        for lane in videoLanes {
            guard mapping.lanes.indices.contains(lane.laneIndex),
                let choice = resolvedPlan.choices.videoTargetsByLane[lane.laneIndex],
                lane.recommendedPreset == choice.preset,
                lane.recommendedCanvas == choice.canvas,
                lane.recommendedDynamicRange == choice.dynamicRange,
                lane.dynamicRangeChoices == [choice.dynamicRange],
                choice.canvas.width.isMultiple(of: 2), choice.canvas.height.isMultiple(of: 2)
            else {
                if lane.dynamicRangeChoices.count != 1
                    || !lane.dynamicRangeChoices.contains(
                        resolvedPlan.choices.videoTargetsByLane[lane.laneIndex]?.dynamicRange
                            ?? .sdr
                    )
                {
                    throw JoinNormalizationCommandError.unsupportedDynamicRange(
                        laneIndex: lane.laneIndex
                    )
                }
                throw JoinNormalizationCommandError.inconsistentPlan
            }
            guard capabilities.verifiedEncoder(for: choice.preset) != nil else {
                throw JoinNormalizationCommandError.unavailableEncoder(choice.preset)
            }
            let mappingLane = mapping.lanes[lane.laneIndex]
            let hdr10Signal: MediaHDR10Signal?
            switch choice.dynamicRange {
            case .sdr:
                hdr10Signal = nil
            case .hdr10:
                guard choice.preset == .av1Quality || choice.preset == .hevcCompatibility else {
                    throw JoinNormalizationCommandError.unsupportedDynamicRange(
                        laneIndex: lane.laneIndex
                    )
                }
                let signals = sources.indices.compactMap { sourceIndex in
                    mappingLane.trackIDsBySource[sourceIndex]
                        .flatMap { indexedTracks[sourceIndex][$0] }
                        .flatMap(MediaHDR10Signal.init(track:))
                }
                guard signals.count == sources.count, let first = signals.first,
                    signals.allSatisfy({ $0 == first })
                else {
                    throw JoinNormalizationCommandError.unsupportedDynamicRange(
                        laneIndex: lane.laneIndex
                    )
                }
                hdr10Signal = first
            }
            var inputLabels = [String]()
            for sourceIndex in sources.indices {
                guard let trackID = mappingLane.trackIDsBySource[sourceIndex],
                    let track = indexedTracks[sourceIndex][trackID]
                else {
                    throw JoinNormalizationCommandError.unsupportedDynamicRange(
                        laneIndex: lane.laneIndex
                    )
                }
                let isReviewedDynamicRange =
                    switch choice.dynamicRange {
                    case .sdr:
                        MediaHDR10Signal.isBT709SDR(track)
                    case .hdr10:
                        MediaHDR10Signal(track: track) == hdr10Signal
                    }
                guard isReviewedDynamicRange else {
                    throw JoinNormalizationCommandError.unsupportedDynamicRange(
                        laneIndex: lane.laneIndex
                    )
                }
                guard let duration = sources[sourceIndex].duration,
                    duration.nanoseconds > 0
                else {
                    throw JoinNormalizationCommandError.unsupportedSourceDuration(
                        sourceIndex: sourceIndex
                    )
                }
                let label = "jv\(lane.laneIndex)s\(sourceIndex)"
                graphParts.append(
                    "[\(sourceIndex):\(trackID)]setpts=PTS-STARTPTS,"
                        + "scale=w=\(choice.canvas.width):h=\(choice.canvas.height):"
                        + "force_original_aspect_ratio=decrease:flags=lanczos,"
                        + "pad=w=\(choice.canvas.width):h=\(choice.canvas.height):"
                        + "x=(ow-iw)/2:y=(oh-ih)/2:color=black,"
                        + "format=\(videoArguments.filterPixelFormat(for: choice.preset)),"
                        + "\(videoArguments.setParamsFilter(for: choice.dynamicRange)),setsar=1,"
                        + "tpad=stop_mode=clone:stop_duration=\(decimalSeconds(duration)),"
                        + "trim=duration=\(decimalSeconds(duration)),"
                        + "setpts=PTS-STARTPTS[\(label)]"
                )
                inputLabels.append("[\(label)]")
            }
            let outputLabel = "jv\(lane.laneIndex)"
            graphParts.append(
                inputLabels.joined()
                    + "concat=n=\(sources.count):v=1:a=0[\(outputLabel)]"
            )
            videoOutputs.append((lane.laneIndex, outputLabel, choice, hdr10Signal))
        }

        var audioOutputs = [(laneIndex: Int, label: String, choice: JoinAudioTargetChoice)]()
        for lane in audioLanes {
            guard mapping.lanes.indices.contains(lane.laneIndex),
                let choice = resolvedPlan.choices.audioTargetsByLane[lane.laneIndex],
                let aacEncoder = capabilities.aacEncoder, capabilities.aac == .verified,
                let safeLayout = safeAudioLayout(choice.channelLayout, channels: choice.channels)
            else {
                if capabilities.aac != .verified || capabilities.aacEncoder == nil {
                    throw JoinNormalizationCommandError.unavailableAAC
                }
                throw JoinNormalizationCommandError.unsupportedAudioLayout(
                    laneIndex: lane.laneIndex
                )
            }
            let mappingLane = mapping.lanes[lane.laneIndex]
            var inputLabels = [String]()
            for sourceIndex in sources.indices {
                let label = "ja\(lane.laneIndex)s\(sourceIndex)"
                guard let trackID = mappingLane.trackIDsBySource[sourceIndex] else {
                    guard choice.allowsSyntheticSilence,
                        let duration = sources[sourceIndex].duration,
                        duration.nanoseconds > 0
                    else {
                        throw JoinNormalizationCommandError.unsupportedSourceDuration(
                            sourceIndex: sourceIndex
                        )
                    }
                    graphParts.append(
                        "anullsrc=r=\(choice.sampleRate):cl=\(safeLayout),"
                            + "atrim=end=\(decimalSeconds(duration)),"
                            + "asetpts=PTS-STARTPTS[\(label)]"
                    )
                    inputLabels.append("[\(label)]")
                    continue
                }
                guard let track = indexedTracks[sourceIndex][trackID],
                    safeAudioLayout(track.channelLayout ?? "", channels: track.channels ?? 0)
                        != nil,
                    let duration = sources[sourceIndex].duration,
                    duration.nanoseconds > 0
                else {
                    if sources[sourceIndex].duration?.nanoseconds ?? 0 <= 0 {
                        throw JoinNormalizationCommandError.unsupportedSourceDuration(
                            sourceIndex: sourceIndex
                        )
                    }
                    throw JoinNormalizationCommandError.unsupportedAudioLayout(
                        laneIndex: lane.laneIndex
                    )
                }
                let sampleFormat = aacEncoder == "aac_at" ? "s16" : "fltp"
                graphParts.append(
                    "[\(sourceIndex):\(trackID)]"
                        + "aresample=\(choice.sampleRate):first_pts=0,"
                        + "aformat=sample_fmts=\(sampleFormat):"
                        + "sample_rates=\(choice.sampleRate):channel_layouts=\(safeLayout),"
                        + "apad=pad_dur=\(decimalSeconds(duration)),"
                        + "atrim=end=\(decimalSeconds(duration)),"
                        + "asetpts=PTS-STARTPTS[\(label)]"
                )
                inputLabels.append("[\(label)]")
            }
            let outputLabel = "ja\(lane.laneIndex)"
            graphParts.append(
                inputLabels.joined()
                    + "concat=n=\(sources.count):v=0:a=1[\(outputLabel)]"
            )
            audioOutputs.append((lane.laneIndex, outputLabel, choice))
        }

        let graph = graphParts.joined(separator: ";")
        guard !graph.isEmpty, graph.utf8.count <= Self.maximumCommandBytes else {
            throw JoinNormalizationCommandError.commandTooLarge
        }
        var arguments = ["-hide_banner", "-nostdin", "-loglevel", "error"]
        for (sourceIndex, source) in sources.enumerated() {
            for output in videoOutputs where output.hdr10Signal != nil {
                guard
                    let trackID = mapping.lanes[output.laneIndex]
                        .trackIDsBySource[sourceIndex],
                    let signal = output.hdr10Signal
                else {
                    throw JoinNormalizationCommandError.inconsistentPlan
                }
                arguments.append(
                    contentsOf: videoArguments.inputMetadataArguments(
                        signal,
                        streamSpecifier: String(trackID)
                    )
                )
            }
            arguments.append(contentsOf: ["-i", source.sourceURL.standardizedFileURL.path])
        }
        arguments.append(contentsOf: ["-filter_complex", graph])
        for (outputIndex, output) in videoOutputs.enumerated() {
            guard let encoder = capabilities.verifiedEncoder(for: output.choice.preset) else {
                throw JoinNormalizationCommandError.unavailableEncoder(output.choice.preset)
            }
            arguments.append(contentsOf: ["-map", "[\(output.label)]"])
            do {
                arguments.append(
                    contentsOf: try videoArguments.make(
                        outputIndex: outputIndex,
                        encoder: encoder,
                        preset: output.choice.preset,
                        rateControl: output.choice.rateControl,
                        dynamicRange: output.choice.dynamicRange,
                        hdr10Signal: output.hdr10Signal
                    )
                )
            } catch {
                throw JoinNormalizationCommandError.inconsistentPlan
            }
        }
        for (outputIndex, output) in audioOutputs.enumerated() {
            guard let aacEncoder = capabilities.aacEncoder, capabilities.aac == .verified else {
                throw JoinNormalizationCommandError.unavailableAAC
            }
            arguments.append(contentsOf: [
                "-map", "[\(output.label)]",
                "-c:a:\(outputIndex)", aacEncoder,
                "-b:a:\(outputIndex)", String(output.choice.bitrate),
                "-ar:a:\(outputIndex)", String(output.choice.sampleRate),
                "-ac:a:\(outputIndex)", String(output.choice.channels),
            ])
        }
        arguments.append(contentsOf: [
            "-map_metadata", "-1", "-map_chapters", "-1",
            "-f", "matroska", outputURL.path,
        ])
        let commandBytes = arguments.reduce(0) { $0 + $1.utf8.count + 1 }
        guard arguments.count <= Self.maximumArguments, commandBytes <= Self.maximumCommandBytes
        else {
            throw JoinNormalizationCommandError.commandTooLarge
        }
        return JoinNormalizationFFmpegCommand(
            arguments: arguments,
            outputURL: outputURL,
            encodedVideoLaneIndices: videoOutputs.map(\.laneIndex),
            encodedAudioLaneIndices: audioOutputs.map(\.laneIndex)
        )
    }

    private func safeAudioLayout(_ layout: String, channels: Int) -> String? {
        let normalizedLayout = normalized(layout)
        let allowed: Set<String>
        switch channels {
        case 1: allowed = ["mono"]
        case 2: allowed = ["stereo"]
        case 6: allowed = ["5.1", "5.1(side)"]
        case 8: allowed = ["7.1", "7.1(wide)"]
        default: return nil
        }
        return allowed.contains(normalizedLayout) ? normalizedLayout : nil
    }

    private func safeAbsolutePath(_ url: URL) -> Bool {
        url.isFileURL && url.path.hasPrefix("/") && !url.path.contains("\0")
            && (1...4_096).contains(url.path.utf8.count)
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func decimalSeconds(_ duration: MediaTime) -> String {
        let whole = duration.nanoseconds / 1_000_000_000
        let fraction = duration.nanoseconds % 1_000_000_000
        return "\(whole).\(String(format: "%09lld", fraction))"
    }

    private static let maximumArguments = 10_000
    private static let maximumCommandBytes = 1_048_576
}
