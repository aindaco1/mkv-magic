import Foundation
import MKVMagicCore
import MKVMagicPlanning
import XCTest

final class MKVRemuxPlannerTests: XCTestCase {
    private let planner = MKVRemuxPlanner()

    func testAcceptsCompatibleMP4MOVAndWebMWithoutEncoding() throws {
        for (path, container, videoCodec) in [
            ("/Media/Movie.mp4", "mov,mp4,m4a,3gp,3g2,mj2", "h264"),
            ("/Media/Movie.MOV", "mov,mp4,m4a,3gp,3g2,mj2", "prores"),
            ("/Media/Movie.webm", "matroska,webm", "vp9"),
        ] {
            let source = asset(path: path, container: container, videoCodec: videoCodec)
            let plan = try planner.resolve(source: source)

            XCTAssertEqual(plan.source, source)
            XCTAssertEqual(plan.trackIDsInOutputOrder, [4, 9])
            XCTAssertEqual(plan.copiedTrackCount, 2)
            XCTAssertEqual(plan.videoEncodeCount, 0)
            XCTAssertEqual(plan.audioEncodeCount, 0)
            XCTAssertTrue(planner.canOffer(for: source))
        }
    }

    func testAcceptsEveryDeclaredVideoAndAudioCopyFamily() throws {
        for codec in ["av1", "h264", "hevc", "prores", "vp8", "vp9", "mpeg2video"] {
            XCTAssertNoThrow(try planner.resolve(source: asset(videoCodec: codec)), codec)
        }
        for codec in [
            "aac", "ac3", "eac3", "opus", "vorbis", "flac", "alac", "pcm_s16le",
            "mp3", "dts", "truehd",
        ] {
            XCTAssertNoThrow(
                try planner.resolve(
                    source: asset(
                        tracks: [
                            MediaTrack(id: 4, kind: .video, codec: "h264"),
                            MediaTrack(id: 9, kind: .audio, codec: codec),
                        ]
                    )
                ),
                codec
            )
        }
    }

    func testAcceptsSupportedSubtitleCodecsAndRefusesTX3GConversion() throws {
        for codec in ["subrip", "ass", "ssa", "webvtt", "hdmv_pgs_subtitle", "dvd_subtitle"] {
            let source = asset(
                tracks: defaultTracks + [
                    MediaTrack(id: 12, kind: .subtitle, codec: codec, language: "eng")
                ]
            )
            XCTAssertEqual(try planner.resolve(source: source).trackIDsInOutputOrder, [4, 9, 12])
        }
        let timedText = asset(
            tracks: defaultTracks + [MediaTrack(id: 12, kind: .subtitle, codec: "mov_text")]
        )
        XCTAssertThrowsError(try planner.resolve(source: timedText)) { error in
            XCTAssertEqual(
                error as? MKVRemuxPlanningError,
                .unsupportedTrack(trackID: 12, codec: "mov_text")
            )
            XCTAssertTrue(error.localizedDescription.contains("TX3G"))
        }
    }

