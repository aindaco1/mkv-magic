import Foundation
import MKVMagicCore
import MKVMagicSystem
import XCTest

@testable import MKVMagicMedia

private struct StubRunner: CommandRunning {
    let result: CommandResult

    func run(_ request: CommandRequest) async throws -> CommandResult {
        result
    }
}

final class FFprobeInspectorTests: XCTestCase {
    private var inputURL: URL!

    override func setUpWithError() throws {
        inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-input-\(UUID().uuidString).mkv")
        try Data("fixture".utf8).write(to: inputURL, options: .withoutOverwriting)
    }

    override func tearDownWithError() throws {
        if inputURL != nil { try FileManager.default.removeItem(at: inputURL) }
    }

    func testNormalizesFormatTracksAndChapters() async throws {
        let json = #"""
            {
              "streams": [
                {
                  "index": 0,
                  "codec_name": "av1",
                  "codec_long_name": "Alliance for Open Media AV1",
                  "codec_type": "video",
                  "profile": "Main",
                  "level": 8,
                  "bit_rate": "6000000",
                  "width": 1920,
                  "height": 1080,
                  "pix_fmt": "yuv420p10le",
                  "avg_frame_rate": "24000/1001",
                  "color_range": "tv",
                  "color_space": "bt2020nc",
                  "color_transfer": "smpte2084",
                  "color_primaries": "bt2020",
                  "side_data_list": [
                    {"side_data_type": "Mastering display metadata"},
                    {"side_data_type": "Content light level metadata"}
                  ],
                  "disposition": {"default": 1, "forced": 0, "original": 1},
                  "tags": {"language": "eng", "title": "Picture"}
                },
                {
                  "index": 1,
                  "codec_name": "aac",
                  "codec_type": "audio",
                  "sample_rate": "48000",
                  "channels": 6,
                  "channel_layout": "5.1",
                  "disposition": {"default": 1, "forced": 0},
                  "tags": {"language": "eng"}
                }
              ],
              "chapters": [
                {"id": 0, "start_time": "0.0", "end_time": "60.0", "tags": {"title": "Part 1", "language": "eng"}}
              ],
              "format": {
                "format_name": "matroska,webm",
                "format_long_name": "Matroska / WebM",
                "duration": "120.5",
                "size": "1000000",
                "bit_rate": "66390",
                "tags": {"title": "Example"}
              }
            }
            """#
        let inspector = FFprobeInspector(
            ffprobeURL: URL(fileURLWithPath: "/usr/bin/true"),
            runner: StubRunner(
                result: CommandResult(
                    exitCode: 0,
                    standardOutput: CommandOutput(data: Data(json.utf8), wasTruncated: false),
                    standardError: CommandOutput(data: Data(), wasTruncated: false)
                )
            )
        )
        let asset = try await inspector.inspect(inputURL)
        let repeatedAsset = try await inspector.inspect(inputURL)
        XCTAssertEqual(asset.container, "matroska")
        XCTAssertEqual(asset.id, repeatedAsset.id)
        XCTAssertEqual(asset.chapters.map(\.id), repeatedAsset.chapters.map(\.id))
        XCTAssertEqual(asset.formatLongName, "Matroska / WebM")
        XCTAssertEqual(asset.duration?.seconds, 120.5)
        XCTAssertEqual(asset.tracks.count, 2)
        XCTAssertEqual(asset.tracks[0].dimensions, MediaDimensions(width: 1920, height: 1080))
        XCTAssertEqual(asset.tracks[0].codecLongName, "Alliance for Open Media AV1")
        XCTAssertEqual(asset.tracks[0].level, 8)
        XCTAssertEqual(asset.tracks[0].bitDepth, 10)
        XCTAssertEqual(asset.tracks[0].bitrate, 6_000_000)
        XCTAssertTrue(asset.tracks[0].isOriginal)
        XCTAssertEqual(asset.tracks[0].colorInfo?.transfer, "smpte2084")
        XCTAssertEqual(asset.tracks[0].hdrFormats, ["HDR10 metadata"])
        XCTAssertEqual(asset.tracks[1].channelLayout, "5.1")
        XCTAssertEqual(asset.chapters.first?.title, "Part 1")
        XCTAssertEqual(asset.metadata["title"], "Example")
    }

    func testNonzeroExitPreservesBoundedFailure() async {
        let inspector = FFprobeInspector(
            ffprobeURL: URL(fileURLWithPath: "/usr/bin/false"),
            runner: StubRunner(
                result: CommandResult(
                    exitCode: 1,
                    standardOutput: CommandOutput(data: Data(), wasTruncated: false),
                    standardError: CommandOutput(
                        data: Data("invalid media".utf8), wasTruncated: false)
                )
            )
        )
        do {
            _ = try await inspector.inspect(inputURL)
            XCTFail("Expected tool failure")
        } catch {
            XCTAssertEqual(
                error as? MediaInspectionError,
                .toolFailed(tool: "ffprobe", exitCode: 1, message: "invalid media")
            )
        }
    }
}
