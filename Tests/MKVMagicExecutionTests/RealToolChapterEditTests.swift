import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

final class RealToolChapterEditTests: XCTestCase {
    func testBundledToolsRoundTripNestedChaptersThenDeleteThemFromVerifiedCopies() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-chapters-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let rawAudio = fixtureRoot.appendingPathComponent("silence.pcm")
        let sourceURL = fixtureRoot.appendingPathComponent("source.mkv")
        let chapteredURL = fixtureRoot.appendingPathComponent("chaptered.mkv")
        let chapterlessURL = fixtureRoot.appendingPathComponent("chapterless.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)

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

        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        let executor = ChapterEditExecutor(
            mkvextractURL: try catalog.url(for: .mkvextract),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        )
        let source = try await inspector.inspect(sourceURL)
        let emptyPreview = try await executor.preview(source: source)
        XCTAssertEqual(emptyPreview.original, MatroskaChapterDocument())

        let desired = MatroskaChapterDocument(
            editions: [
                MatroskaChapterEdition(
                    uid: 901,
                    isDefault: true,
                    chapters: [
                        MatroskaChapterAtom(
                            uid: 902,
                            start: .zero,
                            displays: [
                                ChapterDisplay(
                                    title: "Part & One", language: "en-US", country: "US"),
                                ChapterDisplay(title: "Première partie", language: "fr"),
                            ],
                            children: [
                                MatroskaChapterAtom(
                                    uid: 903,
                                    start: .zero,
                                    end: MediaTime(nanoseconds: 500_000_001),
                                    displays: [ChapterDisplay(title: "Opening", language: "en")]
                                ),
                                MatroskaChapterAtom(
                                    uid: 904,
                                    start: MediaTime(nanoseconds: 500_000_001),
                                    displays: [ChapterDisplay(title: "Second Beat", language: "en")]
                                ),
                            ]
                        )
                    ]
                )
            ]
        )
        let chaptered = try await executor.execute(
            preview: emptyPreview,
            desired: desired,
            destinationURL: chapteredURL
        )
        // The general inspector reports top-level atoms; the exact audit below traverses all 3.
        XCTAssertEqual(chaptered.chapterEntryCount, 1)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: sourceURL)), sourceDigest)

        let chapteredPreview = try await executor.preview(source: chaptered)
        XCTAssertEqual(chapteredPreview.original.chapterCount, 3)
        XCTAssertEqual(
            chapteredPreview.original.editions.first?.chapters.first?.displays.map(\.title),
            ["Part & One", "Première partie"]
        )
        XCTAssertEqual(
            chapteredPreview.original.editions.first?.chapters.first?.children.first?.end?
                .nanoseconds,
            500_000_001
        )

        let chapterless = try await executor.execute(
            preview: chapteredPreview,
            desired: MatroskaChapterDocument(),
            destinationURL: chapterlessURL
        )
        XCTAssertEqual(chapterless.chapterEntryCount, 0)
        let chapterlessPreview = try await executor.preview(source: chapterless)
        XCTAssertTrue(chapterlessPreview.original.editions.isEmpty)
    }
}
