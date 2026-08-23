import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

final class RealToolEmbeddedSubtitleCleanupTests: XCTestCase {
    func testRealToolsCleanEmbeddedSRTInPlaceWithoutEncodingOrSourceMutation() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-embedded-subtitle-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let rawAudioURL = root.appendingPathComponent("silence.pcm")
        let audioURL = root.appendingPathComponent("audio.mka")
        let targetSubtitleURL = root.appendingPathComponent("english.srt")
        let retainedSubtitleURL = root.appendingPathComponent("french.srt")
        let timestampOverrideURL = root.appendingPathComponent("english-timestamps.txt")
        let chapterURL = root.appendingPathComponent("chapters.xml")
        let fontURL = root.appendingPathComponent("Fixture.ttf")
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let outputURL = root.appendingPathComponent("Movie — Cleaned.mkv")
        let extractedURL = root.appendingPathComponent("verified.srt")
        try Data(repeating: 0, count: 192_000).write(to: rawAudioURL)
        try Data(
            ("1\n00:00:00,000 --> 00:00:00,500\ny0u said HE11O.\n\n"
                + "2\n00:00:00,500 --> 00:00:01,000\nModel 3 stays.\n\n"
                + "3\n00:00:01,000 --> 00:00:01,500\nDownloaded from YTS.MX\n")
                .utf8
        ).write(to: targetSubtitleURL)
        try Data(
            "1\n00:00:00,000 --> 00:00:01,500\nBonjour\n".utf8
        ).write(to: retainedSubtitleURL)
        try Data(
            ("# timestamp format v2\n0\n499.998496\n"
                + "999.996992\n1499.995488\n").utf8
        ).write(to: timestampOverrideURL)
        try Data("font fixture".utf8).write(to: fontURL)
        try Data(
            ("<?xml version=\"1.0\"?>\n<Chapters><EditionEntry><ChapterAtom>"
                + "<ChapterTimeStart>00:00:00.000000000</ChapterTimeStart>"
                + "<ChapterDisplay><ChapterString>Opening</ChapterString>"
                + "<ChapterLanguage>eng</ChapterLanguage></ChapterDisplay>"
                + "</ChapterAtom></EditionEntry></Chapters>\n").utf8
        ).write(to: chapterURL)

