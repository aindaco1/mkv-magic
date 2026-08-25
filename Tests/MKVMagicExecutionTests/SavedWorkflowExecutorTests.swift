import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor SavedWorkflowRecordingRunner: CommandRunning {
    private let sourceURLToMutate: URL?
    private(set) var executableNames = [String]()
    private(set) var requests = [CommandRequest]()
    private(set) var subtitleInputs = [Data]()

    init(sourceURLToMutate: URL? = nil) {
        self.sourceURLToMutate = sourceURLToMutate
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        executableNames.append(request.executableURL.lastPathComponent)
        requests.append(request)
        if request.executableURL.lastPathComponent == "mkvextract",
            request.arguments.first == "tracks",
            request.arguments.count == 3,
            let separator = request.arguments[2].firstIndex(of: ":"),
            let subtitleData = subtitleInputs.last
        {
            let outputPath = String(
                request.arguments[2][request.arguments[2].index(after: separator)...]
            )
            try subtitleData.write(
                to: URL(fileURLWithPath: outputPath),
                options: .withoutOverwriting
            )
        }
        if request.executableURL.lastPathComponent == "mkvmerge" {
            guard request.arguments.first == "--output", request.arguments.count > 1 else {
                throw CocoaError(.fileWriteUnknown)
            }
            try Data("remuxed".utf8).write(
                to: URL(fileURLWithPath: request.arguments[1]),
                options: .withoutOverwriting
            )
            if let subtitlePath = request.arguments.first(where: {
                URL(fileURLWithPath: $0).lastPathComponent.hasPrefix("external-subtitle.")
            }) {
                subtitleInputs.append(try Data(contentsOf: URL(fileURLWithPath: subtitlePath)))
            }
        }
        if request.executableURL.lastPathComponent == "mkvpropedit",
            let sourceURLToMutate
        {
            try Data("changed while the tool was running".utf8).write(to: sourceURLToMutate)
        }
        return CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}

private func containsPair(_ first: String, _ second: String, in values: [String]) -> Bool {
    values.indices.dropLast().contains { values[$0] == first && values[$0 + 1] == second }
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

private struct UnchangedWorkflowInspector: MediaInspecting {
    let original: MediaAsset

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: original.container,
            formatLongName: original.formatLongName,
            duration: original.duration,
            fileSize: original.fileSize,
            bitrate: original.bitrate,
            tracks: original.tracks,
            chapters: original.chapters,
            attachments: original.attachments,
            metadata: original.metadata,
            chapterEntryCount: original.chapterEntryCount,
            globalTagCount: original.globalTagCount,
            trackTagCount: original.trackTagCount,
            segmentUID: original.segmentUID,
            muxingApplication: original.muxingApplication,
            writingApplication: original.writingApplication,
            warnings: original.warnings
        )
    }
}

private struct ClearedTagsWorkflowInspector: MediaInspecting {
    let original: MediaAsset
    let removesSegmentTitle: Bool

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: original.container,
            formatLongName: original.formatLongName,
            duration: original.duration,
            fileSize: original.fileSize,
            bitrate: original.bitrate,
            tracks: original.tracks.map {
                MediaTrack(
                    id: $0.id,
                    kind: $0.kind,
                    codec: $0.codec,
                    codecLongName: $0.codecLongName,
                    codecID: $0.codecID,
                    profile: $0.profile,
                    level: $0.level,
                    uid: $0.uid,
                    language: $0.language,
                    title: $0.title,
                    isDefault: $0.isDefault,
                    isForced: $0.isForced,
                    isEnabled: $0.isEnabled,
                    isCommentary: $0.isCommentary,
                    isHearingImpaired: $0.isHearingImpaired,
                    isVisualImpaired: $0.isVisualImpaired,
                    isOriginal: $0.isOriginal,
                    isTextDescription: $0.isTextDescription,
                    bitrate: $0.bitrate,
                    channels: $0.channels,
                    channelLayout: $0.channelLayout,
                    sampleRate: $0.sampleRate,
                    dimensions: $0.dimensions,
                    displayDimensions: $0.displayDimensions,
                    pixelFormat: $0.pixelFormat,
                    bitDepth: $0.bitDepth,
                    frameRate: $0.frameRate,
                    colorInfo: $0.colorInfo,
                    masteringDisplayMetadata: $0.masteringDisplayMetadata,
                    contentLightLevelMetadata: $0.contentLightLevelMetadata,
                    hdrFormats: $0.hdrFormats
                )
            },
            chapters: original.chapters,
            attachments: original.attachments,
            metadata: removesSegmentTitle
                ? original.metadata.filter {
                    $0.key.caseInsensitiveCompare("title") != .orderedSame
                        && $0.key != "COMMENT"
                } : original.metadata.filter { $0.key != "COMMENT" },
            chapterEntryCount: original.chapterEntryCount,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: original.segmentUID,
            muxingApplication: original.muxingApplication,
            writingApplication: original.writingApplication,
            warnings: original.warnings
        )
    }
}

