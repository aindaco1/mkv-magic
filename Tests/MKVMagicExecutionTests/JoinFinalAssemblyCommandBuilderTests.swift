import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import XCTest

final class JoinFinalAssemblyCommandBuilderTests: XCTestCase {
    func testBuildsOneMuxForNormalizedVideoAndDirectlyAppendedAudio() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let command = try JoinFinalAssemblyCommandBuilder().build(
            sources: fixture.sources,
            resolvedPlan: fixture.resolved,
            normalizedBundle: fixture.normalizedBundle,
            chapters: fixture.chapters,
            chaptersURL: fixture.chaptersURL,
            outputURL: fixture.outputURL
        )

        XCTAssertEqual(command.outputURL, fixture.outputURL)
        XCTAssertEqual(
            command.lanes,
            [
                JoinFinalLaneInput(
                    laneIndex: 0,
                    mechanism: .normalized,
                    inputFileID: 0,
                    inputTrackID: 5,
                    metadataSourceIndex: 0
                ),
                JoinFinalLaneInput(
                    laneIndex: 1,
                    mechanism: .packetCopy,
                    inputFileID: 1,
                    inputTrackID: 1,
                    metadataSourceIndex: 0
                ),
            ]
        )
        XCTAssertEqual(value(after: "--append-to", in: command.arguments), "2:1:1:1")
        XCTAssertEqual(value(after: "--track-order", in: command.arguments), "0:5,1:1")
        XCTAssertEqual(command.arguments.filter { $0 == "--output" }.count, 1)
        XCTAssertFalse(command.arguments.contains("--engage"))
        XCTAssertFalse(command.arguments.contains("--overwrite"))
        XCTAssertTrue(command.arguments.contains(fixture.normalizedBundle.sourceURL.path))
        XCTAssertTrue(command.arguments.contains(fixture.sources[0].sourceURL.path))
        XCTAssertTrue(command.arguments.contains("+\(fixture.sources[1].sourceURL.path)"))
        XCTAssertEqual(value(after: "--title", in: command.arguments), "Joined Feature")
        XCTAssertEqual(
            value(after: "--chapters", in: command.arguments),
            fixture.chaptersURL.path
        )
    }

    func testRendersReviewedTrackMetadataAndAttachmentSelection() throws {
        let fixture = try makeFixture(
            secondAudioTitle: "Director Commentary",
            retainedAttachmentIDs: [1: [8]]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let command = try JoinFinalAssemblyCommandBuilder().build(
            sources: fixture.sources,
            resolvedPlan: fixture.resolved,
            normalizedBundle: fixture.normalizedBundle,
            chapters: fixture.chapters,
            chaptersURL: fixture.chaptersURL,
            outputURL: fixture.outputURL
        )

        XCTAssertEqual(command.lanes[1].metadataSourceIndex, 1)
        XCTAssertTrue(containsPair("--track-name", "1:Director Commentary", command.arguments))
        XCTAssertTrue(containsPair("--language", "1:en", command.arguments))
        XCTAssertTrue(containsPair("--default-track-flag", "1:1", command.arguments))
        XCTAssertTrue(containsPair("--commentary-flag", "1:1", command.arguments))
        XCTAssertTrue(containsPair("--attachments", "8", command.arguments))
        XCTAssertEqual(command.retainedAttachmentIDsBySource, [1: [8]])
    }

    func testRejectsChangedChaptersAndExistingOutput() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let changed = try JoinedChapterComposer().compose([
            chapterSource(title: "Only One", duration: 2_000_000_000)
        ])
        try MatroskaChapterXMLCodec().serialize(changed.document).write(
            to: fixture.chaptersURL
        )

        XCTAssertThrowsError(
            try JoinFinalAssemblyCommandBuilder().build(
                sources: fixture.sources,
                resolvedPlan: fixture.resolved,
                normalizedBundle: fixture.normalizedBundle,
                chapters: fixture.chapters,
                chaptersURL: fixture.chaptersURL,
                outputURL: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(error as? JoinFinalAssemblyCommandError, .invalidChapters)
        }

        try MatroskaChapterXMLCodec().serialize(fixture.chapters.document).write(
            to: fixture.chaptersURL
        )
        try Data([1]).write(to: fixture.outputURL)
        XCTAssertThrowsError(
            try JoinFinalAssemblyCommandBuilder().build(
                sources: fixture.sources,
                resolvedPlan: fixture.resolved,
                normalizedBundle: fixture.normalizedBundle,
                chapters: fixture.chapters,
                chaptersURL: fixture.chaptersURL,
                outputURL: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(error as? JoinFinalAssemblyCommandError, .existingOutput)
        }
    }

    func testRejectsNormalizedBundleDriftAndUnpreservedSourceTags() throws {
        let drifted = try makeFixture(normalizedCodec: "av1")
        defer { try? FileManager.default.removeItem(at: drifted.root) }
        XCTAssertThrowsError(
            try JoinFinalAssemblyCommandBuilder().build(
                sources: drifted.sources,
                resolvedPlan: drifted.resolved,
                normalizedBundle: drifted.normalizedBundle,
                chapters: drifted.chapters,
                chaptersURL: drifted.chaptersURL,
                outputURL: drifted.outputURL
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinFinalAssemblyCommandError,
                .normalizedBundleMismatch
            )
        }

        let tagged = try makeFixture(globalTagCount: 1)
        defer { try? FileManager.default.removeItem(at: tagged.root) }
        XCTAssertThrowsError(
            try JoinFinalAssemblyCommandBuilder().build(
                sources: tagged.sources,
                resolvedPlan: tagged.resolved,
                normalizedBundle: tagged.normalizedBundle,
                chapters: tagged.chapters,
                chaptersURL: tagged.chaptersURL,
                outputURL: tagged.outputURL
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinFinalAssemblyCommandError,
                .unsupportedTagPreservation(sourceIndex: 0)
            )
        }
    }

    func testRejectsSymlinkedInputAndUnsafeUserText() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let link = fixture.root.appendingPathComponent("linked-normalized.mkv")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.normalizedBundle.sourceURL
        )
        let linkedBundle = normalizedBundle(
            at: link,
            codec: "hevc",
            duration: 2_000_000_000
        )
        XCTAssertThrowsError(
            try JoinFinalAssemblyCommandBuilder().build(
                sources: fixture.sources,
                resolvedPlan: fixture.resolved,
                normalizedBundle: linkedBundle,
                chapters: fixture.chapters,
                chaptersURL: fixture.chaptersURL,
                outputURL: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(error as? JoinFinalAssemblyCommandError, .invalidPath)
        }

        let unsafe = try makeFixture(title: "Bad\0Title")
        defer { try? FileManager.default.removeItem(at: unsafe.root) }
        XCTAssertThrowsError(
            try JoinFinalAssemblyCommandBuilder().build(
                sources: unsafe.sources,
                resolvedPlan: unsafe.resolved,
                normalizedBundle: unsafe.normalizedBundle,
                chapters: unsafe.chapters,
                chaptersURL: unsafe.chaptersURL,
                outputURL: unsafe.outputURL
            )
        ) { error in
            XCTAssertEqual(
                error as? JoinFinalAssemblyCommandError,
                .unsupportedContainerMetadata(sourceIndex: 0)
            )
        }
    }

    private struct Fixture {
        let root: URL
        let sources: [MediaAsset]
        let resolved: ResolvedJoinNormalizationPlan
        let normalizedBundle: MediaAsset
        let chapters: JoinedChapterComposition
        let chaptersURL: URL
        let outputURL: URL
    }

    private func makeFixture(
        title: String = "Joined Feature",
        secondAudioTitle: String = "Main Audio",
        retainedAttachmentIDs: [Int: Set<Int>] = [:],
        normalizedCodec: String = "hevc",
        globalTagCount: Int = 0
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-final-command-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let firstURL = root.appendingPathComponent("Part 1.mkv")
        let secondURL = root.appendingPathComponent("Part 2.mkv")
        let normalizedURL = root.appendingPathComponent("normalized.mkv")
        try Data([1]).write(to: firstURL)
        try Data([2]).write(to: secondURL)
        try Data([3]).write(to: normalizedURL)

        let secondAttachments =
            retainedAttachmentIDs[1] == nil
            ? []
            : [MediaAttachment(id: 8, filename: "poster.jpg", mimeType: "image/jpeg")]
        let sources = [
            asset(
                url: firstURL,
                title: title,
                video: video(width: 64, height: 48),
                audio: audio(title: "Main Audio", commentary: false),
                globalTagCount: globalTagCount
            ),
            asset(
                url: secondURL,
                title: title,
                video: video(width: 80, height: 64),
                audio: audio(
                    title: secondAudioTitle,
                    commentary: secondAudioTitle != "Main Audio"
                ),
                attachments: secondAttachments,
                globalTagCount: 0
            ),
        ]
        let mapping = JoinTrackMapping(lanes: [
            JoinTrackLane(kind: .video, trackIDsBySource: [0, 0]),
            JoinTrackLane(kind: .audio, trackIDsBySource: [1, 1]),
        ])
        let proposal = try JoinNormalizationPlanner().propose(
            sources: sources,
            mapping: mapping,
            preferredVideoPreset: .hevcCompatibility
        )
        let videoLane = try XCTUnwrap(proposal.videoLanes.first)
        var metadataSources = [Int: Int]()
        if proposal.decisions.contains(where: { $0.kind == .trackMetadata }) {
            metadataSources[1] = 1
        }
        let resolved = try JoinNormalizationChoiceResolver().resolve(
            sources: sources,
            proposal: proposal,
            choices: JoinNormalizationChoices(
                videoTargetsByLane: [
                    0: JoinVideoTargetChoice(
                        preset: .hevcCompatibility,
                        canvas: try XCTUnwrap(videoLane.recommendedCanvas),
                        frameRatePolicy: .preserveSourceTiming,
                        dynamicRange: .sdr,
                        rateControl: .averageBitrate(500_000)
                    )
                ],
                retainedAttachmentIDsBySource: retainedAttachmentIDs,
                metadataSourceByLane: metadataSources
            ),
            availableVideoPresets: [.hevcCompatibility],
            aacAvailable: true
        )
        let chapters = try JoinedChapterComposer().compose([
            chapterSource(title: "Part 1", duration: 1_000_000_000),
            chapterSource(title: "Part 2", duration: 1_000_000_000),
        ])
        let chaptersURL = root.appendingPathComponent("chapters.xml")
        try MatroskaChapterXMLCodec().serialize(chapters.document).write(to: chaptersURL)
        return Fixture(
            root: root,
            sources: sources,
            resolved: resolved,
            normalizedBundle: normalizedBundle(
                at: normalizedURL,
                codec: normalizedCodec,
                duration: 2_000_000_000
            ),
            chapters: chapters,
            chaptersURL: chaptersURL,
            outputURL: root.appendingPathComponent("final.mkv")
        )
    }

    private func asset(
        url: URL,
        title: String,
        video: MediaTrack,
        audio: MediaTrack,
        attachments: [MediaAttachment] = [],
        globalTagCount: Int
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: url,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 1_000_000_000),
            fileSize: 1,
            tracks: [video, audio],
            attachments: attachments,
            metadata: ["title": title],
            chapterEntryCount: 0,
            globalTagCount: globalTagCount,
            trackTagCount: 0
        )
    }

    private func video(width: Int, height: Int) -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            profile: "High",
            level: 40,
            dimensions: MediaDimensions(width: width, height: height),
            displayDimensions: MediaDimensions(width: width, height: height),
            pixelFormat: "yuv420p",
            bitDepth: 8,
            frameRate: "24/1",
            colorInfo: MediaColorInfo(
                range: "tv",
                primaries: "bt709",
                transfer: "bt709",
                matrix: "bt709"
            )
        )
    }

    private func audio(title: String, commentary: Bool) -> MediaTrack {
        MediaTrack(
            id: 1,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            profile: "LC",
            language: "en",
            title: title,
            isDefault: true,
            isCommentary: commentary,
            channels: 2,
            channelLayout: "stereo",
            sampleRate: 48_000
        )
    }

    private func normalizedBundle(at url: URL, codec: String, duration: Int64) -> MediaAsset {
        MediaAsset(
            sourceURL: url,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: duration),
            fileSize: 1,
            tracks: [
                MediaTrack(
                    id: 5,
                    kind: .video,
                    codec: codec,
                    dimensions: MediaDimensions(width: 80, height: 64),
                    displayDimensions: MediaDimensions(width: 80, height: 64),
                    pixelFormat: "yuv420p10le",
                    bitDepth: 10,
                    frameRate: "24/1",
                    colorInfo: MediaColorInfo(
                        range: "tv",
                        primaries: "bt709",
                        transfer: "bt709",
                        matrix: "bt709"
                    )
                )
            ],
            chapterEntryCount: 0,
            globalTagCount: 0,
            trackTagCount: 0
        )
    }

    private func chapterSource(title: String, duration: Int64) -> JoinedChapterSource {
        let time = MediaTime(nanoseconds: duration)
        return JoinedChapterSource(
            title: title,
            duration: time,
            retainedStart: .zero,
            retainedEnd: time,
            selectedEditionChapters: []
        )
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    private func containsPair(_ flag: String, _ value: String, _ arguments: [String]) -> Bool {
        arguments.indices.contains { index in
            arguments[index] == flag && arguments.indices.contains(index + 1)
                && arguments[index + 1] == value
        }
    }
}
