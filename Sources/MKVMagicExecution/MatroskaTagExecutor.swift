import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum MatroskaTagExecutionError: Error, Equatable, Sendable {
    case staleSource
    case unsafeExtractedDocument
    case extractionChanged
    case toolFailed(tool: String, exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension MatroskaTagExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .staleSource:
            "The MKV or its tags changed after the tag action was reviewed."
        case .unsafeExtractedDocument:
            "mkvextract did not create a safe, bounded Matroska tag document."
        case .extractionChanged:
            "The extracted Matroska tags changed after review. Inspect the source again."
        case .toolFailed(let tool, let exitCode, let message):
            "\(tool) could not process the Matroska tags (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified output was saved as \(outputURL.lastPathComponent), but its final reopen audit failed: \(reason)"
        }
    }
}

public struct MatroskaTagPreview: Equatable, Sendable {
    public let source: MediaAsset
    public let document: MatroskaTagXMLDocument
    public let sourceRevision: MediaSourceRevision
    fileprivate let digest: Data

    fileprivate init(
        source: MediaAsset,
        document: MatroskaTagXMLDocument,
        sourceRevision: MediaSourceRevision
    ) {
        self.source = source
        self.document = document
        self.sourceRevision = sourceRevision
        digest = Data(SHA256.hash(data: document.data))
    }
}

public struct MatroskaTagExportResult: Equatable, Sendable {
    public let outputURL: URL
    public let byteCount: Int
    public let counts: MatroskaTagCounts

    public init(outputURL: URL, byteCount: Int, counts: MatroskaTagCounts) {
        self.outputURL = outputURL
        self.byteCount = byteCount
        self.counts = counts
    }
}

private struct MatroskaTagDocumentExtractor<Runner: CommandRunning>: Sendable {
    let mkvextractURL: URL
    let runner: Runner

    func extract(
        from sourceURL: URL,
        expectedCounts: MatroskaTagCounts
    ) async throws -> MatroskaTagXMLDocument {
        try await PrivateTemporaryDirectory.withDirectory(prefix: "mkv-magic-tag-extract") {
            directory in
            let outputURL = directory.appendingPathComponent("tags.xml", isDirectory: false)
            return try await extract(
                from: sourceURL,
                to: outputURL,
                expectedCounts: expectedCounts
            )
        }
    }

    func extract(
        from sourceURL: URL,
        to outputURL: URL,
        expectedCounts: MatroskaTagCounts
    ) async throws -> MatroskaTagXMLDocument {
        let result = try await runner.run(
            CommandRequest(
                executableURL: mkvextractURL,
                arguments: [
                    sourceURL.path,
                    "--abort-on-warnings",
                    "tags",
                    "--no-bom",
                    outputURL.path,
                ],
                timeout: 120,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0,
            !result.standardOutput.wasTruncated,
            !result.standardError.wasTruncated
        else {
            throw MatroskaTagExecutionError.toolFailed(
                tool: "mkvextract",
                exitCode: result.exitCode,
                message: conciseMessage(result)
            )
        }
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            guard expectedCounts.total == 0 else {
                throw MatroskaTagExecutionError.unsafeExtractedDocument
            }
            return try emptyDocument()
        }
        guard
            let values = try? outputURL.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let size = values.fileSize,
            size >= 0,
            size <= MatroskaTagXMLDocument.maximumInputBytes
        else {
            throw MatroskaTagExecutionError.unsafeExtractedDocument
        }
        guard size > 0 else {
            guard expectedCounts.total == 0 else {
                throw MatroskaTagExecutionError.unsafeExtractedDocument
            }
            return try emptyDocument()
        }
        let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
        return try MatroskaTagXMLDocument(data: data, expectedCounts: expectedCounts)
    }

    func read(
        _ outputURL: URL,
        expectedCounts: MatroskaTagCounts
    ) throws -> MatroskaTagXMLDocument {
        guard
            let values = try? outputURL.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let size = values.fileSize,
            size > 0,
            size <= MatroskaTagXMLDocument.maximumInputBytes
        else {
            throw MatroskaTagExecutionError.unsafeExtractedDocument
        }
        return try MatroskaTagXMLDocument(
            data: Data(contentsOf: outputURL, options: .mappedIfSafe),
            expectedCounts: expectedCounts
        )
    }

    private func conciseMessage(_ result: CommandResult) -> String {
        let message =
            [result.standardError.text, result.standardOutput.text]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Unknown tool error"
        return String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }

    private func emptyDocument() throws -> MatroskaTagXMLDocument {
        try MatroskaTagXMLDocument(
            data: Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Tags>\n</Tags>\n".utf8),
            expectedCounts: MatroskaTagCounts(global: 0, track: 0)
        )
    }
}

public struct MatroskaTagExecutor<Runner: CommandRunning, Inspector: MediaInspecting>: Sendable {
    private let propertyEditor: MKVPropertyEditor<Runner>
    private let inspector: Inspector
    private let extractor: MatroskaTagDocumentExtractor<Runner>
    private let removalVerifier = MatroskaTagRemovalOutputVerifier()

    public init(
        mkvextractURL: URL,
        mkvpropeditURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        propertyEditor = MKVPropertyEditor(executableURL: mkvpropeditURL, runner: runner)
        self.inspector = inspector
        extractor = MatroskaTagDocumentExtractor(mkvextractURL: mkvextractURL, runner: runner)
    }

