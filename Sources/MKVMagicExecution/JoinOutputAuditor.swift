import Foundation
import MKVMagicCore
import MKVMagicSystem

private let joinAuditMaximumHalfWindowNanoseconds: Int64 = 1_000_000_000
private let joinAuditPacketHashPolicy = CommandLineDigestPolicy(
    requiredPrefix: "SHA256:",
    hexDigestByteCount: 64,
    allowedSuffixSeparator: Character(",").asciiValue
)
private let joinAuditFrameHashPolicy = CommandTrailingHexDigestPolicy(
    commentPrefix: 35,
    fieldSeparator: 44,
    hexDigestByteCount: 64
)

public struct JoinPacketFingerprintInput: Equatable, Sendable {
    public let fileURL: URL
    public let trackID: Int

    public init(fileURL: URL, trackID: Int) {
        self.fileURL = fileURL
        self.trackID = trackID
    }
}

public struct JoinPacketAuditLane: Equatable, Sendable {
    public let laneIndex: Int
    public let kind: MediaTrackKind
    public let outputTrackID: Int
    public let expectedInputs: [JoinPacketFingerprintInput]

    public init(
        laneIndex: Int,
        kind: MediaTrackKind,
        outputTrackID: Int,
        expectedInputs: [JoinPacketFingerprintInput]
    ) {
        self.laneIndex = laneIndex
        self.kind = kind
        self.outputTrackID = outputTrackID
        self.expectedInputs = expectedInputs
    }
}

public enum JoinOutputAuditError: Error, Equatable, Sendable {
    case invalidTimeline
    case invalidLanePlan
    case unsafeInput
    case decodeFailed(boundaryIndex: Int, exitCode: Int32, message: String)
    case truncatedDecodeDiagnostics(boundaryIndex: Int)
    case packetFingerprintFailed(laneIndex: Int, reason: String)
    case packetCountChanged(laneIndex: Int)
    case packetPayloadChanged(laneIndex: Int)
}

extension JoinOutputAuditError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidTimeline:
            "Join-boundary verification needs at least two positive source durations."
        case .invalidLanePlan:
            "The joined output cannot be matched to the reviewed packet lanes."
        case .unsafeInput:
            "Join-boundary verification requires safe, unchanged regular media files."
        case .decodeFailed(let boundaryIndex, let exitCode, let message):
            "The joined output did not decode cleanly across boundary \(boundaryIndex + 1) "
                + "(code \(exitCode)): \(message)"
        case .truncatedDecodeDiagnostics(let boundaryIndex):
            "Boundary \(boundaryIndex + 1) emitted more decode diagnostics than the safety limit."
        case .packetFingerprintFailed(let laneIndex, let reason):
            "Packet fingerprinting failed for lane \(laneIndex + 1): \(reason)"
        case .packetCountChanged(let laneIndex):
            "The packet count changed while lane \(laneIndex + 1) was copied."
        case .packetPayloadChanged(let laneIndex):
            "Encoded packet payloads changed while lane \(laneIndex + 1) was copied."
        }
    }
}

/// Independently audits the actual media payload after a join. Short windows
/// spanning every part boundary must decode without an FFmpeg error, and every
/// final packet-copy lane must contain the exact ordered encoded packet payloads
/// from its reviewed inputs. Packet listings are digested as a stream, so this
/// remains memory-bounded for feature-length media.
public struct JoinOutputAuditor<Runner: CommandRunning & CommandLineDigesting>: Sendable {
    private let ffmpegURL: URL
    private let ffprobeURL: URL
    private let runner: Runner

    public init(ffmpegURL: URL, ffprobeURL: URL, runner: Runner) {
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
        self.runner = runner
    }

