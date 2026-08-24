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
        XCTAssertTrue(result.duration.isFinite)
        XCTAssertGreaterThan(result.duration, 0)
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

    func testStreamsIntegerKeyedDigestsAcrossCommandsWithoutMixingLanes() async throws {
        let a = String(repeating: "a", count: 64)
        let b = String(repeating: "b", count: 64)
        let c = String(repeating: "c", count: 64)
        let d = String(repeating: "d", count: 64)
        let ignored = String(repeating: "e", count: 64)
        let runner = FoundationCommandRunner()

        let digests = try await runner.digestIntegerKeyedLines(
            [
                CommandIntegerKeyedDigestRequest(
                    command: CommandRequest(
                        executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                        arguments: [
                            "%s",
                            "0,SHA256:\(a),side data\n1,SHA256:\(b)\n9,ignored \(ignored)\n",
                        ],
                        outputLimit: 1_024
                    ),
                    emittedKeyToDigestKey: [0: 10, 1: 20]
                ),
                CommandIntegerKeyedDigestRequest(
                    command: CommandRequest(
                        executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                        arguments: ["%s", "4,SHA256:\(c)\n5,SHA256:\(d)\n"],
                        outputLimit: 1_024
                    ),
                    emittedKeyToDigestKey: [4: 10, 5: 20]
                ),
            ],
            policy: CommandIntegerKeyedLineDigestPolicy(
                keySeparator: 44,
                requiredPrefix: "SHA256:",
                hexDigestByteCount: 64,
                allowedSuffixSeparator: 44
            )
        )

        XCTAssertEqual(digests[10]?.lineCount, 2)
        XCTAssertEqual(digests[20]?.lineCount, 2)
        XCTAssertEqual(
            digests[10]?.sha256,
            Data(SHA256.hash(data: Data("SHA256:\(a)\nSHA256:\(c)\n".utf8)))
        )
        XCTAssertEqual(
            digests[20]?.sha256,
            Data(SHA256.hash(data: Data("SHA256:\(b)\nSHA256:\(d)\n".utf8)))
        )
    }

    func testIntegerKeyedDigestRejectsMissingAndAmbiguousLanes() async throws {
        let hash = String(repeating: "a", count: 64)
        let runner = FoundationCommandRunner()
        let command = CommandRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", "0,SHA256:\(hash)\n"]
        )
        let policy = CommandIntegerKeyedLineDigestPolicy(
            keySeparator: 44,
            requiredPrefix: "SHA256:",
            hexDigestByteCount: 64
        )

        do {
            _ = try await runner.digestIntegerKeyedLines(
                [CommandIntegerKeyedDigestRequest(command: command, emittedKeyToDigestKey: [1: 1])],
                policy: policy
            )
            XCTFail("Expected a missing requested lane to fail closed")
        } catch {
            XCTAssertEqual(error as? CommandLineDigestError, .emptyOutput)
        }
        do {
            _ = try await runner.digestIntegerKeyedLines(
                [
                    CommandIntegerKeyedDigestRequest(
                        command: command,
                        emittedKeyToDigestKey: [0: 1, 1: 1]
                    )
                ],
                policy: policy
            )
            XCTFail("Expected duplicate logical lanes to be rejected")
        } catch {
            XCTAssertEqual(error as? CommandLineDigestError, .invalidPolicy)
        }
    }

    func testIntegerKeyedDigestRejectsMalformedLinesAndToolFailure() async throws {
        let hash = String(repeating: "a", count: 64)
        let runner = FoundationCommandRunner()
        let policy = CommandIntegerKeyedLineDigestPolicy(
            keySeparator: 44,
            requiredPrefix: "SHA256:",
            hexDigestByteCount: 64
        )
        let malformedOutputs = [
            "bad,SHA256:\(hash)\n",
            "0,SHA256:short\n",
            "0,SHA256:\(String(repeating: "a", count: 5_000))\n",
        ]
        for output in malformedOutputs {
            do {
                _ = try await runner.digestIntegerKeyedLines(
                    [
                        CommandIntegerKeyedDigestRequest(
                            command: CommandRequest(
                                executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                                arguments: ["%s", output]
                            ),
                            emittedKeyToDigestKey: [0: 0]
                        )
                    ],
                    policy: policy
                )
                XCTFail("Expected malformed keyed output to fail closed")
            } catch {
                XCTAssertEqual(error as? CommandLineDigestError, .malformedOutput)
            }
        }

        do {
            _ = try await runner.digestIntegerKeyedLines(
                [
                    CommandIntegerKeyedDigestRequest(
                        command: CommandRequest(
                            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
                            arguments: []
                        ),
                        emittedKeyToDigestKey: [0: 0]
                    )
                ],
                policy: policy
            )
            XCTFail("Expected a failed keyed digest command to fail closed")
        } catch {
            XCTAssertEqual(
                error as? CommandLineDigestError,
                .commandFailed(index: 0, exitCode: 1, message: "Unknown tool error")
            )
        }
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

    func testCancellationTerminatesRunAndDigestProcessesPromptly() async throws {
        let command = Task {
            try await FoundationCommandRunner().run(
                CommandRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["5"],
                    timeout: 10
                )
            )
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let start = DispatchTime.now().uptimeNanoseconds
        command.cancel()

        do {
            _ = try await command.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? CommandRunnerError, .cancelled)
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        XCTAssertLessThan(elapsed, 2_000_000_000)

        let digest = Task {
            try await FoundationCommandRunner().digestLines(
                [
                    CommandRequest(
                        executableURL: URL(fileURLWithPath: "/bin/sleep"),
                        arguments: ["5"],
                        timeout: 10
                    )
                ],
                policy: CommandLineDigestPolicy(
                    requiredPrefix: "SHA256:",
                    hexDigestByteCount: 64
                )
            )
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        digest.cancel()
        do {
            _ = try await digest.value
            XCTFail("Expected digest cancellation")
        } catch {
            XCTAssertEqual(error as? CommandRunnerError, .cancelled)
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
