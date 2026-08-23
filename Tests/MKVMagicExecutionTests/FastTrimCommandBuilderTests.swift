import Foundation
import MKVMagicCore
import MKVMagicExecution
import XCTest

final class FastTrimCommandBuilderTests: XCTestCase {
    func testBuildsExactKeyframePartsCommandWithoutShellOrEncoding() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-fast-trim-command-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source file.mkv")
        let output = root.appendingPathComponent("Trimmed file.mkv")
        try Data([1]).write(to: source)
        let plan = FastTrimPlan(
            requested: range(3, 7),
            adjusted: range(4, 8)
        )

        let command = try FastTrimCommandBuilder().build(
            sourceURL: source,
            plan: plan,
            outputURL: output
        )

        XCTAssertEqual(
            command.arguments,
            [
                "--abort-on-warnings",
                "--flush-on-close",
                "--normalize-language-ietf", "canonical",
                "--disable-track-statistics-tags",
                "--output", output.path,
                "--split", "parts:00:00:04.000000000-00:00:08.000000000",
                "--no-chapters",
                source.path,
            ]
        )
        XCTAssertFalse(command.arguments.contains(where: { $0.contains(";") }))
        XCTAssertFalse(command.arguments.contains("ffmpeg"))
    }

    func testRejectsOverwriteWrongContainerAndInconsistentPlan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-fast-trim-command-errors-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mkv")
        let output = root.appendingPathComponent("output.mkv")
        try Data([1]).write(to: source)
        try Data([2]).write(to: output)

        XCTAssertThrowsError(
            try FastTrimCommandBuilder().build(
                sourceURL: source,
                plan: FastTrimPlan(requested: range(1, 4), adjusted: range(2, 4)),
                outputURL: output
            )
        ) { XCTAssertEqual($0 as? FastTrimCommandError, .existingOutput) }
        XCTAssertThrowsError(
            try FastTrimCommandBuilder().build(
                sourceURL: source.deletingPathExtension().appendingPathExtension("mp4"),
                plan: FastTrimPlan(requested: range(1, 4), adjusted: range(2, 4)),
                outputURL: root.appendingPathComponent("new.mkv")
            )
        ) { XCTAssertEqual($0 as? FastTrimCommandError, .invalidPath) }
        XCTAssertThrowsError(
            try FastTrimCommandBuilder().build(
                sourceURL: source,
                plan: FastTrimPlan(requested: range(3, 7), adjusted: range(2, 8)),
                outputURL: root.appendingPathComponent("new.mkv")
            )
        ) { XCTAssertEqual($0 as? FastTrimCommandError, .invalidPlan) }
    }

    private func range(_ start: Int64, _ end: Int64) -> MediaTrimRange {
        MediaTrimRange(
            start: MediaTime(nanoseconds: start * 1_000_000_000),
            end: MediaTime(nanoseconds: end * 1_000_000_000)
        )
    }
}
