import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import XCTest

final class MKVRemuxCommandBuilderTests: XCTestCase {
    func testBuildsOneShellFreeMkvmergeCopyWithExplicitTrackOrder() throws {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie; $(touch nope).mp4"),
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            duration: MediaTime(nanoseconds: 1_000_000_000),
            tracks: [
                MediaTrack(id: 3, kind: .video, codec: "h264"),
                MediaTrack(id: 7, kind: .audio, codec: "aac"),
            ]
        )
        let plan = try MKVRemuxPlanner().resolve(source: source)
        let output = URL(fileURLWithPath: "/private/working-copy.mkv")

        XCTAssertEqual(
            try MKVRemuxCommandBuilder().build(plan: plan, outputURL: output),
            [
                "--output", output.path,
                "--abort-on-warnings",
                "--flush-on-close",
                "--normalize-language-ietf", "canonical",
                "--disable-track-statistics-tags",
                "--no-buttons",
                "--track-order", "0:3,0:7",
                source.sourceURL.path,
            ]
        )
    }

    func testRejectsWrongExistingAndInconsistentDestinations() throws {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mp4"),
            container: "mov",
            duration: MediaTime(nanoseconds: 1_000_000_000),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "h264")]
        )
        let plan = try MKVRemuxPlanner().resolve(source: source)
        XCTAssertThrowsError(
            try MKVRemuxCommandBuilder().build(
                plan: plan,
                outputURL: URL(fileURLWithPath: "/private/output.mp4")
            )
        ) { XCTAssertEqual($0 as? MKVRemuxCommandError, .unsupportedDestination) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("existing.mkv")
        try Data("existing".utf8).write(to: existing)
        XCTAssertThrowsError(
            try MKVRemuxCommandBuilder().build(plan: plan, outputURL: existing)
        ) { XCTAssertEqual($0 as? MKVRemuxCommandError, .destinationExists) }

        let inconsistent = ResolvedMKVRemuxPlan(
            source: source,
            trackIDsInOutputOrder: [9]
        )
        XCTAssertThrowsError(
            try MKVRemuxCommandBuilder().build(
                plan: inconsistent,
                outputURL: root.appendingPathComponent("output.mkv")
            )
        ) { XCTAssertEqual($0 as? MKVRemuxCommandError, .inconsistentPlan) }
    }

    func testBuildsOnePassRemuxWithReviewedAudioLanguageAndSubtitleLast() throws {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.en.mp4"),
            container: "mov",
            duration: MediaTime(seconds: 10),
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "h264"),
                MediaTrack(id: 1, kind: .audio, codec: "aac", language: "und"),
            ]
        )
        let plan = try MKVRemuxPlanner().resolve(source: source)
        let subtitle = URL(fileURLWithPath: "/Media/Movie.fr.srt")
        let arguments = try MKVRemuxCommandBuilder().build(
            plan: plan,
            outputURL: URL(fileURLWithPath: "/private/output.mkv"),
            trackLanguageOverrides: [1: "eng"],
            externalSubtitle: (
                subtitle,
                ExternalSubtitleTrackMetadata(language: "fr", name: "French")
            )
        )

        XCTAssertEqual(arguments.filter { $0 == source.sourceURL.path }.count, 1)
        XCTAssertEqual(arguments.filter { $0 == subtitle.path }.count, 1)
        XCTAssertEqual(arguments.suffix(1), [subtitle.path])
        XCTAssertTrue(arguments.contains("1:en"))
        XCTAssertTrue(arguments.contains("0:fr"))
        XCTAssertTrue(arguments.contains("0:0,0:1,1:0"))
    }

    func testAuthorsReviewedChaptersAndDisablesImplicitMP4ChapterTranslation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Chaptered.mp4"),
            container: "mov",
            duration: MediaTime(seconds: 10),
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "hevc"),
                MediaTrack(id: 1, kind: .audio, codec: "aac"),
            ],
            chapters: [
                ChapterNode(title: "Opening", start: .zero, end: MediaTime(seconds: 4)),
                ChapterNode(
                    title: "Second",
                    start: try XCTUnwrap(MediaTime(seconds: 4)),
                    end: MediaTime(seconds: 10)
                ),
            ]
        )
        let plan = try MKVRemuxPlanner().resolve(source: source)
        let document = try MatroskaChapterDocument.importingInspectedChapters(
            source.chapters,
            sourceID: source.id,
            mediaDuration: try XCTUnwrap(source.duration)
        )
        let chaptersURL = root.appendingPathComponent("reviewed-chapters.xml")
        try MatroskaChapterXMLCodec().serialize(document).write(to: chaptersURL)

        let arguments = try MKVRemuxCommandBuilder().build(
            plan: plan,
            outputURL: root.appendingPathComponent("output.mkv"),
            reviewedChaptersURL: chaptersURL
        )

        let authoredIndex = try XCTUnwrap(arguments.firstIndex(of: "--chapters"))
        XCTAssertEqual(arguments[authoredIndex + 1], chaptersURL.path)
        let sourceIndex = try XCTUnwrap(arguments.firstIndex(of: source.sourceURL.path))
        XCTAssertEqual(arguments[sourceIndex - 1], "--no-chapters")
        XCTAssertThrowsError(
            try MKVRemuxCommandBuilder().build(
                plan: plan,
                outputURL: root.appendingPathComponent("missing-reviewed-chapters.mkv")
            )
        ) { XCTAssertEqual($0 as? MKVRemuxCommandError, .inconsistentPlan) }
    }
}
