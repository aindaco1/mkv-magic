import Foundation
import MKVMagicCore
import MKVMagicSystem

enum MatroskaTextSubtitleExtractorError: Error, Equatable, Sendable {
    case unsafeRequest
    case unsafeExtractedSubtitle
    case oversizedExtractedSubtitle
    case toolFailed(exitCode: Int32, message: String)
}

struct MatroskaTextSubtitleExtractor<Runner: CommandRunning>: Sendable {
    let mkvextractURL: URL
    let runner: Runner

    func extract(
        sourceURL: URL,
        trackID: Int,
        format: ExternalTextSubtitleFormat,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void = { _ in }
    ) async throws -> Data {
        guard trackID >= 0, Self.safeAbsoluteFilePath(sourceURL) else {
            throw MatroskaTextSubtitleExtractorError.unsafeRequest
        }
        return try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-subtitle-extraction"
        ) { directory in
            let outputURL = directory.appendingPathComponent(
                "embedded-subtitle.\(format.filenameExtension)"
            )
            let result = try await runner.run(
                MKVToolNixProgress.request(
                    executableURL: mkvextractURL,
                    arguments: ["tracks", sourceURL.path, "\(trackID):\(outputURL.path)"],
                    timeout: 120,
                    phase: .extractingTrack,
                    onProgress: onProgress
                )
            )
            guard result.exitCode == 0,
                !result.standardOutput.wasTruncated,
                !result.standardError.wasTruncated
            else {
                let rawMessage =
                    result.standardError.text.isEmpty
                    ? result.standardOutput.text : result.standardError.text
                throw MatroskaTextSubtitleExtractorError.toolFailed(
                    exitCode: result.exitCode,
                    message: String(
                        rawMessage.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240)
                    )
                )
            }
            do {
                return try SafeSubtitleTextFile.read(
                    outputURL,
                    allowedExtensions: [format.filenameExtension],
                    maximumInputBytes: SubtitleCleanupExecutor.maximumInputBytes
                )
            } catch let error as SafeSubtitleTextFileError {
                switch error {
                case .oversizedInput:
                    throw MatroskaTextSubtitleExtractorError.oversizedExtractedSubtitle
                case .unsafeInput, .unsupportedExtension:
                    throw MatroskaTextSubtitleExtractorError.unsafeExtractedSubtitle
                }
            }
        }
    }

    private static func safeAbsoluteFilePath(_ url: URL) -> Bool {
        let path = url.path
        return url.isFileURL && path.hasPrefix("/") && !path.contains("\0")
            && (1...4_096).contains(path.utf8.count)
    }
}
