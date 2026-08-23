import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem
import XCTest

private actor JoinAuditRunner: CommandRunning, CommandLineDigesting {
    enum FingerprintBehavior: Sendable {
        case matching
        case wrongCount
        case wrongPayload
    }

    private let decodeExitCode: Int32
    private let decodeMessage: String
    private let fingerprintBehavior: FingerprintBehavior
    private var commandRequests = [CommandRequest]()
    private var digestRequests = [[CommandRequest]]()

    init(
        decodeExitCode: Int32 = 0,
        decodeMessage: String = "",
        fingerprintBehavior: FingerprintBehavior = .matching
    ) {
        self.decodeExitCode = decodeExitCode
        self.decodeMessage = decodeMessage
        self.fingerprintBehavior = fingerprintBehavior
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        commandRequests.append(request)
        return CommandResult(
            exitCode: decodeExitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(
                data: Data(decodeMessage.utf8),
                wasTruncated: false
            )
        )
    }

    func digestLines(
        _ requests: [CommandRequest],
        policy: CommandLineDigestPolicy
    ) async throws -> CommandLineDigest {
        digestRequests.append(requests)
        let isOutput =
            requests.count == 1
            && requests[0].arguments.contains(where: { $0.hasSuffix("output.mkv") })
        switch (fingerprintBehavior, isOutput) {
        case (.wrongCount, true):
            return CommandLineDigest(sha256: Data(repeating: 1, count: 32), lineCount: 19)
        case (.wrongPayload, true):
            return CommandLineDigest(sha256: Data(repeating: 2, count: 32), lineCount: 20)
        default:
            return CommandLineDigest(sha256: Data(repeating: 1, count: 32), lineCount: 20)
        }
    }

    func digestTrailingHexLines(
        _ requests: [CommandRequest],
        policy: CommandTrailingHexDigestPolicy
    ) async throws -> CommandLineDigest {
        try await digestLines(
            requests,
            policy: CommandLineDigestPolicy(
                requiredPrefix: "SHA256:",
                hexDigestByteCount: policy.hexDigestByteCount
            )
        )
    }

    func capturedCommands() -> [CommandRequest] { commandRequests }
    func capturedDigests() -> [[CommandRequest]] { digestRequests }
}

