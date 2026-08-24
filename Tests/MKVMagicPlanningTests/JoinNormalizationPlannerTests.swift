import MKVMagicCore
import MKVMagicPlanning
import XCTest

final class JoinNormalizationPlannerTests: XCTestCase {
    func testCompatibleLanesRemainPacketCopiesWithZeroEncodes() throws {
        let sources = [
            asset(part: 1, tracks: [video(id: 0), audio(id: 1)]),
            asset(part: 2, tracks: [video(id: 10), audio(id: 11)]),
        ]
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping(video: [0, 10], audio: [1, 11])
        )

        XCTAssertTrue(proposal.blockers.isEmpty)
        XCTAssertTrue(proposal.decisions.isEmpty)
        XCTAssertEqual(proposal.impact.videoEncodeCount, 0)
        XCTAssertEqual(proposal.impact.audioEncodeCount, 0)
        XCTAssertTrue(proposal.impact.copiesVideo)
        XCTAssertEqual(proposal.videoLanes[0].sourceActions, [.copyAppend, .copyAppend])
        XCTAssertEqual(proposal.audioLanes[0].sourceActions, [.copyAppend, .copyAppend])
    }

    func testIncompatibleVideoUsesOneAV1GenerationAndLargestCanvas() throws {
        let sources = [
            asset(part: 1, tracks: [video(id: 0)]),
            asset(
                part: 2,
                tracks: [
                    video(
                        id: 10,
                        codec: "hevc",
                        codecID: "V_MPEGH/ISO/HEVC",
                        width: 3_840,
                        height: 2_160
                    )
                ]
            ),
        ]
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10])
            ])
        )

        XCTAssertTrue(proposal.blockers.isEmpty)
        XCTAssertEqual(proposal.impact.videoEncodeCount, 1)
        XCTAssertEqual(proposal.videoLanes.count, 1)
        let lane = proposal.videoLanes[0]
        XCTAssertEqual(lane.sourceActions, [.encodeOnce, .encodeOnce])
        XCTAssertEqual(lane.recommendedPreset, .av1Quality)
        XCTAssertEqual(lane.recommendedCanvas, MediaDimensions(width: 3_840, height: 2_160))
        XCTAssertEqual(lane.recommendedFrameRatePolicy, .preserveSourceTiming)
        XCTAssertEqual(lane.recommendedDynamicRange, .sdr)
        XCTAssertEqual(lane.outputPixelFormat, "yuv420p10le")
        XCTAssertEqual(lane.outputBitDepth, 10)
        XCTAssertEqual(
            proposal.decisions.filter { $0.kind == .videoTarget }.map(\.laneIndex),
            [0]
        )
        XCTAssertTrue(
            proposal.impact.warnings.contains { $0.contains("one final encoded generation") }
        )

        let h264Fallback = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10])
            ]),
            preferredVideoPreset: .h264Compatibility
        )
        XCTAssertEqual(h264Fallback.videoLanes[0].recommendedPreset, .h264Compatibility)
        XCTAssertEqual(h264Fallback.videoLanes[0].outputPixelFormat, "yuv420p")
        XCTAssertEqual(h264Fallback.videoLanes[0].outputBitDepth, 8)
    }

    func testAudioMismatchPreservesLargestLayoutWithOneAACLaneEncode() throws {
        let sources = [
            asset(part: 1, tracks: [video(id: 0), audio(id: 1, channels: 2)]),
            asset(
                part: 2,
                tracks: [
                    video(id: 10),
                    audio(
                        id: 11,
                        codec: "ac3",
                        codecID: "A_AC3",
                        channels: 6,
                        sampleRate: 48_000
                    ),
                ]
            ),
        ]
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping(video: [0, 10], audio: [1, 11])
        )

        XCTAssertTrue(proposal.blockers.isEmpty)
        XCTAssertEqual(proposal.impact.videoEncodeCount, 0)
        XCTAssertEqual(proposal.impact.audioEncodeCount, 1)
        XCTAssertEqual(proposal.videoLanes[0].sourceActions, [.copyAppend, .copyAppend])
        let lane = proposal.audioLanes[0]
        XCTAssertEqual(lane.sourceActions, [.encodeOnce, .encodeOnce])
        XCTAssertEqual(lane.outputCodec, "AAC")
        XCTAssertEqual(lane.outputChannels, 6)
        XCTAssertEqual(lane.outputChannelLayout, "5.1(side)")
        XCTAssertEqual(lane.outputSampleRate, 48_000)
        XCTAssertEqual(lane.outputBitrate, 512_000)
        XCTAssertTrue(proposal.decisions.contains { $0.kind == .audioTarget })
    }

    func testMissingAudioRequiresConfirmedSilenceWithoutDownmix() throws {
        let sources = [
            asset(part: 1, tracks: [video(id: 0), audio(id: 1, channels: 6)]),
            asset(part: 2, tracks: [video(id: 10)]),
        ]
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping(video: [0, 10], audio: [1, nil])
        )

        XCTAssertTrue(proposal.blockers.isEmpty)
        XCTAssertEqual(proposal.audioLanes[0].sourceActions, [.encodeOnce, .synthesizeSilence])
        XCTAssertEqual(proposal.audioLanes[0].outputChannels, 6)
        XCTAssertTrue(proposal.decisions.contains { $0.kind == .missingAudio })
        XCTAssertTrue(proposal.decisions.contains { $0.summary.contains("never fabricated") })
    }

    func testMixedSDRAndHDRDefaultsToReviewedSDRToneMapping() throws {
        let sources = [
            asset(part: 1, tracks: [video(id: 0)]),
            asset(part: 2, tracks: [hdr10Video(id: 10)]),
        ]
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10])
            ])
        )

        XCTAssertTrue(proposal.blockers.isEmpty)
        XCTAssertEqual(proposal.videoLanes[0].recommendedDynamicRange, .sdr)
        XCTAssertEqual(proposal.videoLanes[0].dynamicRangeChoices, [.sdr])
        XCTAssertTrue(
            proposal.decisions.contains {
                $0.kind == .mixedDynamicRange && $0.summary.contains("only the HDR Parts")
            }
        )
        XCTAssertEqual(proposal.impact.videoEncodeCount, 1)
    }

    func testMixedRangeRejectsIncompleteHDR10FactsBeforeToneMapping() throws {
        let sources = [
            asset(part: 1, tracks: [video(id: 0)]),
            asset(part: 2, tracks: [hdr10Video(id: 10, includeStaticMetadata: false)]),
        ]
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10])
            ])
        )

        XCTAssertTrue(
            proposal.blockers.contains {
                $0.summary.contains("unknown or unsupported dynamic-range metadata")
            }
        )
        XCTAssertFalse(proposal.decisions.contains { $0.kind == .mixedDynamicRange })
    }

    func testUniformStaticHDR10PreservesOneIdenticalSignalAndRequiresTenBitCodec() throws {
        let sources = [
            asset(part: 1, tracks: [hdr10Video(id: 0, width: 1_920, height: 1_080)]),
            asset(part: 2, tracks: [hdr10Video(id: 10)]),
        ]
        let mapping = JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .video, trackIDsBySource: [0, 10])
        ])
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping
        )

        XCTAssertTrue(proposal.blockers.isEmpty)
        XCTAssertEqual(proposal.videoLanes[0].recommendedPreset, .av1Quality)
        XCTAssertEqual(proposal.videoLanes[0].recommendedDynamicRange, .hdr10)
        XCTAssertEqual(proposal.videoLanes[0].dynamicRangeChoices, [.hdr10])
        XCTAssertEqual(proposal.videoLanes[0].outputBitDepth, 10)

        let incompatibleCodec = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping,
            preferredVideoPreset: .h264Compatibility
        )
        XCTAssertTrue(
            incompatibleCodec.blockers.contains { $0.summary.contains("AV1 or HEVC") }
        )

        let metadataDrift = try JoinNormalizationPlanner().propose(
            sources: [
                sources[0],
                asset(part: 2, tracks: [hdr10Video(id: 10, maxContentLightLevel: 999)]),
            ],
            mapping: mapping
        )
        XCTAssertTrue(
            metadataDrift.blockers.contains { $0.summary.contains("differing") }
        )
    }

    func testDolbyVisionNormalizationFailsClosed() throws {
        let dolbyVision = MediaTrack(
            id: 10,
            kind: .video,
            codec: "hevc",
            codecID: "V_MPEGH/ISO/HEVC",
            profile: "Main 10",
            level: 153,
            dimensions: MediaDimensions(width: 3_840, height: 2_160),
            displayDimensions: MediaDimensions(width: 3_840, height: 2_160),
            pixelFormat: "yuv420p10le",
            bitDepth: 10,
            frameRate: "24000/1001",
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt2020",
                transfer: "smpte2084",
                matrix: "bt2020nc"
            ),
            hdrFormats: ["Dolby Vision"]
        )
        let proposal = try JoinNormalizationPlanner().propose(
            sources: [
                asset(part: 1, tracks: [video(id: 0)]), asset(part: 2, tracks: [dolbyVision]),
            ],
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10])
            ])
        )

        XCTAssertFalse(proposal.canAdvanceToExplicitChoices)
        XCTAssertTrue(proposal.blockers.contains { $0.summary.contains("Dolby Vision") })
    }

    func testImageSubtitleCodecMismatchDoesNotOfferOCR() throws {
        let pgs = subtitle(id: 2, codec: "hdmv_pgs_subtitle", codecID: "S_HDMV/PGS")
        let vob = subtitle(id: 12, codec: "dvd_subtitle", codecID: "S_VOBSUB")
        let proposal = try JoinNormalizationPlanner().propose(
            sources: [asset(part: 1, tracks: [pgs]), asset(part: 2, tracks: [vob])],
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .subtitle, trackIDsBySource: [2, 12])
            ])
        )

        XCTAssertEqual(proposal.subtitleLanes[0].mechanism, .unsupported)
        XCTAssertTrue(proposal.blockers.contains { $0.summary.contains("image-to-text") })
    }

    func testUnknownAndUnboundedProbeParametersFailClosed() throws {
        let unknown = MediaTrack(id: 0, kind: .video, codec: "av1")
        let proposal = try JoinNormalizationPlanner().propose(
            sources: [asset(part: 1, tracks: [unknown]), asset(part: 2, tracks: [unknown])],
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 0])
            ])
        )

        XCTAssertEqual(proposal.impact.videoEncodeCount, 0)
        XCTAssertTrue(proposal.blockers.contains { $0.summary.contains("safe copy") })

        let unbounded = try JoinNormalizationPlanner().propose(
            sources: [
                asset(part: 1, tracks: [video(id: 0)]),
                asset(
                    part: 2,
                    tracks: [
                        video(
                            id: 10,
                            codec: "hevc",
                            codecID: "V_MPEGH/ISO/HEVC",
                            width: Int.max,
                            height: Int.max
                        )
                    ]
                ),
            ],
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10])
            ])
        )
        XCTAssertTrue(unbounded.blockers.contains { $0.summary.contains("bounded") })
    }

    func testReviewedReportMustStillMatchCurrentFacts() throws {
        let sources = [
            asset(part: 1, tracks: [video(id: 0)]), asset(part: 2, tracks: [video(id: 10)]),
        ]
        let mapping = JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .video, trackIDsBySource: [0, 10])
        ])
        let stale = JoinCompatibilityReport(
            mapping: mapping,
            disposition: .unsupported,
            issues: [],
            requiresAuthoritativeMKVToolNixValidation: true
        )

        XCTAssertThrowsError(
            try JoinNormalizationPlanner().propose(
                sources: sources,
                mapping: mapping,
                reviewedReport: stale
            )
        ) { error in
            XCTAssertEqual(error as? JoinNormalizationPlanningError, .reportChanged)
        }
    }

    private func mapping(video: [Int?], audio: [Int?]) -> JoinTrackMapping {
        JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .video, trackIDsBySource: video),
            JoinTrackLane(kind: .audio, trackIDsBySource: audio),
        ])
    }

    private func asset(part: Int, tracks: [MediaTrack]) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Part \(part).mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            tracks: tracks
        )
    }

    private func video(
        id: Int,
        codec: String = "h264",
        codecID: String = "V_MPEG4/ISO/AVC",
        width: Int = 1_920,
        height: Int = 1_080
    ) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .video,
            codec: codec,
            codecID: codecID,
            profile: codec == "h264" ? "High" : "Main 10",
            level: codec == "h264" ? 40 : 153,
            dimensions: MediaDimensions(width: width, height: height),
            displayDimensions: MediaDimensions(width: width, height: height),
            pixelFormat: codec == "h264" ? "yuv420p" : "yuv420p10le",
            bitDepth: codec == "h264" ? 8 : 10,
            frameRate: "24000/1001",
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt709",
                transfer: "bt709",
                matrix: "bt709"
            )
        )
    }

    private func hdr10Video(
        id: Int,
        width: Int = 3_840,
        height: Int = 2_160,
        maxContentLightLevel: Int = 1_000,
        includeStaticMetadata: Bool = true
    ) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .video,
            codec: "hevc",
            codecID: "V_MPEGH/ISO/HEVC",
            profile: "Main 10",
            level: 153,
            dimensions: MediaDimensions(width: width, height: height),
            displayDimensions: MediaDimensions(width: width, height: height),
            pixelFormat: "yuv420p10le",
            bitDepth: 10,
            frameRate: "24000/1001",
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt2020",
                transfer: "smpte2084",
                matrix: "bt2020nc"
            ),
            masteringDisplayMetadata: includeStaticMetadata ? hdrMasteringDisplay : nil,
            contentLightLevelMetadata: includeStaticMetadata
                ? MediaContentLightLevelMetadata(
                    maxContentLightLevel: maxContentLightLevel,
                    maxFrameAverageLightLevel: 400
                ) : nil,
            hdrFormats: ["HDR10 metadata"]
        )
    }

    private var hdrMasteringDisplay: MediaMasteringDisplayMetadata {
        MediaMasteringDisplayMetadata(
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
    }

    private func audio(
        id: Int,
        codec: String = "aac",
        codecID: String = "A_AAC",
        channels: Int = 2,
        sampleRate: Int = 48_000
    ) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .audio,
            codec: codec,
            codecID: codecID,
            profile: codec == "aac" ? "LC" : nil,
            language: "en",
            isDefault: true,
            channels: channels,
            channelLayout: channels == 2 ? "stereo" : "5.1(side)",
            sampleRate: sampleRate
        )
    }

    private func subtitle(id: Int, codec: String, codecID: String) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .subtitle,
            codec: codec,
            codecID: codecID,
            language: "en"
        )
    }
}
