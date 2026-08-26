import Foundation
import MKVMagicCore
import MKVMagicSystem

public enum VideoKeyframeProbeError: Error, Equatable, Sendable {
    case toolFailed(exitCode: Int32, message: String)
    case truncatedOutput
    case malformedOutput
    case noKeyframes
}

extension VideoKeyframeProbeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .toolFailed(let exitCode, let message):
            "ffprobe could not read video keyframes (code \(exitCode)): \(message)"
        case .truncatedOutput: "The bounded keyframe report was too large to review safely."
        case .malformedOutput: "ffprobe returned an invalid keyframe report."
        case .noKeyframes: "ffprobe did not find a usable keyframe in the primary video track."
        }
    }
}

public struct VideoKeyframeProbe<Runner: CommandRunning>: Sendable {
    private static var maximumKeyframes: Int { 500_000 }

    private let ffprobeURL: URL
    private let runner: Runner

    public init(ffprobeURL: URL, runner: Runner) {
        self.ffprobeURL = ffprobeURL
        self.runner = runner
    }

    public func probe(sourceURL: URL) async throws -> [MediaTime] {
        let result = try await runner.run(
            CommandRequest(
                executableURL: ffprobeURL,
                arguments: [
                    "-v", "error",
                    "-select_streams", "v:0",
                    "-skip_frame", "nokey",
                    "-show_frames",
                    "-show_entries", "frame=best_effort_timestamp_time",
                    "-of", "json",
                    sourceURL.path,
                ],
                timeout: 60 * 60,
                outputLimit: 16_777_216
            )
        )
        guard result.exitCode == 0 else {
            throw VideoKeyframeProbeError.toolFailed(
                exitCode: result.exitCode,
                message: result.conciseFailureMessage
            )
        }
        guard !result.standardOutput.wasTruncated else {
            throw VideoKeyframeProbeError.truncatedOutput
        }
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: result.standardOutput.data)
        } catch {
            throw VideoKeyframeProbeError.malformedOutput
        }
        let frames = document.frames ?? []
        guard !frames.isEmpty, frames.count <= Self.maximumKeyframes else {
            throw frames.isEmpty
                ? VideoKeyframeProbeError.noKeyframes
                : VideoKeyframeProbeError.truncatedOutput
        }
        var times = [MediaTime]()
        times.reserveCapacity(frames.count)
        for frame in frames {
            guard let raw = frame.bestEffortTimestampTime,
                let time = parseDecimalSeconds(raw), time >= .zero
            else {
                throw VideoKeyframeProbeError.malformedOutput
            }
            times.append(time)
        }
        let normalized = Array(Set(times)).sorted()
        guard !normalized.isEmpty else { throw VideoKeyframeProbeError.noKeyframes }
        return normalized
    }

    private func parseDecimalSeconds(_ raw: String) -> MediaTime? {
        let pieces = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2, let whole = Int64(pieces[0]), whole >= 0 else { return nil }
        let wholeResult = whole.multipliedReportingOverflow(by: 1_000_000_000)
        guard !wholeResult.overflow else { return nil }
        var fraction: Int64 = 0
        if pieces.count == 2 {
            let digits = pieces[1]
            guard !digits.isEmpty, digits.count <= 9,
                digits.allSatisfy(\.isNumber),
                let value = Int64(digits)
            else { return nil }
            var scale: Int64 = 1
            for _ in digits.count..<9 {
                let result = scale.multipliedReportingOverflow(by: 10)
                guard !result.overflow else { return nil }
                scale = result.partialValue
            }
            let result = value.multipliedReportingOverflow(by: scale)
            guard !result.overflow else { return nil }
            fraction = result.partialValue
        }
        let total = wholeResult.partialValue.addingReportingOverflow(fraction)
        guard !total.overflow else { return nil }
        return MediaTime(nanoseconds: total.partialValue)
    }

}

private struct Document: Decodable {
    let frames: [Frame]?
}

private struct Frame: Decodable {
    let bestEffortTimestampTime: String?

    enum CodingKeys: String, CodingKey {
        case bestEffortTimestampTime = "best_effort_timestamp_time"
    }
}
