import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

private actor LosslessJoinToolRunner: CommandRunning {
    private let wrongChapters: Bool
    private let toolExitCode: Int32
    private let sourceToMutate: URL?
    private var expectedChapterData: Data?
    private var requests = [CommandRequest]()

    init(
        wrongChapters: Bool = false,
        toolExitCode: Int32 = 0,
        sourceToMutate: URL? = nil
    ) {
        self.wrongChapters = wrongChapters
        self.toolExitCode = toolExitCode
        self.sourceToMutate = sourceToMutate
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        switch request.executableURL.lastPathComponent {
        case "mkvmerge":
            guard toolExitCode == 0,
                let outputIndex = request.arguments.firstIndex(of: "--output"),
                request.arguments.indices.contains(outputIndex + 1),
                let chapterIndex = request.arguments.firstIndex(of: "--chapters"),
                request.arguments.indices.contains(chapterIndex + 1)
            else {
                return result(exitCode: toolExitCode == 0 ? 2 : toolExitCode)
            }
            expectedChapterData = try Data(
                contentsOf: URL(fileURLWithPath: request.arguments[chapterIndex + 1])
            )
            try Data("joined output".utf8).write(
                to: URL(fileURLWithPath: request.arguments[outputIndex + 1])
            )
            if let sourceToMutate {
                try Data("source changed while joining".utf8).write(
                    to: sourceToMutate,
                    options: .atomic
                )
            }
            return result(exitCode: 0)
        case "mkvextract":
            guard request.arguments.count == 3, let expectedChapterData else {
                return result(exitCode: 2)
            }
            let data =
                wrongChapters
                ? try MatroskaChapterXMLCodec().serialize(MatroskaChapterDocument())
                : expectedChapterData
            try data.write(to: URL(fileURLWithPath: request.arguments[2]))
            return result(exitCode: 0)
        default:
            return result(exitCode: 2)
        }
    }

    func capturedRequests() -> [CommandRequest] { requests }

    private func result(exitCode: Int32) -> CommandResult {
        CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(
                data: exitCode == 0 ? Data() : Data("fixture failure".utf8),
                wasTruncated: false
            )
        )
    }
}

private struct LosslessJoinInspector: MediaInspecting {
    let sources: [MediaAsset]
    let chapters: JoinedChapterComposition
    let wrongDuration: Bool

    init(
        sources: [MediaAsset],
        chapters: JoinedChapterComposition,
        wrongDuration: Bool = false
    ) {
        self.sources = sources
        self.chapters = chapters
        self.wrongDuration = wrongDuration
    }

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: "matroska,webm",
            duration: wrongDuration
                ? MediaTime(nanoseconds: chapters.duration.nanoseconds + 1_000_000_000)
                : chapters.duration,
            fileSize: Int64(
                (try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            ),
            tracks: sources[0].tracks,
            metadata: sources[0].metadata,
            chapterEntryCount: chapters.document.editions.reduce(0) {
                $0 + $1.chapters.count
            },
            globalTagCount: sources[0].globalTagCount,
            trackTagCount: sources[0].trackTagCount,
            segmentUID: "99999999999999999999999999999999",
            muxingApplication: "libebml",
            writingApplication: "mkvmerge"
        )
    }
}

private actor LosslessJoinStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()

    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func values() -> [VerifiedOutputExecutionStage] { stages }
}

