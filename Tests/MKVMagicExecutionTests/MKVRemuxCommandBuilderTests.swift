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
}
