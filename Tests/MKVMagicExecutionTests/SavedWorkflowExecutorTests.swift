import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor SavedWorkflowRecordingRunner: CommandRunning {
    private(set) var executableNames = [String]()
    private(set) var requests = [CommandRequest]()

    func run(_ request: CommandRequest) async throws -> CommandResult {
        executableNames.append(request.executableURL.lastPathComponent)
        requests.append(request)
        if request.executableURL.lastPathComponent == "mkvmerge" {
            guard request.arguments.first == "--output", request.arguments.count > 1 else {
                throw CocoaError(.fileWriteUnknown)
            }
            try Data("remuxed".utf8).write(
                to: URL(fileURLWithPath: request.arguments[1]),
                options: .withoutOverwriting
            )
        }
        return CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}

private struct CombinedWorkflowInspector: MediaInspecting {
    let tracks: [MediaTrack]

    init(retainedTrack: MediaTrack) {
        tracks = [retainedTrack]
    }

    init(tracks: [MediaTrack]) {
        self.tracks = tracks
    }

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: 8,
            tracks: tracks,
            metadata: ["encoder": "mkvmerge"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "output-segment"
        )
    }
}

final class SavedWorkflowExecutorTests: XCTestCase {
    func testCleanupAndTitleRemovalShareOneVerifiedOutputPipeline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-saved-workflow-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.mkv")
        let destinationURL = root.appendingPathComponent("output.mkv")
        let sourceBytes = Data("original".utf8)
        try sourceBytes.write(to: sourceURL)
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)
        let audio = MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 20)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            tracks: [video, audio],
            metadata: ["title": "Movie", "encoder": "source"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )
        let runner = SavedWorkflowRecordingRunner()
        let executor = SavedWorkflowExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: CombinedWorkflowInspector(retainedTrack: video)
        )

        let output = try await executor.execute(
            source: source,
            trackRemoval: TrackRemoval(trackUIDs: [20]),
            removesSegmentTitle: true,
            destinationURL: destinationURL
        )
        let executableNames = await runner.executableNames

        XCTAssertEqual(executableNames, ["mkvmerge", "mkvpropedit"])
        XCTAssertEqual(output.metadata["title"], nil)
        XCTAssertEqual(output.tracks.map(\.uid), [10])
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testCleanupExternalSubtitleAndTitleRemovalUseOneRemux() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-saved-workflow-subtitle-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.srt")
        let destinationURL = root.appendingPathComponent("output.mkv")
        let sourceBytes = Data("original".utf8)
        let subtitleBytes = Data("1\n00:00:00,000 --> 00:00:01,000\nEnglish\n".utf8)
        try sourceBytes.write(to: sourceURL)
        try subtitleBytes.write(to: subtitleURL)
        let subtitlePreview = try await SubtitleCleanupExecutor().preview(
            sourceURL: subtitleURL
        )
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)
        let french = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            uid: 20,
            language: "fr"
        )
        let added = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 30,
            language: "en",
            title: "English",
            isDefault: true
        )
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            tracks: [video, french],
            metadata: ["title": "Movie", "encoder": "source"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )
        let metadata = ExternalSubtitleTrackMetadata(
            language: "en",
            name: "English",
            isDefault: true
        )
        let runtimeInput = SavedWorkflowExternalSubtitleInput(
            sourceURL: subtitleURL,
            metadata: metadata,
            format: .subRip
        )
        let runner = SavedWorkflowRecordingRunner()
        let executor = SavedWorkflowExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: CombinedWorkflowInspector(tracks: [video, added])
        )

        let output = try await executor.execute(
            source: source,
            trackRemoval: TrackRemoval(trackUIDs: [20]),
            removesSegmentTitle: true,
            externalSubtitleInput: runtimeInput,
            externalSubtitlePreview: .subRip(subtitlePreview),
            destinationURL: destinationURL
        )
        let executableNames = await runner.executableNames
        let requests = await runner.requests

        XCTAssertEqual(executableNames, ["mkvmerge", "mkvpropedit"])
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvmerge" }.count,
            1
        )
        XCTAssertTrue(requests[0].arguments.contains("--no-subtitles"))
        XCTAssertEqual(requests[0].arguments.suffix(2), ["--track-order", "0:0,1:0"])
        XCTAssertEqual(output.tracks.map(\.uid), [10, 30])
        XCTAssertNil(output.metadata["title"])
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: subtitleURL), subtitleBytes)
    }
}
