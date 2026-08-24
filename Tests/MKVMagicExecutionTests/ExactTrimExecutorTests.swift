import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

private actor ExactTrimToolRunner: CommandRunning {
    private let sourceURL: URL
    private let sourceChapters: Data
    private let failingTool: String?
    private let wrongOutputChapters: Bool
    private let sourceToMutate: URL?
    private var outputChapters: Data?
    private var requests = [CommandRequest]()

    init(
        sourceURL: URL,
        sourceChapters: Data,
        failingTool: String? = nil,
        wrongOutputChapters: Bool = false,
        sourceToMutate: URL? = nil
    ) {
        self.sourceURL = sourceURL
        self.sourceChapters = sourceChapters
        self.failingTool = failingTool
        self.wrongOutputChapters = wrongOutputChapters
        self.sourceToMutate = sourceToMutate
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        let tool = request.executableURL.lastPathComponent
        if failingTool == tool { return result(exitCode: 81) }
        switch tool {
        case "ffmpeg":
            guard let output = request.arguments.last else { return result(exitCode: 2) }
            try Data("one generation exact trim".utf8).write(
                to: URL(fileURLWithPath: output)
            )
            if let sourceToMutate {
                try Data("changed during exact encode".utf8).write(
                    to: sourceToMutate,
                    options: .atomic
                )
            }
            return result()
        case "mkvextract":
            guard request.arguments.count == 3 else { return result(exitCode: 2) }
            let inputURL = URL(fileURLWithPath: request.arguments[0])
            let outputURL = URL(fileURLWithPath: request.arguments[2])
            let data: Data
            if inputURL == sourceURL {
                data = sourceChapters
            } else if wrongOutputChapters {
                data = try MatroskaChapterXMLCodec().serialize(MatroskaChapterDocument())
            } else if let outputChapters {
                data = outputChapters
            } else {
                return result(exitCode: 2)
            }
            try data.write(to: outputURL)
            return result()
        case "mkvpropedit":
            guard let chapters = value(after: "--chapters", in: request.arguments),
                !chapters.isEmpty
            else {
                outputChapters = try MatroskaChapterXMLCodec().serialize(
                    MatroskaChapterDocument()
                )
                return result()
            }
            outputChapters = try Data(contentsOf: URL(fileURLWithPath: chapters))
            return result()
        default:
            return result(exitCode: 2)
        }
    }

    func capturedRequests() -> [CommandRequest] { requests }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    private func result(exitCode: Int32 = 0) -> CommandResult {
        CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(
                data: exitCode == 0 ? Data() : Data("fixture tool failure".utf8),
                wasTruncated: false
            )
        )
    }
}

private actor ExactTrimInspector: MediaInspecting {
    enum Behavior: Equatable, Sendable {
        case valid
        case fullDuration
        case wrongDuration
        case wrongVideo
        case wrongCommittedVideo
    }

    private let source: MediaAsset
    private let behavior: Behavior
    private var inspections = 0

    init(source: MediaAsset, behavior: Behavior = .valid) {
        self.source = source
        self.behavior = behavior
    }

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        inspections += 1
        let wrongVideo =
            behavior == .wrongVideo
            || (behavior == .wrongCommittedVideo && inspections == 2)
        let sourceAudio = source.tracks[1]
        return MediaAsset(
            sourceURL: inputURL,
            container: "matroska,webm",
            duration: MediaTime(
                nanoseconds:
                    behavior == .wrongDuration
                    ? 4_000_000_000 : (behavior == .fullDuration ? 10_000_000_000 : 5_500_000_000)
            ),
            fileSize: Int64(
                (try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            ),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: wrongVideo ? "h264" : "hevc",
                    codecID: wrongVideo ? "V_MPEG4/ISO/AVC" : "V_MPEGH/ISO/HEVC",
                    profile: wrongVideo ? "High" : "Main 10",
                    uid: 500,
                    isDefault: true,
                    dimensions: MediaDimensions(width: 160, height: 90),
                    pixelFormat: wrongVideo ? "yuv420p" : "p010le",
                    bitDepth: wrongVideo ? 8 : 10,
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
                    codec: sourceAudio.codec,
                    codecID: sourceAudio.codecID,
                    profile: sourceAudio.profile,
                    uid: 501,
                    language: sourceAudio.language,
                    title: sourceAudio.title,
                    isDefault: sourceAudio.isDefault,
                    channels: sourceAudio.channels,
                    channelLayout: sourceAudio.channelLayout,
                    sampleRate: sourceAudio.sampleRate
                ),
            ],
            metadata: source.metadata,
            chapterEntryCount: 1,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "EXACT-OUTPUT"
        )
    }
}