        let audioResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudioURL.path,
                    "-c:a", "aac", audioURL.path,
                ],
                timeout: 60
            ))
        XCTAssertEqual(audioResult.exitCode, 0, audioResult.standardError.text)
        let muxResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .mkvmerge),
                arguments: [
                    "--output", sourceURL.path,
                    "--abort-on-warnings",
                    "--title", "Movie",
                    "--chapters", chapterURL.path,
                    "--attachment-mime-type", "application/x-truetype-font",
                    "--attachment-name", "Fixture.ttf",
                    "--attach-file", fontURL.path,
                    audioURL.path,
                    "--language", "0:en",
                    "--track-name", "0:English SDH",
                    "--default-track-flag", "0:yes",
                    "--forced-display-flag", "0:yes",
                    "--hearing-impaired-flag", "0:yes",
                    "--timestamps", "0:\(timestampOverrideURL.path)",
                    targetSubtitleURL.path,
                    "--language", "0:fr",
                    "--track-name", "0:French",
                    retainedSubtitleURL.path,
                    "--track-order", "0:0,1:0,2:0",
                ],
                timeout: 60
            ))
        XCTAssertEqual(muxResult.exitCode, 0, muxResult.standardError.text)

        let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        let source = try await inspector.inspect(sourceURL)
        let target = try XCTUnwrap(
            source.tracks.first { $0.title == "English SDH" }
        )
        let targetUID = try XCTUnwrap(target.uid)
        XCTAssertEqual(EmbeddedTextSubtitlePolicy.format(for: target), .subRip)
        let sourceSubtitleOrdinal = source.tracks.prefix { $0.uid != targetUID }
            .filter { $0.kind == .subtitle }.count
        let sourcePacketResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffprobe),
                arguments: [
                    "-v", "error",
                    "-select_streams", "s:\(sourceSubtitleOrdinal)",
                    "-show_packets",
                    "-show_entries", "packet=pts_time,duration_time",
                    "-of", "csv=p=0",
                    sourceURL.path,
                ],
                timeout: 60
            ))
        XCTAssertEqual(
            sourcePacketResult.exitCode,
            0,
            sourcePacketResult.standardError.text
        )
        let executor = EmbeddedSubtitleCleanupExecutor(
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            mkvextractURL: try catalog.url(for: .mkvextract),
            ffprobeURL: try catalog.url(for: .ffprobe),
            runner: runner,
            inspector: inspector
        )
        let preview = try await executor.preview(source: source, trackUID: targetUID)
        XCTAssertEqual(preview.cleanupChangeCount, 2)
        let output = try await executor.execute(
            preview: preview,
            restoringIDs: [],
            destinationURL: outputURL
        )

        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: sourceURL)), sourceDigest)
        XCTAssertEqual(output.tracks.compactMap(\.uid), source.tracks.compactMap(\.uid))
        XCTAssertEqual(output.tracks.map(\.kind), source.tracks.map(\.kind))
        XCTAssertEqual(output.chapters.count, source.chapters.count)
        XCTAssertEqual(output.chapterEntryCount, source.chapterEntryCount)
        XCTAssertEqual(output.attachments, source.attachments)
        let replaced = try XCTUnwrap(output.tracks.first { $0.uid == targetUID })
        XCTAssertEqual(replaced.title, "English SDH")
        XCTAssertEqual(try TrackLanguageTag.canonical(replaced.language ?? "und"), "en")
        XCTAssertTrue(replaced.isDefault)
        XCTAssertTrue(replaced.isForced)
        XCTAssertTrue(replaced.isHearingImpaired)
        let extractResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .mkvextract),
                arguments: [
                    "tracks", outputURL.path, "\(replaced.id):\(extractedURL.path)",
                ],
                timeout: 60
            ))
        XCTAssertEqual(extractResult.exitCode, 0, extractResult.standardError.text)
        let outputSubtitleOrdinal = output.tracks.prefix { $0.uid != targetUID }
            .filter { $0.kind == .subtitle }.count
        let outputPacketResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffprobe),
                arguments: [
                    "-v", "error",
                    "-select_streams", "s:\(outputSubtitleOrdinal)",
                    "-show_packets",
                    "-show_entries", "packet=pts_time,duration_time",
                    "-of", "csv=p=0",
                    outputURL.path,
                ],
                timeout: 60
            ))
        XCTAssertEqual(
            outputPacketResult.exitCode,
            0,
            outputPacketResult.standardError.text
        )
        let sourcePacketLines = sourcePacketResult.standardOutput.text.split(
            whereSeparator: \.isNewline)
        let outputPacketLines = outputPacketResult.standardOutput.text.split(
            whereSeparator: \.isNewline)
        XCTAssertEqual(
            outputPacketLines,
            Array(sourcePacketLines.prefix(2)),
            "Embedded cleanup must preserve fractional Matroska packet timestamps exactly."
        )
        XCTAssertEqual(sourcePacketLines.count, 3)
        XCTAssertEqual(outputPacketLines.count, 2)
        let extracted = String(decoding: try Data(contentsOf: extractedURL), as: UTF8.self)
        XCTAssertTrue(extracted.contains("you said HELLO."), extracted)
        XCTAssertTrue(extracted.contains("Model 3 stays."), extracted)
        XCTAssertFalse(extracted.localizedCaseInsensitiveContains("YTS.MX"), extracted)
        XCTAssertTrue(
            String(decoding: try Data(contentsOf: targetSubtitleURL), as: UTF8.self)
                .contains("y0u said HE11O.")
        )
    }
}