private struct ImageAttachmentWorkflowInspector: MediaInspecting {
    let original: MediaAsset
    let retainedAttachment: MediaAttachment

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: original.container,
            formatLongName: original.formatLongName,
            duration: original.duration,
            fileSize: original.fileSize,
            bitrate: original.bitrate,
            tracks: original.tracks,
            chapters: original.chapters,
            attachments: [
                MediaAttachment(
                    id: 0,
                    filename: retainedAttachment.filename,
                    mimeType: retainedAttachment.mimeType,
                    size: retainedAttachment.size,
                    description: retainedAttachment.description,
                    uid: retainedAttachment.uid
                )
            ],
            metadata: ["encoder": "mkvmerge"],
            chapterEntryCount: original.chapterEntryCount,
            globalTagCount: original.globalTagCount,
            trackTagCount: original.trackTagCount,
            segmentUID: "output-segment"
        )
    }
}

private struct CommentaryWorkflowInspector: MediaInspecting {
    let original: MediaAsset
    let markedUIDs: Set<UInt64>
    let namesByUID: [UInt64: String]

    func inspect(_ inputURL: URL) async throws -> MediaAsset {
        MediaAsset(
            sourceURL: inputURL,
            container: original.container,
            formatLongName: original.formatLongName,
            duration: original.duration,
            fileSize: original.fileSize,
            bitrate: original.bitrate,
            tracks: original.tracks.map { track in
                MediaTrack(
                    id: track.id,
                    kind: track.kind,
                    codec: track.codec,
                    codecLongName: track.codecLongName,
                    codecID: track.codecID,
                    profile: track.profile,
                    level: track.level,
                    uid: track.uid,
                    language: track.language,
                    title: track.uid.flatMap { namesByUID[$0] } ?? track.title,
                    isDefault: track.isDefault,
                    isForced: track.isForced,
                    isEnabled: track.isEnabled,
                    isCommentary: track.uid.map(markedUIDs.contains) == true
                        ? true : track.isCommentary,
                    isHearingImpaired: track.isHearingImpaired,
                    isVisualImpaired: track.isVisualImpaired,
                    isOriginal: track.isOriginal,
                    isTextDescription: track.isTextDescription,
                    bitrate: track.bitrate,
                    channels: track.channels,
                    channelLayout: track.channelLayout,
                    sampleRate: track.sampleRate,
                    dimensions: track.dimensions,
                    displayDimensions: track.displayDimensions,
                    pixelFormat: track.pixelFormat,
                    bitDepth: track.bitDepth,
                    frameRate: track.frameRate,
                    colorInfo: track.colorInfo,
                    masteringDisplayMetadata: track.masteringDisplayMetadata,
                    contentLightLevelMetadata: track.contentLightLevelMetadata,
                    hdrFormats: track.hdrFormats,
                    tags: track.tags
                )
            },
            chapters: original.chapters,
            attachments: original.attachments,
            metadata: original.metadata,
            chapterEntryCount: original.chapterEntryCount,
            globalTagCount: original.globalTagCount,
            trackTagCount: original.trackTagCount,
            segmentUID: original.segmentUID,
            muxingApplication: original.muxingApplication,
            writingApplication: original.writingApplication,
            warnings: original.warnings
        )
    }
}

