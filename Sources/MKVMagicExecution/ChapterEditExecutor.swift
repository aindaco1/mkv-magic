import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum ChapterEditExecutionError: Error, Equatable, Sendable {
    case unsupportedSource
    case staleSource
    case noChanges
    case unsafeChapterOutput
    case chapterVerificationFailed
    case toolFailed(tool: String, exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension ChapterEditExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Chapter editing requires an inspected Matroska source."
        case .staleSource:
            "The MKV or its chapters changed after the Chapter Studio preview was opened."
        case .noChanges:
            "The chapter document has not changed."
        case .unsafeChapterOutput:
            "mkvextract did not create a safe, bounded chapter document."
        case .chapterVerificationFailed:
            "The output chapters do not exactly match the reviewed nested chapter document."
        case .toolFailed(let tool, let exitCode, let message):
            "\(tool) could not process the chapters (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct ChapterSourceRevision: Equatable, Sendable {
    public let fileSize: Int64
    public let modificationDate: Date
    public let fileNumber: UInt64?
    public let systemNumber: UInt64?

    public init(
        fileSize: Int64,
        modificationDate: Date,
        fileNumber: UInt64? = nil,
        systemNumber: UInt64? = nil
    ) {
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.fileNumber = fileNumber
        self.systemNumber = systemNumber
    }

    static func read(_ rawURL: URL) throws -> Self {
        let url = rawURL.standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/"),
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true, values.isSymbolicLink != true
        else {
            throw ChapterEditExecutionError.unsupportedSource
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            throw ChapterEditExecutionError.unsupportedSource
        }
        return Self(
            fileSize: size,
            modificationDate: modificationDate,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            systemNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value
        )
    }
}

public struct ChapterEditPreview: Equatable, Sendable {
    public let source: MediaAsset
    public let original: MatroskaChapterDocument
    public let sourceRevision: ChapterSourceRevision
    public let canonicalSHA256: Data

    public init(
        source: MediaAsset,
        original: MatroskaChapterDocument,
        sourceRevision: ChapterSourceRevision,
        canonicalSHA256: Data
    ) {
        self.source = source
        self.original = original
        self.sourceRevision = sourceRevision
        self.canonicalSHA256 = canonicalSHA256
    }
}

public struct ChapterEditExecutor<Runner: CommandRunning, Inspector: MediaInspecting>: Sendable {
    private struct ExtractedDocument: Sendable {
        let document: MatroskaChapterDocument
        let canonicalData: Data

        var digest: Data { Data(SHA256.hash(data: canonicalData)) }
    }

    private let mkvextractURL: URL
    private let mkvpropeditURL: URL
    private let runner: Runner
    private let inspector: Inspector
    private let codec = MatroskaChapterXMLCodec()
    private let verifier = ChapterReplacementOutputVerifier()

    public init(
        mkvextractURL: URL,
        mkvpropeditURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        self.mkvextractURL = mkvextractURL
        self.mkvpropeditURL = mkvpropeditURL
        self.runner = runner
        self.inspector = inspector
    }

    public func preview(source: MediaAsset) async throws -> ChapterEditPreview {
        guard MatroskaEditingPolicy.supports(source) else {
            throw ChapterEditExecutionError.unsupportedSource
        }
        let before = try ChapterSourceRevision.read(source.sourceURL)
        let extracted = try await extract(from: source.sourceURL)
        guard try ChapterSourceRevision.read(source.sourceURL) == before else {
            throw ChapterEditExecutionError.staleSource
        }
        return ChapterEditPreview(
            source: source,
            original: extracted.document,
            sourceRevision: before,
            canonicalSHA256: extracted.digest
        )
    }

    public func execute(
        preview: ChapterEditPreview,
        desired rawDesired: MatroskaChapterDocument,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard MatroskaEditingPolicy.supports(preview.source) else {
            throw ChapterEditExecutionError.unsupportedSource
        }
        let desired = try rawDesired.validated(mediaDuration: preview.source.duration)
        let desiredCanonical = try codec.serialize(desired)
        guard Data(SHA256.hash(data: desiredCanonical)) != preview.canonicalSHA256 else {
            throw ChapterEditExecutionError.noChanges
        }
        try await validateCurrent(preview)

        let transaction = VerifiedOutputTransaction(
            sourceURL: preview.source.sourceURL,
            destinationURL: destinationURL
        )
        do {
            let workingURL = try await transaction.prepareClone()
            guard try ChapterSourceRevision.read(preview.source.sourceURL) == preview.sourceRevision
            else {
                throw ChapterEditExecutionError.staleSource
            }
            try await replaceChapters(
                in: workingURL, with: desiredCanonical, isEmpty: desired.editions.isEmpty)
            try await onStage(.verifying)
            let temporaryAsset = try await inspector.inspect(workingURL)
            try verifier.verify(original: preview.source, output: temporaryAsset)
            try await verifyChapters(in: workingURL, expectedCanonical: desiredCanonical)
            try await transaction.markVerified()
            try await onStage(.committing)
            let committedURL = try await transaction.commit()
            do {
                let committedAsset = try await inspector.inspect(committedURL)
                try verifier.verify(original: preview.source, output: committedAsset)
                try await verifyChapters(
                    in: committedURL,
                    expectedCanonical: desiredCanonical
                )
                return committedAsset
            } catch {
                throw ChapterEditExecutionError.committedOutputAuditFailed(
                    outputURL: committedURL,
                    reason: error.localizedDescription
                )
            }
        } catch {
            await transaction.cancel()
            throw error
        }
    }

    public func validateCurrent(_ preview: ChapterEditPreview) async throws {
        guard try ChapterSourceRevision.read(preview.source.sourceURL) == preview.sourceRevision
        else {
            throw ChapterEditExecutionError.staleSource
        }
        let current = try await extract(from: preview.source.sourceURL)
        guard current.digest == preview.canonicalSHA256,
            try ChapterSourceRevision.read(preview.source.sourceURL) == preview.sourceRevision
        else {
            throw ChapterEditExecutionError.staleSource
        }
    }

    private func replaceChapters(
        in fileURL: URL,
        with canonicalData: Data,
        isEmpty: Bool
    ) async throws {
        try await withPrivateDirectory { directory in
            let chapterURL = directory.appendingPathComponent("chapters.xml", isDirectory: false)
            if !isEmpty {
                try canonicalData.write(to: chapterURL, options: .atomic)
            }
            try await run(
                tool: "mkvpropedit",
                executableURL: mkvpropeditURL,
                arguments: [
                    "--abort-on-warnings", fileURL.path, "--chapters",
                    isEmpty ? "" : chapterURL.path,
                ],
                timeout: 120
            )
        }
    }

    private func verifyChapters(in fileURL: URL, expectedCanonical: Data) async throws {
        let extracted = try await extract(from: fileURL)
        guard extracted.canonicalData == expectedCanonical else {
            throw ChapterEditExecutionError.chapterVerificationFailed
        }
    }

    private func extract(from fileURL: URL) async throws -> ExtractedDocument {
        try await withPrivateDirectory { directory in
            let outputURL = directory.appendingPathComponent("chapters.xml", isDirectory: false)
            try await run(
                tool: "mkvextract",
                executableURL: mkvextractURL,
                arguments: [fileURL.path, "chapters", outputURL.path],
                timeout: 120
            )
            if !FileManager.default.fileExists(atPath: outputURL.path) {
                return try emptyExtractedDocument()
            }
            guard
                let values = try? outputURL.resourceValues(forKeys: [
                    .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
                ]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                let size = values.fileSize,
                size >= 0,
                size <= MatroskaChapterXMLCodec.maximumInputBytes
            else {
                throw ChapterEditExecutionError.unsafeChapterOutput
            }
            if size == 0 {
                return try emptyExtractedDocument()
            }
            let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
            let document = try codec.parse(data)
            return ExtractedDocument(
                document: document,
                canonicalData: try codec.serialize(document)
            )
        }
    }

    private func emptyExtractedDocument() throws -> ExtractedDocument {
        let document = MatroskaChapterDocument()
        return ExtractedDocument(
            document: document,
            canonicalData: try codec.serialize(document)
        )
    }

    private func run(
        tool: String,
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws {
        let result = try await runner.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: arguments,
                timeout: timeout,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0 else {
            let message =
                [result.standardError.text, result.standardOutput.text]
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                ?? "Unknown tool error"
            throw ChapterEditExecutionError.toolFailed(
                tool: tool,
                exitCode: result.exitCode,
                message: String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
            )
        }
    }

    private func withPrivateDirectory<T: Sendable>(
        _ operation: (URL) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-chapters-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await operation(directory)
    }
}
