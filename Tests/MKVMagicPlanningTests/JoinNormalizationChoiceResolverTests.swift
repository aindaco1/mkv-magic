import Foundation
import MKVMagicCore
import MKVMagicPlanning
import XCTest

final class JoinNormalizationChoiceResolverTests: XCTestCase {
    func testResolvesExactHEVCChoiceBoundToInspectedReport() throws {
        let sources = incompatibleVideoSources()
        let proposal = try proposal(for: sources, preferredPreset: .hevcCompatibility)
        let choices = JoinNormalizationChoices(videoTargetsByLane: [
            0: videoChoice(proposal, preset: .hevcCompatibility)
        ])

        let resolved = try JoinNormalizationChoiceResolver().resolve(
            sources: sources,
            proposal: proposal,
            choices: choices,
            availableVideoPresets: [.hevcCompatibility, .h264Compatibility],
            aacAvailable: false
        )

        XCTAssertEqual(resolved.proposal, proposal)
        XCTAssertEqual(resolved.choices, choices)
    }

    func testRejectsMissingUnavailableAndInvalidVideoChoices() throws {
        let sources = incompatibleVideoSources()
        let proposal = try proposal(for: sources, preferredPreset: .hevcCompatibility)
        let resolver = JoinNormalizationChoiceResolver()

        XCTAssertThrowsError(
            try resolver.resolve(
                sources: sources,
                proposal: proposal,
                choices: JoinNormalizationChoices(),
                availableVideoPresets: [.hevcCompatibility],
                aacAvailable: true
            )
        ) { error in
            guard
                case .missingDecision(kind: .videoTarget, laneIndex: 0, sourceIndex: nil) =
                    error as? JoinNormalizationChoiceError
            else { return XCTFail("Unexpected error: \(error)") }
        }

        let exact = JoinNormalizationChoices(videoTargetsByLane: [
            0: videoChoice(proposal, preset: .hevcCompatibility)
        ])
        XCTAssertThrowsError(
            try resolver.resolve(
                sources: sources,
                proposal: proposal,
                choices: exact,
                availableVideoPresets: [.h264Compatibility],
                aacAvailable: true
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinNormalizationChoiceError,
                .unavailableVideoPreset(.hevcCompatibility)
            )
        }

        let invalid = JoinNormalizationChoices(videoTargetsByLane: [
            0: JoinVideoTargetChoice(
                preset: .hevcCompatibility,
                canvas: try XCTUnwrap(proposal.videoLanes[0].recommendedCanvas),
                frameRatePolicy: .preserveSourceTiming,
                dynamicRange: .sdr,
                rateControl: .constantQuality(30)
            )
        ])
        XCTAssertThrowsError(
            try resolver.resolve(
                sources: sources,
                proposal: proposal,
                choices: invalid,
                availableVideoPresets: [.hevcCompatibility],
                aacAvailable: true
            )
        ) { error in
            XCTAssertEqual(error as? JoinNormalizationChoiceError, .invalidChoice)
        }
    }

    func testAcceptsOnlyBoundedSVTAV1TuningOnAV1() throws {
        let sources = incompatibleVideoSources()
        let proposal = try proposal(for: sources, preferredPreset: .av1Quality)
        func choice(_ tuning: VideoEncoderTuning) -> JoinNormalizationChoices {
            JoinNormalizationChoices(videoTargetsByLane: [
                0: JoinVideoTargetChoice(
                    preset: .av1Quality,
                    canvas: proposal.videoLanes[0].recommendedCanvas!,
                    frameRatePolicy: .preserveSourceTiming,
                    dynamicRange: .sdr,
                    rateControl: .constantQuality(24),
                    encoderTuning: tuning
                )
            ])
        }
        XCTAssertNoThrow(
            try JoinNormalizationChoiceResolver().resolve(
                sources: sources,
                proposal: proposal,
                choices: choice(.svtAV1Preset(5)),
                availableVideoPresets: [.av1Quality],
                aacAvailable: false
            )
        )
        XCTAssertThrowsError(
            try JoinNormalizationChoiceResolver().resolve(
                sources: sources,
                proposal: proposal,
                choices: choice(.svtAV1Preset(14)),
                availableVideoPresets: [.av1Quality],
                aacAvailable: false
            )
        ) { XCTAssertEqual($0 as? JoinNormalizationChoiceError, .invalidChoice) }
    }