    public func preview(source: MediaAsset) async throws -> MatroskaTagPreview {
        let revision = try readRevision(source.sourceURL)
        let current = try await inspector.inspect(source.sourceURL)
        guard MatroskaAssetSnapshot(current) == MatroskaAssetSnapshot(source),
            (try? MediaSourceRevision.read(source.sourceURL)) == revision
        else {
            throw MatroskaTagExecutionError.staleSource
        }
        let counts = try MatroskaTagPolicy.counts(in: current)
        let document = try await extractor.extract(
            from: current.sourceURL,
            expectedCounts: counts
        )
        guard (try? MediaSourceRevision.read(source.sourceURL)) == revision else {
            throw MatroskaTagExecutionError.staleSource
        }
        return MatroskaTagPreview(
            source: current,
            document: document,
            sourceRevision: revision
        )
    }

    public func export(
        preview: MatroskaTagPreview,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MatroskaTagExportResult {
        let current = try await validateCurrent(preview)
        let validateSource = try mediaFileRevisionValidator(
            sourceURL: current.sourceURL,
            expectedRevision: preview.sourceRevision,
            changedError: MatroskaTagExecutionError.staleSource
        )
        let transaction = VerifiedOutputTransaction(
            sourceURL: current.sourceURL,
            destinationURL: destinationURL
        )
        do {
            try Task.checkCancellation()
            try validateSource()
            let temporaryURL = try await transaction.prepareEmptyOutput()
            let document = try await extractor.extract(
                from: current.sourceURL,
                to: temporaryURL,
                expectedCounts: preview.document.counts
            )
            try requireExact(document, preview: preview)
            try Task.checkCancellation()
            try validateSource()
            try await onStage(.verifying)
            try await transaction.markVerified()
            try await onStage(.committing)
            try Task.checkCancellation()
            try validateSource()
            let committedURL = try await transaction.commit()
            do {
                let reopened = try extractor.read(
                    committedURL,
                    expectedCounts: preview.document.counts
                )
                try requireExact(reopened, preview: preview)
                try validateSource()
            } catch {
                throw MatroskaTagExecutionError.committedOutputAuditFailed(
                    outputURL: committedURL,
                    reason: error.localizedDescription
                )
            }
            return MatroskaTagExportResult(
                outputURL: committedURL,
                byteCount: document.data.count,
                counts: document.counts
            )
        } catch {
            await transaction.cancel()
            throw error
        }
    }

    public func removeAll(
        preview: MatroskaTagPreview,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = {
            _ in
        }
    ) async throws -> MediaAsset {
        let current = try await validateCurrent(preview)
        let validateSource = try mediaFileRevisionValidator(
            sourceURL: current.sourceURL,
            expectedRevision: preview.sourceRevision,
            changedError: MatroskaTagExecutionError.staleSource
        )
        let emptyCounts = MatroskaTagCounts(global: 0, track: 0)
        return try await VerifiedOutputPipeline(inspector: inspector).execute(
            source: current,
            destinationURL: destinationURL,
            preparation: .clone,
            produce: { outputURL in
                try await clearTags(in: outputURL)
            },
            verify: { output in
                try removalVerifier.verify(original: current, output: output)
                let extracted = try await extractor.extract(
                    from: output.sourceURL,
                    expectedCounts: emptyCounts
                )
                guard extracted.counts == emptyCounts else {
                    throw OutputVerificationError.tagsChanged
                }
            },
            validateSource: validateSource,
            committedAuditError: { outputURL, reason in
                MatroskaTagExecutionError.committedOutputAuditFailed(
                    outputURL: outputURL,
                    reason: reason
                )
            },
            onStage: onStage
        )
    }

    private func validateCurrent(_ preview: MatroskaTagPreview) async throws -> MediaAsset {
        let current = try await inspector.inspect(preview.source.sourceURL)
        guard MatroskaAssetSnapshot(current) == MatroskaAssetSnapshot(preview.source),
            (try? MediaSourceRevision.read(current.sourceURL)) == preview.sourceRevision
        else {
            throw MatroskaTagExecutionError.staleSource
        }
        let counts = try MatroskaTagPolicy.counts(in: current)
        let document = try await extractor.extract(from: current.sourceURL, expectedCounts: counts)
        try requireExact(document, preview: preview)
        guard (try? MediaSourceRevision.read(current.sourceURL)) == preview.sourceRevision else {
            throw MatroskaTagExecutionError.staleSource
        }
        return current
    }

    private func requireExact(
        _ document: MatroskaTagXMLDocument,
        preview: MatroskaTagPreview
    ) throws {
        guard document.counts == preview.document.counts,
            Data(SHA256.hash(data: document.data)) == preview.digest,
            document.data == preview.document.data
        else {
            throw MatroskaTagExecutionError.extractionChanged
        }
    }

    private func clearTags(in outputURL: URL) async throws {
        do {
            try await propertyEditor.clearAllTags(at: outputURL)
        } catch MKVPropertyEditError.toolFailed(let exitCode, let message) {
            throw MatroskaTagExecutionError.toolFailed(
                tool: "mkvpropedit",
                exitCode: exitCode,
                message: message
            )
        }
    }

    private func readRevision(_ sourceURL: URL) throws -> MediaSourceRevision {
        do {
            return try MediaSourceRevision.read(sourceURL)
        } catch {
            throw MatroskaTagExecutionError.staleSource
        }
    }
}
