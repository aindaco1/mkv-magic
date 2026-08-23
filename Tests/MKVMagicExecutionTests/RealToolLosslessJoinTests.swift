import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

final class RealToolLosslessJoinTests: XCTestCase {
    func testBundledToolsHardJoinCompatibleMKVsWithExactNestedChapters() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-real-lossless-join-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawOne = root.appendingPathComponent("one.pcm")
        let rawTwo = root.appendingPathComponent("two.pcm")
        let rawThree = root.appendingPathComponent("three.pcm")
        let sourceOne = root.appendingPathComponent("one.mkv")
        let sourceTwo = root.appendingPathComponent("two.mkv")
        let sourceThree = root.appendingPathComponent("three.mkv")
        let destination = root.appendingPathComponent("joined.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawOne)
        try Data(repeating: 1, count: 96_000).write(to: rawTwo)
        try Data(repeating: 2, count: 96_000).write(to: rawThree)

        for (raw, output) in [
            (rawOne, sourceOne), (rawTwo, sourceTwo), (rawThree, sourceThree),
        ] {
            let result = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .ffmpeg),
                    arguments: [
                        "-hide_banner", "-loglevel", "error",
                        "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", raw.path,
                        "-c:a", "aac",
                        "-metadata", "title=Lossless Join Fixture",
                        "-metadata:s:a:0", "language=eng",
                        "-metadata:s:a:0", "title=Main Audio",
                        output.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(result.exitCode, 0, result.standardError.text)
        }

        let sourceURLs = [sourceOne, sourceTwo, sourceThree]
        let digests = try sourceURLs.map {
            SHA256.hash(data: try Data(contentsOf: $0))
        }
        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        var sources = [MediaAsset]()
        for sourceURL in sourceURLs {
            try await sources.append(inspector.inspect(sourceURL))
        }
        let proposal = try JoinTrackMappingProposer().propose(sources: sources)
        XCTAssertTrue(proposal.ambiguities.isEmpty)
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: proposal.mapping
        )
        XCTAssertEqual(report.disposition, .losslessCandidate)

        let chapterSources = try sources.enumerated().map { index, source in
            let duration = try XCTUnwrap(source.duration)
            return JoinedChapterSource(
                title: "Part \(index + 1)",
                duration: duration,
                retainedStart: .zero,
                retainedEnd: duration,
                selectedEditionChapters: []
            )
        }
        let chapters = try JoinedChapterComposer().compose(chapterSources)
        let executor = LosslessJoinExecutor(
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            mkvextractURL: try catalog.url(for: .mkvextract),
            runner: runner,
            inspector: inspector
        )
        let preview = try executor.preview(
            sources: sources,
            mapping: proposal.mapping,
            chapters: chapters
        )

        let output = try await executor.execute(
            preview: preview,
            destinationURL: destination
        )

        XCTAssertEqual(output.tracks.count, 1)
        XCTAssertEqual(output.tracks[0].uid, sources[0].tracks[0].uid)
        XCTAssertEqual(output.tracks[0].codecID, sources[0].tracks[0].codecID)
        XCTAssertEqual(output.chapterEntryCount, 3)
        XCTAssertEqual(output.metadata["title"], "Lossless Join Fixture")
        XCTAssertEqual(
            try sourceURLs.map {
                SHA256.hash(data: try Data(contentsOf: $0))
            },
            digests
        )

        let chapterPreview = try await ChapterEditExecutor(
            mkvextractURL: try catalog.url(for: .mkvextract),
            mkvpropeditURL: try catalog.url(for: .mkvpropedit),
            runner: runner,
            inspector: inspector
        ).preview(source: output)
        let codec = MatroskaChapterXMLCodec()
        XCTAssertEqual(
            try codec.serialize(chapterPreview.original),
            try codec.serialize(chapters.document)
        )
    }
}
