import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor EmbeddedSubtitleRecordingRunner: CommandRunning {
    private(set) var requests = [CommandRequest]()
    private(set) var cleanedInputs = [Data]()
    private(set) var timestampInputs = [Data]()
    private var sourcePacketProbeCount = 0
    let sourceURL: URL
    let sourceSubtitle: Data
    let sourcePacketTimeline: Data
    let changedSourcePacketTimeline: Data?
    let outputExtractOverride: Data?
    let outputPacketTimelineOverride: Data?

    init(
        sourceURL: URL,
        sourceSubtitle: Data,
        sourcePacketTimeline: Data = Data(
            "{\"packets\":[{\"pts\":0,\"duration\":1000}],"
                .appending("\"streams\":[{\"time_base\":\"1/1000\"}]}").utf8
        ),
        changedSourcePacketTimeline: Data? = nil,
        outputExtractOverride: Data? = nil,
        outputPacketTimelineOverride: Data? = nil
    ) {
        self.sourceURL = sourceURL
        self.sourceSubtitle = sourceSubtitle
        self.sourcePacketTimeline = sourcePacketTimeline
        self.changedSourcePacketTimeline = changedSourcePacketTimeline
        self.outputExtractOverride = outputExtractOverride
        self.outputPacketTimelineOverride = outputPacketTimelineOverride
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        if request.arguments.first == "tracks", request.arguments.count == 3,
            let separator = request.arguments[2].firstIndex(of: ":")
        {
            let outputPath = String(
                request.arguments[2][request.arguments[2].index(after: separator)...]
            )
            let inputURL = URL(fileURLWithPath: request.arguments[1])
            let data =
                inputURL.standardizedFileURL == sourceURL.standardizedFileURL
                ? sourceSubtitle
                : (outputExtractOverride ?? cleanedInputs.last ?? sourceSubtitle)
            try data.write(to: URL(fileURLWithPath: outputPath), options: .withoutOverwriting)
            return Self.success()
        }
        if request.executableURL.lastPathComponent == "ffprobe" {
            let inputURL = URL(fileURLWithPath: request.arguments.last ?? "")
            let data: Data
            if inputURL.standardizedFileURL == sourceURL.standardizedFileURL {
                sourcePacketProbeCount += 1
                data =
                    sourcePacketProbeCount > 1
                    ? (changedSourcePacketTimeline ?? sourcePacketTimeline)
                    : sourcePacketTimeline
            } else {
                data = outputPacketTimelineOverride ?? sourcePacketTimeline
            }
            return Self.success(standardOutput: data)
        }
        if request.arguments.first == "--output", request.arguments.count > 1 {
            if let inputPath = request.arguments.first(where: {
                ["srt", "ass", "ssa"].contains(URL(fileURLWithPath: $0).pathExtension)
            }) {
                cleanedInputs.append(try Data(contentsOf: URL(fileURLWithPath: inputPath)))
            }
            if let timestampArgument = request.arguments.first(where: {
                $0.hasPrefix("0:")
                    && URL(fileURLWithPath: String($0.dropFirst(2)))
                        .lastPathComponent == "embedded-subtitle-timestamps.txt"
            }) {
                timestampInputs.append(
                    try Data(
                        contentsOf: URL(fileURLWithPath: String(timestampArgument.dropFirst(2))))
                )
            }
            try Data("remuxed".utf8).write(
                to: URL(fileURLWithPath: request.arguments[1]),
                options: .withoutOverwriting
            )
            return Self.success()
        }
        if request.executableURL.lastPathComponent == "mkvpropedit" {
            return Self.success()
        }
        throw CocoaError(.fileReadUnknown)
    }

    private static func success(standardOutput: Data = Data()) -> CommandResult {
        CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: standardOutput, wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}

private struct EmbeddedSubtitleInspector: MediaInspecting {
    let sourceURL: URL
    let source: MediaAsset
    let output: MediaAsset

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        guard inputURL.standardizedFileURL != sourceURL.standardizedFileURL else {
            return source
        }
        return MediaAsset(
            id: output.id,
            sourceURL: inputURL,
            container: output.container,
            duration: output.duration,
            fileSize: output.fileSize,
            bitrate: output.bitrate,
            tracks: output.tracks,
            chapters: output.chapters,
            attachments: output.attachments,
            metadata: output.metadata,
            chapterEntryCount: output.chapterEntryCount,
            globalTagCount: output.globalTagCount,
            trackTagCount: output.trackTagCount,
            segmentUID: output.segmentUID
        )
    }
}

