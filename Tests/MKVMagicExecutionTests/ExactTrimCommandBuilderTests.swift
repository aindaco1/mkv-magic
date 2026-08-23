import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
import XCTest

final class ExactTrimCommandBuilderTests: XCTestCase {
    func testBuildsOneExactVideoGenerationAndPacketCopiesAudio() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try resolve(
            source: fixture.source,
            choice: ExactTrimChoice(
                videoPreset: .hevcCompatibility,
                videoRateControl: .averageBitrate(2_000_000),
                audioPolicy: .packetCopy
            ),
            range: MediaTrimRange(
                start: MediaTime(nanoseconds: 2_250_000_000),
                end: MediaTime(nanoseconds: 7_750_000_000)
            )
        )
        let output = fixture.root.appendingPathComponent("Exact.mkv")

        let command = try ExactTrimCommandBuilder().build(
            resolvedPlan: plan,
            capabilities: capabilities(),
            outputURL: output
        )

        XCTAssertEqual(value(after: "-ss", in: command.arguments), "2.250000000")
        XCTAssertFalse(command.arguments.contains("-accurate_seek"))
        XCTAssertGreaterThan(
            try XCTUnwrap(command.arguments.firstIndex(of: "-ss")),
            try XCTUnwrap(command.arguments.firstIndex(of: "-i"))
        )
        XCTAssertEqual(value(after: "-t", in: command.arguments), "5.500000000")
        XCTAssertEqual(values(afterEach: "-map", in: command.arguments), ["0:0", "0:1"])
        XCTAssertEqual(value(after: "-c", in: command.arguments), "copy")
        XCTAssertEqual(
            value(after: "-c:v:0", in: command.arguments),
            "hevc_videotoolbox"
        )
        XCTAssertEqual(value(after: "-profile:v:0", in: command.arguments), "main10")
        XCTAssertEqual(value(after: "-b:v:0", in: command.arguments), "2000000")
        XCTAssertFalse(command.arguments.contains("-filter_complex"))
        XCTAssertFalse(command.arguments.contains("-c:a:0"))
        XCTAssertEqual(value(after: "-map_metadata", in: command.arguments), "0")
        XCTAssertEqual(value(after: "-map_chapters", in: command.arguments), "-1")
        XCTAssertEqual(command.arguments.last, output.path)
        XCTAssertEqual(command.encodedVideoTrackID, 0)
        XCTAssertEqual(command.encodedAudioTrackIDs, [])
        XCTAssertEqual(command.copiedAudioTrackIDs, [1])
    }

    func testAACPolicyEncodesEachAudioTrackOnceWithoutChangingLayoutFacts() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try resolve(
            source: fixture.source,
            choice: ExactTrimChoice(
                videoPreset: .h264Compatibility,
                videoRateControl: .averageBitrate(3_000_000),
                audioPolicy: .aacPreserveLayout
            ),
            range: range(1, 9),
            presets: [.h264Compatibility]
        )

        let command = try ExactTrimCommandBuilder().build(
            resolvedPlan: plan,
            capabilities: capabilities(),
            outputURL: fixture.root.appendingPathComponent("AAC.mkv")
        )

        XCTAssertEqual(value(after: "-c:a:0", in: command.arguments), "aac_at")
        XCTAssertEqual(value(after: "-b:a:0", in: command.arguments), "192000")
        XCTAssertEqual(value(after: "-ar:a:0", in: command.arguments), "48000")
        XCTAssertEqual(value(after: "-ac:a:0", in: command.arguments), "2")
        XCTAssertEqual(command.encodedAudioTrackIDs, [1])
        XCTAssertEqual(command.copiedAudioTrackIDs, [])
    }

    func testRejectsExistingOutputAndCapabilityRegression() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try resolve(
            source: fixture.source,
            choice: ExactTrimChoice(
                videoPreset: .hevcCompatibility,
                videoRateControl: .averageBitrate(2_000_000)
            ),
            range: range(1, 9)
        )
        let output = fixture.root.appendingPathComponent("Existing.mkv")
        try Data([2]).write(to: output)
        XCTAssertThrowsError(
            try ExactTrimCommandBuilder().build(
                resolvedPlan: plan,
                capabilities: capabilities(),
                outputURL: output
            )
        ) { XCTAssertEqual($0 as? ExactTrimCommandError, .existingOutput) }

        XCTAssertThrowsError(
            try ExactTrimCommandBuilder().build(
                resolvedPlan: plan,
                capabilities: .unavailable,
                outputURL: fixture.root.appendingPathComponent("New.mkv")
            )
        ) {
            XCTAssertEqual(
                $0 as? ExactTrimCommandError,
                .unavailableEncoder(.hevcCompatibility)
            )
        }
    }

    private struct Fixture {
        let root: URL
        let source: MediaAsset
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-exact-command-\(UUID().uuidString)",
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
                duration: MediaTime(nanoseconds: 10_000_000_000),
                fileSize: 1,
                tracks: [videoTrack(), audioTrack()],
                metadata: ["title": "Feature"],
                chapterEntryCount: 0,
                globalTagCount: 0,
                trackTagCount: 0,
                segmentUID: "SOURCE"
            )
        )
    }

    private func resolve(
        source: MediaAsset,
        choice: ExactTrimChoice,
        range: MediaTrimRange,
        presets: Set<VideoPreset> = [.hevcCompatibility]
    ) throws -> ResolvedExactTrimPlan {
        try ExactTrimPlanner().resolve(
            source: source,
            range: range,
            choice: choice,
            availableVideoPresets: presets,
            aacAvailable: true
        )
    }

    private func capabilities() -> FFmpegEncodingCapabilities {
        FFmpegEncodingCapabilities(
            softwareAV1: .unavailable,
            softwareAV1Encoder: nil,
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .unavailable,
            proResEncoder: nil,
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters
        )
    }

    private func videoTrack() -> MediaTrack {
        MediaTrack(
            id: 0,
            kind: .video,
            codec: "h264",
            codecID: "V_MPEG4/ISO/AVC",
            profile: "High",
            uid: 100,
            isDefault: true,
            dimensions: MediaDimensions(width: 160, height: 90),
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

    private func audioTrack() -> MediaTrack {
        MediaTrack(
            id: 1,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            profile: "LC",
            uid: 101,
            language: "en",
            title: "Main Audio",
            isDefault: true,
            channels: 2,
            channelLayout: "stereo",
            sampleRate: 48_000
        )
    }

    private func range(_ start: Int64, _ end: Int64) -> MediaTrimRange {
        MediaTrimRange(
            start: MediaTime(nanoseconds: start * 1_000_000_000),
            end: MediaTime(nanoseconds: end * 1_000_000_000)
        )
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
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
