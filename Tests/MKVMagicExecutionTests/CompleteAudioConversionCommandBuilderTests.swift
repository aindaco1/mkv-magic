import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import XCTest

final class CompleteAudioConversionCommandBuilderTests: XCTestCase {
    func testBuildsOneAudioOnlyPassAndCopiesEveryOtherTrack() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try CompleteAudioConversionPlanner().resolve(
            source: fixture.source,
            preset: .opusQuality,
            availableAudioPresets: [.opusQuality]
        )

        let command = try CompleteAudioConversionCommandBuilder().build(
            resolvedPlan: plan,
            capabilities: capabilities(),
            outputURL: fixture.root.appendingPathComponent("Output.mkv")
        )

        XCTAssertEqual(
            values(afterEach: "-map", in: command.arguments),
            [
                "0:0", "0:1", "0:2", "0:3", "0:t?",
            ])
        XCTAssertEqual(value(after: "-c", in: command.arguments), "copy")
        XCTAssertNil(value(after: "-c:a:0", in: command.arguments))
        XCTAssertEqual(value(after: "-c:a:1", in: command.arguments), "libopus")
        XCTAssertEqual(value(after: "-ar:a:1", in: command.arguments), "48000")
        XCTAssertEqual(value(after: "-ac:a:1", in: command.arguments), "6")
        XCTAssertEqual(value(after: "-channel_layout:a:1", in: command.arguments), "5.1")
        XCTAssertEqual(value(after: "-mapping_family:a:1", in: command.arguments), "1")
        XCTAssertFalse(command.arguments.contains("-c:v:0"))
        XCTAssertEqual(value(after: "-map_metadata", in: command.arguments), "0")
        XCTAssertEqual(value(after: "-map_chapters", in: command.arguments), "-1")
        XCTAssertEqual(command.encodedAudioTrackIDs, [2])
        XCTAssertEqual(command.copiedTrackIDs, [0, 1, 3])
    }

    func testRejectsExistingOutputAndCapabilityRegression() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try CompleteAudioConversionPlanner().resolve(
            source: fixture.source,
            preset: .opusQuality,
            availableAudioPresets: [.opusQuality]
        )
        let existing = fixture.root.appendingPathComponent("Existing.mkv")
        try Data([2]).write(to: existing)

        XCTAssertThrowsError(
            try CompleteAudioConversionCommandBuilder().build(
                resolvedPlan: plan,
                capabilities: capabilities(),
                outputURL: existing
            )
        ) {
            XCTAssertEqual(
                $0 as? CompleteAudioConversionCommandError,
                .existingOutput
            )
        }
        XCTAssertThrowsError(
            try CompleteAudioConversionCommandBuilder().build(
                resolvedPlan: plan,
                capabilities: .unavailable,
                outputURL: fixture.root.appendingPathComponent("Unavailable.mkv")
            )
        ) {
            XCTAssertEqual(
                $0 as? CompleteAudioConversionCommandError,
                .unavailableAudioPreset(.opusQuality)
            )
        }
    }

    private struct Fixture {
        let root: URL
        let source: MediaAsset
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-audio-command-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sourceURL = root.appendingPathComponent("Source.mkv")
        try Data([1]).write(to: sourceURL)
        return Fixture(
            root: root,
            source: MediaAsset(
                sourceURL: sourceURL,
                container: "matroska,webm",
                duration: MediaTime(seconds: 10),
                fileSize: 1,
                tracks: [
                    MediaTrack(
                        id: 0,
                        kind: .video,
                        codec: "av1",
                        dimensions: MediaDimensions(width: 160, height: 90)
                    ),
                    MediaTrack(
                        id: 1,
                        kind: .audio,
                        codec: "opus",
                        channels: 2,
                        channelLayout: "stereo",
                        sampleRate: 48_000
                    ),
                    MediaTrack(
                        id: 2,
                        kind: .audio,
                        codec: "eac3",
                        channels: 6,
                        channelLayout: "5.1",
                        sampleRate: 48_000
                    ),
                    MediaTrack(id: 3, kind: .subtitle, codec: "subrip"),
                ],
                attachments: [
                    MediaAttachment(id: 4, filename: "cover.jpg", mimeType: "image/jpeg")
                ],
                globalTagCount: 0,
                trackTagCount: 0
            )
        )
    }

    private func capabilities() -> FFmpegEncodingCapabilities {
        FFmpegEncodingCapabilities(
            softwareAV1: .unavailable,
            softwareAV1Encoder: nil,
            hevc10VideoToolbox: .unavailable,
            h264VideoToolbox: .unavailable,
            proRes: .unavailable,
            proResEncoder: nil,
            aac: .unavailable,
            aacEncoder: nil,
            availableFilters: [],
            audioCapabilities: [
                .opusQuality: .init(status: .verified, encoder: "libopus")
            ]
        )
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
            arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    private func values(afterEach flag: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == flag, arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
    }
}
