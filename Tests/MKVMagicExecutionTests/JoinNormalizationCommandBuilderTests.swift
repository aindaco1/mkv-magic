import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import XCTest

final class JoinNormalizationCommandBuilderTests: XCTestCase {
    func testBuildsOneBoundedVideoInvocationWithOneEncodedGeneration() throws {
        let sources = incompatibleVideoSources()
        let resolved = try resolve(
            sources: sources,
            mapping: mapping(video: [0, 0]),
            preset: .hevcCompatibility
        )
        let output = URL(fileURLWithPath: "/output/normalized-streams.mkv")

        let command = try JoinNormalizationCommandBuilder().build(
            sources: sources,
            resolvedPlan: resolved,
            capabilities: capabilities(),
            outputURL: output
        )

        XCTAssertEqual(command.outputURL, output)
        XCTAssertEqual(command.encodedVideoLaneIndices, [0])
        XCTAssertTrue(command.encodedAudioLaneIndices.isEmpty)
        XCTAssertEqual(command.arguments.filter { $0 == "-i" }.count, 2)
        XCTAssertEqual(command.arguments.filter { $0 == "-filter_complex" }.count, 1)
        XCTAssertEqual(command.arguments.filter { $0 == "hevc_videotoolbox" }.count, 1)
        XCTAssertEqual(command.arguments.filter { $0 == "-map" }.count, 1)
        XCTAssertFalse(command.arguments.contains("-y"))
        XCTAssertEqual(command.arguments.suffix(2), ["matroska", output.path])

        let graph = try XCTUnwrap(value(after: "-filter_complex", in: command.arguments))
        XCTAssertEqual(graph.components(separatedBy: "concat=n=2:v=1:a=0").count - 1, 1)
        XCTAssertEqual(graph.components(separatedBy: "scale=w=1920:h=1080").count - 1, 2)
        XCTAssertTrue(graph.contains("[0:0]setpts=PTS-STARTPTS"))
        XCTAssertTrue(graph.contains("[1:0]setpts=PTS-STARTPTS"))
        XCTAssertLessThan(graph.utf8.count, 1_048_576)
        XCTAssertEqual(value(after: "-map_metadata", in: command.arguments), "-1")
        XCTAssertEqual(value(after: "-map_chapters", in: command.arguments), "-1")
    }

    func testFusesVideoAndAudioLayoutNormalizationIntoOneGraph() throws {
        let sources = [
            asset(
                part: 1,
                tracks: [
                    video(id: 0, width: 1_920, height: 1_080),
                    audio(id: 1, channels: 2, sampleRate: 44_100),
                ]
            ),
            asset(
                part: 2,
                tracks: [
                    video(id: 0, width: 1_280, height: 720),
                    audio(id: 1, channels: 6, sampleRate: 48_000),
                ]
            ),
        ]
        let resolved = try resolve(
            sources: sources,
            mapping: mapping(video: [0, 0], audio: [1, 1]),
            preset: .hevcCompatibility
        )

        let command = try JoinNormalizationCommandBuilder().build(
            sources: sources,
            resolvedPlan: resolved,
            capabilities: capabilities(),
            outputURL: URL(fileURLWithPath: "/output/fused.mkv")
        )

        XCTAssertEqual(command.encodedVideoLaneIndices, [0])
        XCTAssertEqual(command.encodedAudioLaneIndices, [1])
        XCTAssertEqual(command.arguments.filter { $0 == "-filter_complex" }.count, 1)
        XCTAssertEqual(command.arguments.filter { $0 == "hevc_videotoolbox" }.count, 1)
        XCTAssertEqual(command.arguments.filter { $0 == "aac_at" }.count, 1)
        XCTAssertEqual(command.arguments.filter { $0 == "-map" }.count, 2)
        let graph = try XCTUnwrap(value(after: "-filter_complex", in: command.arguments))
        XCTAssertEqual(graph.components(separatedBy: "concat=n=2:v=1:a=0").count - 1, 1)
        XCTAssertEqual(graph.components(separatedBy: "concat=n=2:v=0:a=1").count - 1, 1)
        XCTAssertEqual(graph.components(separatedBy: "channel_layouts=5.1(side)").count - 1, 2)
    }

    func testSynthesizesOnlyExplicitlyApprovedMissingAudioForExactPartDuration() throws {
        let sources = [
            asset(part: 1, tracks: [audio(id: 0, channels: 2)]),
            asset(part: 2, tracks: [], duration: 1_250_000_001),
        ]
        let resolved = try resolve(
            sources: sources,
            mapping: mapping(audio: [0, nil]),
            allowsSyntheticSilence: true
        )

        let command = try JoinNormalizationCommandBuilder().build(
            sources: sources,
            resolvedPlan: resolved,
            capabilities: capabilities(),
            outputURL: URL(fileURLWithPath: "/output/with-silence.mkv")
        )

        let graph = try XCTUnwrap(value(after: "-filter_complex", in: command.arguments))
        XCTAssertTrue(graph.contains("anullsrc=r=48000:cl=stereo"))
        XCTAssertTrue(graph.contains("atrim=end=1.250000001"))
        XCTAssertEqual(command.encodedAudioLaneIndices, [0])
    }