    func testAcceptsVorbisButDefersChapteredWebMUntilNestedHierarchyCanBeProved() throws {
        let webM = asset(
            path: "/Media/Movie.webm",
            container: "matroska,webm",
            tracks: [
                MediaTrack(id: 4, kind: .video, codec: "vp9"),
                MediaTrack(id: 9, kind: .audio, codec: "vorbis"),
            ]
        )
        XCTAssertNoThrow(try planner.resolve(source: webM))
        XCTAssertThrowsError(
            try planner.resolve(
                source: asset(
                    path: "/Media/Movie.webm",
                    container: "matroska,webm",
                    videoCodec: "vp9",
                    chapters: [ChapterNode(title: "Opening", start: .zero)]
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? MKVRemuxPlanningError,
                .chapteredWebMRequiresExactHierarchyAudit
            )
        }
    }

    func testRecognizesOnlyTheMP4ChapterCarrierAsNonMedia() throws {
        let chaptered = asset(
            tracks: defaultTracks + [
                MediaTrack(id: 12, kind: .data, codec: "bin_data")
            ],
            chapters: [ChapterNode(title: "Opening", start: .zero)]
        )
        let plan = try planner.resolve(source: chaptered)
        XCTAssertEqual(plan.trackIDsInOutputOrder, [4, 9])
        XCTAssertEqual(plan.chapterCarrierTrackIDs, [12])

        XCTAssertThrowsError(
            try planner.resolve(
                source: asset(
                    tracks: defaultTracks + [
                        MediaTrack(id: 12, kind: .data, codec: "bin_data")
                    ]
                )
            )
        ) { XCTAssertEqual($0 as? MKVRemuxPlanningError, .unsupportedStructure) }
    }

    func testRejectsUnsupportedContainersTracksAndAmbiguousVideo() {
        XCTAssertThrowsError(
            try planner.resolve(source: asset(path: "/Media/Movie.avi", container: "avi"))
        ) { XCTAssertEqual($0 as? MKVRemuxPlanningError, .unsupportedContainer) }
        XCTAssertThrowsError(
            try planner.resolve(source: asset(path: "/Media/Movie.mp4", container: "avi"))
        ) { XCTAssertEqual($0 as? MKVRemuxPlanningError, .unsupportedContainer) }
        XCTAssertThrowsError(
            try planner.resolve(source: asset(path: "/Media/Movie.webm", container: "avi"))
        ) { XCTAssertEqual($0 as? MKVRemuxPlanningError, .unsupportedContainer) }
        XCTAssertThrowsError(
            try planner.resolve(source: asset(path: "/Media/Movie.mkv", container: "matroska"))
        ) { XCTAssertEqual($0 as? MKVRemuxPlanningError, .alreadyMatroskaMKV) }
        XCTAssertThrowsError(
            try planner.resolve(source: asset(tracks: [defaultTracks[1]]))
        ) { XCTAssertEqual($0 as? MKVRemuxPlanningError, .missingVideo) }
        XCTAssertThrowsError(
            try planner.resolve(
                source: asset(
                    tracks: defaultTracks + [MediaTrack(id: 11, kind: .video, codec: "h264")]
                )
            )
        ) { XCTAssertEqual($0 as? MKVRemuxPlanningError, .multipleVideoTracks) }
        XCTAssertThrowsError(
            try planner.resolve(
                source: asset(
                    tracks: defaultTracks + [MediaTrack(id: 15, kind: .data, codec: "tmcd")]
                )
            )
        ) { XCTAssertEqual($0 as? MKVRemuxPlanningError, .unsupportedStructure) }
    }

    func testRejectsUnknownCodecsDurationAndDuplicateIndexes() {
        XCTAssertThrowsError(
            try planner.resolve(source: asset(videoCodec: "indeo5"))
        ) {
            XCTAssertEqual(
                $0 as? MKVRemuxPlanningError,
                .unsupportedTrack(trackID: 4, codec: "indeo5")
            )
        }
        XCTAssertThrowsError(
            try planner.resolve(source: asset(duration: nil))
        ) { XCTAssertEqual($0 as? MKVRemuxPlanningError, .invalidDuration) }
        XCTAssertThrowsError(
            try planner.resolve(
                source: asset(
                    tracks: [
                        MediaTrack(id: 4, kind: .video, codec: "h264"),
                        MediaTrack(id: 4, kind: .audio, codec: "aac"),
                    ]
                )
            )
        ) { XCTAssertEqual($0 as? MKVRemuxPlanningError, .unstableTrackIdentity) }
    }

    private var defaultTracks: [MediaTrack] {
        [
            MediaTrack(id: 4, kind: .video, codec: "h264"),
            MediaTrack(id: 9, kind: .audio, codec: "aac", language: "eng"),
        ]
    }

    private func asset(
        path: String = "/Media/Movie.mp4",
        container: String = "mov,mp4,m4a,3gp,3g2,mj2",
        duration: MediaTime? = MediaTime(nanoseconds: 60_000_000_000),
        videoCodec: String = "h264",
        tracks: [MediaTrack]? = nil,
        chapters: [ChapterNode] = []
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: path),
            container: container,
            duration: duration,
            tracks: tracks ?? [
                MediaTrack(id: 4, kind: .video, codec: videoCodec),
                MediaTrack(id: 9, kind: .audio, codec: "aac", language: "eng"),
            ],
            chapters: chapters
        )
    }
}
