import Foundation
import MKVMagicCore
import MKVMagicPlanning
import XCTest

final class ExactTrimPlannerTests: XCTestCase {
    func testWholeFileIsRejectedAsATrimButResolvedAsOneTranscodeGeneration() throws {
        let source = makeSource()
        let fullRange = MediaTrimRange(
            start: .zero,
            end: try XCTUnwrap(source.duration)
        )
        let choice = ExactTrimChoice(
            videoPreset: .hevcCompatibility,
            videoRateControl: .averageBitrate(2_000_000)
        )
        XCTAssertThrowsError(
            try ExactTrimPlanner().resolve(
                source: source,
                range: fullRange,
                choice: choice,
                availableVideoPresets: [.hevcCompatibility],
                aacAvailable: true
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .noChange) }

        let transcode = try ExactTrimPlanner().resolve(
            source: source,
            range: fullRange,
            choice: choice,
            operation: .transcode,
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )

        XCTAssertEqual(transcode.operation, .transcode)
        XCTAssertEqual(transcode.range, fullRange)
        XCTAssertEqual(transcode.videoEncodeCount, 1)
        XCTAssertEqual(transcode.audioEncodeCount, 0)
        XCTAssertThrowsError(
            try ExactTrimPlanner().resolve(
                source: source,
                range: range(1, 9),
                choice: choice,
                operation: .transcode,
                availableVideoPresets: [.hevcCompatibility],
                aacAvailable: true
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .invalidRange) }
    }

    func testCommonVideoInputsResolveOnlyAsBoundedFullFileMKVTranscodes() throws {
        let chapters = [
            ChapterNode(
                title: "Opening",
                start: .zero,
                end: MediaTime(nanoseconds: 5_000_000_000),
                language: "en"
            ),
            ChapterNode(
                title: "Second Act",
                start: MediaTime(nanoseconds: 5_000_000_000),
                end: MediaTime(nanoseconds: 10_000_000_000),
                language: "en"
            ),
        ]
        let source = makeCommonSource(
            extension: "mp4",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            chapters: chapters,
            extraTrack: MediaTrack(id: 2, kind: .data, codec: "bin_data")
        )
        let choice = ExactTrimChoice(
            videoPreset: .h264Compatibility,
            videoRateControl: .averageBitrate(1_000_000)
        )
        let fullRange = MediaTrimRange(start: .zero, end: try XCTUnwrap(source.duration))
        let plan = try ExactTrimPlanner().resolve(
            source: source,
            range: fullRange,
            choice: choice,
            operation: .transcode,
            availableVideoPresets: [.h264Compatibility],
            aacAvailable: true
        )

        XCTAssertEqual(plan.sourceKind, .quickTime)
        XCTAssertEqual(plan.trackIDsInOutputOrder, [0, 1])
        XCTAssertEqual(plan.copiedAudioTrackIDs, [1])
        XCTAssertEqual(plan.subtitleTrackIDs, [])
        XCTAssertEqual(plan.videoEncodeCount, 1)
        XCTAssertTrue(ExactTrimPlanner().canOfferTranscode(for: source))
        XCTAssertThrowsError(
            try ExactTrimPlanner().resolve(
                source: source,
                range: range(1, 9),
                choice: choice,
                availableVideoPresets: [.h264Compatibility],
                aacAvailable: true
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .unsupportedSource) }

        let webM = makeCommonSource(
            extension: "webm",
            container: "matroska,webm",
            audioCodec: "opus"
        )
        let webMPlan = try ExactTrimPlanner().resolve(
            source: webM,
            range: MediaTrimRange(start: .zero, end: try XCTUnwrap(webM.duration)),
            choice: choice,
            operation: .transcode,
            availableVideoPresets: [.h264Compatibility],
            aacAvailable: true
        )
        XCTAssertEqual(webMPlan.sourceKind, .webM)
    }

