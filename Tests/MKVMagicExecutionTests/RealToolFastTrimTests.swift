import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem
import XCTest

final class RealToolFastTrimTests: XCTestCase {
    func testBundledToolsFastTrimAtDisclosedKeyframesWithExactNestedChapters() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let runner = FoundationCommandRunner()
        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-real-fast-trim"
        ) { root in
            let rawURL = root.appendingPathComponent("frames.yuv")
            let sourceURL = root.appendingPathComponent("Source.mkv")
            let destinationURL = root.appendingPathComponent("Fast Trimmed.mkv")
            let width = 64
            let height = 48
            let frameCount = 100
            let bytesPerFrame = width * height * 3 / 2
            try Data(repeating: 32, count: bytesPerFrame * frameCount).write(to: rawURL)

            let encode = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .ffmpeg),
                    arguments: [
                        "-hide_banner", "-nostdin", "-loglevel", "error",
                        "-f", "rawvideo", "-pixel_format", "yuv420p",
                        "-video_size", "\(width)x\(height)", "-framerate", "10",
                        "-i", rawURL.path,
                        "-frames:v", "\(frameCount)",
                        "-c:v", "mpeg4", "-g", "20", "-bf", "0", "-q:v", "5",
                        "-metadata", "title=Fast Trim Fixture",
                        sourceURL.path,
                    ],
                    timeout: 120
                )
            )
            XCTAssertEqual(encode.exitCode, 0, encode.standardError.text)

            let sourceChapters = nestedChapters()
            let chapterURL = root.appendingPathComponent("source-chapters.xml")
            try MatroskaChapterXMLCodec().serialize(sourceChapters).write(to: chapterURL)
            let setChapters = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .mkvpropedit),
                    arguments: [
                        "--abort-on-warnings", sourceURL.path,
                        "--chapters", chapterURL.path,
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(setChapters.exitCode, 0, setChapters.standardError.text)

            let sourceDigest = SHA256.hash(data: try Data(contentsOf: sourceURL))
            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let source = try await inspector.inspect(sourceURL)
            XCTAssertEqual(source.tracks.filter { $0.kind == .video }.count, 1)
            XCTAssertEqual(source.chapterEntryCount, 1)
            let executor = FastTrimExecutor(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            )
            let requested = MediaTrimRange(
                start: MediaTime(nanoseconds: 3_000_000_000),
                end: MediaTime(nanoseconds: 7_000_000_000)
            )
            let preview = try await executor.preview(
                source: source,
                requestedRange: requested
            )

            XCTAssertEqual(preview.plan.adjusted.start, MediaTime(nanoseconds: 4_000_000_000))
            XCTAssertEqual(preview.plan.adjusted.end, MediaTime(nanoseconds: 8_000_000_000))
            XCTAssertTrue(preview.plan.startWasAdjusted)
            XCTAssertTrue(preview.plan.endWasAdjusted)
            let output = try await executor.execute(
                preview: preview,
                destinationURL: destinationURL
            )

            XCTAssertEqual(output.sourceURL, destinationURL)
            XCTAssertEqual(output.tracks.count, source.tracks.count)
            XCTAssertEqual(output.tracks[0].uid, source.tracks[0].uid)
            XCTAssertEqual(output.chapterEntryCount, 1)
            XCTAssertEqual(
                SHA256.hash(data: try Data(contentsOf: sourceURL)),
                sourceDigest
            )
            let duration = try XCTUnwrap(output.duration?.nanoseconds)
            XCTAssertGreaterThanOrEqual(duration, 3_900_000_000)
            XCTAssertLessThanOrEqual(duration, 4_100_000_000)

            let outputChapters = try await ChapterEditExecutor(
                mkvextractURL: try catalog.url(for: .mkvextract),
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            ).preview(source: output)
            let codec = MatroskaChapterXMLCodec()
            XCTAssertEqual(
                try codec.serialize(outputChapters.original),
                try codec.serialize(preview.trimmedChapters)
            )

            let decode = try await runner.run(
                CommandRequest(
                    executableURL: try catalog.url(for: .ffmpeg),
                    arguments: [
                        "-hide_banner", "-nostdin", "-loglevel", "error",
                        "-i", destinationURL.path,
                        "-map", "0:v:0", "-f", "null", "-",
                    ],
                    timeout: 60
                )
            )
            XCTAssertEqual(decode.exitCode, 0, decode.standardError.text)
        }
    }

    private func nestedChapters() -> MatroskaChapterDocument {
        let duration = MediaTime(nanoseconds: 10_000_000_000)
        return MatroskaChapterDocument(editions: [
            MatroskaChapterEdition(
                isDefault: true,
                chapters: [
                    MatroskaChapterAtom(
                        start: .zero,
                        end: duration,
                        displays: [ChapterDisplay(title: "Feature")],
                        children: [
                            MatroskaChapterAtom(
                                start: .zero,
                                end: MediaTime(nanoseconds: 5_000_000_000),
                                displays: [ChapterDisplay(title: "First Half")]
                            ),
                            MatroskaChapterAtom(
                                start: MediaTime(nanoseconds: 5_000_000_000),
                                end: duration,
                                displays: [ChapterDisplay(title: "Second Half")]
                            ),
                        ]
                    )
                ]
            )
        ])
    }
}
