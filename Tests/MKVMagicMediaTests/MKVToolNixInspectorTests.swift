import Foundation
import MKVMagicCore
import MKVMagicSystem
import XCTest

@testable import MKVMagicMedia

private actor MKVRequestRecorder {
    private(set) var requests: [CommandRequest] = []

    func append(_ request: CommandRequest) {
        requests.append(request)
    }
}

private struct MKVStubRunner: CommandRunning {
    let result: CommandResult
    let recorder: MKVRequestRecorder

    func run(_ request: CommandRequest) async throws -> CommandResult {
        await recorder.append(request)
        return result
    }
}

final class MKVToolNixInspectorTests: XCTestCase {
    private var inputURL: URL!

    override func setUpWithError() throws {
        inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-mkvmerge-\(UUID().uuidString).mkv")
        try Data("fixture".utf8).write(to: inputURL, options: .withoutOverwriting)
    }

    override func tearDownWithError() throws {
        if inputURL != nil { try FileManager.default.removeItem(at: inputURL) }
    }

    func testNormalizesMatroskaStructureAndUsesJSONIdentification() async throws {
        let json = #"""
            {
              "attachments": [
                {
                  "content_type": "application/x-truetype-font",
                  "description": "Subtitle font",
                  "file_name": "Example.ttf",
                  "id": 3,
                  "properties": {"uid": 11747804573300770621},
                  "size": 869
                }
              ],
              "chapters": [{"num_entries": 4}],
              "container": {
                "properties": {
                  "duration": 120500000000,
                  "muxing_application": "libebml",
                  "segment_uid": "00112233445566778899aabbccddeeff",
                  "title": "Example",
                  "writing_application": "mkvmerge"
                },
                "recognized": true,
                "supported": true,
                "type": "Matroska"
              },
              "errors": [],
              "global_tags": [{"num_entries": 2}],
              "track_tags": [{"num_entries": 3, "track_id": 0}],
              "tracks": [
                {
                  "codec": "AV1",
                  "id": 0,
                  "properties": {
                    "codec_id": "V_AV1",
                    "default_track": true,
                    "display_dimensions": "1920x1080",
                    "enabled_track": true,
                    "flag_original": true,
                    "forced_track": false,
                    "language": "eng",
                    "language_ietf": "en-US",
                    "pixel_dimensions": "1920x1080",
                    "track_name": "Picture",
                    "uid": 1234,
                    "video_bits_per_colour": 10
                  },
                  "type": "video"
                }
              ],
              "warnings": ["fixture warning"]
            }
            """#
        let recorder = MKVRequestRecorder()
        let inspector = MKVToolNixInspector(
            mkvmergeURL: URL(fileURLWithPath: "/usr/bin/true"),
            runner: MKVStubRunner(result: result(json), recorder: recorder)
        )

        let inspection = try await inspector.inspect(inputURL)

        XCTAssertEqual(inspection.containerType, "Matroska")
        XCTAssertEqual(inspection.duration?.seconds, 120.5)
        XCTAssertEqual(inspection.chapterEntryCount, 4)
        XCTAssertEqual(inspection.globalTagCount, 2)
        XCTAssertEqual(inspection.trackTagCount, 3)
        XCTAssertEqual(inspection.tracks.first?.codecID, "V_AV1")
        XCTAssertEqual(inspection.tracks.first?.language, "en-US")
        XCTAssertEqual(
            inspection.tracks.first?.dimensions, MediaDimensions(width: 1920, height: 1080))
        XCTAssertEqual(inspection.tracks.first?.bitDepth, 10)
        XCTAssertEqual(inspection.attachments.first?.filename, "Example.ttf")
        XCTAssertEqual(inspection.attachments.first?.description, "Subtitle font")
        XCTAssertEqual(inspection.warnings, ["fixture warning"])

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            ["--identification-format", "json", "--identify", inputURL.path]
        )
    }

    func testMalformedJSONFailsClosed() async {
        let inspector = MKVToolNixInspector(
            mkvmergeURL: URL(fileURLWithPath: "/usr/bin/true"),
            runner: MKVStubRunner(result: result("{}"), recorder: MKVRequestRecorder())
        )
        do {
            _ = try await inspector.inspect(inputURL)
            XCTFail("Expected malformed response")
        } catch {
            XCTAssertEqual(error as? MediaInspectionError, .malformedResponse(tool: "mkvmerge"))
        }
    }

    private func result(_ json: String) -> CommandResult {
        CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(json.utf8), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}