final class LosslessJoinExecutorTests: XCTestCase {
    func testCommandUsesExplicitAdjacentMappingAndScopedInputPolicy() throws {
        let sources = commandAssets()
        let mapping = mappingForThreeTracks()
        let arguments = try MKVLosslessJoiner<FoundationCommandRunner>.arguments(
            sources: sources,
            mapping: mapping,
            chaptersURL: URL(fileURLWithPath: "/private/chapters.xml"),
            outputURL: URL(fileURLWithPath: "/private/output.mkv")
        )

        XCTAssertEqual(
            arguments,
            [
                "--output", "/private/output.mkv",
                "--abort-on-warnings",
                "--flush-on-close",
                "--normalize-language-ietf", "canonical",
                "--disable-track-statistics-tags",
                "--append-mode", "file",
                "--append-to",
                "1:10:0:0,2:20:1:10,1:11:0:1,2:21:1:11,1:12:0:2,2:22:1:12",
                "--track-order", "0:0,0:1,0:2",
                "--chapters", "/private/chapters.xml",
                "--video-tracks", "0",
                "--audio-tracks", "1",
                "--subtitle-tracks", "2",
                "--no-buttons", "--no-attachments", "--no-chapters",
                "/private/part-one.mkv",
                "--video-tracks", "10",
                "--audio-tracks", "11",
                "--subtitle-tracks", "12",
                "--no-buttons", "--no-attachments", "--no-chapters",
                "--no-track-tags", "--no-global-tags",
                "+/private/part-two.mkv",
                "--video-tracks", "20",
                "--audio-tracks", "21",
                "--subtitle-tracks", "22",
                "--no-buttons", "--no-attachments", "--no-chapters",
                "--no-track-tags", "--no-global-tags",
                "+/private/part-three.mkv",
            ]
        )
    }

    func testVerifiedJoinCommitsOneOutputAndPreservesEverySource() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let originalBytes = try fixture.sources.map { try Data(contentsOf: $0.sourceURL) }
        let runner = LosslessJoinToolRunner()
        let executor = makeExecutor(
            runner: runner,
            sources: fixture.sources,
            chapters: fixture.chapters
        )
        let preview = try executor.preview(
            sources: fixture.sources,
            mapping: fixture.mapping,
            chapters: fixture.chapters
        )
        let destination = fixture.directory.appendingPathComponent("joined.mkv")
        let recorder = LosslessJoinStageRecorder()

        let output = try await executor.execute(
            preview: preview,
            destinationURL: destination,
            onStage: { stage in await recorder.append(stage) }
        )