    public func audit(
        sources: [MediaAsset],
        output: MediaAsset,
        lanes: [JoinPacketAuditLane]
    ) async throws {
        let boundaries = try boundaryWindows(sources: sources)
        guard safeRegularFile(output.sourceURL),
            lanes.flatMap(\.expectedInputs).allSatisfy({ safeRegularFile($0.fileURL) })
        else {
            throw JoinOutputAuditError.unsafeInput
        }
        guard Set(lanes.map(\.laneIndex)).count == lanes.count,
            Set(lanes.map(\.outputTrackID)).count == lanes.count,
            lanes.allSatisfy({ lane in
                lane.laneIndex >= 0 && lane.outputTrackID >= 0
                    && !lane.expectedInputs.isEmpty
                    && lane.expectedInputs.allSatisfy({ $0.trackID >= 0 })
            })
        else {
            throw JoinOutputAuditError.invalidLanePlan
        }
        var outputTracks = [Int: MediaTrack]()
        for track in output.tracks where track.kind != .attachment {
            guard track.id >= 0, outputTracks.updateValue(track, forKey: track.id) == nil
            else {
                throw JoinOutputAuditError.invalidLanePlan
            }
        }
        guard lanes.allSatisfy({ outputTracks[$0.outputTrackID]?.kind == $0.kind }) else {
            throw JoinOutputAuditError.invalidLanePlan
        }

        try await decodeBoundaries(
            boundaries,
            outputURL: output.sourceURL,
            trackIDs: output.tracks.filter { $0.kind == .video || $0.kind == .audio }
                .map(\.id)
        )
        for lane in lanes.sorted(by: { $0.laneIndex < $1.laneIndex }) {
            try Task.checkCancellation()
            let expected: CommandLineDigest
            let actual: CommandLineDigest
            do {
                let outputInput = JoinPacketFingerprintInput(
                    fileURL: output.sourceURL,
                    trackID: lane.outputTrackID
                )
                if lane.kind == .video,
                    let filter = canonicalVideoBitstreamFilter(
                        outputTracks[lane.outputTrackID]
                    )
                {
                    expected = try await runner.digestTrailingHexLines(
                        lane.expectedInputs.map {
                            videoFingerprintRequest($0, bitstreamFilter: filter)
                        },
                        policy: joinAuditFrameHashPolicy
                    )
                    actual = try await runner.digestTrailingHexLines(
                        [videoFingerprintRequest(outputInput, bitstreamFilter: filter)],
                        policy: joinAuditFrameHashPolicy
                    )
                } else {
                    expected = try await runner.digestLines(
                        lane.expectedInputs.map { fingerprintRequest($0) },
                        policy: joinAuditPacketHashPolicy
                    )
                    actual = try await runner.digestLines(
                        [
                            fingerprintRequest(
                                JoinPacketFingerprintInput(
                                    fileURL: output.sourceURL,
                                    trackID: lane.outputTrackID
                                )
                            )
                        ],
                        policy: joinAuditPacketHashPolicy
                    )
                }
            } catch {
                throw JoinOutputAuditError.packetFingerprintFailed(
                    laneIndex: lane.laneIndex,
                    reason: String(error.localizedDescription.prefix(240))
                )
            }
            guard expected.lineCount == actual.lineCount else {
                throw JoinOutputAuditError.packetCountChanged(laneIndex: lane.laneIndex)
            }
            guard expected.sha256 == actual.sha256 else {
                throw JoinOutputAuditError.packetPayloadChanged(laneIndex: lane.laneIndex)
            }
        }
    }