    func testRejectsUnknownDurationBeforeSynthesizingSilence() throws {
        let known = asset(part: 1, tracks: [audio(id: 0, channels: 2)])
        let unknown = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Part 2.mkv"),
            container: "matroska,webm",
            tracks: []
        )
        let sources = [known, unknown]
        let resolved = try resolve(
            sources: sources,
            mapping: mapping(audio: [0, nil]),
            allowsSyntheticSilence: true
        )

        XCTAssertThrowsError(
            try JoinNormalizationCommandBuilder().build(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities(),
                outputURL: URL(fileURLWithPath: "/output/unknown-duration.mkv")
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationCommandError,
                .unsupportedSourceDuration(sourceIndex: 1)
            )
        }
    }

    func testRejectsHDRUntilExactColorPipelineIsExecutable() throws {
        let sources = [
            asset(part: 1, tracks: [video(id: 0)]),
            asset(part: 2, tracks: [hdr10Video(id: 0)]),
        ]
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping(video: [0, 0]),
            preferredVideoPreset: .hevcCompatibility
        )
        let choice = JoinVideoTargetChoice(
            preset: .hevcCompatibility,
            canvas: try XCTUnwrap(proposal.videoLanes[0].recommendedCanvas),
            frameRatePolicy: .preserveSourceTiming,
            dynamicRange: .sdr,
            rateControl: .averageBitrate(8_000_000)
        )
        let resolved = try JoinNormalizationChoiceResolver().resolve(
            sources: sources,
            proposal: proposal,
            choices: JoinNormalizationChoices(videoTargetsByLane: [0: choice]),
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )

        XCTAssertThrowsError(
            try JoinNormalizationCommandBuilder().build(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities(),
                outputURL: URL(fileURLWithPath: "/output/hdr.mkv")
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationCommandError,
                .unsupportedDynamicRange(laneIndex: 0)
            )
        }
    }

    func testRejectsCapabilityRegressionMissingFilterAndExistingOutput() throws {
        let sources = incompatibleVideoSources()
        let resolved = try resolve(
            sources: sources,
            mapping: mapping(video: [0, 0]),
            preset: .hevcCompatibility
        )
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-existing-\(UUID().uuidString).mkv"
        )
        try Data().write(to: output)
        defer { try? FileManager.default.removeItem(at: output) }

        XCTAssertThrowsError(
            try JoinNormalizationCommandBuilder().build(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities(hevcStatus: .declared),
                outputURL: URL(fileURLWithPath: "/output/no-encoder.mkv")
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationCommandError,
                .unavailableEncoder(.hevcCompatibility)
            )
        }

        var noScale = FFmpegEncodingCapabilities.requiredJoinFilters
        noScale.remove("scale")
        XCTAssertThrowsError(
            try JoinNormalizationCommandBuilder().build(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities(filters: noScale),
                outputURL: URL(fileURLWithPath: "/output/no-scale.mkv")
            )
        ) { error in
            XCTAssertEqual(error as? JoinNormalizationCommandError, .missingFilter("scale"))
        }

        XCTAssertThrowsError(
            try JoinNormalizationCommandBuilder().build(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities(),
                outputURL: output
            )
        ) { error in
            XCTAssertEqual(error as? JoinNormalizationCommandError, .existingOutput)
        }
    }

    func testRendersOnlyTheExplicitRateControlForEveryVideoPreset() throws {
        let cases: [(VideoPreset, JoinVideoRateControl, String, String)] = [
            (.av1Quality, .constantQuality(28), "libsvtav1", "-crf:v:0"),
            (.hevcCompatibility, .averageBitrate(8_000_000), "hevc_videotoolbox", "-b:v:0"),
            (.h264Compatibility, .averageBitrate(8_000_000), "h264_videotoolbox", "-b:v:0"),
            (.proRes, .codecDefault, "prores_ks", "-profile:v:0"),
        ]
        for (preset, rateControl, encoder, expectedFlag) in cases {
            let sources = incompatibleVideoSources()
            let resolved = try resolve(
                sources: sources,
                mapping: mapping(video: [0, 0]),
                preset: preset,
                rateControl: rateControl
            )
            let command = try JoinNormalizationCommandBuilder().build(
                sources: sources,
                resolvedPlan: resolved,
                capabilities: capabilities(),
                outputURL: URL(fileURLWithPath: "/output/\(preset.rawValue).mkv")
            )

            XCTAssertEqual(command.arguments.filter { $0 == encoder }.count, 1, preset.rawValue)
            XCTAssertTrue(command.arguments.contains(expectedFlag), preset.rawValue)
        }
    }

    private func resolve(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        preset: VideoPreset = .hevcCompatibility,
        rateControl explicitRateControl: JoinVideoRateControl? = nil,
        allowsSyntheticSilence: Bool = false
    ) throws -> ResolvedJoinNormalizationPlan {
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping,
            preferredVideoPreset: preset
        )
        var videoTargets = [Int: JoinVideoTargetChoice]()
        for lane in proposal.videoLanes where lane.encodesVideo {
            let rateControl: JoinVideoRateControl
            if let explicitRateControl {
                rateControl = explicitRateControl
            } else {
                rateControl =
                    switch preset {
                    case .av1Quality: .constantQuality(28)
                    case .hevcCompatibility, .h264Compatibility: .averageBitrate(8_000_000)
                    case .proRes: .codecDefault
                    }
            }
            videoTargets[lane.laneIndex] = JoinVideoTargetChoice(
                preset: preset,
                canvas: try XCTUnwrap(lane.recommendedCanvas),
                frameRatePolicy: try XCTUnwrap(lane.recommendedFrameRatePolicy),
                dynamicRange: try XCTUnwrap(lane.recommendedDynamicRange),
                rateControl: rateControl
            )
        }
        var audioTargets = [Int: JoinAudioTargetChoice]()
        for lane in proposal.audioLanes where lane.encodesAudio {
            audioTargets[lane.laneIndex] = JoinAudioTargetChoice(
                codec: try XCTUnwrap(lane.outputCodec),
                channels: try XCTUnwrap(lane.outputChannels),
                channelLayout: try XCTUnwrap(lane.outputChannelLayout),
                sampleRate: try XCTUnwrap(lane.outputSampleRate),
                bitrate: try XCTUnwrap(lane.outputBitrate),
                allowsSyntheticSilence: allowsSyntheticSilence
            )
        }
        let choices = JoinNormalizationChoices(
            videoTargetsByLane: videoTargets,
            audioTargetsByLane: audioTargets
        )
        return try JoinNormalizationChoiceResolver().resolve(
            sources: sources,
            proposal: proposal,
            choices: choices,
            availableVideoPresets: Set(capabilities().availableVideoPresets),
            aacAvailable: true
        )
    }

    private func capabilities(
        hevcStatus: FFmpegCapabilityStatus = .verified,
        filters: Set<String> = FFmpegEncodingCapabilities.requiredJoinFilters
    ) -> FFmpegEncodingCapabilities {
        FFmpegEncodingCapabilities(
            softwareAV1: .verified,
            softwareAV1Encoder: "libsvtav1",
            hevc10VideoToolbox: hevcStatus,
            h264VideoToolbox: .verified,
            proRes: .verified,
            proResEncoder: "prores_ks",
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: filters
        )
    }

    private func mapping(video: [Int?]? = nil, audio: [Int?]? = nil) -> JoinTrackMapping {
        var lanes = [JoinTrackLane]()
        if let video { lanes.append(JoinTrackLane(kind: .video, trackIDsBySource: video)) }
        if let audio { lanes.append(JoinTrackLane(kind: .audio, trackIDsBySource: audio)) }
        return JoinTrackMapping(lanes: lanes)
    }

    private func incompatibleVideoSources() -> [MediaAsset] {
        [
            asset(part: 1, tracks: [video(id: 0, width: 1_920, height: 1_080)]),
            asset(part: 2, tracks: [video(id: 0, width: 1_280, height: 720)]),
        ]
    }

    private func asset(
        part: Int,
        tracks: [MediaTrack],
        duration: Int64 = 1_000_000_000
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Part \(part).mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: duration),
            tracks: tracks
        )
    }

    private func video(
        id: Int,
        width: Int = 1_920,
        height: Int = 1_080
    ) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            profile: "High",
            level: 40,
            dimensions: MediaDimensions(width: width, height: height),
            displayDimensions: MediaDimensions(width: width, height: height),
            pixelFormat: "yuv420p",
            bitDepth: 8,
            frameRate: "24/1",
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt709",
                transfer: "bt709",
                matrix: "bt709"
            )
        )
    }

    private func hdr10Video(id: Int) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .video,
            codec: "hevc",
            codecID: "V_MPEGH/ISO/HEVC",
            profile: "Main 10",
            level: 153,
            dimensions: MediaDimensions(width: 3_840, height: 2_160),
            displayDimensions: MediaDimensions(width: 3_840, height: 2_160),
            pixelFormat: "yuv420p10le",
            bitDepth: 10,
            frameRate: "24/1",
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt2020",
                transfer: "smpte2084",
                matrix: "bt2020nc"
            ),
            hdrFormats: ["HDR10"]
        )
    }

    private func audio(id: Int, channels: Int, sampleRate: Int = 48_000) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            profile: "LC",
            language: "en",
            isDefault: true,
            channels: channels,
            channelLayout: channels == 2 ? "stereo" : "5.1(side)",
            sampleRate: sampleRate
        )
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}
