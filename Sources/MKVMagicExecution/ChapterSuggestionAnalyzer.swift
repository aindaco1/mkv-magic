import Foundation
import MKVMagicCore
import MKVMagicSystem

public enum ChapterSuggestionAnalyzerError: Error, Equatable, Sendable {
    case unsupportedSource
    case noSupportedStreams
    case staleSource
    case truncatedAnalysis
    case ffmpegFailed(exitCode: Int32, message: String)
}

extension ChapterSuggestionAnalyzerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Chapter analysis requires a safe local media file with a known duration."
        case .noSupportedStreams:
            "The selected detectors do not match an available video or audio track."
        case .staleSource:
            "The media file changed while chapter suggestions were being analyzed."
        case .truncatedAnalysis:
            "FFmpeg produced more analysis data than can be reviewed safely."
        case .ffmpegFailed(let exitCode, let message):
            "FFmpeg could not analyze chapter boundaries (code \(exitCode)): \(message)"
        }
    }
}

public struct FFmpegChapterSuggestionAnalyzer<Runner: CommandRunning>: Sendable {
    private let ffmpegURL: URL
    private let runner: Runner

    public init(ffmpegURL: URL, runner: Runner) {
        self.ffmpegURL = ffmpegURL
        self.runner = runner
    }

    public func analyze(
        source: MediaAsset,
        existingChapterStarts: [MediaTime] = [],
        options rawOptions: ChapterSuggestionOptions = ChapterSuggestionOptions()
    ) async throws -> [ChapterSuggestion] {
        let options = try rawOptions.validated()
        guard let duration = source.duration, duration > .zero else {
            throw ChapterSuggestionAnalyzerError.unsupportedSource
        }
        let before: ChapterSourceRevision
        do {
            before = try ChapterSourceRevision.read(source.sourceURL)
        } catch {
            throw ChapterSuggestionAnalyzerError.unsupportedSource
        }

        let hasVideo = source.tracks.contains { $0.kind == .video }
        let hasAudio = source.tracks.contains { $0.kind == .audio }
        let detectsScene = options.detectsSceneChanges && hasVideo
        let detectsBlack = options.detectsBlackFrames && hasVideo
        let detectsSilence = options.detectsSilence && hasAudio
        guard detectsScene || detectsBlack || detectsSilence else {
            throw ChapterSuggestionAnalyzerError.noSupportedStreams
        }

        let graph = Self.filterGraph(
            options: options,
            detectsScene: detectsScene,
            detectsBlack: detectsBlack,
            detectsSilence: detectsSilence
        )
        var arguments = [
            "-hide_banner", "-nostdin", "-nostats", "-loglevel", "info",
            "-i", source.sourceURL.path,
            "-filter_complex", graph.filter,
        ]
        for output in graph.outputs {
            arguments += ["-map", "[\(output)]"]
        }
        arguments += ["-f", "null", "-"]

        let timeout = max(120, min(21_600, duration.seconds * 10))
        let result = try await runner.run(
            CommandRequest(
                executableURL: ffmpegURL,
                arguments: arguments,
                timeout: timeout,
                outputLimit: 16_777_216
            )
        )
        guard result.exitCode == 0 else {
            let rawMessage =
                result.standardError.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = rawMessage.isEmpty ? "Unknown tool error" : String(rawMessage.prefix(240))
            throw ChapterSuggestionAnalyzerError.ffmpegFailed(
                exitCode: result.exitCode,
                message: message
            )
        }
        guard !result.standardError.wasTruncated, !result.standardOutput.wasTruncated else {
            throw ChapterSuggestionAnalyzerError.truncatedAnalysis
        }
        guard (try? ChapterSourceRevision.read(source.sourceURL)) == before else {
            throw ChapterSuggestionAnalyzerError.staleSource
        }

        let detections = Self.parseDetections(result.standardError.text)
        return try ChapterSuggestionConsolidator.consolidate(
            detections,
            duration: duration,
            existingChapterStarts: existingChapterStarts,
            options: options
        )
    }

    private static func filterGraph(
        options: ChapterSuggestionOptions,
        detectsScene: Bool,
        detectsBlack: Bool,
        detectsSilence: Bool
    ) -> (filter: String, outputs: [String]) {
        let sceneThreshold = decimal(options.sceneThreshold)
        let blackDuration = decimal(options.blackMinimumDuration.seconds)
        let blackThreshold = decimal(options.blackPictureThreshold)
        let silenceNoise = decimal(options.silenceNoiseDecibels)
        let silenceDuration = decimal(options.silenceMinimumDuration.seconds)
        var filters = [String]()
        var outputs = [String]()
        let videoInput =
            "[0:v:0]fps=10,scale=w=min(640\\,iw):h=-2:flags=fast_bilinear"

        if detectsScene && detectsBlack {
            filters.append("\(videoInput),split=2[scenein][blackin]")
            filters.append(
                "[scenein]select=gt(scene\\,\(sceneThreshold)),showinfo[sceneout]")
            filters.append(
                "[blackin]blackdetect=d=\(blackDuration):pic_th=\(blackThreshold)[blackout]")
            outputs += ["sceneout", "blackout"]
        } else if detectsScene {
            filters.append(
                "\(videoInput),select=gt(scene\\,\(sceneThreshold)),showinfo[sceneout]")
            outputs.append("sceneout")
        } else if detectsBlack {
            filters.append(
                "\(videoInput),blackdetect=d=\(blackDuration):pic_th=\(blackThreshold)[blackout]")
            outputs.append("blackout")
        }
        if detectsSilence {
            filters.append(
                "[0:a:0]silencedetect=n=\(silenceNoise)dB:d=\(silenceDuration)[silenceout]")
            outputs.append("silenceout")
        }
        return (filters.joined(separator: ";"), outputs)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func parseDetections(_ text: String) -> [ChapterSuggestionDetection] {
        var result = [ChapterSuggestionDetection]()
        for line in text.split(whereSeparator: \Character.isNewline) {
            let value = String(line)
            if value.contains("showinfo"), let seconds = number(after: "pts_time:", in: value),
                let time = MediaTime(seconds: seconds)
            {
                result.append(ChapterSuggestionDetection(time: time, signal: .sceneChange))
            }
            if value.contains("blackdetect"),
                let seconds = number(after: "black_end:", in: value),
                let time = MediaTime(seconds: seconds)
            {
                result.append(ChapterSuggestionDetection(time: time, signal: .blackFrame))
            }
            if value.contains("silencedetect"),
                let seconds = number(after: "silence_end:", in: value),
                let time = MediaTime(seconds: seconds)
            {
                result.append(ChapterSuggestionDetection(time: time, signal: .silence))
            }
        }
        return result
    }

    private static func number(after marker: String, in line: String) -> Double? {
        guard let markerRange = line.range(of: marker) else { return nil }
        let suffix = line[markerRange.upperBound...].drop(while: \Character.isWhitespace)
        let token = suffix.prefix { character in
            character.isNumber || character == "." || character == "-" || character == "+"
                || character == "e" || character == "E"
        }
        guard !token.isEmpty, let value = Double(token), value.isFinite else { return nil }
        return value
    }
}
