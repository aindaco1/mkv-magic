import Foundation
import XCTest

@testable import MKVMagicSystem

final class CommandRunnerTests: XCTestCase {
    func testDefaultEnvironmentIsMinimalAndUnicodeSafe() {
        let environment = CommandRequest.defaultEnvironment

        XCTAssertEqual(environment["LC_ALL"], "C.UTF-8")
        XCTAssertEqual(environment["LANG"], "C.UTF-8")
        XCTAssertEqual(environment["PATH"], "/usr/bin:/bin")
        XCTAssertNil(environment["HOME"])
    }

    func testManySequentialCommandsAllReachTermination() async throws {
        let runner = FoundationCommandRunner()
        for _ in 0..<32 {
            let result = try await runner.run(
                CommandRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                    arguments: [],
                    timeout: 2
                )
            )
            XCTAssertEqual(result.exitCode, 0)
        }
    }

    func testRunsExactExecutableWithArguments() async throws {
        let result = try await FoundationCommandRunner().run(
            CommandRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "hello"])
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput.text, "hello")
        XCTAssertEqual(result.standardError.text, "")
    }

    func testRetainsBoundedTailAndReportsTruncation() async throws {
        let output = String(repeating: "a", count: 1_200) + String(repeating: "z", count: 1_200)
        let result = try await FoundationCommandRunner().run(
            CommandRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: ["%s", output],
                outputLimit: 1_024
            )
        )
        XCTAssertTrue(result.standardOutput.wasTruncated)
        XCTAssertEqual(result.standardOutput.data.count, 1_024)
        XCTAssertTrue(result.standardOutput.text.allSatisfy { $0 == "z" })
    }

    func testTimeoutTerminatesProcess() async {
        do {
            _ = try await FoundationCommandRunner().run(
                CommandRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["2"],
                    timeout: 0.05
                )
            )
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? CommandRunnerError, .timedOut)
        }
    }

    func testRelativeExecutableIsRejected() async {
        do {
            _ = try await FoundationCommandRunner().run(
                CommandRequest(executableURL: URL(fileURLWithPath: "ffprobe"), arguments: [])
            )
            XCTFail("Expected unsafe executable error")
        } catch {
            XCTAssertEqual(error as? CommandRunnerError, .unsafeExecutable)
        }
    }
}