    func testCommonInputConversionFailsClosedForUnpreservedStructureMetadataAndAudio() throws {
        let planner = ExactTrimPlanner()
        let choice = ExactTrimChoice(
            videoPreset: .h264Compatibility,
            videoRateControl: .averageBitrate(1_000_000)
        )
        func resolve(
            _ source: MediaAsset,
            choice selectedChoice: ExactTrimChoice? = nil
        ) throws -> ResolvedExactTrimPlan {
            try planner.resolve(
                source: source,
                range: MediaTrimRange(start: .zero, end: try XCTUnwrap(source.duration)),
                choice: selectedChoice ?? choice,
                operation: .transcode,
                availableVideoPresets: [.h264Compatibility],
                aacAvailable: true,
                availableAudioPresets: [.aacCompatibility]
            )
        }

        XCTAssertThrowsError(
            try resolve(
                makeCommonSource(
                    extraTrack: MediaTrack(id: 2, kind: .subtitle, codec: "mov_text")
                )
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .unsupportedTracks) }
        XCTAssertThrowsError(
            try resolve(makeCommonSource(metadata: ["title": "Feature", "artist": "Author"]))
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .unsupportedCommonMetadata) }
        XCTAssertThrowsError(
            try resolve(
                makeCommonSource(
                    extension: "webm",
                    container: "matroska,webm",
                    chapters: [ChapterNode(title: "Opening", start: .zero)]
                )
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .unsupportedCommonChapters) }
        XCTAssertThrowsError(
            try resolve(
                makeCommonSource(
                    chapters: [ChapterNode(title: " ", start: .zero)]
                )
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .unsupportedCommonChapters) }
        XCTAssertThrowsError(
            try resolve(
                makeCommonSource(
                    chapters: [ChapterNode(title: "Opening", start: .zero)],
                    reportedChapterCount: 2
                )
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .unsupportedCommonChapters) }