final class SavedWorkflowExecutorTests: XCTestCase {
    func testCommentaryFlagsUseOneVerifiedPropertyEditAndPreserveSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-saved-workflow-commentary-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.mkv")
        let destinationURL = root.appendingPathComponent("output.mkv")
        let sourceBytes = Data("reviewed commentary source".utf8)
        try sourceBytes.write(to: sourceURL)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            formatLongName: "Matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10),
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    uid: 11,
                    language: "en",
                    title: "Director Commentary",
                    isDefault: true,
                    channels: 2,
                    channelLayout: "stereo",
                    sampleRate: 48_000
                ),
            ],
            metadata: ["title": "Movie"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )
        let edits = try SavedWorkflowCompiler().compile(
            SavedWorkflow(
                name: "Commentary metadata",
                steps: [
                    SavedWorkflowStep(action: .markCommentaryTracks),
                    SavedWorkflowStep(action: .normalizeCommentaryNames),
                ]
            ),
            for: source
        ).trackMetadataEdits
        let runner = SavedWorkflowRecordingRunner()
        let executor = SavedWorkflowExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: CommentaryWorkflowInspector(
                original: source,
                markedUIDs: [11],
                namesByUID: [11: "Commentary"]
            )
        )

        let output = try await executor.execute(
            source: source,
            trackRemoval: nil,
            trackMetadataEdits: edits,
            removesSegmentTitle: false,
            destinationURL: destinationURL
        )
        let requests = await runner.requests

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].executableURL.lastPathComponent, "mkvpropedit")
        XCTAssertTrue(containsPair("--edit", "track:=11", in: requests[0].arguments))
        XCTAssertTrue(containsPair("--set", "name=Commentary", in: requests[0].arguments))
        XCTAssertTrue(containsPair("--set", "flag-commentary=1", in: requests[0].arguments))
        let outputTrack = output.tracks.first(where: { $0.uid == 11 })
        XCTAssertEqual(outputTrack?.title, "Commentary")
        XCTAssertTrue(outputTrack?.isCommentary == true)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: destinationURL), sourceBytes)
    }

    func testImageAttachmentCleanupUsesOneVerifiedRemuxAndPreservesFont() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-saved-workflow-images-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.mkv")
        let destinationURL = root.appendingPathComponent("output.mkv")
        let sourceBytes = Data("reviewed source with image and font".utf8)
        try sourceBytes.write(to: sourceURL)
        let poster = MediaAttachment(
            id: 2,
            filename: "Poster.jpg",
            mimeType: "image/jpeg",
            size: 100,
            uid: 22
        )
        let font = MediaAttachment(
            id: 4,
            filename: "Subtitle.ttf",
            mimeType: "font/ttf",
            size: 20,
            uid: 44
        )
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            formatLongName: "Matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)],
            attachments: [poster, font],
            metadata: ["encoder": "source"],
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
            inspector: ImageAttachmentWorkflowInspector(
                original: source,
                retainedAttachment: font
            )
        )

        let output = try await executor.execute(
            source: source,
            trackRemoval: nil,
            attachmentRemoval: MatroskaAttachmentRemoval(attachmentUIDs: [22]),
            removesSegmentTitle: false,
            destinationURL: destinationURL
        )
        let requests = await runner.requests

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].executableURL.lastPathComponent, "mkvmerge")
        XCTAssertTrue(containsPair("--attachments", "4", in: requests[0].arguments))
        XCTAssertEqual(output.attachments.map(\.uid), [44])
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
    }

    func testTitleAndAllTagsClearInOneVerifiedPropertyEdit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-saved-workflow-tags-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.mkv")
        let destinationURL = root.appendingPathComponent("output.mkv")
        let sourceBytes = Data("reviewed tagged source".utf8)
        try sourceBytes.write(to: sourceURL)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            formatLongName: "Matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: "av1",
                    uid: 10,
                    tags: ["ARTIST": "Fixture"]
                )
            ],
            metadata: ["title": "Remove Me", "COMMENT": "Remove this tag"],
            chapterEntryCount: 0,
            globalTagCount: 1,
            trackTagCount: 1,
            segmentUID: "source-segment"
        )
        let runner = SavedWorkflowRecordingRunner()
        let executor = SavedWorkflowExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: ClearedTagsWorkflowInspector(
                original: source,
                removesSegmentTitle: true
            )
        )

        let output = try await executor.execute(
            source: source,
            trackRemoval: nil,
            removesSegmentTitle: true,
            clearsAllTags: true,
            destinationURL: destinationURL
        )
        let requests = await runner.requests

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].executableURL.lastPathComponent, "mkvpropedit")
        XCTAssertEqual(requests[0].arguments.first, "--abort-on-warnings")
        XCTAssertEqual(
            Array(requests[0].arguments.dropFirst(2)),
            ["--edit", "info", "--delete", "title", "--tags", "all:"]
        )
        XCTAssertEqual(output.globalTagCount, 0)
        XCTAssertEqual(output.trackTagCount, 0)
        XCTAssertNil(output.metadata["title"])
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: destinationURL), sourceBytes)
    }

    func testFilenameOnlyWorkflowCommitsUnchangedCloneWithoutMediaTools() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-saved-workflow-filename-copy-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Movie.2025.1080p.mkv")
        let destinationURL = root.appendingPathComponent("Movie (2025).mkv")
        let sourceBytes = Data("unchanged media bytes".utf8)
        try sourceBytes.write(to: sourceURL)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            formatLongName: "Matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            bitrate: 128_000,
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)],
            metadata: ["title": "Movie"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment",
            muxingApplication: "mkvmerge",
            writingApplication: "mkvmerge"
        )
        let runner = SavedWorkflowRecordingRunner()
        let executor = SavedWorkflowExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: UnchangedWorkflowInspector(original: source)
        )

        let output = try await executor.execute(
            source: source,
            trackRemoval: nil,
            removesSegmentTitle: false,
            createsUnchangedCopy: true,
            destinationURL: destinationURL
        )
        let executableNames = await runner.executableNames

        XCTAssertEqual(executableNames, [])
        XCTAssertEqual(output.sourceURL, destinationURL)
        XCTAssertEqual(try Data(contentsOf: destinationURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
    }

    func testNoOperationWorkflowStillFailsWithoutReviewedCopyIntent() async throws {
        let sourceURL = URL(fileURLWithPath: "/private/media/source.mkv")
        let source = MediaAsset(sourceURL: sourceURL, container: "matroska")
        let executor = SavedWorkflowExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: SavedWorkflowRecordingRunner(),
            inspector: UnchangedWorkflowInspector(original: source)
        )

        do {
            _ = try await executor.execute(
                source: source,
                trackRemoval: nil,
                removesSegmentTitle: false,
                destinationURL: URL(fileURLWithPath: "/private/media/output.mkv")
            )
            XCTFail("Expected no-operation refusal")
        } catch {
            XCTAssertEqual(error as? SavedWorkflowExecutionError, .noOperations)
        }
    }

    func testSourceMutationDuringToolRunCannotCommitOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-saved-workflow-mid-run-change-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.mkv")
        let destinationURL = root.appendingPathComponent("output.mkv")
        try Data("reviewed source".utf8).write(to: sourceURL)
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: 15,
            tracks: [video],
            metadata: ["title": "Movie"],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0,
            segmentUID: "source-segment"
        )
        let reviewedRevision = try MediaFileRevisionReader().read(sourceURL)
        let runner = SavedWorkflowRecordingRunner(sourceURLToMutate: sourceURL)
        let executor = SavedWorkflowExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: runner,
            inspector: CombinedWorkflowInspector(retainedTrack: video)
        )

        do {
            _ = try await executor.execute(
                source: source,
                trackRemoval: nil,
                removesSegmentTitle: true,
                expectedSourceRevision: reviewedRevision,
                destinationURL: destinationURL
            )
            XCTFail("Expected a mid-execution source change to prevent commit")
        } catch {
            XCTAssertEqual(error as? SavedWorkflowExecutionError, .sourceChangedSinceReview)
        }

        let executableNames = await runner.executableNames
        XCTAssertEqual(executableNames, ["mkvpropedit"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(
            try Data(contentsOf: sourceURL),
            Data("changed while the tool was running".utf8)
        )
    }

    func testReviewedSourceRevisionMismatchFailsBeforeCreatingOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-saved-workflow-stale-source-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.mkv")
        let destinationURL = root.appendingPathComponent("output.mkv")
        let sourceBytes = Data("current source".utf8)
        try sourceBytes.write(to: sourceURL)
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10)
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska",
            duration: MediaTime(seconds: 10),
            fileSize: Int64(sourceBytes.count),
            tracks: [video],
            metadata: ["title": "Movie"],
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
        let staleRevision = MediaFileRevision(
            fileSize: Int64(sourceBytes.count + 1),
            modificationDate: Date(timeIntervalSince1970: 0)
        )

        do {
            _ = try await executor.execute(
                source: source,
                trackRemoval: nil,
                removesSegmentTitle: true,
                expectedSourceRevision: staleRevision,
                destinationURL: destinationURL
            )
            XCTFail("Expected stale reviewed input to fail closed")
        } catch {
            XCTAssertEqual(error as? SavedWorkflowExecutionError, .sourceChangedSinceReview)
        }

        let executableNames = await runner.executableNames
        XCTAssertTrue(executableNames.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
    }

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

    func testTrackAndReviewedSubtitleCleanupWithTitleRemovalUseOneRemux() async throws {
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
        let subtitleBytes = Data(
            ("1\n00:00:00,000 --> 00:00:01,000\nDownloaded from\nYTS.MX\n\n"
                + "2\n00:00:01,000 --> 00:00:02,000\n  English  \n").utf8
        )
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
            format: .subRip,
            reviewedCleanupChangeCount: 2
        )
        let runner = SavedWorkflowRecordingRunner()
        let executor = SavedWorkflowExecutor(
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            mkvpropeditURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            mkvextractURL: URL(fileURLWithPath: "/tools/mkvextract"),
            runner: runner,
            inspector: CombinedWorkflowInspector(tracks: [video, added])
        )

        let output = try await executor.execute(
            source: source,
            trackRemoval: TrackRemoval(trackUIDs: [20]),
            removesSegmentTitle: true,
            externalSubtitleInput: runtimeInput,
            externalSubtitlePayload: .reviewedCleanup(
                .subRip(subtitlePreview),
                restoringIDs: []
            ),
            destinationURL: destinationURL
        )
        let executableNames = await runner.executableNames
        let requests = await runner.requests
        let subtitleInputs = await runner.subtitleInputs

        XCTAssertEqual(
            executableNames,
            ["mkvmerge", "mkvpropedit", "mkvextract", "mkvextract"]
        )
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
        XCTAssertEqual(
            subtitleInputs,
            [Data("1\n00:00:01,000 --> 00:00:02,000\nEnglish\n".utf8)]
        )
    }
}
