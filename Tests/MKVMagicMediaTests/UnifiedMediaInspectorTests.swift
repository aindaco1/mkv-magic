import Foundation
import MKVMagicCore
import MKVMagicSystem
import XCTest

@testable import MKVMagicMedia

private actor UnifiedRequestRecorder {
    private(set) var tools: [String] = []

    func append(_ tool: String) {
        tools.append(tool)
    }
}

private struct UnifiedStubRunner: CommandRunning {
    let ffprobeResult: CommandResult
    let mkvmergeResult: CommandResult
    let recorder: UnifiedRequestRecorder

    func run(_ request: CommandRequest) async throws -> CommandResult {
        let tool = request.executableURL.lastPathComponent
        await recorder.append(tool)
        return tool == "ffprobe" ? ffprobeResult : mkvmergeResult
    }
}

final class UnifiedMediaInspectorTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-unified-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if rootURL != nil { try FileManager.default.removeItem(at: rootURL) }
    }

    func testMatroskaDetailsMergeWithoutDiscardingFFprobeCodecFacts() async throws {
        let input = rootURL.appendingPathComponent("Movie.mkv")
        try Data("fixture".utf8).write(to: input)
        let recorder = UnifiedRequestRecorder()
        let inspector = UnifiedMediaInspector(
            ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            runner: UnifiedStubRunner(
                ffprobeResult: result(ffprobeJSON(container: "matroska,webm")),
                mkvmergeResult: result(mkvmergeJSON),
                recorder: recorder
            )
        )

        let asset = try await inspector.inspect(input)
        let tools = await recorder.tools

        XCTAssertEqual(tools, ["ffprobe", "mkvmerge"])
        XCTAssertEqual(asset.tracks.count, 1)
        XCTAssertEqual(asset.tracks.first?.codec, "av1")
        XCTAssertEqual(asset.tracks.first?.codecID, "V_AV1")
        XCTAssertEqual(asset.tracks.first?.uid, 99)
        XCTAssertTrue(asset.tracks.first?.isCommentary == true)
        XCTAssertEqual(asset.attachments.first?.filename, "Font.otf")
        XCTAssertEqual(asset.chapterEntryCount, 6)
        XCTAssertEqual(asset.metadata["title"], "Authoritative title")
        XCTAssertEqual(asset.segmentUID, "aabbccdd")
    }

    func testNonMatroskaUsesFFprobeOnly() async throws {
        let input = rootURL.appendingPathComponent("Movie.mp4")
        try Data("fixture".utf8).write(to: input)
        let recorder = UnifiedRequestRecorder()
        let inspector = UnifiedMediaInspector(
            ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
            mkvmergeURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            runner: UnifiedStubRunner(
                ffprobeResult: result(ffprobeJSON(container: "mov,mp4,m4a,3gp,3g2,mj2")),
                mkvmergeResult: result("{}"),
                recorder: recorder
            )
        )

        let asset = try await inspector.inspect(input)
        let tools = await recorder.tools

        XCTAssertEqual(tools, ["ffprobe"])
        XCTAssertEqual(asset.container, "mov")
        XCTAssertTrue(asset.attachments.isEmpty)
    }

    private func result(_ json: String) -> CommandResult {
        CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(json.utf8), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }

    private func ffprobeJSON(container: String) -> String {
        #"""
        {
          "streams": [
            {
              "index": 0,
              "codec_name": "av1",
              "codec_type": "video",
              "width": 1920,
              "height": 1080,
              "disposition": {"default": 1, "forced": 0},
              "tags": {"language": "eng"}
            },
            {
              "index": 1,
              "codec_name": "mjpeg",
              "codec_type": "video",
              "disposition": {"default": 0, "attached_pic": 1},
              "tags": {"filename": "Poster.jpg"}
            },
            {
              "index": 2,
              "codec_name": "unknown",
              "codec_type": "attachment",
              "tags": {"filename": "Font.otf"}
            }
          ],
          "format": {
            "format_name": "\#(container)",
            "duration": "60.0",
            "tags": {"title": "FFprobe title"}
          }
        }
        """#
    }

    private var mkvmergeJSON: String {
        #"""
        {
          "attachments": [
            {
              "content_type": "font/otf",
              "file_name": "Font.otf",
              "id": 1,
              "properties": {"uid": 101},
              "size": 2048
            }
          ],
          "chapters": [{"num_entries": 6}],
          "container": {
            "properties": {
              "duration": 60000000000,
              "segment_uid": "aabbccdd",
              "title": "Authoritative title"
            },
            "recognized": true,
            "supported": true,
            "type": "Matroska"
          },
          "errors": [],
          "global_tags": [],
          "track_tags": [],
          "tracks": [
            {
              "codec": "AV1",
              "id": 0,
              "properties": {
                "codec_id": "V_AV1",
                "default_track": true,
                "enabled_track": true,
                "flag_commentary": true,
                "forced_track": false,
                "language_ietf": "en",
                "pixel_dimensions": "1920x1080",
                "uid": 99
              },
              "type": "video"
            }
          ],
          "warnings": []
        }
        """#
    }
}
