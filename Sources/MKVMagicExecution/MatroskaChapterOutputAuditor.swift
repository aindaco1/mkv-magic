import Foundation
import MKVMagicCore
import MKVMagicSystem

enum MatroskaChapterOutputAuditError: Error, Equatable, Sendable {
    case toolFailed(exitCode: Int32, message: String)
    case unsafeExtractedDocument
    case mismatch
}

/// Re-extracts chapters from a completed Matroska file and compares canonical
/// nested XML. Both lossless and normalized joins use this exact audit.
struct MatroskaChapterOutputAuditor<Runner: CommandRunning>: Sendable {
    let mkvextractURL: URL
    let runner: Runner

    func verify(fileURL: URL, expectedCanonical: Data) async throws {
        let extracted = try await canonicalChapters(from: fileURL)
        guard extracted == expectedCanonical else {
            throw MatroskaChapterOutputAuditError.mismatch
        }
    }

    private func canonicalChapters(from fileURL: URL) async throws -> Data {
        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-chapter-audit"
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
                return try codec.serialize(MatroskaChapterDocument())
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
            if size == 0 {
                return try codec.serialize(MatroskaChapterDocument())
            }
            let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
            return try codec.serialize(codec.parse(data))
        }
    }

    private func conciseMessage(_ result: CommandResult) -> String {
        let message =
            [result.standardError.text, result.standardOutput.text]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Unknown tool error"
        return String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }
}