    func testRejectsChoicesAfterSourceFactsChange() throws {
        let sources = incompatibleVideoSources()
        let proposal = try proposal(for: sources, preferredPreset: .hevcCompatibility)
        let changed = [sources[0], asset(part: 2, tracks: [video(id: 0, width: 640, height: 360)])]

        XCTAssertThrowsError(
            try JoinNormalizationChoiceResolver().resolve(
                sources: changed,
                proposal: proposal,
                choices: JoinNormalizationChoices(videoTargetsByLane: [
                    0: videoChoice(proposal, preset: .hevcCompatibility)
                ]),
                availableVideoPresets: [.hevcCompatibility],
                aacAvailable: true
            )
        ) { error in
            XCTAssertEqual(error as? JoinNormalizationChoiceError, .reportChanged)
        }
    }

    func testAudioChoiceRequiresVerifiedAACAndExplicitSilenceApproval() throws {
        let sources = [
            asset(part: 1, tracks: [audio(id: 0, channels: 6)]),
            asset(part: 2, tracks: []),
        ]
        let mapping = JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .audio, trackIDsBySource: [0, nil])
        ])
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping
        )
        let lane = proposal.audioLanes[0]
        let denied = JoinAudioTargetChoice(
            codec: try XCTUnwrap(lane.outputCodec),
            channels: try XCTUnwrap(lane.outputChannels),
            channelLayout: try XCTUnwrap(lane.outputChannelLayout),
            sampleRate: try XCTUnwrap(lane.outputSampleRate),
            bitrate: try XCTUnwrap(lane.outputBitrate),
            allowsSyntheticSilence: false
        )

        XCTAssertThrowsError(
            try JoinNormalizationChoiceResolver().resolve(
                sources: sources,
                proposal: proposal,
                choices: JoinNormalizationChoices(audioTargetsByLane: [0: denied]),
                availableVideoPresets: [],
                aacAvailable: true
            )
        ) { error in
            guard
                case .missingDecision(kind: .missingAudio, laneIndex: 0, sourceIndex: nil) =
                    error as? JoinNormalizationChoiceError
            else { return XCTFail("Unexpected error: \(error)") }
        }

        let approved = JoinAudioTargetChoice(
            codec: denied.codec,
            channels: denied.channels,
            channelLayout: denied.channelLayout,
            sampleRate: denied.sampleRate,
            bitrate: denied.bitrate,
            allowsSyntheticSilence: true
        )
        XCTAssertThrowsError(
            try JoinNormalizationChoiceResolver().resolve(
                sources: sources,
                proposal: proposal,
                choices: JoinNormalizationChoices(audioTargetsByLane: [0: approved]),
                availableVideoPresets: [],
                aacAvailable: false
            )
        ) { error in
            XCTAssertEqual(error as? JoinNormalizationChoiceError, .unavailableAAC)
        }
        XCTAssertNoThrow(
            try JoinNormalizationChoiceResolver().resolve(
                sources: sources,
                proposal: proposal,
                choices: JoinNormalizationChoices(audioTargetsByLane: [0: approved]),
                availableVideoPresets: [],
                aacAvailable: true
            )
        )
    }

    func testEveryAttachmentAndMetadataDecisionIsExplicitAndNoExtrasAreAccepted() throws {
        let first = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Part 1.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 1_000_000_000),
            tracks: [audio(id: 0, language: "en")],
            attachments: [MediaAttachment(id: 7, filename: "cover.jpg")]
        )
        let second = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Part 2.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 1_000_000_000),
            tracks: [audio(id: 0, language: "fr")],
            attachments: [MediaAttachment(id: 9, filename: "font.ttf")]
        )
        let sources = [first, second]
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .audio, trackIDsBySource: [0, 0])
            ])
        )
        XCTAssertEqual(proposal.decisions.filter { $0.kind == .attachmentPolicy }.count, 2)
        XCTAssertEqual(proposal.decisions.filter { $0.kind == .trackMetadata }.count, 1)

        let choices = JoinNormalizationChoices(
            retainedAttachmentIDsBySource: [0: [7], 1: []],
            metadataSourceByLane: [0: 0]
        )
        XCTAssertNoThrow(
            try JoinNormalizationChoiceResolver().resolve(
                sources: sources,
                proposal: proposal,
                choices: choices,
                availableVideoPresets: [],
                aacAvailable: false
            )
        )

        let extras = JoinNormalizationChoices(
            retainedAttachmentIDsBySource: [0: [7], 1: [], 2: []],
            metadataSourceByLane: [0: 0]
        )
        XCTAssertThrowsError(
            try JoinNormalizationChoiceResolver().resolve(
                sources: sources,
                proposal: proposal,
                choices: extras,
                availableVideoPresets: [],
                aacAvailable: false
            )
        ) { error in
            XCTAssertEqual(error as? JoinNormalizationChoiceError, .unexpectedChoice)
        }
    }

    func testOddRecommendedCanvasIsRoundedUpAndUnrepresentableEvenCanvasBlocks() throws {
        let odd = [
            asset(part: 1, tracks: [video(id: 0)]),
            asset(part: 2, tracks: [video(id: 0, width: 1_919, height: 1_079)]),
        ]
        let oddProposal = try proposal(for: odd)
        XCTAssertEqual(
            oddProposal.videoLanes[0].recommendedCanvas,
            MediaDimensions(width: 1_920, height: 1_080)
        )

        let maximumOdd = [
            asset(part: 1, tracks: [video(id: 0)]),
            asset(part: 2, tracks: [video(id: 0, width: 65_535, height: 1_081)]),
        ]
        let blocked = try proposal(for: maximumOdd)
        XCTAssertTrue(blocked.blockers.contains { $0.summary.contains("even-sized") })
    }

    private func proposal(
        for sources: [MediaAsset],
        preferredPreset: VideoPreset = .av1Quality
    ) throws -> JoinNormalizationProposal {
        try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 0])
            ]),
            preferredVideoPreset: preferredPreset
        )
    }

    private func incompatibleVideoSources() -> [MediaAsset] {
        [
            asset(part: 1, tracks: [video(id: 0, width: 1_920, height: 1_080)]),
            asset(part: 2, tracks: [video(id: 0, width: 1_280, height: 720)]),
        ]
    }

    private func videoChoice(
        _ proposal: JoinNormalizationProposal,
        preset: VideoPreset
    ) -> JoinVideoTargetChoice {
        JoinVideoTargetChoice(
            preset: preset,
            canvas: proposal.videoLanes[0].recommendedCanvas!,
            frameRatePolicy: .preserveSourceTiming,
            dynamicRange: .sdr,
            rateControl: .averageBitrate(8_000_000)
        )
    }

    private func asset(part: Int, tracks: [MediaTrack]) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Part \(part).mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 1_000_000_000),
            tracks: tracks
        )
    }

    private func video(id: Int, width: Int = 1_920, height: Int = 1_080) -> MediaTrack {
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

    private func audio(
        id: Int,
        channels: Int = 2,
        language: String = "en"
    ) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            profile: "LC",
            language: language,
            isDefault: true,
            channels: channels,
            channelLayout: channels == 2 ? "stereo" : "5.1(side)",
            sampleRate: 48_000
        )
    }
}