private actor ExactTrimStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()
    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func values() -> [VerifiedOutputExecutionStage] { stages }
}

final class ExactTrimExecutorTests: XCTestCase {
    func testWholeFileTranscodePreservesNestedChapterDocumentAndEncodesVideoOnce() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = ExactTrimToolRunner(
            sourceURL: fixture.source.sourceURL,
            sourceChapters: fixture.chapterData
        )
        let executor = makeExecutor(
            runner: runner,
            inspector: ExactTrimInspector(source: fixture.source, behavior: .fullDuration)
        )
        let preview = try await executor.preview(
            source: fixture.source,
            range: MediaTrimRange(
                start: .zero,
                end: try XCTUnwrap(fixture.source.duration)
            ),
            choice: choice(),
            operation: .transcode,
            capabilities: capabilities()
        )

        XCTAssertEqual(preview.resolvedPlan.operation, .transcode)
        XCTAssertEqual(preview.trimmedChapters, preview.originalChapters)
        let destination = fixture.root.appendingPathComponent("Converted.mkv")
        _ = try await executor.execute(preview: preview, destinationURL: destination)

        let requests = await runner.capturedRequests()
        let ffmpeg = try XCTUnwrap(
            requests.first { $0.executableURL.lastPathComponent == "ffmpeg" }
        )
        XCTAssertEqual(value(after: "-ss", in: ffmpeg.arguments), "0.000000000")
        XCTAssertEqual(value(after: "-t", in: ffmpeg.arguments), "10.000000000")
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "ffmpeg" }.count,
            1
        )
    }

    func testExecutesOneVideoGenerationCopiesAudioAndAuditsExactChaptersTwice() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let originalBytes = try Data(contentsOf: fixture.source.sourceURL)
        let runner = ExactTrimToolRunner(
            sourceURL: fixture.source.sourceURL,
            sourceChapters: fixture.chapterData
        )
        let executor = makeExecutor(
            runner: runner,
            inspector: ExactTrimInspector(source: fixture.source)
        )
        let preview = try await executor.preview(
            source: fixture.source,
            range: exactRange(),
            choice: choice(),
            capabilities: capabilities()
        )
        XCTAssertEqual(preview.resolvedPlan.range, exactRange())
        XCTAssertEqual(preview.encodedVideoTrackID, 0)
        XCTAssertEqual(preview.encodedAudioTrackIDs, [])
        XCTAssertEqual(preview.copiedAudioTrackIDs, [1])
        XCTAssertEqual(preview.trimmedChapters.editions[0].chapters[0].start, .zero)
        XCTAssertEqual(
            preview.trimmedChapters.editions[0].chapters[0].end,
            MediaTime(nanoseconds: 5_500_000_000)
        )
        let destination = fixture.root.appendingPathComponent("Exact Trim.mkv")
        let recorder = ExactTrimStageRecorder()

        let output = try await executor.execute(
            preview: preview,
            destinationURL: destination,
            onStage: { stage in await recorder.append(stage) }
        )

        XCTAssertEqual(output.sourceURL, destination)
        XCTAssertEqual(try Data(contentsOf: fixture.source.sourceURL), originalBytes)
        let stages = await recorder.values()
        XCTAssertEqual(stages, [.verifying, .committing])
        let requests = await runner.capturedRequests()
        XCTAssertEqual(requests.filter { $0.executableURL.lastPathComponent == "ffmpeg" }.count, 1)
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvpropedit" }.count,
            1
        )
        let ffmpeg = try XCTUnwrap(
            requests.first { $0.executableURL.lastPathComponent == "ffmpeg" }
        )
        XCTAssertEqual(value(after: "-ss", in: ffmpeg.arguments), "2.250000000")
        XCTAssertEqual(value(after: "-t", in: ffmpeg.arguments), "5.500000000")
        XCTAssertEqual(value(after: "-c", in: ffmpeg.arguments), "copy")
        XCTAssertEqual(value(after: "-c:v:0", in: ffmpeg.arguments), "hevc_videotoolbox")
        XCTAssertFalse(ffmpeg.arguments.contains("-c:a:0"))
        XCTAssertNotEqual(ffmpeg.arguments.last, destination.path)
        let propertyEdit = try XCTUnwrap(
            requests.first { $0.executableURL.lastPathComponent == "mkvpropedit" }
        )
        XCTAssertEqual(value(after: "--tags", in: propertyEdit.arguments), "all:")
        let outputExtracts = requests.filter {
            $0.executableURL.lastPathComponent == "mkvextract"
                && $0.arguments.first != fixture.source.sourceURL.path
        }
        XCTAssertEqual(outputExtracts.count, 2)
    }

    func testChangedSourceBeforeOrDuringEncodeNeverCommits() async throws {
        let before = try makeFixture()
        defer { try? FileManager.default.removeItem(at: before.root) }
        let beforeRunner = ExactTrimToolRunner(
            sourceURL: before.source.sourceURL,
            sourceChapters: before.chapterData
        )
        let beforeExecutor = makeExecutor(
            runner: beforeRunner,
            inspector: ExactTrimInspector(source: before.source)
        )
        let beforePreview = try await beforeExecutor.preview(
            source: before.source,
            range: exactRange(),
            choice: choice(),
            capabilities: capabilities()
        )
        try Data("changed before exact trim".utf8).write(
            to: before.source.sourceURL,
            options: .atomic
        )
        let beforeDestination = before.root.appendingPathComponent("before.mkv")
        await exactAssertThrows(
            try await beforeExecutor.execute(
                preview: beforePreview,
                destinationURL: beforeDestination
            )
        ) { XCTAssertEqual($0 as? ExactTrimExecutionError, .staleSource) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: beforeDestination.path))

        let during = try makeFixture()
        defer { try? FileManager.default.removeItem(at: during.root) }
        let duringRunner = ExactTrimToolRunner(
            sourceURL: during.source.sourceURL,
            sourceChapters: during.chapterData,
            sourceToMutate: during.source.sourceURL
        )
        let duringExecutor = makeExecutor(
            runner: duringRunner,
            inspector: ExactTrimInspector(source: during.source)
        )
        let duringPreview = try await duringExecutor.preview(
            source: during.source,
            range: exactRange(),
            choice: choice(),
            capabilities: capabilities()
        )
        let duringDestination = during.root.appendingPathComponent("during.mkv")
        await exactAssertThrows(
            try await duringExecutor.execute(
                preview: duringPreview,
                destinationURL: duringDestination
            )
        ) { XCTAssertEqual($0 as? ExactTrimExecutionError, .staleSource) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: duringDestination.path))
    }

    func testToolVideoDurationAndChapterFailuresLeaveNoDestination() async throws {
        for mode in 0..<4 {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let runner = ExactTrimToolRunner(
                sourceURL: fixture.source.sourceURL,
                sourceChapters: fixture.chapterData,
                failingTool: mode == 0 ? "ffmpeg" : nil,
                wrongOutputChapters: mode == 3
            )
            let behavior: ExactTrimInspector.Behavior =
                switch mode {
                case 1: .wrongVideo
                case 2: .wrongDuration
                default: .valid
                }
            let executor = makeExecutor(
                runner: runner,
                inspector: ExactTrimInspector(source: fixture.source, behavior: behavior)
            )
            let preview = try await executor.preview(
                source: fixture.source,
                range: exactRange(),
                choice: choice(),
                capabilities: capabilities()
            )
            let destination = fixture.root.appendingPathComponent("failed.mkv")
            await exactAssertThrows(
                try await executor.execute(
                    preview: preview,
                    destinationURL: destination
                )
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testCommittedReopenFailureReportsSavedOutput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = ExactTrimToolRunner(
            sourceURL: fixture.source.sourceURL,
            sourceChapters: fixture.chapterData
        )
        let executor = makeExecutor(
            runner: runner,
            inspector: ExactTrimInspector(
                source: fixture.source,
                behavior: .wrongCommittedVideo
            )
        )
        let preview = try await executor.preview(
            source: fixture.source,
            range: exactRange(),
            choice: choice(),
            capabilities: capabilities()
        )
        let destination = fixture.root.appendingPathComponent("audit-failed.mkv")

        await exactAssertThrows(
            try await executor.execute(preview: preview, destinationURL: destination)
        ) { error in
            guard
                case .committedOutputAuditFailed(let outputURL, _) =
                    error as? ExactTrimExecutionError
            else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(outputURL, destination)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    private struct Fixture {
        let root: URL
        let source: MediaAsset
        let chapterData: Data
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-exact-executor-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sourceURL = root.appendingPathComponent("Source.mkv")
        try Data("original exact source".utf8).write(to: sourceURL)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            fileSize: Int64("original exact source".utf8.count),
            tracks: [sourceVideo(), sourceAudio()],
            metadata: ["title": "Feature"],
            chapterEntryCount: 1,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "SOURCE-SEGMENT"
        )
        let chapters = MatroskaChapterDocument(editions: [
            MatroskaChapterEdition(
                isDefault: true,
                chapters: [
                    MatroskaChapterAtom(
                        start: .zero,
                        end: MediaTime(nanoseconds: 10_000_000_000),
                        displays: [ChapterDisplay(title: "Complete Feature")]
                    )
                ]
            )
        ])
        return Fixture(
            root: root,
            source: source,
            chapterData: try MatroskaChapterXMLCodec().serialize(chapters)
        )
    }

    private func makeExecutor(
        runner: ExactTrimToolRunner,
        inspector: ExactTrimInspector
    ) -> ExactTrimExecutor<ExactTrimToolRunner, ExactTrimInspector> {
        ExactTrimExecutor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: inspector
        )
    }

    private func capabilities() -> FFmpegEncodingCapabilities {
        FFmpegEncodingCapabilities(
            softwareAV1: .unavailable,
            softwareAV1Encoder: nil,
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .unavailable,
            proResEncoder: nil,
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters
        )
    }

    private func choice() -> ExactTrimChoice {
        ExactTrimChoice(
            videoPreset: .hevcCompatibility,
            videoRateControl: .averageBitrate(2_000_000),
            audioPolicy: .packetCopy
        )
    }

    private func exactRange() -> MediaTrimRange {
        MediaTrimRange(
            start: MediaTime(nanoseconds: 2_250_000_000),
            end: MediaTime(nanoseconds: 7_750_000_000)
        )
    }

    private func sourceVideo() -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            profile: "High",
            uid: 100,
            isDefault: true,
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
        )
    }

    private func sourceAudio() -> MediaTrack {
        MediaTrack(
            id: 1,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            profile: "LC",
            uid: 101,
            language: "en",
            title: "Main Audio",
            isDefault: true,
            channels: 2,
            channelLayout: "stereo",
            sampleRate: 48_000
        )
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}

private func exactAssertThrows<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (any Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
