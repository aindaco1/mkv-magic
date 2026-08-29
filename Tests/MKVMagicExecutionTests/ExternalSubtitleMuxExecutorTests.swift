import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor SubtitleMuxRecordingRunner: CommandRunning {
    private(set) var requests = [CommandRequest]()
    private(set) var subtitleInputs = [Data]()
    private let extractedSubtitleOverride: Data?
    private let committedExtractedSubtitleOverride: Data?

    init(
        extractedSubtitleOverride: Data? = nil,
        committedExtractedSubtitleOverride: Data? = nil
    ) {
        self.extractedSubtitleOverride = extractedSubtitleOverride
        self.committedExtractedSubtitleOverride = committedExtractedSubtitleOverride
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        let arguments =
            request.arguments.first == "--gui-mode"
            ? Array(request.arguments.dropFirst()) : request.arguments
        if arguments.first == "tracks",
            arguments.count == 3,
            let separator = arguments[2].firstIndex(of: ":"),
            let subtitleData =
                (URL(fileURLWithPath: arguments[1]).lastPathComponent == "working-copy.mkv"
                    ? extractedSubtitleOverride : committedExtractedSubtitleOverride)
                ?? extractedSubtitleOverride ?? subtitleInputs.last
        {
            let outputPath = String(
                arguments[2][arguments[2].index(after: separator)...])
            try subtitleData.write(
                to: URL(fileURLWithPath: outputPath),
                options: .withoutOverwriting
            )
            return CommandResult(
                exitCode: 0,
                standardOutput: CommandOutput(data: Data(), wasTruncated: false),
                standardError: CommandOutput(data: Data(), wasTruncated: false)
            )
        }
        if let subtitlePath = arguments.first(where: {
            URL(fileURLWithPath: $0).lastPathComponent.hasPrefix("external-subtitle.")
        }) {
            subtitleInputs.append(try Data(contentsOf: URL(fileURLWithPath: subtitlePath)))
        }
        guard arguments.first == "--output", arguments.count > 1 else {
            throw CocoaError(.fileWriteUnknown)
        }
        try Data("muxed".utf8).write(
            to: URL(fileURLWithPath: arguments[1]),
            options: .withoutOverwriting
        )
        return CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}

private struct SubtitleMuxInspector: MediaInspecting {
    let sourceTrack: MediaTrack
    let addedTrack: MediaTrack

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: "matroska,webm",
            duration: MediaTime(seconds: 10),
            fileSize: 5,
            tracks: [sourceTrack, addedTrack],
            metadata: ["encoder": "mkvmerge"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "output-segment"
        )
    }
}

private enum InjectedSubtitleMuxFailure: Error {
    case historyWrite
}

