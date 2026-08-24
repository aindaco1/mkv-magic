import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

private actor RemuxExecutorRunner: CommandRunning, CommandLineDigesting {
    let sourceToMutate: URL?
    let exitCode: Int32
    private var requests = [CommandRequest]()

    init(sourceToMutate: URL? = nil, exitCode: Int32 = 0) {
        self.sourceToMutate = sourceToMutate
        self.exitCode = exitCode
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        if request.executableURL.lastPathComponent == "mkvmerge", exitCode == 0,
            let outputIndex = request.arguments.firstIndex(of: "--output"),
            request.arguments.indices.contains(outputIndex + 1)
        {
            try Data("remuxed output".utf8).write(
                to: URL(fileURLWithPath: request.arguments[outputIndex + 1])
            )
            if let sourceToMutate {
                try Data("changed during remux".utf8).write(to: sourceToMutate)
            }
        }
        return CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(
                data: exitCode == 0 ? Data() : Data("fixture failure".utf8),
                wasTruncated: false
            )
        )
    }

    func digestLines(
        _ requests: [CommandRequest],
        policy: CommandLineDigestPolicy
    ) async throws -> CommandLineDigest {
        self.requests.append(contentsOf: requests)
        return digest
    }

    func digestTrailingHexLines(
        _ requests: [CommandRequest],
        policy: CommandTrailingHexDigestPolicy
    ) async throws -> CommandLineDigest {
        self.requests.append(contentsOf: requests)
        return digest
    }

    func digestIntegerKeyedLines(
        _ requests: [CommandIntegerKeyedDigestRequest],
        policy: CommandIntegerKeyedLineDigestPolicy
    ) async throws -> [Int: CommandLineDigest] {
        self.requests.append(contentsOf: requests.map(\.command))
        let keys = Set(requests.flatMap { $0.emittedKeyToDigestKey.values })
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, digest) })
    }

    func capturedRequests() -> [CommandRequest] { requests }

    private var digest: CommandLineDigest {
        CommandLineDigest(sha256: Data(repeating: 7, count: 32), lineCount: 4)
    }
}

private struct RemuxExecutorInspector: MediaInspecting {
    let source: MediaAsset

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: "matroska,webm",
            duration: source.duration,
            fileSize: Int64(
                (try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            ),
            tracks: source.tracks.enumerated().map { index, track in
                MediaTrack(
                    id: index,
                    kind: track.kind,
                    codec: track.codec,
                    profile: track.profile,
                    level: track.level,
                    uid: UInt64(index + 100),
                    language: track.language,
                    title: track.title,
                    isDefault: track.isDefault,
                    isForced: track.isForced,
                    isEnabled: track.isEnabled,
                    isCommentary: track.isCommentary,
                    isHearingImpaired: track.isHearingImpaired,
                    isVisualImpaired: track.isVisualImpaired,
                    isOriginal: track.isOriginal,
                    isTextDescription: track.isTextDescription,
                    channels: track.channels,
                    channelLayout: track.channelLayout,
                    sampleRate: track.sampleRate,
                    dimensions: track.dimensions,
                    pixelFormat: track.pixelFormat,
                    bitDepth: track.bitDepth,
                    frameRate: track.frameRate,
                    colorInfo: track.colorInfo,
                    masteringDisplayMetadata: track.masteringDisplayMetadata,
                    contentLightLevelMetadata: track.contentLightLevelMetadata,
                    hdrFormats: track.hdrFormats
                )
            },
            chapters: source.chapters,
            metadata: source.metadata,
            chapterEntryCount: source.chapterEntryCount,
            segmentUID: "0123456789abcdef0123456789abcdef"
        )
    }
}

private actor RemuxStageRecorder {
    private var stages = [VerifiedOutputExecutionStage]()
    func append(_ stage: VerifiedOutputExecutionStage) { stages.append(stage) }
    func values() -> [VerifiedOutputExecutionStage] { stages }
}

final class MKVRemuxExecutorTests: XCTestCase {
    func testCommitsOneVerifiedOutputAndPreservesSource() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let originalData = try Data(contentsOf: fixture.source.sourceURL)
        let runner = RemuxExecutorRunner()
        let executor = makeExecutor(runner: runner, source: fixture.source)
        let preview = try executor.preview(source: fixture.source)
        let destination = fixture.root.appendingPathComponent("Movie.mkv")
        let stages = RemuxStageRecorder()

        let output = try await executor.execute(
            preview: preview,
            destinationURL: destination,
            onStage: { stage in await stages.append(stage) }
        )

        XCTAssertEqual(output.sourceURL, destination)
        XCTAssertEqual(try Data(contentsOf: fixture.source.sourceURL), originalData)
        let observedStages = await stages.values()
        XCTAssertEqual(observedStages, [.verifying, .committing])
        let requests = await runner.capturedRequests()
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvmerge" }.count,
            1
        )
        XCTAssertGreaterThanOrEqual(
            requests.filter { $0.executableURL.lastPathComponent == "ffprobe" }.count,
            4
        )
    }

    func testSourceMutationAndToolFailureLeaveNoDestination() async throws {
        for failure in ["mutation", "tool"] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let runner = RemuxExecutorRunner(
                sourceToMutate: failure == "mutation" ? fixture.source.sourceURL : nil,
                exitCode: failure == "tool" ? 2 : 0
            )
            let executor = makeExecutor(runner: runner, source: fixture.source)
            let preview = try executor.preview(source: fixture.source)
            let destination = fixture.root.appendingPathComponent("Failed.mkv")

            do {
                _ = try await executor.execute(
                    preview: preview,
                    destinationURL: destination
                )
                XCTFail("Expected \(failure) to fail")
            } catch {
                if failure == "mutation" {
                    XCTAssertEqual(error as? MKVRemuxExecutionError, .staleSource)
                } else {
                    XCTAssertEqual(
                        error as? MKVRemuxExecutionError,
                        .toolFailed(exitCode: 2, message: "fixture failure")
                    )
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    private func makeExecutor(
        runner: RemuxExecutorRunner,
        source: MediaAsset
    ) -> MKVRemuxExecutor<RemuxExecutorRunner, RemuxExecutorInspector> {
        MKVRemuxExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
            runner: runner,
            inspector: RemuxExecutorInspector(source: source)
        )
    }

    private func makeFixture() throws -> (root: URL, source: MediaAsset) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-remux-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sourceURL = root.appendingPathComponent("Movie.mp4")
        try Data("original mp4".utf8).write(to: sourceURL)
        return (
            root,
            MediaAsset(
                sourceURL: sourceURL,
                container: "mov,mp4,m4a,3gp,3g2,mj2",
                duration: MediaTime(nanoseconds: 1_000_000_000),
                fileSize: 12,
                tracks: [
                    MediaTrack(
                        id: 4,
                        kind: .video,
                        codec: "vp9",
                        isDefault: true,
                        dimensions: MediaDimensions(width: 320, height: 180),
                        pixelFormat: "yuv420p",
                        bitDepth: 8,
                        frameRate: "24/1"
                    ),
                    MediaTrack(
                        id: 9,
                        kind: .audio,
                        codec: "aac",
                        language: "eng",
                        title: "Main Audio",
                        isDefault: true,
                        channels: 2,
                        channelLayout: "stereo",
                        sampleRate: 48_000
                    ),
                ],
                chapters: [
                    ChapterNode(
                        title: "Opening",
                        start: .zero,
                        end: MediaTime(nanoseconds: 500_000_000),
                        language: "eng"
                    )
                ],
                metadata: ["title": "Fixture"],
                chapterEntryCount: 1
            )
        )
    }
}
