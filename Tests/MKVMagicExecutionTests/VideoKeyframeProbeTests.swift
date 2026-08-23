import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

private actor KeyframeProbeRunner: CommandRunning {
    let result: CommandResult
    private var requests = [CommandRequest]()

    init(json: String, exitCode: Int32 = 0, truncated: Bool = false) {
        result = CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(
                data: Data(json.utf8),
                wasTruncated: truncated
            ),
            standardError: CommandOutput(
                data: exitCode == 0 ? Data() : Data("probe failed".utf8),
                wasTruncated: false
            )
        )
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        return result
    }

    func capturedRequests() -> [CommandRequest] { requests }
}

final class VideoKeyframeProbeTests: XCTestCase {
    func testParsesSortsAndDeduplicatesBoundedKeyframes() async throws {
        let runner = KeyframeProbeRunner(
            json: """
                {"frames":[
                  {"best_effort_timestamp_time":"4.125000000"},
                  {"best_effort_timestamp_time":"0.000000"},
                  {"best_effort_timestamp_time":"4.125000000"},
                  {"best_effort_timestamp_time":"8.5"}
                ]}
                """
        )
        let source = URL(fileURLWithPath: "/media/Feature.mkv")
        let times = try await VideoKeyframeProbe(
            ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
            runner: runner
        ).probe(sourceURL: source)

        XCTAssertEqual(
            times,
            [
                MediaTime(nanoseconds: 0),
                MediaTime(nanoseconds: 4_125_000_000),
                MediaTime(nanoseconds: 8_500_000_000),
            ]
        )
        let captured = await runner.capturedRequests()
        let request = try XCTUnwrap(captured.first)
        XCTAssertEqual(request.executableURL.path, "/tools/ffprobe")
        XCTAssertEqual(value(after: "-select_streams", in: request.arguments), "v:0")
        XCTAssertEqual(value(after: "-skip_frame", in: request.arguments), "nokey")
        XCTAssertTrue(request.arguments.contains("-show_frames"))
        XCTAssertEqual(request.arguments.last, source.path)
    }

    func testRejectsToolFailureTruncationAndMalformedOrEmptyReports() async {
        let cases: [(KeyframeProbeRunner, VideoKeyframeProbeError)] = [
            (
                KeyframeProbeRunner(json: "{}", exitCode: 9),
                .toolFailed(exitCode: 9, message: "probe failed")
            ),
            (KeyframeProbeRunner(json: "{}", truncated: true), .truncatedOutput),
            (
                KeyframeProbeRunner(
                    json: "{\"frames\":[{\"best_effort_timestamp_time\":\"NaN\"}]}"
                ),
                .malformedOutput
            ),
            (KeyframeProbeRunner(json: "{\"frames\":[]}"), .noKeyframes),
        ]
        for (runner, expected) in cases {
            do {
                _ = try await VideoKeyframeProbe(
                    ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
                    runner: runner
                ).probe(sourceURL: URL(fileURLWithPath: "/media/source.mkv"))
                XCTFail("Expected keyframe probe failure")
            } catch {
                XCTAssertEqual(error as? VideoKeyframeProbeError, expected)
            }
        }
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}
