import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicPlanning
import MKVMagicSystem

public enum MKVRemuxExecutionError: Error, Equatable, Sendable {
    case unsupportedDestination
    case unsafeSource
    case staleSource
    case toolFailed(exitCode: Int32, message: String)
    case copiedTrackVerificationFailed(reason: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension MKVRemuxExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedDestination: "Remux to MKV creates one .mkv output."
        case .unsafeSource: "Remux to MKV needs a safe regular source file."
        case .staleSource: "The source changed after the zero-encode remux was reviewed."
        case .toolFailed(let exitCode, let message):
            "mkvmerge could not create the temporary MKV (code \(exitCode)): \(message)"
        case .copiedTrackVerificationFailed(let reason):
            "A copied media track did not match the reviewed source: \(reason)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen audit failed: \(reason)"
        }
    }
}

public struct MKVRemuxPreview: Hashable, Sendable {
    public let plan: ResolvedMKVRemuxPlan
    public let sourceRevision: MediaSourceRevision

    public init(plan: ResolvedMKVRemuxPlan, sourceRevision: MediaSourceRevision) {
        self.plan = plan
        self.sourceRevision = sourceRevision
    }

    public var source: MediaAsset { plan.source }
}

public struct MKVRemuxExecutor<
    Runner: CommandRunning & CommandLineDigesting,
    Inspector: MediaInspecting
>: Sendable {
    private let mkvmergeURL: URL
    private let ffmpegURL: URL
    private let ffprobeURL: URL
    private let runner: Runner
    private let inspector: Inspector
    private let planner = MKVRemuxPlanner()
    private let commandBuilder = MKVRemuxCommandBuilder()
    private let verifier = MKVRemuxOutputVerifier()

    public init(
        mkvmergeURL: URL,
        ffmpegURL: URL,
        ffprobeURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        self.mkvmergeURL = mkvmergeURL
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
        self.runner = runner
        self.inspector = inspector
    }

    public func preview(source: MediaAsset) throws -> MKVRemuxPreview {
        let plan = try planner.resolve(source: source)
        let revision: MediaSourceRevision
        do {
            revision = try MediaSourceRevision.read(source.sourceURL)
        } catch {
            throw MKVRemuxExecutionError.unsafeSource
        }
        return MKVRemuxPreview(plan: plan, sourceRevision: revision)
    }

    public func execute(
        preview: MKVRemuxPreview,
        destinationURL: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in },
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw MKVRemuxExecutionError.unsupportedDestination
        }
        let validateSource = try mediaFileRevisionValidator(
            sourceURL: preview.source.sourceURL,
            expectedRevision: preview.sourceRevision,
            changedError: MKVRemuxExecutionError.staleSource
        )
        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: preview.source,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                try Task.checkCancellation()
                try validateSource()
                let arguments = try commandBuilder.build(
                    plan: preview.plan,
                    outputURL: outputURL
                )
                let result = try await runner.run(
                    MKVToolNixProgress.request(
                        executableURL: mkvmergeURL,
                        arguments: arguments,
                        timeout: 24 * 60 * 60,
                        onProgress: onProgress
                    )
                )
                guard result.exitCode == 0,
                    !result.standardError.wasTruncated,
                    !result.standardOutput.wasTruncated
                else {
                    let rawMessage =
                        result.standardError.text.isEmpty
                        ? result.standardOutput.text : result.standardError.text
                    throw MKVRemuxExecutionError.toolFailed(
                        exitCode: result.exitCode,
                        message: String(rawMessage.prefix(240))
                    )
                }
                try validateSource()
            },
            verify: { output in
                try verifier.verify(plan: preview.plan, output: output)
                let copiedTrackIDs = Set(preview.plan.trackIDsInOutputOrder)
                let sourceTracks = preview.source.tracks.filter {
                    copiedTrackIDs.contains($0.id)
                }
                let outputTracks = output.tracks.filter { $0.kind != .attachment }
                let lanes = zip(sourceTracks, outputTracks).enumerated().map {
                    JoinPacketAuditLane(
                        laneIndex: $0.offset,
                        kind: $0.element.0.kind,
                        outputTrackID: $0.element.1.id,
                        expectedInputs: [
                            JoinPacketFingerprintInput(
                                fileURL: preview.source.sourceURL,
                                trackID: $0.element.0.id
                            )
                        ]
                    )
                }
                do {
                    try await JoinOutputAuditor(
                        ffmpegURL: ffmpegURL,
                        ffprobeURL: ffprobeURL,
                        runner: runner
                    ).auditPacketCopies(
                        sources: [preview.source],
                        output: output,
                        lanes: lanes
                    )
                } catch {
                    throw MKVRemuxExecutionError.copiedTrackVerificationFailed(
                        reason: String(error.localizedDescription.prefix(240))
                    )
                }
                try validateSource()
            },
            validateSource: validateSource,
            committedAuditError: { outputURL, reason in
                MKVRemuxExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }
}
