import Foundation
import MKVMagicCore
import MKVMagicSystem

public struct ChapterThumbnail: Equatable, Sendable {
    public let time: MediaTime
    public let imageData: Data

    public init(time: MediaTime, imageData: Data) {
        self.time = time
        self.imageData = imageData
    }
}

public enum ChapterThumbnailGeneratorError: Error, Equatable, Sendable {
    case unsupportedSource
    case noVideoTrack
    case invalidRequest
    case staleSource
    case unsafeOutput
    case ffmpegFailed(exitCode: Int32, message: String)
}

extension ChapterThumbnailGeneratorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Thumbnail extraction requires a safe local media file with a known duration."
        case .noVideoTrack:
            "The selected file has no video track for thumbnails."
        case .invalidRequest:
            "Choose one to five unique thumbnail times inside the media duration."
        case .staleSource:
            "The media file changed while thumbnails were being extracted."
        case .unsafeOutput:
            "FFmpeg did not create a safe, bounded JPEG thumbnail."
        case .ffmpegFailed(let exitCode, let message):
            "FFmpeg could not extract a thumbnail (code \(exitCode)): \(message)"
        }
    }
}

public struct FFmpegChapterThumbnailGenerator<Runner: CommandRunning>: Sendable {
    public static var maximumThumbnailBytes: Int { 4_194_304 }

    private let ffmpegURL: URL
    private let runner: Runner

    public init(ffmpegURL: URL, runner: Runner) {
        self.ffmpegURL = ffmpegURL
        self.runner = runner
    }

    public func generate(
        source: MediaAsset,
        times rawTimes: [MediaTime],
        expectedSourceRevision: ChapterSourceRevision? = nil
    ) async throws -> [ChapterThumbnail] {
        guard let duration = source.duration, duration > .zero else {
            throw ChapterThumbnailGeneratorError.unsupportedSource
        }
        guard source.tracks.contains(where: { $0.kind == .video }) else {
            throw ChapterThumbnailGeneratorError.noVideoTrack
        }
        let times = Array(Set(rawTimes)).sorted()
        guard times.count == rawTimes.count, (1...5).contains(times.count),
            times.allSatisfy({ $0 >= .zero && $0 < duration })
        else {
            throw ChapterThumbnailGeneratorError.invalidRequest
        }
        let before: ChapterSourceRevision
        do {
            before = try ChapterSourceRevision.read(source.sourceURL)
        } catch {
            throw ChapterThumbnailGeneratorError.unsupportedSource
        }
        if let expectedSourceRevision, before != expectedSourceRevision {
            throw ChapterThumbnailGeneratorError.staleSource
        }

        return try await withPrivateDirectory { directory in
            var thumbnails = [ChapterThumbnail]()
            for (index, time) in times.enumerated() {
                try Task.checkCancellation()
                guard (try? ChapterSourceRevision.read(source.sourceURL)) == before else {
                    throw ChapterThumbnailGeneratorError.staleSource
                }
                let outputURL = directory.appendingPathComponent(
                    String(format: "thumbnail-%02d.jpg", index),
                    isDirectory: false
                )
                let result: CommandResult
                do {
                    result = try await runner.run(
                        CommandRequest(
                            executableURL: ffmpegURL,
                            arguments: [
                                "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
                                "-ss", Self.timestamp(time), "-i", source.sourceURL.path,
                                "-map", "0:v:0", "-frames:v", "1",
                                "-vf",
                                "scale=w=min(480\\,iw):h=-2:flags=fast_bilinear",
                                "-an", "-sn", "-dn", "-c:v", "mjpeg", "-q:v", "4",
                                "-f", "image2", "-update", "1",
                                outputURL.path,
                            ],
                            timeout: 120,
                            outputLimit: 1_048_576
                        )
                    )
                } catch CommandRunnerError.cancelled {
                    throw CancellationError()
                }
                try Task.checkCancellation()
                guard result.exitCode == 0 else {
                    let rawMessage =
                        result.standardError.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let message =
                        rawMessage.isEmpty ? "Unknown tool error" : String(rawMessage.prefix(240))
                    throw ChapterThumbnailGeneratorError.ffmpegFailed(
                        exitCode: result.exitCode,
                        message: message
                    )
                }
                guard !result.standardError.wasTruncated, !result.standardOutput.wasTruncated,
                    let values = try? outputURL.resourceValues(forKeys: [
                        .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
                    ]),
                    values.isRegularFile == true,
                    values.isSymbolicLink != true,
                    let size = values.fileSize,
                    (4...Self.maximumThumbnailBytes).contains(size)
                else {
                    throw ChapterThumbnailGeneratorError.unsafeOutput
                }
                let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
                guard (4...Self.maximumThumbnailBytes).contains(data.count),
                    data.starts(with: Self.jpegStart), data.suffix(2) == Self.jpegEnd
                else {
                    throw ChapterThumbnailGeneratorError.unsafeOutput
                }
                thumbnails.append(ChapterThumbnail(time: time, imageData: data))
            }
            guard (try? ChapterSourceRevision.read(source.sourceURL)) == before else {
                throw ChapterThumbnailGeneratorError.staleSource
            }
            try Task.checkCancellation()
            return thumbnails
        }
    }

    private static var jpegStart: Data { Data([0xFF, 0xD8]) }
    private static var jpegEnd: Data { Data([0xFF, 0xD9]) }

    private static func timestamp(_ time: MediaTime) -> String {
        let seconds = time.nanoseconds / 1_000_000_000
        let fraction = time.nanoseconds % 1_000_000_000
        return String(format: "%lld.%09lld", seconds, fraction)
    }

    private func withPrivateDirectory<T: Sendable>(
        _ operation: (URL) async throws -> T
    ) async throws -> T {
        try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-thumbnails",
            operation
        )
    }
}
