import MKVMagicCore
import XCTest

final class JoinCompatibilityTests: XCTestCase {
    func testMatchingKnownParametersAreALosslessCandidateWithExplicitTrackIDs() throws {
        let sources = [
            asset(index: 0, tracks: [video(id: 0), audio(id: 1)]),
            asset(index: 1, tracks: [video(id: 10), audio(id: 11)]),
        ]
        let mapping = JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
            JoinTrackLane(kind: .audio, trackIDsBySource: [1, 11]),
        ])

        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: mapping
        )

        XCTAssertEqual(report.mapping, mapping)
        XCTAssertEqual(report.disposition, .losslessCandidate)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.requiresAuthoritativeMKVToolNixValidation)
    }

    func testVideoAndAudioParameterDifferencesRequireNormalization() throws {
        let referenceVideo = video(id: 0)
        let changedVideo = MediaTrack(
            id: 10,
            kind: .video,
            codec: "hevc",
            codecID: "V_MPEGH/ISO/HEVC",
            profile: "Main 10",
            level: 153,
            language: "und",
            title: "Main Video",
            isDefault: true,
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
            hdrFormats: ["HDR10 metadata"]
        )
        let changedAudio = MediaTrack(
            id: 11,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            profile: "HE-AAC",
            language: "en",
            title: "Main Audio",
            isDefault: true,
            channels: 2,
            channelLayout: "stereo",
            sampleRate: 44_100
        )
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: [
                asset(index: 0, tracks: [referenceVideo, audio(id: 1)]),
                asset(index: 1, tracks: [changedVideo, changedAudio]),
            ],
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
                JoinTrackLane(kind: .audio, trackIDsBySource: [1, 11]),
            ])
        )

        XCTAssertEqual(report.disposition, .normalizationRequired)
        let reasons = Set(report.issues.map(\.reason))
        XCTAssertTrue(
            reasons.isSuperset(of: [
                .codec, .profile, .level, .dimensions, .displayDimensions, .pixelFormat, .bitDepth,
                .color, .hdr, .sampleRate, .channels, .channelLayout,
            ]))
        XCTAssertTrue(report.issues.allSatisfy { $0.sourceIndex == 1 })
    }

    func testMetadataFrameRateAndMissingSubtitleRequireConfirmationWithoutEncoding() throws {
        let firstSubtitle = subtitle(id: 2)
        let extraSubtitle = MediaTrack(
            id: 3,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            language: "fr",
            title: "French"
        )
        let secondVideo = video(id: 10, frameRate: "30000/1001")
        let secondSubtitle = MediaTrack(
            id: 12,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            language: "en",
            title: "English SDH",
            isDefault: true,
            isHearingImpaired: true
        )
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: [
                asset(index: 0, tracks: [video(id: 0), firstSubtitle, extraSubtitle]),
                asset(index: 1, tracks: [secondVideo, secondSubtitle]),
            ],
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
                JoinTrackLane(kind: .subtitle, trackIDsBySource: [2, 12]),
                JoinTrackLane(kind: .subtitle, trackIDsBySource: [3, nil]),
            ])
        )

        XCTAssertEqual(report.disposition, .confirmationRequired)
        let reasons = Set(report.issues.map(\.reason))
        XCTAssertTrue(reasons.isSuperset(of: [.frameRate, .role, .title, .flags, .missingTrack]))
        XCTAssertFalse(report.issues.contains { $0.severity == .normalizationRequired })
        XCTAssertFalse(report.issues.contains { $0.reason == .language })
    }

    func testUnknownRequiredFactsFailClosedToConfirmation() throws {
        let unknownVideo = MediaTrack(id: 0, kind: .video, codec: "av1")
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: [
                asset(index: 0, tracks: [unknownVideo]),
                asset(index: 1, tracks: [unknownVideo]),
            ],
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 0])
            ])
        )

        XCTAssertEqual(report.disposition, .confirmationRequired)
        XCTAssertEqual(Set(report.issues.map(\.reason)), [.incompleteParameters])
    }

    func testUnsupportedTracksAttachmentsAndContainersAreNeverSilent() throws {
        let attachment = MediaAttachment(id: 0, filename: "font.ttf")
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: [
                asset(
                    index: 0,
                    tracks: [video(id: 0), MediaTrack(id: 5, kind: .data, codec: "bin")],
                    attachments: [attachment]
                ),
                asset(index: 1, container: "mov", tracks: [video(id: 10)]),
            ],
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10])
            ])
        )

        XCTAssertEqual(report.disposition, .unsupported)
        XCTAssertTrue(
            report.issues.contains {
                $0.reason == .unsupportedTrackKind && $0.sourceIndex == 0 && $0.trackID == 5
            })
        XCTAssertTrue(
            report.issues.contains {
                $0.reason == .attachmentSelection && $0.sourceIndex == 0
            })
        XCTAssertTrue(
            report.issues.contains {
                $0.reason == .nonMatroskaSource && $0.sourceIndex == 1
            })
    }

    func testProposalPairsReorderedTracksByIdentityThenLanguageAndRole() throws {
        let frenchAAC = MediaTrack(
            id: 2,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            profile: "LC",
            language: "fr",
            title: "French",
            channels: 2,
            channelLayout: "stereo",
            sampleRate: 48_000
        )
        let frenchOpus = MediaTrack(
            id: 12,
            kind: .audio,
            codec: "opus",
            codecID: "A_OPUS",
            language: "fre",
            title: "French",
            channels: 2,
            channelLayout: "stereo",
            sampleRate: 48_000
        )
        let sources = [
            asset(index: 0, tracks: [video(id: 0), audio(id: 1), frenchAAC]),
            asset(index: 1, tracks: [frenchOpus, video(id: 10), audio(id: 11)]),
        ]

        let proposal = try JoinTrackMappingProposer().propose(sources: sources)

        XCTAssertEqual(proposal.ambiguities, [])
        XCTAssertEqual(
            proposal.mapping.lanes,
            [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
                JoinTrackLane(kind: .audio, trackIDsBySource: [1, 11]),
                JoinTrackLane(kind: .audio, trackIDsBySource: [2, 12]),
            ]
        )
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: proposal.mapping
        )
        XCTAssertEqual(report.disposition, .normalizationRequired)
        XCTAssertTrue(report.issues.contains { $0.reason == .codec && $0.laneIndex == 2 })
    }

    func testProposalLeavesIndistinguishableDuplicatesVisiblyAmbiguous() throws {
        let sources = [
            asset(index: 0, tracks: [video(id: 0), subtitle(id: 1), subtitle(id: 2)]),
            asset(index: 1, tracks: [video(id: 10), subtitle(id: 11), subtitle(id: 12)]),
        ]

        let first = try JoinTrackMappingProposer().propose(sources: sources)
        let second = try JoinTrackMappingProposer().propose(sources: sources)

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.mapping.lanes,
            [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
                JoinTrackLane(kind: .subtitle, trackIDsBySource: [1, nil]),
                JoinTrackLane(kind: .subtitle, trackIDsBySource: [2, nil]),
                JoinTrackLane(kind: .subtitle, trackIDsBySource: [nil, 11]),
                JoinTrackLane(kind: .subtitle, trackIDsBySource: [nil, 12]),
            ]
        )
        XCTAssertEqual(
            first.ambiguities,
            [
                JoinTrackMappingAmbiguity(
                    sourceIndex: 1,
                    kind: .subtitle,
                    trackIDs: [11, 12],
                    candidateLaneIndices: [1, 2]
                )
            ]
        )
    }

    func testProposalUsesObviousOneToOneLaneButStillReportsMetadataDifference() throws {
        let frenchAudio = MediaTrack(
            id: 11,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            profile: "LC",
            language: "fr",
            title: "Main Audio",
            isDefault: true,
            channels: 6,
            channelLayout: "5.1(side)",
            sampleRate: 48_000
        )
        let sources = [
            asset(index: 0, tracks: [audio(id: 1)]),
            asset(index: 1, tracks: [frenchAudio]),
        ]

        let proposal = try JoinTrackMappingProposer().propose(sources: sources)
        XCTAssertEqual(
            proposal.mapping.lanes,
            [
                JoinTrackLane(kind: .audio, trackIDsBySource: [1, 11])
            ])
        XCTAssertEqual(proposal.ambiguities, [])
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: proposal.mapping
        )
        XCTAssertEqual(report.disposition, .confirmationRequired)
        XCTAssertTrue(report.issues.contains { $0.reason == .language })
    }

    func testMappingValidationRejectsEverySilentLossOrAmbiguityClass() throws {
        let sources = [
            asset(index: 0, tracks: [video(id: 0), audio(id: 1)]),
            asset(index: 1, tracks: [video(id: 10), audio(id: 11)]),
        ]
        assertError(
            .invalidSourceCount,
            sources: [sources[0]],
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0])
            ])
        )
        assertError(.emptyMapping, sources: sources, mapping: JoinTrackMapping(lanes: []))
        assertError(
            .invalidLaneWidth(laneIndex: 0),
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0])
            ])
        )
        assertError(
            .emptyLane(laneIndex: 0),
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [nil, nil])
            ])
        )
        assertError(
            .unsupportedLaneKind(laneIndex: 0),
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .data, trackIDsBySource: [nil, nil])
            ])
        )
        assertError(
            .missingTrack(sourceIndex: 1, trackID: 99),
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 99])
            ])
        )
        assertError(
            .kindMismatch(sourceIndex: 1, trackID: 11),
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 11])
            ])
        )
        assertError(
            .duplicateAssignment(sourceIndex: 0, trackID: 0),
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
                JoinTrackLane(kind: .video, trackIDsBySource: [0, nil]),
            ])
        )
        assertError(
            .unmappedTrack(sourceIndex: 0, trackID: 1),
            sources: sources,
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
                JoinTrackLane(kind: .audio, trackIDsBySource: [nil, 11]),
            ])
        )

        let duplicateIDSource = asset(
            index: 0,
            tracks: [video(id: 0), MediaTrack(id: 0, kind: .audio, codec: "aac")]
        )
        assertError(
            .duplicateTrackID(sourceIndex: 0, trackID: 0),
            sources: [duplicateIDSource, sources[1]],
            mapping: JoinTrackMapping(lanes: [
                JoinTrackLane(kind: .video, trackIDsBySource: [0, 10])
            ])
        )
    }

    func testSourceAndTrackCountsAreBoundedBeforeProposalAllocation() throws {
        let empty = asset(index: 0, tracks: [])
        assertProposalError(
            .invalidSourceCount,
            sources: Array(
                repeating: empty,
                count: JoinCompatibilityAnalyzer.maximumSources + 1
            )
        )

        let oversizedTracks = (0...JoinCompatibilityAnalyzer.maximumTracks).map {
            MediaTrack(id: $0, kind: .data, codec: "bin")
        }
        assertProposalError(
            .tooManyTracks,
            sources: [asset(index: 0, tracks: oversizedTracks), empty]
        )
    }

    private func assertError(
        _ expected: JoinTrackMappingError,
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try JoinCompatibilityAnalyzer().analyze(sources: sources, mapping: mapping),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? JoinTrackMappingError, expected, file: file, line: line)
        }
    }

    private func assertProposalError(
        _ expected: JoinTrackMappingError,
        sources: [MediaAsset],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try JoinTrackMappingProposer().propose(sources: sources),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? JoinTrackMappingError, expected, file: file, line: line)
        }
    }

    private func asset(
        index: Int,
        container: String = "matroska",
        tracks: [MediaTrack],
        attachments: [MediaAttachment] = []
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: "/tmp/source-\(index).mkv"),
            container: container,
            tracks: tracks,
            attachments: attachments
        )
    }

    private func video(id: Int, frameRate: String = "24000/1001") -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .video,
            codec: "av1",
            codecID: "V_AV1",
            profile: "Main",
            level: 13,
            language: "und",
            title: "Main Video",
            isDefault: true,
            dimensions: MediaDimensions(width: 1_920, height: 1_080),
            displayDimensions: MediaDimensions(width: 1_920, height: 1_080),
            pixelFormat: "yuv420p",
            bitDepth: 8,
            frameRate: frameRate,
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt709",
                transfer: "bt709",
                matrix: "bt709"
            )
        )
    }

    private func audio(id: Int) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            profile: "LC",
            language: "eng",
            title: "Main Audio",
            isDefault: true,
            channels: 6,
            channelLayout: "5.1(side)",
            sampleRate: 48_000
        )
    }

    private func subtitle(id: Int) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            language: "eng",
            title: "English"
        )
    }
}