        XCTAssertEqual(output.sourceURL, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(
            try fixture.sources.map { try Data(contentsOf: $0.sourceURL) },
            originalBytes
        )
        let stages = await recorder.values()
        XCTAssertEqual(stages, [.verifying, .committing])
        let requests = await runner.capturedRequests()
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvmerge" }.count,
            1
        )
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvextract" }.count,
            2
        )
    }

    func testChangedSourceAfterPreviewFailsBeforeMkvmerge() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let runner = LosslessJoinToolRunner()
        let executor = makeExecutor(
            runner: runner,
            sources: fixture.sources,
            chapters: fixture.chapters
        )
        let preview = try executor.preview(
            sources: fixture.sources,
            mapping: fixture.mapping,
            chapters: fixture.chapters
        )
        try Data("changed second source".utf8).write(
            to: fixture.sources[1].sourceURL,
            options: .atomic
        )
        let destination = fixture.directory.appendingPathComponent("stale.mkv")

        do {
            _ = try await executor.execute(preview: preview, destinationURL: destination)
            XCTFail("Expected stale source refusal")
        } catch {
            XCTAssertEqual(error as? LosslessJoinExecutionError, .staleSource)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let requests = await runner.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testSourceChangedWhileMkvmergeRunsCannotCommit() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let runner = LosslessJoinToolRunner(sourceToMutate: fixture.sources[1].sourceURL)
        let executor = makeExecutor(
            runner: runner,
            sources: fixture.sources,
            chapters: fixture.chapters
        )
        let preview = try executor.preview(
            sources: fixture.sources,
            mapping: fixture.mapping,
            chapters: fixture.chapters
        )
        let destination = fixture.directory.appendingPathComponent("changed-during-run.mkv")

        do {
            _ = try await executor.execute(preview: preview, destinationURL: destination)
            XCTFail("Expected source revision refusal")
        } catch {
            XCTAssertEqual(error as? LosslessJoinExecutionError, .staleSource)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let requests = await runner.capturedRequests()
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvmerge" }.count,
            1
        )
        XCTAssertFalse(requests.contains { $0.executableURL.lastPathComponent == "mkvextract" })
    }

    func testWrongChaptersOrOutputDurationNeverCommits() async throws {
        for wrongDuration in [false, true] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let runner = LosslessJoinToolRunner(wrongChapters: !wrongDuration)
            let executor = LosslessJoinExecutor(
                mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
                mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
                runner: runner,
                inspector: LosslessJoinInspector(
                    sources: fixture.sources,
                    chapters: fixture.chapters,
                    wrongDuration: wrongDuration
                )
            )
            let preview = try executor.preview(
                sources: fixture.sources,
                mapping: fixture.mapping,
                chapters: fixture.chapters
            )
            let destination = fixture.directory.appendingPathComponent("bad.mkv")

            do {
                _ = try await executor.execute(preview: preview, destinationURL: destination)
                XCTFail("Expected output verification refusal")
            } catch {
                if wrongDuration {
                    XCTAssertEqual(error as? OutputVerificationError, .durationChanged)
                } else {
                    XCTAssertEqual(
                        error as? LosslessJoinExecutionError,
                        .chapterVerificationFailed
                    )
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testReviewClassificationsAndUnstableUIDsCannotRenderACommand() throws {
        var sources = commandAssets()
        let incompatible = MediaTrack(
            id: 10,
            kind: .video,
            codec: "hevc",
            codecID: "V_MPEGH/ISO/HEVC",
            profile: "Main",
            level: 13,
            uid: 110,
            language: "und",
            isDefault: true,
            dimensions: MediaDimensions(width: 1_920, height: 1_080),
            displayDimensions: MediaDimensions(width: 1_920, height: 1_080),
            pixelFormat: "yuv420p",
            bitDepth: 8,
            frameRate: "24",
            colorInfo: MediaColorInfo()
        )
        sources[1] = replacingTrack(in: sources[1], trackID: 10, with: incompatible)
        XCTAssertThrowsError(
            try MKVLosslessJoiner<FoundationCommandRunner>.arguments(
                sources: sources,
                mapping: mappingForThreeTracks(),
                chaptersURL: URL(fileURLWithPath: "/private/chapters.xml"),
                outputURL: URL(fileURLWithPath: "/private/output.mkv")
            )
        ) { error in
            XCTAssertEqual(
                error as? LosslessJoinExecutionError,
                .requiresReview(.normalizationRequired)
            )
        }

        var unstableSources = commandAssets()
        unstableSources[0] = replacingTrack(
            in: unstableSources[0],
            trackID: 0,
            with: video(id: 0, uid: nil)
        )
        XCTAssertThrowsError(
            try MKVLosslessJoiner<FoundationCommandRunner>.arguments(
                sources: unstableSources,
                mapping: mappingForThreeTracks(),
                chaptersURL: URL(fileURLWithPath: "/private/chapters.xml"),
                outputURL: URL(fileURLWithPath: "/private/output.mkv")
            )
        ) { error in
            XCTAssertEqual(
                error as? LosslessJoinExecutionError,
                .missingStableTrackIdentity
            )
        }
    }

    private func makeExecutor(
        runner: LosslessJoinToolRunner,
        sources: [MediaAsset],
        chapters: JoinedChapterComposition
    ) -> LosslessJoinExecutor<LosslessJoinToolRunner, LosslessJoinInspector> {
        LosslessJoinExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: LosslessJoinInspector(sources: sources, chapters: chapters)
        )
    }

    private func makeFixture() throws -> (
        directory: URL,
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        chapters: JoinedChapterComposition
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-lossless-join-unit-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let firstURL = directory.appendingPathComponent("one.mkv")
        let secondURL = directory.appendingPathComponent("two.mkv")
        try Data("first source".utf8).write(to: firstURL)
        try Data("second source".utf8).write(to: secondURL)
        let duration = MediaTime(nanoseconds: 1_000_000_000)
        let sources = [
            asset(
                url: firstURL,
                duration: duration,
                fileSize: 12,
                tracks: [video(id: 0, uid: 100), audio(id: 1, uid: 101)],
                segmentUID: "11111111111111111111111111111111"
            ),
            asset(
                url: secondURL,
                duration: duration,
                fileSize: 13,
                tracks: [video(id: 10, uid: 110), audio(id: 11, uid: 111)],
                segmentUID: "22222222222222222222222222222222"
            ),
        ]
        let mapping = JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .video, trackIDsBySource: [0, 10]),
            JoinTrackLane(kind: .audio, trackIDsBySource: [1, 11]),
        ])
        let chapters = try JoinedChapterComposer().compose([
            JoinedChapterSource(
                title: "One",
                duration: duration,
                retainedStart: .zero,
                retainedEnd: duration,
                selectedEditionChapters: []
            ),
            JoinedChapterSource(
                title: "Two",
                duration: duration,
                retainedStart: .zero,
                retainedEnd: duration,
                selectedEditionChapters: []
            ),
        ])
        return (directory, sources, mapping, chapters)
    }

    private func commandAssets() -> [MediaAsset] {
        let duration = MediaTime(nanoseconds: 1_000_000_000)
        return [
            asset(
                url: URL(fileURLWithPath: "/private/part-one.mkv"),
                duration: duration,
                tracks: [
                    video(id: 0, uid: 100), audio(id: 1, uid: 101), subtitle(id: 2, uid: 102),
                ],
                segmentUID: "11111111111111111111111111111111"
            ),
            asset(
                url: URL(fileURLWithPath: "/private/part-two.mkv"),
                duration: duration,
                tracks: [
                    video(id: 10, uid: 110), audio(id: 11, uid: 111),
                    subtitle(id: 12, uid: 112),
                ],
                segmentUID: "22222222222222222222222222222222"
            ),
            asset(
                url: URL(fileURLWithPath: "/private/part-three.mkv"),
                duration: duration,
                tracks: [
                    video(id: 20, uid: 120), audio(id: 21, uid: 121),
                    subtitle(id: 22, uid: 122),
                ],
                segmentUID: "33333333333333333333333333333333"
            ),
        ]
    }

    private func mappingForThreeTracks() -> JoinTrackMapping {
        JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .video, trackIDsBySource: [0, 10, 20]),
            JoinTrackLane(kind: .audio, trackIDsBySource: [1, 11, 21]),
            JoinTrackLane(kind: .subtitle, trackIDsBySource: [2, 12, 22]),
        ])
    }

    private func asset(
        url: URL,
        duration: MediaTime,
        fileSize: Int64? = nil,
        tracks: [MediaTrack],
        segmentUID: String
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: url,
            container: "matroska,webm",
            duration: duration,
            fileSize: fileSize,
            tracks: tracks,
            metadata: ["title": "Joined Fixture"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: segmentUID
        )
    }

    private func video(id: Int, uid: UInt64?) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .video,
            codec: "av1",
            codecID: "V_AV1",
            profile: "Main",
            level: 13,
            uid: uid,
            language: "und",
            isDefault: true,
            dimensions: MediaDimensions(width: 1_920, height: 1_080),
            displayDimensions: MediaDimensions(width: 1_920, height: 1_080),
            pixelFormat: "yuv420p",
            bitDepth: 8,
            frameRate: "24",
            colorInfo: MediaColorInfo()
        )
    }

    private func audio(id: Int, uid: UInt64) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            profile: "LC",
            uid: uid,
            language: "en",
            title: "Main Audio",
            isDefault: true,
            channels: 2,
            channelLayout: "stereo",
            sampleRate: 48_000
        )
    }

    private func subtitle(id: Int, uid: UInt64) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: uid,
            language: "en",
            title: "English"
        )
    }

    private func replacingTrack(
        in asset: MediaAsset,
        trackID: Int,
        with replacement: MediaTrack
    ) -> MediaAsset {
        MediaAsset(
            id: asset.id,
            sourceURL: asset.sourceURL,
            container: asset.container,
            formatLongName: asset.formatLongName,
            duration: asset.duration,
            fileSize: asset.fileSize,
            bitrate: asset.bitrate,
            tracks: asset.tracks.map { $0.id == trackID ? replacement : $0 },
            chapters: asset.chapters,
            attachments: asset.attachments,
            metadata: asset.metadata,
            chapterEntryCount: asset.chapterEntryCount,
            globalTagCount: asset.globalTagCount,
            trackTagCount: asset.trackTagCount,
            segmentUID: asset.segmentUID,
            muxingApplication: asset.muxingApplication,
            writingApplication: asset.writingApplication,
            warnings: asset.warnings
        )
    }
}
