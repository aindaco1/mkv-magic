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
        case keyedFailure
    }

    private let decodeExitCode: Int32
    private let decodeMessage: String
    private let fingerprintBehavior: FingerprintBehavior
    private var commandRequests = [CommandRequest]()
    private var digestRequests = [[CommandRequest]]()
    private var keyedDigestRequests = [[CommandIntegerKeyedDigestRequest]]()

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

    func digestIntegerKeyedLines(
        _ requests: [CommandIntegerKeyedDigestRequest],
        policy: CommandIntegerKeyedLineDigestPolicy
    ) async throws -> [Int: CommandLineDigest] {
        keyedDigestRequests.append(requests)
        if case .keyedFailure = fingerprintBehavior {
            throw CommandLineDigestError.commandFailed(
                index: 0,
                exitCode: 2,
                message: "fixture keyed failure"
            )
        }
        let isOutput =
            requests.count == 1
            && requests[0].command.arguments.contains(where: { $0.hasSuffix("output.mkv") })
        let digest: CommandLineDigest
        switch (fingerprintBehavior, isOutput) {
        case (.wrongCount, true):
            digest = CommandLineDigest(sha256: Data(repeating: 1, count: 32), lineCount: 19)
        case (.wrongPayload, true):
            digest = CommandLineDigest(sha256: Data(repeating: 2, count: 32), lineCount: 20)
        default:
            digest = CommandLineDigest(sha256: Data(repeating: 1, count: 32), lineCount: 20)
        }
        let keys = Set(requests.flatMap { $0.emittedKeyToDigestKey.values })
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, digest) })
    }

    func capturedCommands() -> [CommandRequest] { commandRequests }
    func capturedDigests() -> [[CommandRequest]] { digestRequests }
    func capturedKeyedDigests() -> [[CommandIntegerKeyedDigestRequest]] {
        keyedDigestRequests
    }
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
        for (codec, codecID, canonicalFilter) in [
            ("h264", "V_MPEG4/ISO/AVC", "filter_units=remove_types=7|8|9"),
            ("vp9", "V_VP9", nil),
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

            if let canonicalFilter {
                let digests = await runner.capturedDigests()
                XCTAssertEqual(digests.count, 2)
                XCTAssertTrue(
                    digests.flatMap { $0 }.allSatisfy {
                        $0.executableURL.lastPathComponent == "ffmpeg"
                            && $0.arguments.contains(canonicalFilter)
                    })
            } else {
                let digests = await runner.capturedKeyedDigests()
                XCTAssertEqual(digests.count, 2)
                XCTAssertEqual(digests[0].count, fixture.sources.count)
                XCTAssertEqual(digests[1].count, 1)
                XCTAssertTrue(
                    digests.flatMap { $0 }.allSatisfy {
                        $0.command.executableURL.lastPathComponent == "ffprobe"
                            && $0.command.arguments.contains("packet=stream_index,data_hash")
                            && value(after: "-select_streams", in: $0.command.arguments) == "v"
                    })
            }
        }
    }

    func testExactPacketLanesShareOneBoundedScanPerInputAndOutput() async throws {
        let fixture = try makeFixture(codec: "vp9", codecID: "V_VP9")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let audio = MediaTrack(
            id: 1,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            channels: 2,
            sampleRate: 48_000
        )
        let alternateAudio = MediaTrack(
            id: 2,
            kind: .audio,
            codec: "aac",
            codecID: "A_AAC",
            language: "spa",
            channels: 2,
            sampleRate: 48_000
        )
        let sources = fixture.sources.map {
            MediaAsset(
                sourceURL: $0.sourceURL,
                container: $0.container,
                duration: $0.duration,
                fileSize: $0.fileSize,
                tracks: [audio, alternateAudio]
            )
        }
        let output = MediaAsset(
            sourceURL: fixture.output.sourceURL,
            container: fixture.output.container,
            duration: fixture.output.duration,
            fileSize: fixture.output.fileSize,
            tracks: [audio, alternateAudio]
        )
        let lanes = [
            JoinPacketAuditLane(
                laneIndex: 4,
                kind: .audio,
                outputTrackID: 1,
                expectedInputs: sources.map {
                    JoinPacketFingerprintInput(fileURL: $0.sourceURL, trackID: 1)
                }
            ),
            JoinPacketAuditLane(
                laneIndex: 7,
                kind: .audio,
                outputTrackID: 2,
                expectedInputs: sources.map {
                    JoinPacketFingerprintInput(fileURL: $0.sourceURL, trackID: 2)
                }
            ),
        ]
        let runner = JoinAuditRunner()
        let auditor = JoinOutputAuditor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
            runner: runner
        )

        try await auditor.audit(sources: sources, output: output, lanes: lanes)

        let batches = await runner.capturedKeyedDigests()
        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches[0].count, sources.count)
        XCTAssertEqual(batches[1].count, 1)
        XCTAssertTrue(
            batches[0].allSatisfy {
                $0.emittedKeyToDigestKey == [1: 4, 2: 7]
                    && value(after: "-select_streams", in: $0.command.arguments) == "a"
            })
        XCTAssertEqual(batches[1][0].emittedKeyToDigestKey, [1: 4, 2: 7])

        let failingRunner = JoinAuditRunner(fingerprintBehavior: .keyedFailure)
        let failingAuditor = JoinOutputAuditor(
            ffmpegURL: URL(fileURLWithPath: "/tools/ffmpeg"),
            ffprobeURL: URL(fileURLWithPath: "/tools/ffprobe"),
            runner: failingRunner
        )
        await XCTAssertThrowsJoinAuditError(
            try await failingAuditor.audit(sources: sources, output: output, lanes: lanes)
        ) { error in
            XCTAssertEqual(
                error,
                .packetFingerprintBatchFailed(
                    laneIndices: [4, 7],
                    reason: "Digest command 1 failed (code 2): fixture keyed failure"
                )
            )
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
