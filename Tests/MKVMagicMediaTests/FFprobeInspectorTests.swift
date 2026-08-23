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
                  "codec_type": "video",
                  "profile": "Main",
                  "width": 1920,
                  "height": 1080,
                  "pix_fmt": "yuv420p10le",
                  "bits_per_raw_sample": "10",
                  "avg_frame_rate": "24000/1001",
                  "disposition": {"default": 1, "forced": 0},
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
        XCTAssertEqual(asset.container, "matroska")
        XCTAssertEqual(asset.duration?.seconds, 120.5)
        XCTAssertEqual(asset.tracks.count, 2)
        XCTAssertEqual(asset.tracks[0].dimensions, MediaDimensions(width: 1920, height: 1080))
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
                .toolFailed(exitCode: 1, message: "invalid media")
            )
        }
    }
}