final class ExternalSubtitleMuxExecutorTests: XCTestCase {
    func testReviewedSRTCleanupFeedsOneRemuxAndIsExtractedAfterVerifyAndCommit() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.srt")
        let outputURL = root.appendingPathComponent("Movie — Clean Subtitled.mkv")
        let sourceBytes = Data("original".utf8)
        let subtitleBytes = Data(
            ("1\n00:00:00,000 --> 00:00:01,000\nDownloaded from\nYTS.MX\n\n"
                + "2\n00:00:01,000 --> 00:00:02,000\n  Dialogue  \n").utf8
        )
        try sourceBytes.write(to: sourceURL)
        try subtitleBytes.write(to: subtitleURL)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: subtitleURL)
        XCTAssertEqual(preview.cleanup.changes.count, 2)
        let payload = ExternalSubtitleMuxPayload.reviewedCleanup(
            .subRip(preview),
            restoringIDs: []
        )
        let sourceTrack = MediaTrack(
            id: 0,
            kind: .video,
            codec: "av1",
            codecID: "V_AV1",
            uid: 42
        )
        let runner = SubtitleMuxRecordingRunner()
        let executor = ExternalSubtitleMuxExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: SubtitleMuxInspector(
                sourceTrack: sourceTrack,
                addedTrack: MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "subrip",
                    codecID: "S_TEXT/UTF8",
                    uid: 84,
                    language: "en"
                )
            )
        )
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            tracks: [sourceTrack],
            metadata: ["encoder": "source"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )

        _ = try await executor.execute(
            source: source,
            subtitlePayload: payload,
            metadata: ExternalSubtitleTrackMetadata(language: "en"),
            destinationURL: outputURL
        )
        let requests = await runner.requests
        let subtitleInputs = await runner.subtitleInputs

        XCTAssertEqual(payload.appliedCleanupChangeCount, 2)
        XCTAssertEqual(requests.filter { $0.arguments.first == "--gui-mode" }.count, 1)
        XCTAssertEqual(requests.filter { $0.arguments.first == "tracks" }.count, 2)
        XCTAssertEqual(
            subtitleInputs,
            [Data("1\n00:00:01,000 --> 00:00:02,000\nDialogue\n".utf8)]
        )
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: subtitleURL), subtitleBytes)
    }

    func testReviewedCleanupRejectsUnknownChangeIdentifierBeforeToolExecution() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.srt")
        let outputURL = root.appendingPathComponent("Output.mkv")
        try Data("source".utf8).write(to: sourceURL)
        try Data("1\n00:00:00,000 --> 00:00:01,000\n Text \n".utf8).write(
            to: subtitleURL
        )
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: subtitleURL)
        let runner = SubtitleMuxRecordingRunner()
        let sourceTrack = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 42)
        let executor = ExternalSubtitleMuxExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: SubtitleMuxInspector(
                sourceTrack: sourceTrack,
                addedTrack: MediaTrack(id: 1, kind: .subtitle, codec: "subrip", uid: 84)
            )
        )

        do {
            _ = try await executor.execute(
                source: MediaAsset(
                    sourceURL: sourceURL,
                    container: "matroska",
                    duration: MediaTime(seconds: 1),
                    tracks: [sourceTrack]
                ),
                subtitlePayload: .reviewedCleanup(.subRip(preview), restoringIDs: [999]),
                metadata: ExternalSubtitleTrackMetadata(language: "en"),
                destinationURL: outputURL
            )
            XCTFail("Expected invalid review refusal")
        } catch {
            XCTAssertEqual(error as? ExternalSubtitleMuxError, .invalidCleanupReview)
        }
        let requests = await runner.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testMuxesSubtitleLastWithoutEncodingAndVerifiesCommittedOutput() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.forced.srt")
        let outputURL = root.appendingPathComponent("Movie — Subtitled.mkv")
        let sourceBytes = Data("original".utf8)
        try sourceBytes.write(to: sourceURL)
        try Data("1\n00:00:00,000 --> 00:00:10,000\n Text \n".utf8).write(to: subtitleURL)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: subtitleURL)
        XCTAssertEqual(preview.cleanup.changes.count, 1)
        let sourceTrack = MediaTrack(
            id: 0,
            kind: .video,
            codec: "av1",
            codecID: "V_AV1",
            uid: 42
        )
        let metadata = ExternalSubtitleTrackMetadata(
            language: "en",
            name: "Forced",
            isForced: true
        )
        let runner = SubtitleMuxRecordingRunner()
        let executor = ExternalSubtitleMuxExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            runner: runner,
            inspector: SubtitleMuxInspector(
                sourceTrack: sourceTrack,
                addedTrack: MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "subrip",
                    codecID: "S_TEXT/UTF8",
                    uid: 84,
                    language: "en",
                    title: "Forced",
                    isForced: true
                )
            )
        )
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            tracks: [sourceTrack],
            metadata: ["encoder": "source"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )

        let output = try await executor.execute(
            source: source,
            subtitlePreview: preview,
            metadata: metadata,
            destinationURL: outputURL
        )
        let requests = await runner.requests
        let subtitleInputs = await runner.subtitleInputs

        XCTAssertEqual(output.tracks.map(\.kind), [.video, .subtitle])
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].executableURL.path, "/tools/mkvmerge")
        XCTAssertEqual(requests[0].arguments.first, "--gui-mode")
        let muxArguments = Array(requests[0].arguments.dropFirst())
        XCTAssertEqual(
            muxArguments.prefix(6),
            [
                "--output", muxArguments[1],
                "--abort-on-warnings",
                "--normalize-language-ietf", "canonical",
                "--disable-track-statistics-tags",
            ])
        XCTAssertTrue(muxArguments.contains(sourceURL.path))
        XCTAssertTrue(muxArguments.contains("0:en"))
        XCTAssertTrue(muxArguments.contains("0:Forced"))
        XCTAssertEqual(muxArguments.suffix(2), ["--track-order", "0:0,1:0"])
        let normalizedSubtitlePath = try XCTUnwrap(
            requests[0].arguments.first(where: {
                URL(fileURLWithPath: $0).lastPathComponent == "external-subtitle.srt"
            })
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: normalizedSubtitlePath))
        XCTAssertEqual(
            subtitleInputs,
            [Data("1\n00:00:00,000 --> 00:00:10,000\n Text \n".utf8)]
        )
    }

    func testRejectsChangedSubtitleAndNonMKVDestinationBeforeToolExecution() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.srt")
        try Data("source".utf8).write(to: sourceURL)
        try Data("1\n00:00:00,000 --> 00:00:01,000\nText\n".utf8).write(to: subtitleURL)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: subtitleURL)
        let runner = SubtitleMuxRecordingRunner()
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1", uid: 42)]
        )
        let executor = ExternalSubtitleMuxExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            runner: runner,
            inspector: SubtitleMuxInspector(
                sourceTrack: source.tracks[0],
                addedTrack: MediaTrack(id: 1, kind: .subtitle, codec: "subrip")
            )
        )

        do {
            _ = try await executor.execute(
                source: source,
                subtitlePreview: preview,
                metadata: ExternalSubtitleTrackMetadata(language: "en"),
                destinationURL: root.appendingPathComponent("Movie.mp4")
            )
            XCTFail("Expected destination refusal")
        } catch {
            XCTAssertEqual(error as? ExternalSubtitleMuxError, .unsupportedDestination)
        }
        try Data("1\n00:00:00,000 --> 00:00:01,000\nChanged\n".utf8).write(to: subtitleURL)
        do {
            _ = try await executor.execute(
                source: source,
                subtitlePreview: preview,
                metadata: ExternalSubtitleTrackMetadata(language: "en"),
                destinationURL: root.appendingPathComponent("Movie — Subtitled.mkv")
            )
            XCTFail("Expected stale subtitle refusal")
        } catch {
            XCTAssertEqual(error as? SubtitleCleanupExecutionError, .stalePreview)
        }
        let requests = await runner.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testMuxesStylePreservingASSLastWithoutApplyingCleanupSuggestions() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.ass")
        let outputURL = root.appendingPathComponent("Movie — Subtitled.mkv")
        let sourceBytes = Data("original".utf8)
        let subtitleText =
            "[Script Info]\nTitle: Styled\n"
            + "[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
            + "[Events]\nFormat: Layer, Start, End, Style, Text\n"
            + "Dialogue: 0,0:00:00.00,0:00:10.00,Default,{\\an8} Text \n"
        try sourceBytes.write(to: sourceURL)
        try Data(subtitleText.utf8).write(to: subtitleURL)
        let preview = try await AdvancedSubtitleCleanupExecutor().preview(
            sourceURL: subtitleURL
        )
        XCTAssertEqual(preview.cleanup.changes.count, 1)
        let sourceTrack = MediaTrack(
            id: 0,
            kind: .video,
            codec: "av1",
            codecID: "V_AV1",
            uid: 42
        )
        let runner = SubtitleMuxRecordingRunner()
        let executor = ExternalSubtitleMuxExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: SubtitleMuxInspector(
                sourceTrack: sourceTrack,
                addedTrack: MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "SubStationAlpha",
                    codecID: "S_TEXT/ASS",
                    uid: 84,
                    language: "en",
                    title: "English Styled"
                )
            )
        )
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            tracks: [sourceTrack],
            metadata: ["encoder": "source"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )

        let output = try await executor.execute(
            source: source,
            subtitlePreview: preview,
            metadata: ExternalSubtitleTrackMetadata(
                language: "en",
                name: "English Styled"
            ),
            destinationURL: outputURL
        )
        let requests = await runner.requests
        let subtitleInputs = await runner.subtitleInputs

        XCTAssertEqual(output.tracks.last?.codecID, "S_TEXT/ASS")
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: subtitleURL), Data(subtitleText.utf8))
        XCTAssertEqual(requests.count, 3)
        let temporaryASS = try XCTUnwrap(
            requests[0].arguments.first(where: {
                URL(fileURLWithPath: $0).lastPathComponent == "external-subtitle.ass"
            })
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryASS))
        XCTAssertEqual(subtitleInputs, [Data(subtitleText.utf8)])
        XCTAssertTrue(String(decoding: subtitleInputs[0], as: UTF8.self).contains("{\\an8} Text "))
    }

    func testRejectsMuxedASSWhenExtractedLayoutDoesNotMatchReviewedSource() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.ass")
        let outputURL = root.appendingPathComponent("Movie — Subtitled.mkv")
        let subtitleText =
            "[Script Info]\nScriptType: v4.00+\n"
            + "[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
            + "[Events]\n"
            + "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
            + "Dialogue: 0,0:00:00.00,0:00:10.00,Default,,10,20,30,,{\\an8} Text\n"
        let alteredExtract = subtitleText.replacingOccurrences(of: ",10,20,30,", with: ",99,20,30,")
        try Data("source".utf8).write(to: sourceURL)
        try Data(subtitleText.utf8).write(to: subtitleURL)
        let preview = try await AdvancedSubtitleCleanupExecutor().preview(
            sourceURL: subtitleURL
        )
        let sourceTrack = MediaTrack(
            id: 0,
            kind: .video,
            codec: "av1",
            codecID: "V_AV1",
            uid: 42
        )
        let runner = SubtitleMuxRecordingRunner(
            extractedSubtitleOverride: Data(alteredExtract.utf8)
        )
        let executor = ExternalSubtitleMuxExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: SubtitleMuxInspector(
                sourceTrack: sourceTrack,
                addedTrack: MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "SubStationAlpha",
                    codecID: "S_TEXT/ASS",
                    uid: 84,
                    language: "en"
                )
            )
        )
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            tracks: [sourceTrack],
            metadata: ["encoder": "source"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )

        do {
            _ = try await executor.execute(
                source: source,
                subtitlePreview: preview,
                metadata: ExternalSubtitleTrackMetadata(language: "en"),
                destinationURL: outputURL
            )
            XCTFail("Expected payload verification refusal")
        } catch {
            XCTAssertEqual(error as? ExternalSubtitleMuxError, .subtitleVerificationFailed)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(try Data(contentsOf: subtitleURL), Data(subtitleText.utf8))
        let requests = await runner.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testReportsCommittedAuditFailureWhenReopenedASSLayoutChanges() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.ass")
        let outputURL = root.appendingPathComponent("Movie — Subtitled.mkv")
        let subtitleText =
            "[Script Info]\nScriptType: v4.00+\n"
            + "[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
            + "[Events]\n"
            + "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
            + "Dialogue: 0,0:00:00.00,0:00:10.00,Default,,10,20,30,,{\\an8} Text\n"
        let alteredExtract = subtitleText.replacingOccurrences(
            of: ",10,20,30,",
            with: ",10,20,99,"
        )
        let sourceData = Data("source".utf8)
        try sourceData.write(to: sourceURL)
        try Data(subtitleText.utf8).write(to: subtitleURL)
        let preview = try await AdvancedSubtitleCleanupExecutor().preview(
            sourceURL: subtitleURL
        )
        let sourceTrack = MediaTrack(
            id: 0,
            kind: .video,
            codec: "av1",
            codecID: "V_AV1",
            uid: 42
        )
        let runner = SubtitleMuxRecordingRunner(
            committedExtractedSubtitleOverride: Data(alteredExtract.utf8)
        )
        let executor = ExternalSubtitleMuxExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: SubtitleMuxInspector(
                sourceTrack: sourceTrack,
                addedTrack: MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "SubStationAlpha",
                    codecID: "S_TEXT/ASS",
                    uid: 84,
                    language: "en"
                )
            )
        )
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            tracks: [sourceTrack],
            metadata: ["encoder": "source"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )

        do {
            _ = try await executor.execute(
                source: source,
                subtitlePreview: preview,
                metadata: ExternalSubtitleTrackMetadata(language: "en"),
                destinationURL: outputURL
            )
            XCTFail("Expected committed payload audit failure")
        } catch let error as ExternalSubtitleMuxError {
            guard case .committedOutputAuditFailed(let committedURL, let reason) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(committedURL, outputURL)
            XCTAssertTrue(reason.contains("timing, text, and style audit"))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertEqual(try Data(contentsOf: subtitleURL), Data(subtitleText.utf8))
        let requests = await runner.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testProgressFailureBeforeVerificationRemovesTemporaryMuxAndPreservesInputs() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.mkv")
        let subtitleURL = root.appendingPathComponent("Movie.en.srt")
        let outputURL = root.appendingPathComponent("Movie — Subtitled.mkv")
        let sourceData = Data("source".utf8)
        let subtitleData = Data("1\n00:00:00,000 --> 00:00:01,000\nText\n".utf8)
        try sourceData.write(to: sourceURL)
        try subtitleData.write(to: subtitleURL)
        let preview = try await SubtitleCleanupExecutor().preview(sourceURL: subtitleURL)
        let sourceTrack = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 42)
        let runner = SubtitleMuxRecordingRunner()
        let executor = ExternalSubtitleMuxExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            runner: runner,
            inspector: SubtitleMuxInspector(
                sourceTrack: sourceTrack,
                addedTrack: MediaTrack(id: 1, kind: .subtitle, codec: "subrip")
            )
        )

        do {
            _ = try await executor.execute(
                source: MediaAsset(
                    sourceURL: sourceURL,
                    container: "matroska",
                    duration: MediaTime(seconds: 1),
                    fileSize: Int64(sourceData.count),
                    tracks: [sourceTrack]
                ),
                subtitlePreview: preview,
                metadata: ExternalSubtitleTrackMetadata(language: "en"),
                destinationURL: outputURL,
                onStage: { _ in throw InjectedSubtitleMuxFailure.historyWrite }
            )
            XCTFail("Expected injected progress failure")
        } catch {
            XCTAssertTrue(error is InjectedSubtitleMuxFailure)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertEqual(try Data(contentsOf: subtitleURL), subtitleData)
        let requests = await runner.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        let normalizedSubtitlePath = try XCTUnwrap(
            request.arguments.first(where: {
                URL(fileURLWithPath: $0).lastPathComponent == "external-subtitle.srt"
            })
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: normalizedSubtitlePath))
    }

    func testArgumentValidationRejectsUnsafeTrackNameAndLanguage() {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
        XCTAssertThrowsError(
            try MKVExternalSubtitleMuxer<FoundationCommandRunner>.arguments(
                source: source,
                subtitleURL: URL(fileURLWithPath: "/Media/Movie.srt"),
                metadata: ExternalSubtitleTrackMetadata(language: "not a tag"),
                outputURL: URL(fileURLWithPath: "/Media/Output.mkv")
            )
        ) { error in
            XCTAssertEqual(error as? MKVPropertyEditError, .invalidLanguage)
        }
        XCTAssertThrowsError(
            try MKVExternalSubtitleMuxer<FoundationCommandRunner>.arguments(
                source: source,
                subtitleURL: URL(fileURLWithPath: "/Media/Movie.srt"),
                metadata: ExternalSubtitleTrackMetadata(language: "en", name: "Bad\0Name"),
                outputURL: URL(fileURLWithPath: "/Media/Output.mkv")
            )
        ) { error in
            XCTAssertEqual(error as? ExternalSubtitleMuxError, .invalidTrackName)
        }
    }

    func testImageAttachmentOmissionSharesTheSubtitleRemux() throws {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)],
            attachments: [
                MediaAttachment(
                    id: 2,
                    filename: "Poster.jpg",
                    mimeType: "image/jpeg",
                    uid: 22
                ),
                MediaAttachment(
                    id: 4,
                    filename: "Subtitle.ttf",
                    mimeType: "font/ttf",
                    uid: 44
                ),
            ]
        )

        let arguments = try MKVExternalSubtitleMuxer<FoundationCommandRunner>.arguments(
            source: source,
            subtitleURL: URL(fileURLWithPath: "/Media/Movie.srt"),
            metadata: ExternalSubtitleTrackMetadata(language: "en"),
            attachmentRemoval: MatroskaAttachmentRemoval(attachmentUIDs: [22]),
            outputURL: URL(fileURLWithPath: "/Media/Output.mkv")
        )

        XCTAssertEqual(arguments.filter { $0 == "--output" }.count, 1)
        XCTAssertTrue(containsSubtitleMuxPair("--attachments", "4", in: arguments))
        XCTAssertEqual(arguments.suffix(2), ["--track-order", "0:0,1:0"])
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-subtitle-mux-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}

private func containsSubtitleMuxPair(
    _ first: String,
    _ second: String,
    in values: [String]
) -> Bool {
    zip(values, values.dropFirst()).contains { $0 == first && $1 == second }
}
