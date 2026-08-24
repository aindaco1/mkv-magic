import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum MatroskaAttachmentExtractionError: Error, Equatable, Sendable {
    case unsupportedSource
    case attachmentNotFound
    case staleSource
    case unsafeExtractedAttachment
    case oversizedExtractedAttachment
    case extractionChanged
    case toolFailed(exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension MatroskaAttachmentExtractionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Attachment extraction requires an inspected Matroska file with a bounded attachment."
        case .attachmentNotFound:
            "The selected attachment is no longer available with a stable Matroska identity."
        case .staleSource:
            "The MKV changed after its attachment extraction was reviewed."
        case .unsafeExtractedAttachment:
            "mkvextract did not create a safe regular attachment file of the reviewed size."
        case .oversizedExtractedAttachment:
            "The extracted attachment is larger than MKV Magic allows."
        case .extractionChanged:
            "The extracted attachment changed after review. Inspect the source again."
        case .toolFailed(let exitCode, let message):
            "mkvextract could not extract the selected attachment (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified attachment was saved as \(outputURL.lastPathComponent), but its final reopen audit failed: \(reason)"
        }
    }
}

public struct MatroskaAttachmentExtractionPreview: Equatable, Sendable {
    public let source: MediaAsset
    public let attachment: MediaAttachment
    public let sourceRevision: MediaSourceRevision
    public let byteCount: Int64
    fileprivate let digest: Data

    fileprivate init(
        source: MediaAsset,
        attachment: MediaAttachment,
        sourceRevision: MediaSourceRevision,
        byteCount: Int64,
        digest: Data
    ) {
        self.source = source
        self.attachment = attachment
        self.sourceRevision = sourceRevision
        self.byteCount = byteCount
        self.digest = digest
    }
}

public struct MatroskaAttachmentExtractionResult: Equatable, Sendable {
    public let outputURL: URL
    public let byteCount: Int64

    public init(outputURL: URL, byteCount: Int64) {
        self.outputURL = outputURL
        self.byteCount = byteCount
    }
}

public struct MatroskaAttachmentExtractionExecutor<
    Runner: CommandRunning, Inspector: MediaInspecting