    private func decodeBoundaries(
        _ boundaries: [BoundaryWindow],
        outputURL: URL,
        trackIDs: [Int]
    ) async throws {
        guard !trackIDs.isEmpty else { return }
        for (index, boundary) in boundaries.enumerated() {
            try Task.checkCancellation()
            var arguments = [
                "-hide_banner", "-nostdin", "-loglevel", "error",
                "-xerror", "-err_detect", "explode",
                "-ss", decimalSeconds(boundary.start),
                "-i", outputURL.standardizedFileURL.path,
                "-t", decimalSeconds(boundary.duration),
            ]
            for trackID in trackIDs.sorted() {
                arguments.append(contentsOf: ["-map", "0:\(trackID)"])
            }
            arguments.append(contentsOf: ["-f", "null", "-"])
            let result = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: arguments,
                    timeout: 10 * 60,
                    outputLimit: 1_048_576
                )
            )
            guard !result.standardError.wasTruncated else {
                throw JoinOutputAuditError.truncatedDecodeDiagnostics(boundaryIndex: index)
            }
            let message = result.standardError.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.exitCode == 0, message.isEmpty else {
                throw JoinOutputAuditError.decodeFailed(
                    boundaryIndex: index,
                    exitCode: result.exitCode,
                    message: String(
                        (message.isEmpty ? "Unknown decode error" : message).prefix(240))
                )
            }
        }
    }

    private func fingerprintRequest(_ input: JoinPacketFingerprintInput) -> CommandRequest {
        CommandRequest(
            executableURL: ffprobeURL,
            arguments: [
                "-v", "error",
                "-select_streams", String(input.trackID),
                "-show_packets",
                "-show_entries", "packet=data_hash",
                "-show_data_hash", "sha256",
                "-of", "csv=p=0",
                input.fileURL.standardizedFileURL.path,
            ],
            timeout: 24 * 60 * 60,
            outputLimit: 1_048_576
        )
    }

    private func videoFingerprintRequest(
        _ input: JoinPacketFingerprintInput,
        bitstreamFilter: String
    ) -> CommandRequest {
        CommandRequest(
            executableURL: ffmpegURL,
            arguments: [
                "-hide_banner", "-nostdin", "-loglevel", "error",
                "-i", input.fileURL.standardizedFileURL.path,
                "-map", "0:\(input.trackID)",
                "-c", "copy",
                "-bsf:v", bitstreamFilter,
                "-f", "framehash",
                "-hash", "sha256",
                "-",
            ],
            timeout: 24 * 60 * 60,
            outputLimit: 1_048_576
        )
    }

    private func canonicalVideoBitstreamFilter(_ track: MediaTrack?) -> String? {
        guard let track else { return nil }
        let codec = track.codec.lowercased()
        let codecID = track.codecID?.lowercased() ?? ""
        if codec == "hevc" || codec == "h265" || codecID.contains("hevc") {
            return "filter_units=remove_types=32|33|34|35"
        }
        if codec == "h264" || codec == "avc" || codecID.contains("avc") {
            return "filter_units=remove_types=7|8|9"
        }
        return nil
    }

    private func boundaryWindows(sources: [MediaAsset]) throws -> [BoundaryWindow] {
        guard sources.count >= 2 else { throw JoinOutputAuditError.invalidTimeline }
        let durations = try sources.map { source -> Int64 in
            guard let duration = source.duration, duration.nanoseconds > 0 else {
                throw JoinOutputAuditError.invalidTimeline
            }
            return duration.nanoseconds
        }
        var elapsed: Int64 = 0
        var result = [BoundaryWindow]()
        for index in durations.indices.dropLast() {
            let sum = elapsed.addingReportingOverflow(durations[index])
            guard !sum.overflow else { throw JoinOutputAuditError.invalidTimeline }
            elapsed = sum.partialValue
            let before = min(
                joinAuditMaximumHalfWindowNanoseconds,
                max(1, durations[index] / 2)
            )
            let after = min(
                joinAuditMaximumHalfWindowNanoseconds,
                max(1, durations[index + 1] / 2)
            )
            let start = elapsed.subtractingReportingOverflow(before)
            let windowDuration = before.addingReportingOverflow(after)
            guard !start.overflow, !windowDuration.overflow,
                start.partialValue >= 0, windowDuration.partialValue > 0
            else {
                throw JoinOutputAuditError.invalidTimeline
            }
            result.append(
                BoundaryWindow(
                    start: MediaTime(nanoseconds: start.partialValue),
                    duration: MediaTime(nanoseconds: windowDuration.partialValue)
                )
            )
        }
        return result
    }

    private func safeRegularFile(_ rawURL: URL) -> Bool {
        let url = rawURL.standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0"),
            (1...4_096).contains(url.path.utf8.count),
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func decimalSeconds(_ time: MediaTime) -> String {
        let whole = time.nanoseconds / 1_000_000_000
        let fraction = time.nanoseconds % 1_000_000_000
        guard fraction != 0 else { return String(whole) }
        let digits = String(format: "%09lld", locale: Locale(identifier: "en_US_POSIX"), fraction)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return "\(whole).\(digits)"
    }

    private struct BoundaryWindow: Equatable, Sendable {
        let start: MediaTime
        let duration: MediaTime
    }

}
