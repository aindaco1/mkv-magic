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
            mkvextractURL: try catalog.url(for: .mkvextract),
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

    func testRealToolsAddStylePreservingASSWithoutEncodingAndPreserveOriginal() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        let runner = FoundationCommandRunner()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-ass-mux-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let rawAudio = root.appendingPathComponent("silence.pcm")
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.ass")
        let outputURL = root.appendingPathComponent("Movie — Subtitled.mkv")
        let extractedSubtitleURL = root.appendingPathComponent("extracted.ass")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)
        let subtitleText =
            "[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\n"
            + "[V4+ Styles]\nFormat: Name, Fontname, Fontsize\n"
            + "Style: Default,Arial,48\n"
            + "[Events]\n"
            + "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
            + "Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,{\\an8} Styled, text \n"
        let subtitleData = Data(subtitleText.utf8)
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
        let subtitleDigest = SHA256.hash(data: subtitleData)
        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        let source = try await inspector.inspect(sourceURL)
        let preview = try await AdvancedSubtitleCleanupExecutor().preview(sourceURL: subtitleURL)
        XCTAssertEqual(preview.cleanup.changes.count, 1)
        let output = try await ExternalSubtitleMuxExecutor(
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            mkvextractURL: try catalog.url(for: .mkvextract),
            runner: runner,
            inspector: inspector
        ).execute(
            source: source,
            subtitlePreview: preview,
            metadata: ExternalSubtitleTrackMetadata(
                language: "en",
                name: "English Styled"
            ),
            destinationURL: outputURL
        )

        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: sourceURL)), sourceDigest)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: subtitleURL)), subtitleDigest)
        XCTAssertEqual(output.tracks.count, source.tracks.count + 1)
        let added = try XCTUnwrap(output.tracks.last)
        XCTAssertEqual(added.kind, .subtitle)
        XCTAssertEqual(added.codecID, "S_TEXT/ASS")
        XCTAssertEqual(added.title, "English Styled")

        let extractResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .mkvextract),
                arguments: ["tracks", outputURL.path, "1:\(extractedSubtitleURL.path)"],
                timeout: 60
            )
        )
        XCTAssertEqual(extractResult.exitCode, 0, extractResult.standardError.text)
        let extracted = String(
            decoding: try Data(contentsOf: extractedSubtitleURL),
            as: UTF8.self
        )
        XCTAssertTrue(extracted.contains("Style: Default,Arial,48"))
        XCTAssertTrue(extracted.contains("{\\an8} Styled, text"), extracted)
    }

    func testRealToolsAddLegacyStylePreservingSSAWithoutEncoding() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-ssa-mux-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let rawAudio = root.appendingPathComponent("silence.pcm")
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.ssa")
        let outputURL = root.appendingPathComponent("Movie — Subtitled.mkv")
        let extractedSubtitleURL = root.appendingPathComponent("extracted.ssa")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)
        let subtitleText =
            "[Script Info]\nScriptType: v4.00\n"
            + "[V4 Styles]\n"
            + "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, "
            + "TertiaryColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, "
            + "Alignment, MarginL, MarginR, MarginV, AlphaLevel, Encoding\n"
            + "Style: Default,Arial,24,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,"
            + "-1,0,1,2,0,2,10,10,10,0,0\n"
            + "[Events]\n"
            + "Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
            + "Dialogue: Marked=0,0:00:00.00,0:00:01.00,Default,,0,0,0,,{\\i1}Legacy styled text\n"
        let subtitleData = Data(subtitleText.utf8)
        try subtitleData.write(to: subtitleURL)
        let createResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-c:a", "aac", sourceURL.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(createResult.exitCode, 0, createResult.standardError.text)
        let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
        let subtitleDigest = SHA256.hash(data: subtitleData)
        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        let source = try await inspector.inspect(sourceURL)
        let preview = try await AdvancedSubtitleCleanupExecutor().preview(sourceURL: subtitleURL)
        let output = try await ExternalSubtitleMuxExecutor(
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            mkvextractURL: try catalog.url(for: .mkvextract),
            runner: runner,
            inspector: inspector
        ).execute(
            source: source,
            subtitlePreview: preview,
            metadata: ExternalSubtitleTrackMetadata(language: "en", name: "Legacy Styled"),
            destinationURL: outputURL
        )

        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: sourceURL)), sourceDigest)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: subtitleURL)), subtitleDigest)
        XCTAssertEqual(output.tracks.last?.codecID, "S_TEXT/SSA")
        let extractResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .mkvextract),
                arguments: ["tracks", outputURL.path, "1:\(extractedSubtitleURL.path)"],
                timeout: 60
            )
        )
        XCTAssertEqual(extractResult.exitCode, 0, extractResult.standardError.text)
        let extracted = String(
            decoding: try Data(contentsOf: extractedSubtitleURL),
            as: UTF8.self
        )
        XCTAssertTrue(extracted.contains("Style: Default,Arial,24"), extracted)
        XCTAssertTrue(extracted.contains("{\\i1}Legacy styled text"), extracted)
    }
}
