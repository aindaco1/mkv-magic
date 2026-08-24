import CryptoKit
import Foundation
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

final class RealToolMatroskaTagTests: XCTestCase {
    func testBundledToolsExportAndClearGlobalAndTrackTagsExactly() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-tags-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawAudio = root.appendingPathComponent("silence.pcm")
        let baseURL = root.appendingPathComponent("base.mkv")
        let sourceURL = root.appendingPathComponent("tagged.mkv")
        let globalTagsURL = root.appendingPathComponent("global.xml")
        let trackTagsURL = root.appendingPathComponent("track.xml")
        let exportedURL = root.appendingPathComponent("exported-tags.xml")
        let clearedURL = root.appendingPathComponent("tags-cleared.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)
        try tagXML(name: "TITLE", value: "Fixture Collection").write(to: globalTagsURL)
        try tagXML(name: "ARTIST", value: "Fixture Performer").write(to: trackTagsURL)

        let create = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-c:a", "aac",
                    "-metadata", "title=Stable Segment Title",
                    baseURL.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(create.exitCode, 0, create.standardError.text)
        let tag = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .mkvmerge),
                arguments: [
                    "--output", sourceURL.path,
                    "--global-tags", globalTagsURL.path,
                    "--tags", "0:\(trackTagsURL.path)",
                    baseURL.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(tag.exitCode, 0, tag.standardError.text)

        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        let source = try await inspector.inspect(sourceURL)
        XCTAssertGreaterThanOrEqual(source.globalTagCount ?? 0, 1)
        XCTAssertGreaterThanOrEqual(source.trackTagCount ?? 0, 1)
        XCTAssertEqual(source.metadata["title"], "Stable Segment Title")
        let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
        let executor = MatroskaTagExecutor(
            mkvextractURL: try catalog.url(for: .mkvextract),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        )
        let preview = try await executor.preview(source: source)
        XCTAssertEqual(preview.document.counts.global, source.globalTagCount)
        XCTAssertEqual(preview.document.counts.track, source.trackTagCount)

        let exported = try await executor.export(
            preview: preview,
            destinationURL: exportedURL
        )
        XCTAssertEqual(exported.counts, preview.document.counts)
        XCTAssertEqual(try Data(contentsOf: exportedURL), preview.document.data)

        let cleared = try await executor.removeAll(
            preview: preview,
            destinationURL: clearedURL
        )
        XCTAssertEqual(cleared.globalTagCount, 0)
        XCTAssertEqual(cleared.trackTagCount, 0)
        XCTAssertEqual(cleared.metadata["title"], "Stable Segment Title")
        XCTAssertEqual(cleared.segmentUID, source.segmentUID)
        XCTAssertEqual(cleared.tracks.map(\.uid), source.tracks.map(\.uid))
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: sourceURL)), sourceDigest)
    }

    private func tagXML(name: String, value: String) -> Data {
        Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE Tags SYSTEM "matroskatags.dtd">
            <Tags>
              <Tag>
                <Targets />
                <Simple><Name>\(name)</Name><String>\(value)</String></Simple>
              </Tag>
            </Tags>
            """.utf8
        )
    }
}
