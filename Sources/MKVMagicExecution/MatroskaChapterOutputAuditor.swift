import Foundation
import MKVMagicCore
import MKVMagicSystem

enum MatroskaChapterOutputAuditError: Error, Equatable, Sendable {
    case toolFailed(exitCode: Int32, message: String)
    case unsafeExtractedDocument
    case mismatch
}

struct ExtractedMatroskaChapters: Sendable {
    let document: MatroskaChapterDocument
    let canonicalData: Data
}

/// One bounded chapter extraction path shared by previews and post-output audits.
struct MatroskaChapterDocumentExtractor<Runner: CommandRunning>: Sendable {
    let mkvextractURL: URL
    let runner: Runner

    func extract(from fileURL: URL) async throws -> ExtractedMatroskaChapters {
        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-chapter-extract"
        ) { directory in
            let outputURL = directory.appendingPathComponent(
                "chapters.xml",
                isDirectory: false
            )
            let result = try await runner.run(
                CommandRequest(
                    executableURL: mkvextractURL,
                    arguments: [fileURL.path, "chapters", outputURL.path],
                    timeout: 120,
                    outputLimit: 1_048_576
                )
            )
            guard result.exitCode == 0 else {
                throw MatroskaChapterOutputAuditError.toolFailed(
                    exitCode: result.exitCode,
                    message: conciseMessage(result)
                )
            }
            let codec = MatroskaChapterXMLCodec()
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                return try empty(codec: codec)
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
                throw MatroskaChapterOutputAuditError.unsafeExtractedDocument
            }
            guard size > 0 else { return try empty(codec: codec) }
            let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
            let document = try codec.parse(data)
            return ExtractedMatroskaChapters(
                document: document,
                canonicalData: try codec.serialize(document)
            )
        }
    }

    private func empty(codec: MatroskaChapterXMLCodec) throws -> ExtractedMatroskaChapters {
        let document = MatroskaChapterDocument()
        return ExtractedMatroskaChapters(
            document: document,
            canonicalData: try codec.serialize(document)
        )
    }

    private func conciseMessage(_ result: CommandResult) -> String {
        let message =
            [result.standardError.text, result.standardOutput.text]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Unknown tool error"
        return String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }
}

/// Re-extracts chapters from a completed Matroska file and compares canonical
/// nested XML. Both lossless and normalized joins use this exact audit.
struct MatroskaChapterOutputAuditor<Runner: CommandRunning>: Sendable {
    private let extractor: MatroskaChapterDocumentExtractor<Runner>

    init(mkvextractURL: URL, runner: Runner) {
        extractor = MatroskaChapterDocumentExtractor(
            mkvextractURL: mkvextractURL,
            runner: runner
        )
    }

    func verify(fileURL: URL, expectedCanonical: Data) async throws {
        let extracted = try await extractor.extract(from: fileURL)
        guard extracted.canonicalData == expectedCanonical else {
            throw MatroskaChapterOutputAuditError.mismatch
        }
    }
}
