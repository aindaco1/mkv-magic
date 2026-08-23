import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

final class RealToolExternalSubtitleMuxTests: XCTestCase {
    func testRealToolsAddExternalSRTWithoutEncodingAndPreserveOriginal() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        let runner = FoundationCommandRunner()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-subtitle-mux-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let rawAudio = root.appendingPathComponent("silence.pcm")
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.forced.srt")
        let outputURL = root.appendingPathComponent("Movie — Subtitled.mkv")
        let extractedSubtitleURL = root.appendingPathComponent("extracted.srt")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)
        var subtitleData = Data("1\r\n00:00:00,000 --> 00:00:01,000\r\nCaf".utf8)
        subtitleData.append(0xE9)
        subtitleData.append(contentsOf: Data("\r\n".utf8))
        try subtitleData.write(to: subtitleURL)
        let createResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-c:a", "aac", "-metadata:s:a:0", "language=eng", sourceURL.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(createResult.exitCode, 0, createResult.standardError.text)
        let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
        let subtitleDigest = SHA256.hash(data: try Data(contentsOf: subtitleURL))
        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        let source = try await inspector.inspect(sourceURL)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: subtitleURL)
        let output = try await ExternalSubtitleMuxExecutor(
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner,
            inspector: inspector
        ).execute(
            source: source,
            subtitlePreview: preview,
            metadata: ExternalSubtitleTrackMetadata(
                language: "en",
                name: "Forced",
                isForced: true
            ),
            destinationURL: outputURL
        )

        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: sourceURL)), sourceDigest)
        XCTAssertEqual(output.tracks.count, source.tracks.count + 1)
        let added = try XCTUnwrap(output.tracks.last)
        XCTAssertEqual(added.kind, .subtitle)
        XCTAssertEqual(try TrackLanguageTag.canonical(added.language ?? "und"), "en")
        XCTAssertEqual(added.title, "Forced")
        XCTAssertTrue(added.isForced)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: subtitleURL)), subtitleDigest)

        let extractResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .mkvextract),
                arguments: ["tracks", outputURL.path, "1:\(extractedSubtitleURL.path)"],
                timeout: 60
            )
        )
        XCTAssertEqual(extractResult.exitCode, 0, extractResult.standardError.text)
        XCTAssertTrue(
            String(decoding: try Data(contentsOf: extractedSubtitleURL), as: UTF8.self)
                .contains("Café")
        )
    }
}
