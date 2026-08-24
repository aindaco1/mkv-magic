import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum MatroskaAttachmentRemovalError: Error, Equatable, Sendable {
    case staleSource
    case toolFailed(exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension MatroskaAttachmentRemovalError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .staleSource:
            "The MKV changed after its attachment removal was reviewed."
        case .toolFailed(let exitCode, let message):
            "mkvmerge could not create the attachment-cleaned MKV (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen audit failed: \(reason)"
        }
    }
}

public struct MatroskaAttachmentRemovalPreview: Equatable, Sendable {
    public let source: MediaAsset
    public let removal: MatroskaAttachmentRemoval
    public let removedAttachments: [MediaAttachment]
    public let retainedAttachments: [MediaAttachment]
    public let sourceRevision: MediaSourceRevision

    public init(
        source: MediaAsset,
        removal: MatroskaAttachmentRemoval,
        removedAttachments: [MediaAttachment],
        retainedAttachments: [MediaAttachment],
        sourceRevision: MediaSourceRevision
    ) {
        self.source = source
        self.removal = removal
        self.removedAttachments = removedAttachments
        self.retainedAttachments = retainedAttachments
        self.sourceRevision = sourceRevision
    }
}

public struct MKVAttachmentRemover<Runner: CommandRunning>: Sendable {
    private let executableURL: URL
    private let runner: Runner

    public init(executableURL: URL, runner: Runner) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public func removeAttachments(
        from source: MediaAsset,
        removal: MatroskaAttachmentRemoval,
        outputURL: URL
    ) async throws {
        let arguments = try Self.arguments(
            source: source,
            removal: removal,
            outputURL: outputURL
        )
        let result = try await runner.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: arguments,
                timeout: 24 * 60 * 60,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0,
            !result.standardOutput.wasTruncated,
            !result.standardError.wasTruncated
        else {
            let rawMessage =
                result.standardError.text.isEmpty
                ? result.standardOutput.text : result.standardError.text
            let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MatroskaAttachmentRemovalError.toolFailed(
                exitCode: result.exitCode,
                message: message.isEmpty ? "Unknown tool error" : String(message.prefix(240))
            )
        }
    }

    public static func arguments(
        source: MediaAsset,
        removal: MatroskaAttachmentRemoval,
        outputURL: URL
    ) throws -> [String] {
        let resolution = try MatroskaAttachmentRemovalPolicy.resolve(removal, in: source)
        var arguments = [
            "--output", outputURL.path,
            "--abort-on-warnings",
            "--normalize-language-ietf", "canonical",
        ]
        if resolution.retainedAttachments.isEmpty {
            arguments.append("--no-attachments")
        } else {
            arguments.append(contentsOf: [
                "--attachments",
                resolution.retainedAttachments.map { String($0.id) }.joined(separator: ","),
            ])
        }
        let playableTracks = source.tracks.filter { $0.kind != .attachment }
        if !playableTracks.isEmpty {
            arguments.append(contentsOf: [
                "--track-order",
                playableTracks.map { "0:\($0.id)" }.joined(separator: ","),
            ])
        }
        arguments.append(source.sourceURL.path)
        return arguments
    }
}

public struct MatroskaAttachmentRemovalExecutor<
    Runner: CommandRunning, Inspector: MediaInspecting
>: Sendable {
    private let remover: MKVAttachmentRemover<Runner>
    private let inspector: Inspector
    private let verifier = MatroskaAttachmentRemovalOutputVerifier()

    public init(mkvmergeURL: URL, runner: Runner, inspector: Inspector) {
        remover = MKVAttachmentRemover(executableURL: mkvmergeURL, runner: runner)
        self.inspector = inspector
    }

    public func preview(
        source: MediaAsset,
        removal: MatroskaAttachmentRemoval
    ) async throws -> MatroskaAttachmentRemovalPreview {
        let revision = try readRevision(source.sourceURL)
        let current = try await inspector.inspect(source.sourceURL)
        guard MatroskaAssetSnapshot(current) == MatroskaAssetSnapshot(source),
            (try? MediaSourceRevision.read(source.sourceURL)) == revision
        else {
            throw MatroskaAttachmentRemovalError.staleSource
        }
        let resolution = try MatroskaAttachmentRemovalPolicy.resolve(removal, in: current)
        return MatroskaAttachmentRemovalPreview(
            source: current,
            removal: removal,
            removedAttachments: resolution.removedAttachments,
            retainedAttachments: resolution.retainedAttachments,
            sourceRevision: revision
        )
    }

    public func execute(
        preview: MatroskaAttachmentRemovalPreview,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        let current = try await inspector.inspect(preview.source.sourceURL)
        guard MatroskaAssetSnapshot(current) == MatroskaAssetSnapshot(preview.source) else {
            throw MatroskaAttachmentRemovalError.staleSource
        }
        let resolution = try MatroskaAttachmentRemovalPolicy.resolve(
            preview.removal,
            in: current
        )
        guard resolution.removedAttachments == preview.removedAttachments,
            resolution.retainedAttachments == preview.retainedAttachments
        else {
            throw MatroskaAttachmentRemovalError.staleSource
        }
        let validateSource = try mediaFileRevisionValidator(
            sourceURL: current.sourceURL,
            expectedRevision: preview.sourceRevision,
            changedError: MatroskaAttachmentRemovalError.staleSource
        )
        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: current,
            destinationURL: destinationURL,
            preparation: .empty,
            produce: { outputURL in
                try await remover.removeAttachments(
                    from: current,
                    removal: preview.removal,
                    outputURL: outputURL
                )
            },
            verify: { output in
                try verifier.verify(
                    original: current,
                    output: output,
                    removal: preview.removal
                )
            },
            validateSource: validateSource,
            committedAuditError: { outputURL, reason in
                MatroskaAttachmentRemovalError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }

    private func readRevision(_ sourceURL: URL) throws -> MediaSourceRevision {
        do {
            return try MediaSourceRevision.read(sourceURL)
        } catch {
            throw MatroskaAttachmentRemovalError.staleSource
        }
    }
}