>: Sendable {
    private let mkvextractURL: URL
    private let runner: Runner
    private let inspector: Inspector

    public init(mkvextractURL: URL, runner: Runner, inspector: Inspector) {
        self.mkvextractURL = mkvextractURL
        self.runner = runner
        self.inspector = inspector
    }

    public func preview(
        source: MediaAsset,
        attachmentUID: UInt64
    ) async throws -> MatroskaAttachmentExtractionPreview {
        let current = try await inspector.inspect(source.sourceURL)
        guard MatroskaAssetSnapshot(current) == MatroskaAssetSnapshot(source) else {
            throw MatroskaAttachmentExtractionError.staleSource
        }
        let attachment = try selectedAttachment(in: current, uid: attachmentUID)
        let revision = try sourceRevision(current.sourceURL)
        let snapshot = try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-attachment-extraction"
        ) { directory in
            let outputURL = directory.appendingPathComponent("attachment.bin")
            try await extract(
                sourceURL: current.sourceURL,
                attachmentID: attachment.id,
                outputURL: outputURL
            )
            return try AttachmentFileSnapshot.read(
                outputURL,
                expectedSize: attachment.size
            )
        }
        guard (try? MediaSourceRevision.read(current.sourceURL)) == revision else {
            throw MatroskaAttachmentExtractionError.staleSource
        }
        return MatroskaAttachmentExtractionPreview(
            source: current,
            attachment: attachment,
            sourceRevision: revision,
            byteCount: snapshot.byteCount,
            digest: snapshot.digest
        )
    }

    public func execute(
        preview: MatroskaAttachmentExtractionPreview,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MatroskaAttachmentExtractionResult {
        let current = try await inspector.inspect(preview.source.sourceURL)
        guard MatroskaAssetSnapshot(current) == MatroskaAssetSnapshot(preview.source) else {
            throw MatroskaAttachmentExtractionError.staleSource
        }
        let uid = try attachmentUID(in: preview)
        let attachment = try selectedAttachment(in: current, uid: uid)
        guard attachment == preview.attachment else {
            throw MatroskaAttachmentExtractionError.staleSource
        }
        let validateSource = try mediaFileRevisionValidator(
            sourceURL: current.sourceURL,
            expectedRevision: preview.sourceRevision,
            changedError: MatroskaAttachmentExtractionError.staleSource
        )
        let transaction = VerifiedOutputTransaction(
            sourceURL: current.sourceURL,
            destinationURL: destinationURL
        )
        do {
            try Task.checkCancellation()
            try validateSource()
            let temporaryURL = try await transaction.prepareEmptyOutput()
            try await extract(
                sourceURL: current.sourceURL,
                attachmentID: attachment.id,
                outputURL: temporaryURL
            )
            try Task.checkCancellation()
            let snapshot = try AttachmentFileSnapshot.read(
                temporaryURL,
                expectedSize: attachment.size
            )
            try validateSource()
            guard snapshot.byteCount == preview.byteCount,
                snapshot.digest == preview.digest
            else {
                throw MatroskaAttachmentExtractionError.extractionChanged
            }
            try await onStage(.verifying)
            try Task.checkCancellation()
            try validateSource()
            try await transaction.markVerified()
            try await onStage(.committing)
            try Task.checkCancellation()
            try validateSource()
            let committedURL = try await transaction.commit()
            do {
                let reopened = try AttachmentFileSnapshot.read(
                    committedURL,
                    expectedSize: attachment.size
                )
                guard reopened == snapshot else {
                    throw MatroskaAttachmentExtractionError.extractionChanged
                }
                try Task.checkCancellation()
                try validateSource()
            } catch {
                throw MatroskaAttachmentExtractionError.committedOutputAuditFailed(
                    outputURL: committedURL,
                    reason: error.localizedDescription
                )
            }
            return MatroskaAttachmentExtractionResult(
                outputURL: committedURL,
                byteCount: snapshot.byteCount
            )
        } catch {
            await transaction.cancel()
            throw error
        }
    }

    private func selectedAttachment(in source: MediaAsset, uid: UInt64) throws -> MediaAttachment {
        guard MatroskaEditingPolicy.supports(source) else {
            throw MatroskaAttachmentExtractionError.unsupportedSource
        }
        guard
            let attachment = MatroskaAttachmentExtractionPolicy.extractableAttachments(in: source)
                .first(where: { $0.uid == uid })
        else {
            throw MatroskaAttachmentExtractionError.attachmentNotFound
        }
        return attachment
    }

    private func attachmentUID(in preview: MatroskaAttachmentExtractionPreview) throws -> UInt64 {
        guard let uid = preview.attachment.uid else {
            throw MatroskaAttachmentExtractionError.attachmentNotFound
        }
        return uid
    }

    private func sourceRevision(_ sourceURL: URL) throws -> MediaSourceRevision {
        do {
            return try MediaSourceRevision.read(sourceURL)
        } catch {
            throw MatroskaAttachmentExtractionError.staleSource
        }
    }

    private func extract(
        sourceURL: URL,
        attachmentID: Int,
        outputURL: URL
    ) async throws {
        guard attachmentID >= 0 else {
            throw MatroskaAttachmentExtractionError.attachmentNotFound
        }
        let result = try await runner.run(
            CommandRequest(
                executableURL: mkvextractURL,
                arguments: [
                    "attachments", sourceURL.path, "\(attachmentID):\(outputURL.path)",
                ],
                timeout: 120,
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
            throw MatroskaAttachmentExtractionError.toolFailed(
                exitCode: result.exitCode,
                message: message.isEmpty ? "Unknown tool error" : String(message.prefix(240))
            )
        }
    }
}

private struct AttachmentFileSnapshot: Equatable, Sendable {
    let byteCount: Int64
    let digest: Data

    static func read(_ rawURL: URL, expectedSize: Int64?) throws -> Self {
        let url = rawURL.standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/"),
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let byteCount = values.fileSize.map(Int64.init),
            byteCount > 0
        else {
            throw MatroskaAttachmentExtractionError.unsafeExtractedAttachment
        }
        guard byteCount <= MatroskaAttachmentExtractionPolicy.maximumAttachmentBytes else {
            throw MatroskaAttachmentExtractionError.oversizedExtractedAttachment
        }
        guard expectedSize == nil || expectedSize == byteCount else {
            throw MatroskaAttachmentExtractionError.unsafeExtractedAttachment
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            var bytesRead: Int64 = 0
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                bytesRead += Int64(data.count)
                guard bytesRead <= byteCount else {
                    throw MatroskaAttachmentExtractionError.unsafeExtractedAttachment
                }
                hasher.update(data: data)
            }
            guard bytesRead == byteCount else {
                throw MatroskaAttachmentExtractionError.unsafeExtractedAttachment
            }
            return Self(byteCount: byteCount, digest: Data(hasher.finalize()))
        } catch let error as MatroskaAttachmentExtractionError {
            throw error
        } catch {
            throw MatroskaAttachmentExtractionError.unsafeExtractedAttachment
        }
    }
}
