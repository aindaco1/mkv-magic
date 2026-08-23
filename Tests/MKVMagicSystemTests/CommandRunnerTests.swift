import CryptoKit
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

    func testStreamsAndCanonicalizesDigestLinesAcrossCommandsWithoutOutputLimit() async throws {
        let firstHash = String(repeating: "a", count: 64)
        let secondHash = String(repeating: "B", count: 64)
        let repeated = Array(repeating: "SHA256:\(firstHash),ignored side data\n", count: 2_000)
            .joined()
        let runner = FoundationCommandRunner()

        let digest = try await runner.digestLines(
            [
                CommandRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                    arguments: ["%s", repeated],
                    outputLimit: 1_024
                ),
                CommandRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                    arguments: ["%s", "SHA256:\(secondHash)\n"],
                    outputLimit: 1_024
                ),
            ],
            policy: CommandLineDigestPolicy(
                requiredPrefix: "SHA256:",
                hexDigestByteCount: 64,
                allowedSuffixSeparator: Character(",").asciiValue
            )
        )

        let canonical =
            Array(repeating: "SHA256:\(firstHash)\n", count: 2_000).joined()
            + "SHA256:\(secondHash)\n"
        XCTAssertEqual(digest.lineCount, 2_001)
        XCTAssertEqual(digest.sha256, Data(SHA256.hash(data: Data(canonical.utf8))))
    }

    func testStreamingDigestRejectsMalformedAndEmptyOutput() async throws {
        let runner = FoundationCommandRunner()
        let policy = CommandLineDigestPolicy(
            requiredPrefix: "SHA256:",
            hexDigestByteCount: 64,
            allowedSuffixSeparator: Character(",").asciiValue
        )
        for (output, expected) in [
            ("SHA256:not-a-complete-hash\n", CommandLineDigestError.malformedOutput),
            ("", CommandLineDigestError.emptyOutput),
        ] {
            do {
                _ = try await runner.digestLines(
                    [
                        CommandRequest(
                            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                            arguments: ["%s", output]
                        )
                    ],
                    policy: policy
                )
                XCTFail("Expected streaming digest refusal")
            } catch {
                XCTAssertEqual(error as? CommandLineDigestError, expected)
            }
        }
    }

    func testStreamsTrailingFrameHashesWhileIgnoringBoundedHeaders() async throws {
        let firstHash = String(repeating: "1", count: 64)
        let secondHash = String(repeating: "f", count: 64)
        let frameHash = """
            #format: frame checksums
            #hash: SHA256
            0, 0, 0, 41, 109, \(firstHash)
            0, 41, 41, 41, 72, \(secondHash)

            """

        let digest = try await FoundationCommandRunner().digestTrailingHexLines(
            [
                CommandRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                    arguments: ["%s", frameHash]
                )
            ],
            policy: CommandTrailingHexDigestPolicy(
                commentPrefix: 35,
                fieldSeparator: 44,
                hexDigestByteCount: 64
            )
        )

        let canonical = "\(firstHash)\n\(secondHash)\n"
        XCTAssertEqual(digest.lineCount, 2)
        XCTAssertEqual(digest.sha256, Data(SHA256.hash(data: Data(canonical.utf8))))
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