        let incompatible = makeCommonSource(audioCodec: "wmav2")
        XCTAssertThrowsError(try resolve(incompatible)) { error in
            XCTAssertEqual(
                error as? ExactTrimPlanningError,
                .incompatiblePacketCopy(trackID: 1, codec: "wmav2")
            )
        }
        let converted = try resolve(
            incompatible,
            choice: ExactTrimChoice(
                videoPreset: .h264Compatibility,
                videoRateControl: .averageBitrate(1_000_000),
                audioPolicy: .aacPreserveLayout
            )
        )
        XCTAssertEqual(converted.encodedAudioTrackIDs, [1])
        XCTAssertEqual(converted.copiedAudioTrackIDs, [])
    }

    func testCompleteFileTranscodePacketCopiesSubtitlesButDataStillFailsClosed() throws {
        let subtitle = MediaTrack(
            id: 2,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            language: "en",
            title: "English",
            isDefault: true
        )
        let source = makeSource(extraTrack: subtitle)
        let choice = ExactTrimChoice(
            videoPreset: .hevcCompatibility,
            videoRateControl: .averageBitrate(2_000_000)
        )
        let plan = try ExactTrimPlanner().resolve(
            source: source,
            range: MediaTrimRange(start: .zero, end: try XCTUnwrap(source.duration)),
            choice: choice,
            operation: .transcode,
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )

        XCTAssertEqual(plan.subtitleTrackIDs, [2])
        XCTAssertEqual(plan.trackIDsInOutputOrder, [0, 1, 2])
        XCTAssertEqual(plan.videoEncodeCount, 1)

        let dataSource = makeSource(
            extraTrack: MediaTrack(id: 2, kind: .data, codec: "bin_data")
        )
        XCTAssertThrowsError(
            try ExactTrimPlanner().resolve(
                source: dataSource,
                range: MediaTrimRange(
                    start: .zero,
                    end: try XCTUnwrap(dataSource.duration)
                ),
                choice: choice,
                operation: .transcode,
                availableVideoPresets: [.hevcCompatibility],
                aacAvailable: true
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .unsupportedTracks) }
    }

    func testResolvesOneVideoGenerationWithExplicitCopiedOrAACAudio() throws {
        let source = makeSource()
        let choice = ExactTrimChoice(
            videoPreset: .hevcCompatibility,
            videoRateControl: .averageBitrate(2_000_000),
            audioPolicy: .packetCopy
        )
        let copy = try ExactTrimPlanner().resolve(
            source: source,
            range: range(2, 8),
            choice: choice,
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )

        XCTAssertEqual(copy.videoTrackID, 0)
        XCTAssertEqual(copy.videoDynamicRange, .sdr)
        XCTAssertNil(copy.hdr10Signal)
        XCTAssertEqual(copy.audioTrackIDs, [1])
        XCTAssertEqual(copy.trackIDsInOutputOrder, [0, 1])
        XCTAssertEqual(copy.videoEncodeCount, 1)
        XCTAssertEqual(copy.audioEncodeCount, 0)

        let aac = try ExactTrimPlanner().resolve(
            source: makeSource(audioCodec: "ac3"),
            range: range(2, 8),
            choice: ExactTrimChoice(
                videoPreset: .hevcCompatibility,
                videoRateControl: .averageBitrate(2_000_000),
                audioPolicy: .aacPreserveLayout
            ),
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )
        XCTAssertEqual(aac.audioEncodeCount, 1)
        XCTAssertEqual(aac.encodedAudioTrackIDs, [1])
        XCTAssertEqual(aac.copiedAudioTrackIDs, [])
    }

    func testAdvancedAudioRequiresAProbeAndAnExactlyPreservedLayout() throws {
        let planner = ExactTrimPlanner()
        let source = makeSource(audioCodec: "pcm_s16le")
        for preset in AudioTranscodePreset.allCases {
            let plan = try planner.resolve(
                source: source,
                range: range(2, 8),
                choice: ExactTrimChoice(
                    videoPreset: .hevcCompatibility,
                    videoRateControl: .averageBitrate(2_000_000),
                    audioPolicy: ExactTrimAudioPolicy(preset: preset)
                ),
                availableVideoPresets: [.hevcCompatibility],
                aacAvailable: true,
                availableAudioPresets: Set(AudioTranscodePreset.allCases)
            )
            XCTAssertEqual(plan.audioEncodeCount, 1)
        }

        XCTAssertThrowsError(
            try planner.resolve(
                source: source,
                range: range(2, 8),
                choice: ExactTrimChoice(
                    videoPreset: .hevcCompatibility,
                    videoRateControl: .averageBitrate(2_000_000),
                    audioPolicy: .opusPreserveLayout
                ),
                availableVideoPresets: [.hevcCompatibility],
                aacAvailable: true
            )
        ) {
            XCTAssertEqual(
                $0 as? ExactTrimPlanningError,
                .unavailableAudioPreset(.opusQuality)
            )
        }

        for policy in [ExactTrimAudioPolicy.aacPreserveLayout, .ac3PreserveLayout] {
            XCTAssertThrowsError(
                try planner.resolve(
                    source: makeSource(
                        audioCodec: "flac",
                        audioLayout: "7.1",
                        audioChannels: 8
                    ),
                    range: range(2, 8),
                    choice: ExactTrimChoice(
                        videoPreset: .hevcCompatibility,
                        videoRateControl: .averageBitrate(2_000_000),
                        audioPolicy: policy
                    ),
                    availableVideoPresets: [.hevcCompatibility],
                    aacAvailable: true,
                    availableAudioPresets: Set(AudioTranscodePreset.allCases)
                )
            ) {
                XCTAssertEqual(
                    $0 as? ExactTrimPlanningError,
                    .incompleteAudioFacts(trackID: 1)
                )
            }
        }
        XCTAssertNoThrow(
            try planner.resolve(
                source: makeSource(
                    audioCodec: "flac",
                    audioLayout: "7.1",
                    audioChannels: 8
                ),
                range: range(2, 8),
                choice: ExactTrimChoice(
                    videoPreset: .hevcCompatibility,
                    videoRateControl: .averageBitrate(2_000_000),
                    audioPolicy: .opusPreserveLayout
                ),
                availableVideoPresets: [.hevcCompatibility],
                aacAvailable: true,
                availableAudioPresets: [.opusQuality]
            )
        )
    }

    func testAdvancedAudioCopiesMatchingTracksWithoutRequiringTheirFactsOrEncoder() throws {
        let source = makeSource(
            audioCodec: "AAC",
            audioLayout: nil,
            audioSampleRate: 0
        )
        let plan = try ExactTrimPlanner().resolve(
            source: source,
            range: range(2, 8),
            choice: ExactTrimChoice(
                videoPreset: .hevcCompatibility,
                videoRateControl: .averageBitrate(2_000_000),
                audioPolicy: .aacPreserveLayout
            ),
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: false,
            availableAudioPresets: []
        )

        XCTAssertEqual(plan.audioTrackIDs, [1])
        XCTAssertEqual(plan.encodedAudioTrackIDs, [])
        XCTAssertEqual(plan.copiedAudioTrackIDs, [1])
        XCTAssertEqual(plan.audioEncodeCount, 0)
    }

    func testRecommendationPrefersFirstVerifiedPresetAndPacketCopiesAudio() throws {
        let planner = ExactTrimPlanner()
        let av1 = try XCTUnwrap(
            planner.recommendedChoice(
                for: makeSource(),
                availableVideoPresets: [.av1Quality, .hevcCompatibility]
            )
        )
        XCTAssertEqual(av1.videoPreset, .av1Quality)
        XCTAssertEqual(av1.videoRateControl, .constantQuality(30))
        XCTAssertEqual(
            av1.encoderTuning,
            .svtAV1Preset(VideoEncoderTuning.defaultSVTAV1Preset)
        )
        XCTAssertEqual(av1.audioPolicy, .packetCopy)

        let hevc = try XCTUnwrap(
            planner.recommendedChoice(
                for: makeSource(),
                availableVideoPresets: [.hevcCompatibility]
            )
        )
        XCTAssertEqual(hevc.videoRateControl, .averageBitrate(500_000))

        let hdr = try XCTUnwrap(
            planner.recommendedChoice(
                for: makeSource(hdr10: true),
                availableVideoPresets: [.h264Compatibility, .hevcCompatibility]
            )
        )
        XCTAssertEqual(hdr.videoPreset, .hevcCompatibility)
    }

    func testValidatesBoundedAV1SpeedWithoutLeakingItToOtherCodecs() throws {
        let source = makeSource()
        let planner = ExactTrimPlanner()
        XCTAssertNoThrow(
            try planner.resolve(
                source: source,
                range: range(2, 8),
                choice: ExactTrimChoice(
                    videoPreset: .av1Quality,
                    videoRateControl: .constantQuality(24),
                    encoderTuning: .svtAV1Preset(5)
                ),
                availableVideoPresets: [.av1Quality],
                aacAvailable: true
            )
        )
        for choice in [
            ExactTrimChoice(
                videoPreset: .av1Quality,
                videoRateControl: .constantQuality(24),
                encoderTuning: .svtAV1Preset(14)
            ),
            ExactTrimChoice(
                videoPreset: .hevcCompatibility,
                videoRateControl: .averageBitrate(2_000_000),
                encoderTuning: .svtAV1Preset(8)
            ),
        ] {
            XCTAssertThrowsError(
                try planner.resolve(
                    source: source,
                    range: range(2, 8),
                    choice: choice,
                    availableVideoPresets: [.av1Quality, .hevcCompatibility],
                    aacAvailable: true
                )
            ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .invalidChoice) }
        }
    }

    func testLegacyChoicesDecodeWithTheStableCodecDefaultTuning() throws {
        let exact = ExactTrimChoice(
            videoPreset: .hevcCompatibility,
            videoRateControl: .averageBitrate(2_000_000)
        )
        let legacyExact = try removingEncoderTuning(from: JSONEncoder().encode(exact))
        XCTAssertEqual(
            try JSONDecoder().decode(ExactTrimChoice.self, from: legacyExact).encoderTuning,
            .codecDefault
        )

        let join = JoinVideoTargetChoice(
            preset: .hevcCompatibility,
            canvas: MediaDimensions(width: 1_920, height: 1_080),
            frameRatePolicy: .preserveSourceTiming,
            dynamicRange: .sdr,
            rateControl: .averageBitrate(4_000_000)
        )
        let legacyJoin = try removingEncoderTuning(from: JSONEncoder().encode(join))
        XCTAssertEqual(
            try JSONDecoder().decode(JoinVideoTargetChoice.self, from: legacyJoin).encoderTuning,
            .codecDefault
        )
    }

    func testQualityTiersCompileToBoundedCodecSpecificRateControls() {
        XCTAssertEqual(
            VideoQualityTierPolicy.rateControl(
                preset: .av1Quality,
                recommended: .constantQuality(30),
                tier: .smallerFile
            ),
            .constantQuality(34)
        )
        XCTAssertEqual(
            VideoQualityTierPolicy.rateControl(
                preset: .av1Quality,
                recommended: .constantQuality(30),
                tier: .higherQuality
            ),
            .constantQuality(24)
        )
        XCTAssertEqual(
            VideoQualityTierPolicy.rateControl(
                preset: .hevcCompatibility,
                recommended: .averageBitrate(10_000_000),
                tier: .smallerFile
            ),
            .averageBitrate(7_000_000)
        )
        XCTAssertEqual(
            VideoQualityTierPolicy.rateControl(
                preset: .h264Compatibility,
                recommended: .averageBitrate(10_000_000),
                tier: .higherQuality
            ),
            .averageBitrate(15_000_000)
        )
        XCTAssertNil(
            VideoQualityTierPolicy.rateControl(
                preset: .hevcCompatibility,
                recommended: .constantQuality(30),
                tier: .balanced
            )
        )
    }

    func testResolvesStaticHDR10ForAV1OrHEVCOnly() throws {
        let source = makeSource(hdr10: true)
        let plan = try ExactTrimPlanner().resolve(
            source: source,
            range: range(2, 8),
            choice: ExactTrimChoice(
                videoPreset: .hevcCompatibility,
                videoRateControl: .averageBitrate(2_000_000)
            ),
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )
        XCTAssertEqual(plan.videoDynamicRange, .hdr10)
        XCTAssertEqual(plan.hdr10Signal, MediaHDR10Signal(track: source.tracks[0]))

        XCTAssertThrowsError(
            try ExactTrimPlanner().resolve(
                source: source,
                range: range(2, 8),
                choice: ExactTrimChoice(
                    videoPreset: .h264Compatibility,
                    videoRateControl: .averageBitrate(2_000_000)
                ),
                availableVideoPresets: [.h264Compatibility],
                aacAvailable: true
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .unsupportedDynamicRange) }
    }

    func testFailsClosedForUnsupportedTracksTagsHDRCapabilitiesAndAACFacts() throws {
        let choice = ExactTrimChoice(
            videoPreset: .hevcCompatibility,
            videoRateControl: .averageBitrate(2_000_000)
        )
        let cases: [(MediaAsset, ExactTrimChoice, Set<VideoPreset>, Bool, ExactTrimPlanningError)] =
            [
                (
                    makeSource(extraTrack: MediaTrack(id: 2, kind: .subtitle, codec: "subrip")),
                    choice,
                    [.hevcCompatibility],
                    true,
                    .unsupportedTracks
                ),
                (
                    makeSource(globalTagCount: 1),
                    choice,
                    [.hevcCompatibility],
                    true,
                    .unsupportedTags
                ),
                (
                    makeSource(hdrFormats: ["HDR10 metadata"]),
                    choice,
                    [.hevcCompatibility],
                    true,
                    .unsupportedDynamicRange
                ),
                (
                    makeSource(),
                    choice,
                    [.h264Compatibility],
                    true,
                    .unavailableVideoPreset(.hevcCompatibility)
                ),
                (
                    makeSource(audioCodec: "flac", audioLayout: nil),
                    ExactTrimChoice(
                        videoPreset: .hevcCompatibility,
                        videoRateControl: .averageBitrate(2_000_000),
                        audioPolicy: .aacPreserveLayout
                    ),
                    [.hevcCompatibility],
                    true,
                    .incompleteAudioFacts(trackID: 1)
                ),
            ]
        for (source, selected, presets, aac, expected) in cases {
            XCTAssertThrowsError(
                try ExactTrimPlanner().resolve(
                    source: source,
                    range: range(2, 8),
                    choice: selected,
                    availableVideoPresets: presets,
                    aacAvailable: aac
                )
            ) { XCTAssertEqual($0 as? ExactTrimPlanningError, expected) }
        }
    }

    func testRejectsInvalidNoOpAndReversedRanges() throws {
        let source = makeSource()
        let choice = ExactTrimChoice(
            videoPreset: .h264Compatibility,
            videoRateControl: .averageBitrate(2_000_000)
        )
        XCTAssertThrowsError(
            try ExactTrimPlanner().resolve(
                source: source,
                range: range(0, 10),
                choice: choice,
                availableVideoPresets: [.h264Compatibility],
                aacAvailable: true
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .noChange) }
        XCTAssertThrowsError(
            try ExactTrimPlanner().resolve(
                source: source,
                range: range(8, 2),
                choice: choice,
                availableVideoPresets: [.h264Compatibility],
                aacAvailable: true
            )
        ) { XCTAssertEqual($0 as? ExactTrimPlanningError, .invalidRange) }
    }

    private func makeSource(
        extraTrack: MediaTrack? = nil,
        globalTagCount: Int = 0,
        hdrFormats: [String] = [],
        hdr10: Bool = false,
        audioCodec: String = "aac",
        audioLayout: String? = "stereo",
        audioChannels: Int = 2,
        audioSampleRate: Int = 48_000
    ) -> MediaAsset {
        var tracks = [
            MediaTrack(
                id: 0,
                kind: .video,
                codec: hdr10 ? "hevc" : "h264",
                codecID: hdr10 ? "V_MPEGH/ISO/HEVC" : "V_MPEG4/ISO/AVC",
                profile: hdr10 ? "Main 10" : "High",
                uid: 100,
                isDefault: true,
                dimensions: MediaDimensions(width: 160, height: 90),
                pixelFormat: hdr10 ? "yuv420p10le" : "yuv420p",
                bitDepth: hdr10 ? 10 : 8,
                frameRate: "24/1",
                colorInfo: MediaColorInfo(
                    range: "tv",
                    primaries: hdr10 ? "bt2020" : "bt709",
                    transfer: hdr10 ? "smpte2084" : "bt709",
                    matrix: hdr10 ? "bt2020nc" : "bt709"
                ),
                masteringDisplayMetadata: hdr10 ? masteringDisplay : nil,
                contentLightLevelMetadata: hdr10 ? contentLight : nil,
                hdrFormats: hdr10 ? ["HDR10 metadata"] : hdrFormats
            ),
            MediaTrack(
                id: 1,
                kind: .audio,
                codec: audioCodec,
                codecID: "A_AAC",
                profile: "LC",
                uid: 101,
                language: "en",
                title: "Main Audio",
                isDefault: true,
                channels: audioChannels,
                channelLayout: audioLayout,
                sampleRate: audioSampleRate
            ),
        ]
        if let extraTrack { tracks.append(extraTrack) }
        return MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Feature.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            fileSize: 1_000,
            tracks: tracks,
            metadata: ["title": "Feature"],
            chapterEntryCount: 0,
            globalTagCount: globalTagCount,
            trackTagCount: 0,
            segmentUID: "SOURCE"
        )
    }

    private func makeCommonSource(
        extension sourceExtension: String = "mp4",
        container: String = "mov,mp4,m4a,3gp,3g2,mj2",
        chapters: [ChapterNode] = [],
        audioCodec: String = "aac",
        metadata: [String: String] = ["title": "Feature", "major_brand": "isom"],
        reportedChapterCount: Int? = nil,
        extraTrack: MediaTrack? = nil
    ) -> MediaAsset {
        var tracks = [
            MediaTrack(
                id: 0,
                kind: .video,
                codec: sourceExtension == "webm" ? "vp9" : "h264",
                dimensions: MediaDimensions(width: 160, height: 90),
                pixelFormat: "yuv420p",
                bitDepth: 8,
                frameRate: "24/1",
                colorInfo: MediaColorInfo(
                    range: "tv",
                    primaries: "bt709",
                    transfer: "bt709",
                    matrix: "bt709"
                )
            ),
            MediaTrack(
                id: 1,
                kind: .audio,
                codec: audioCodec,
                language: "en",
                title: "Main Audio",
                isDefault: true,
                channels: 2,
                channelLayout: "stereo",
                sampleRate: 48_000,
                tags: [
                    "handler_name": "SoundHandler",
                    "DURATION": "00:00:10.000000000",
                ]
            ),
        ]
        if let extraTrack { tracks.append(extraTrack) }
        return MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Feature.\(sourceExtension)"),
            container: container,
            duration: MediaTime(nanoseconds: 10_000_000_000),
            fileSize: 1_000,
            tracks: tracks,
            chapters: chapters,
            metadata: metadata,
            chapterEntryCount: reportedChapterCount ?? chapters.count
        )
    }

    private func range(_ start: Int64, _ end: Int64) -> MediaTrimRange {
        MediaTrimRange(
            start: MediaTime(nanoseconds: start * 1_000_000_000),
            end: MediaTime(nanoseconds: end * 1_000_000_000)
        )
    }

    private func removingEncoderTuning(from data: Data) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "encoderTuning")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private let masteringDisplay = MediaMasteringDisplayMetadata(
    redX: 34_000,
    redY: 16_000,
    greenX: 13_250,
    greenY: 34_500,
    blueX: 7_500,
    blueY: 3_000,
    whitePointX: 15_635,
    whitePointY: 16_450,
    maxLuminance: 10_000_000,
    minLuminance: 50
)

private let contentLight = MediaContentLightLevelMetadata(
    maxContentLightLevel: 1_000,
    maxFrameAverageLightLevel: 400
)