final class JoinOutputAuditorTests: XCTestCase {
    func testDecodesEveryBoundaryAndFingerprintsOrderedPacketInputs() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = JoinAuditRunner()
        let auditor = JoinOutputAuditor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
            runner: runner
        )

        try await auditor.audit(
            sources: fixture.sources,
            output: fixture.output,
            lanes: [fixture.lane]
        )

        let commands = await runner.capturedCommands()
        XCTAssertEqual(commands.count, 2)
        XCTAssertTrue(commands.allSatisfy { $0.executableURL.path == "/tools/ffmpeg" })
        XCTAssertEqual(commands.compactMap { value(after: "-ss", in: $0.arguments) }, ["3", "5"])
        XCTAssertEqual(commands.compactMap { value(after: "-t", in: $0.arguments) }, ["2", "2"])
        XCTAssertTrue(commands.allSatisfy { $0.arguments.contains("0:0") })

        let digests = await runner.capturedDigests()
        XCTAssertEqual(digests.count, 2)
        XCTAssertEqual(digests[0].count, 3)
        XCTAssertEqual(
            digests[0].compactMap { value(after: "-i", in: $0.arguments) },
            fixture.sources.map { $0.sourceURL.path }
        )
        XCTAssertEqual(digests[1].count, 1)
        XCTAssertEqual(
            value(after: "-i", in: digests[1][0].arguments),
            fixture.output.sourceURL.path
        )
        XCTAssertTrue(
            digests.flatMap { $0 }.allSatisfy {
                $0.arguments.contains("framehash")
                    && $0.arguments.contains("filter_units=remove_types=32|33|34|35")
                    && $0.arguments.contains("sha256")
            })
    }

    func testDecodeErrorStopsBeforePacketFingerprinting() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = JoinAuditRunner(decodeExitCode: 1, decodeMessage: "corrupt frame")
        let auditor = JoinOutputAuditor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
            runner: runner
        )

        await XCTAssertThrowsJoinAuditError(
            try await auditor.audit(
                sources: fixture.sources,
                output: fixture.output,
                lanes: [fixture.lane]
            )
        ) { error in
            XCTAssertEqual(
                error,
                .decodeFailed(boundaryIndex: 0, exitCode: 1, message: "corrupt frame")
            )
        }
        let digests = await runner.capturedDigests()
        XCTAssertTrue(digests.isEmpty)
    }

    func testPacketCountAndPayloadChangesFailClosed() async throws {
        for (behavior, expected) in [
            (
                JoinAuditRunner.FingerprintBehavior.wrongCount,
                JoinOutputAuditError.packetCountChanged(laneIndex: 0)
            ),
            (
                JoinAuditRunner.FingerprintBehavior.wrongPayload,
                JoinOutputAuditError.packetPayloadChanged(laneIndex: 0)
            ),
        ] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let runner = JoinAuditRunner(fingerprintBehavior: behavior)
            let auditor = JoinOutputAuditor(
                ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
                ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
                runner: runner
            )

            await XCTAssertThrowsJoinAuditError(
                try await auditor.audit(
                    sources: fixture.sources,
                    output: fixture.output,
                    lanes: [fixture.lane]
                )
            ) { error in
                XCTAssertEqual(error, expected)
            }
        }
    }

    func testUsesH264CanonicalUnitsAndExactOtherVideoPackets() async throws {
        for (codec, codecID, expectedTool, expectedMarker) in [
            ("h264", "V_MPEG4/ISO/AVC", "ffmpeg", "filter_units=remove_types=7|8|9"),
            ("vp9", "V_VP9", "ffprobe", "packet=data_hash"),
        ] {
            let fixture = try makeFixture(codec: codec, codecID: codecID)
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let runner = JoinAuditRunner()
            let auditor = JoinOutputAuditor(
                ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
                ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
                runner: runner
            )

            try await auditor.audit(
                sources: fixture.sources,
                output: fixture.output,
                lanes: [fixture.lane]
            )

            let digests = await runner.capturedDigests()
            XCTAssertEqual(digests.count, 2)
            XCTAssertTrue(
                digests.flatMap { $0 }.allSatisfy {
                    $0.executableURL.lastPathComponent == expectedTool
                        && $0.arguments.contains(expectedMarker)
                })
        }
    }

    private func makeFixture(
        codec: String = "hevc",
        codecID: String = "V_MPEGH/ISO/HEVC"
    ) throws -> (
        root: URL,
        sources: [MediaAsset],
        output: MediaAsset,
        lane: JoinPacketAuditLane
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-join-audit-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let durations: [Int64] = [4, 2, 6]
        let sourceURLs = durations.indices.map {
            root.appendingPathComponent("part-\($0 + 1).mkv")
        }
        let outputURL = root.appendingPathComponent("output.mkv")
        for (index, url) in sourceURLs.enumerated() {
            try Data("source \(index)".utf8).write(to: url)
        }
        try Data("joined output".utf8).write(to: outputURL)
        let track = MediaTrack(
            id: 0,
            kind: .video,
            codec: codec,
            codecID: codecID,
            uid: 100,
            dimensions: MediaDimensions(width: 1_920, height: 1_080)
        )
        let sources = zip(sourceURLs, durations).map { url, seconds in
            MediaAsset(
                sourceURL: url,
                container: "matroska",
                duration: MediaTime(seconds: Double(seconds)),
                fileSize: 8,
                tracks: [track]
            )
        }
        let output = MediaAsset(
            sourceURL: outputURL,
            container: "matroska",
            duration: MediaTime(seconds: 12),
            fileSize: 13,
            tracks: [track]
        )
        return (
            root,
            sources,
            output,
            JoinPacketAuditLane(
                laneIndex: 0,
                kind: .video,
                outputTrackID: 0,
                expectedInputs: sources.map {
                    JoinPacketFingerprintInput(fileURL: $0.sourceURL, trackID: 0)
                }
            )
        )
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}

private func XCTAssertThrowsJoinAuditError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (JoinOutputAuditError) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected join output audit to fail")
    } catch let error as JoinOutputAuditError {
        errorHandler(error)
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
}
