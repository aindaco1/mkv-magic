import Foundation
import MKVMagicSystem

public enum VerifiedOutputToolPhase: Equatable, Sendable {
    case multiplexing
    case extractingTrack
}

public struct VerifiedOutputToolProgress: Equatable, Sendable {
    public let phase: VerifiedOutputToolPhase
    public let percentage: Int

    public init(phase: VerifiedOutputToolPhase, percentage: Int) {
        self.phase = phase
        self.percentage = min(max(0, percentage), 100)
    }

    public var fractionCompleted: Double {
        Double(percentage) / 100
    }
}

enum MKVToolNixProgress {
    static func request(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = 1_048_576,
        phase: VerifiedOutputToolPhase = .multiplexing,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void
    ) -> CommandRequest {
        CommandRequest(
            executableURL: executableURL,
            arguments: ["--gui-mode"] + arguments,
            timeout: timeout,
            outputLimit: outputLimit,
            progressReporting: CommandProgressReporting(format: .mkvToolNixGUI) { update in
                await onProgress(
                    VerifiedOutputToolProgress(
                        phase: phase,
                        percentage: Int((update.fractionCompleted * 100).rounded())
                    )
                )
            }
        )
    }
}