final class EmbeddedSubtitleCleanupExecutorTests: XCTestCase {
    func testReplacesReviewedSRTAtOriginalPositionAndPreservesSource() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = EmbeddedSubtitleRecordingRunner(
            sourceURL: fixture.sourceURL,
            sourceSubtitle: fixture.sourceSubtitle
        )
        let executor = makeExecutor(fixture: fixture, runner: runner)
        let preview = try await executor.preview(source: fixture.source, trackUID: 20)
        XCTAssertEqual(preview.cleanupChangeCount, 1)
        guard case .subRip(let subRip) = preview else {
            return XCTFail("Expected SRT preview")
        }
        XCTAssertTrue(subRip.appliesEnglishOCRRules)

        let output = try await executor.execute(
            preview: preview,
            restoringIDs: [],
            destinationURL: fixture.outputURL
        )
        let requests = await runner.requests
        let cleanedInputs = await runner.cleanedInputs
        let timestampInputs = await runner.timestampInputs

        XCTAssertEqual(try Data(contentsOf: fixture.sourceURL), Data("original".utf8))
        XCTAssertEqual(output.tracks.compactMap(\.uid), [10, 20, 30])
        XCTAssertEqual(
            String(decoding: try XCTUnwrap(cleanedInputs.first), as: UTF8.self),
            "1\n00:00:00,000 --> 00:00:01,000\nyou said HELLO.\n"
        )
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvmerge" }.count, 1)
        XCTAssertEqual(
            requests.filter { $0.executableURL.lastPathComponent == "mkvpropedit" }.count,
            1
        )
        XCTAssertEqual(
            timestampInputs,
            [Data("# timestamp format v2\n0\n1000\n".utf8)]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.outputURL.path))
    }

    func testMiddleCueRemovalAvoidsTimestampOverrideThatWouldExtendPreviousCue() async throws {
        let subtitle = Data(
            ("1\n00:00:00,000 --> 00:00:01,000\nFirst retained.\n\n"
                + "2\n00:00:01,000 --> 00:00:02,000\nDownloaded from YTS.MX\n\n"
                + "3\n00:00:02,000 --> 00:00:03,000\nThird retained.\n").utf8
        )
        let packetTimeline = Data(
            ("{\"packets\":["
                + "{\"pts\":0,\"duration\":1000},"
                + "{\"pts\":1000,\"duration\":1000},"
                + "{\"pts\":2000,\"duration\":1000}],"
                + "\"streams\":[{\"time_base\":\"1/1000\"}]}").utf8
        )
        let fixture = try makeFixture(sourceSubtitle: subtitle)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = EmbeddedSubtitleRecordingRunner(
            sourceURL: fixture.sourceURL,
            sourceSubtitle: fixture.sourceSubtitle,
            sourcePacketTimeline: packetTimeline
        )
        let executor = makeExecutor(fixture: fixture, runner: runner)
        let preview = try await executor.preview(source: fixture.source, trackUID: 20)

        _ = try await executor.execute(
            preview: preview,
            restoringIDs: [],
            destinationURL: fixture.outputURL
        )
        let requests = await runner.requests
        let cleanedInputs = await runner.cleanedInputs
        let timestampInputs = await runner.timestampInputs
        let merge = try XCTUnwrap(
            requests.first { $0.executableURL.lastPathComponent == "mkvmerge" }
        )
        let cleaned = String(
            decoding: try XCTUnwrap(cleanedInputs.first),
            as: UTF8.self
        )

        XCTAssertFalse(merge.arguments.contains("--timestamps"))
        XCTAssertTrue(timestampInputs.isEmpty)
        XCTAssertTrue(cleaned.contains("00:00:00,000 --> 00:00:01,000"))
        XCTAssertTrue(cleaned.contains("00:00:02,000 --> 00:00:03,000"))
        XCTAssertFalse(cleaned.contains("YTS.MX"))
    }

    func testChangedSourceAfterPreviewFailsBeforeRemux() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = EmbeddedSubtitleRecordingRunner(
            sourceURL: fixture.sourceURL,
            sourceSubtitle: fixture.sourceSubtitle
        )
        let executor = makeExecutor(fixture: fixture, runner: runner)
        let preview = try await executor.preview(source: fixture.source, trackUID: 20)
        try Data("changed source".utf8).write(to: fixture.sourceURL)

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(
                preview: preview,
                restoringIDs: [],
                destinationURL: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(error as? EmbeddedSubtitleCleanupError, .staleSource)
        }
        let requests = await runner.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.outputURL.path))
    }

    func testChangedOriginalPacketTimelineAfterPreviewFailsBeforeRemux() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = EmbeddedSubtitleRecordingRunner(
            sourceURL: fixture.sourceURL,
            sourceSubtitle: fixture.sourceSubtitle,
            changedSourcePacketTimeline: Data(
                ("{\"packets\":[{\"pts\":0,\"duration\":999}],"
                    + "\"streams\":[{\"time_base\":\"1/1000\"}]}").utf8
            )
        )
        let executor = makeExecutor(fixture: fixture, runner: runner)
        let preview = try await executor.preview(source: fixture.source, trackUID: 20)

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(
                preview: preview,
                restoringIDs: [],
                destinationURL: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(error as? EmbeddedSubtitleCleanupError, .staleSource)
        }
        let requests = await runner.requests
        XCTAssertFalse(
            requests.contains { $0.executableURL.lastPathComponent == "mkvmerge" }
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.outputURL.path))
    }

    func testInvalidPacketTimelineFailsPreview() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = EmbeddedSubtitleRecordingRunner(
            sourceURL: fixture.sourceURL,
            sourceSubtitle: fixture.sourceSubtitle,
            sourcePacketTimeline: Data("not packet data\n".utf8)
        )
        let executor = makeExecutor(fixture: fixture, runner: runner)

        await XCTAssertThrowsErrorAsync(
            try await executor.preview(source: fixture.source, trackUID: 20)
        ) { error in
            XCTAssertEqual(
                error as? EmbeddedSubtitleCleanupError,
                .invalidExtractedTiming
            )
        }
    }

    func testReplacesReviewedASSWhilePreservingStylesAndOverrideTags() async throws {
        let subtitle = Data(
            ("[Script Info]\nScriptType: v4.00+\n"
                + "[V4+ Styles]\nFormat: Name, Fontname, Fontsize\n"
                + "Style: Default,Arial,48\n"
                + "[Events]\n"
                + "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
                + "Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,{\\an8} HE11O \n")
                .utf8
        )
        let fixture = try makeFixture(format: .ass, sourceSubtitle: subtitle)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = EmbeddedSubtitleRecordingRunner(
            sourceURL: fixture.sourceURL,
            sourceSubtitle: fixture.sourceSubtitle
        )
        let executor = makeExecutor(fixture: fixture, runner: runner)
        let preview = try await executor.preview(source: fixture.source, trackUID: 20)
        guard case .advanced(let advanced) = preview else {
            return XCTFail("Expected ASS preview")
        }
        XCTAssertEqual(advanced.cleanup.changes.count, 1)

        _ = try await executor.execute(
            preview: preview,
            restoringIDs: [],
            destinationURL: fixture.outputURL
        )
        let cleanedInputs = await runner.cleanedInputs
        let cleaned = String(
            decoding: try XCTUnwrap(cleanedInputs.first),
            as: UTF8.self
        )
        XCTAssertTrue(cleaned.contains("Style: Default,Arial,48"))
        XCTAssertTrue(cleaned.contains("{\\an8} HELLO"))
    }

    func testPayloadAuditFailureDeletesTemporaryOutput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = EmbeddedSubtitleRecordingRunner(
            sourceURL: fixture.sourceURL,
            sourceSubtitle: fixture.sourceSubtitle,
            outputExtractOverride: Data(
                "1\n00:00:00,000 --> 00:00:01,000\nWrong\n".utf8)
        )
        let executor = makeExecutor(fixture: fixture, runner: runner)
        let preview = try await executor.preview(source: fixture.source, trackUID: 20)

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(
                preview: preview,
                restoringIDs: [],
                destinationURL: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(
                error as? EmbeddedSubtitleCleanupError,
                .subtitleVerificationFailed
            )
        }
        XCTAssertEqual(try Data(contentsOf: fixture.sourceURL), Data("original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.outputURL.path))
    }

    func testExactPacketTimingAuditFailureDeletesTemporaryOutput() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = EmbeddedSubtitleRecordingRunner(
            sourceURL: fixture.sourceURL,
            sourceSubtitle: fixture.sourceSubtitle,
            outputPacketTimelineOverride: Data(
                ("{\"packets\":[{\"pts\":0,\"duration\":999}],"
                    + "\"streams\":[{\"time_base\":\"1/1000\"}]}").utf8
            )
        )
        let executor = makeExecutor(fixture: fixture, runner: runner)
        let preview = try await executor.preview(source: fixture.source, trackUID: 20)

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(
                preview: preview,
                restoringIDs: [],
                destinationURL: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(
                error as? EmbeddedSubtitleCleanupError,
                .subtitleTimingVerificationFailed
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.outputURL.path))
    }

    func testReplacementArgumentsPreserveAllFlagsAndOriginalTrackOrder() throws {
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", codecID: "V_AV1", uid: 10)
        let target = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 20,
            language: "eng",
            title: "English SDH",
            isDefault: true,
            isForced: true,
            isEnabled: false,
            isCommentary: true,
            isHearingImpaired: true,
            isVisualImpaired: true,
            isOriginal: true,
            isTextDescription: true
        )
        let retained = MediaTrack(
            id: 2, kind: .subtitle, codec: "ass", codecID: "S_TEXT/ASS", uid: 30)
        let audio = MediaTrack(id: 3, kind: .audio, codec: "aac", uid: 40)
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            tracks: [video, target, retained, audio]
        )
        let arguments = try MKVEmbeddedSubtitleReplacer<FoundationCommandRunner>.muxArguments(
            source: source,
            trackUID: 20,
            cleanedSubtitleURL: URL(fileURLWithPath: "/Temp/clean.srt"),
            timestampsV2URL: URL(fileURLWithPath: "/Temp/timestamps.txt"),
            outputURL: URL(fileURLWithPath: "/Temp/output.mkv")
        )

        XCTAssertTrue(arguments.contains("--subtitle-tracks"))
        XCTAssertTrue(arguments.contains("2"))
        XCTAssertTrue(arguments.contains("0:en"))
        XCTAssertTrue(arguments.contains("0:English SDH"))
        XCTAssertTrue(arguments.contains("--timestamps"))
        XCTAssertTrue(arguments.contains("0:/Temp/timestamps.txt"))
        for flag in [
            "--default-track-flag", "--forced-display-flag", "--track-enabled-flag",
            "--commentary-flag", "--hearing-impaired-flag", "--visual-impaired-flag",
            "--original-flag", "--text-descriptions-flag",
        ] {
            XCTAssertTrue(arguments.contains(flag), flag)
        }
        XCTAssertEqual(arguments.suffix(2), ["--track-order", "0:0,1:0,0:2,0:3"])
        XCTAssertEqual(
            try MKVEmbeddedSubtitleReplacer<FoundationCommandRunner>.trackUIDArguments(
                source: source,
                trackUID: 20,
                outputURL: URL(fileURLWithPath: "/Temp/output.mkv")
            ),
            ["/Temp/output.mkv", "--edit", "track:s1", "--set", "track-uid=20"]
        )
        XCTAssertEqual(
            try MKVEmbeddedSubtitleReplacer<FoundationCommandRunner>.trackUIDArguments(
                source: source,
                trackUID: 30,
                outputURL: URL(fileURLWithPath: "/Temp/output.mkv")
            )[2],
            "track:s2"
        )
    }

    private func makeExecutor(
        fixture: Fixture,
        runner: EmbeddedSubtitleRecordingRunner
    ) -> EmbeddedSubtitleCleanupExecutor<EmbeddedSubtitleRecordingRunner, EmbeddedSubtitleInspector>
    {
        EmbeddedSubtitleCleanupExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
            runner: runner,
            inspector: EmbeddedSubtitleInspector(
                sourceURL: fixture.sourceURL,
                source: fixture.source,
                output: fixture.output
            )
        )
    }

    private func makeFixture(
        format: ExternalTextSubtitleFormat = .subRip,
        sourceSubtitle: Data? = nil
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-embedded-subtitle-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let outputURL = root.appendingPathComponent("Movie — Clean.mkv")
        let sourceBytes = Data("original".utf8)
        try sourceBytes.write(to: sourceURL)
        let tracks = [
            MediaTrack(id: 0, kind: .video, codec: "av1", codecID: "V_AV1", uid: 10),
            MediaTrack(
                id: 1,
                kind: .subtitle,
                codec: format == .subRip ? "subrip" : "ass",
                codecID: format == .subRip ? "S_TEXT/UTF8" : "S_TEXT/ASS",
                uid: 20,
                language: "en",
                title: "English",
                isDefault: true
            ),
            MediaTrack(id: 2, kind: .audio, codec: "aac", uid: 30, language: "en"),
        ]
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 1),
            fileSize: Int64(sourceBytes.count),
            tracks: tracks,
            metadata: ["encoder": "source"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )
        let output = MediaAsset(
            sourceURL: outputURL,
            container: "matroska",
            duration: MediaTime(seconds: 1),
            fileSize: 7,
            tracks: tracks,
            metadata: ["encoder": "mkvmerge"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "output-segment"
        )
        return Fixture(
            root: root,
            sourceURL: sourceURL,
            outputURL: outputURL,
            sourceSubtitle: sourceSubtitle
                ?? Data("1\n00:00:00,000 --> 00:00:01,000\ny0u said HE11O.\n".utf8),
            source: source,
            output: output
        )
    }
}

private struct Fixture {
    let root: URL
    let sourceURL: URL
    let outputURL: URL
    let sourceSubtitle: Data
    let source: MediaAsset
    let output: MediaAsset
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error")
    } catch {
        errorHandler(error)
    }
}
