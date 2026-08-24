import Foundation
import MKVMagicCore
import MKVMagicPlanning
import MKVMagicSystem

public enum FFmpegEncodingBenchmarkError: Error, Equatable, Sendable {
    case unsafeTool
    case noBenchmarkableEncoder
    case noSuccessfulEncoder
    case invalidEnvironment
    case fixtureCreationFailed
}

extension FFmpegEncodingBenchmarkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafeTool: "The bundled FFmpeg path is unsafe."
        case .noBenchmarkableEncoder:
            "No verified AV1 or HEVC encoder is available for the local encoding test."
        case .noSuccessfulEncoder:
            "Neither available encoder completed the local encoding test."
        case .invalidEnvironment: "The encoding-test runtime identity is invalid."
        case .fixtureCreationFailed: "MKV Magic could not create its private local test pattern."
        }
    }
}

public struct FFmpegEncodingBenchmark<Runner: CommandRunning>: Sendable {
    public static var sourceWidth: Int { 640 }
    public static var sourceHeight: Int { 360 }
    public static var sourceFrameRate: Int { 24 }
    public static var sourceFrameCount: Int { 72 }

    private let ffmpegURL: URL
    private let runner: Runner

    public init(ffmpegURL: URL, runner: Runner) {
        self.ffmpegURL = ffmpegURL.standardizedFileURL
        self.runner = runner
    }

    public func run(
        capabilities: FFmpegEncodingCapabilities,
        environment: EncodingBenchmarkEnvironment
    ) async throws -> EncodingBenchmarkReport {
        guard ffmpegURL.isFileURL, ffmpegURL.path.hasPrefix("/"),
            !ffmpegURL.path.contains("\0")
        else {
            throw FFmpegEncodingBenchmarkError.unsafeTool
        }
        guard Self.valid(environment: environment) else {
            throw FFmpegEncodingBenchmarkError.invalidEnvironment
        }
        let candidates = Self.candidates(capabilities: capabilities)
        guard !candidates.isEmpty else {
            throw FFmpegEncodingBenchmarkError.noBenchmarkableEncoder
        }

        return try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-encoding-test"
        ) { directory in
            let sourceURL = directory.appendingPathComponent("synthetic-p010le.raw")
            do {
                try Self.writeFixture(to: sourceURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FFmpegEncodingBenchmarkError.fixtureCreationFailed
            }

            var attempts = [EncodingBenchmarkAttempt]()
            attempts.reserveCapacity(candidates.count)
            for candidate in candidates {
                try Task.checkCancellation()
                attempts.append(
                    try await attempt(
                        candidate,
                        sourceURL: sourceURL,
                        directory: directory,
                        canMeasurePSNR: capabilities.availableFilters.contains("psnr")
                    )
                )
            }
            guard let recommendation = EncodingBenchmarkRecommendation.choose(from: attempts)
            else {
                throw FFmpegEncodingBenchmarkError.noSuccessfulEncoder
            }
            return EncodingBenchmarkReport(
                environment: environment,
                completedAt: Date(),
                sourceWidth: Self.sourceWidth,
                sourceHeight: Self.sourceHeight,
                sourceFrameRate: Self.sourceFrameRate,
                sourceFrameCount: Self.sourceFrameCount,
                attempts: attempts,
                recommendedPreset: recommendation
            )
        }
    }

    private func attempt(
        _ candidate: Candidate,
        sourceURL: URL,
        directory: URL,
        canMeasurePSNR: Bool
    ) async throws -> EncodingBenchmarkAttempt {
        let outputURL = directory.appendingPathComponent("\(candidate.preset.rawValue).mkv")
        let request: CommandRequest
        do {
            request = try encodeRequest(
                candidate,
                sourceURL: sourceURL,
                outputURL: outputURL
            )
        } catch {
            return failedAttempt(candidate, outcome: .failed)
        }

        let result: CommandResult
        do {
            result = try await runner.run(request)
        } catch let error as CommandRunnerError where error == .timedOut {
            return failedAttempt(candidate, outcome: .timedOut)
        } catch let error as CommandRunnerError where error == .cancelled {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failedAttempt(candidate, outcome: .failed)
        }
        guard result.exitCode == 0, !result.standardOutput.wasTruncated,
            !result.standardError.wasTruncated,
            result.duration.isFinite, result.duration > 0,
            let outputBytes = try? Self.validatedOutputSize(outputURL)
        else {
            return failedAttempt(candidate, outcome: .failed)
        }

        let framesPerSecond = Double(Self.sourceFrameCount) / result.duration
        let sourceRealtimeFactor = framesPerSecond / Double(Self.sourceFrameRate)
        let sourcePixels = Double(Self.sourceWidth * Self.sourceHeight)
        let fullHDPixels = Double(1_920 * 1_080)
        let estimated1080pRealtimeFactor = sourceRealtimeFactor * sourcePixels / fullHDPixels
        let sourceDuration = Double(Self.sourceFrameCount) / Double(Self.sourceFrameRate)
        let bitrate = Int64((Double(outputBytes) * 8 / sourceDuration).rounded())
        let psnr: Double?
        if canMeasurePSNR {
            psnr = try await averagePSNR(
                preset: candidate.preset,
                sourceURL: sourceURL,
                outputURL: outputURL
            )
        } else {
            psnr = nil
        }
        return EncodingBenchmarkAttempt(
            preset: candidate.preset,
            encoder: candidate.encoder,
            outcome: .completed,
            metrics: EncodingBenchmarkMetrics(
                elapsedSeconds: result.duration,
                framesPerSecond: framesPerSecond,
                sourceRealtimeFactor: sourceRealtimeFactor,
                estimated1080pRealtimeFactor: estimated1080pRealtimeFactor,
                outputBytes: outputBytes,
                outputBitrate: bitrate,
                averagePSNR: psnr
            )
        )
    }

    private func encodeRequest(
        _ candidate: Candidate,
        sourceURL: URL,
        outputURL: URL
    ) throws -> CommandRequest {
        var arguments = [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-n",
            "-f", "rawvideo", "-pixel_format", "p010le",
            "-video_size", "\(Self.sourceWidth)x\(Self.sourceHeight)",
            "-framerate", String(Self.sourceFrameRate), "-i", sourceURL.path,
            "-frames:v", String(Self.sourceFrameCount), "-an",
        ]
        arguments.append(
            contentsOf: try FFmpegSDRVideoEncoderArguments().make(
                outputIndex: 0,
                encoder: candidate.encoder,
                preset: candidate.preset,
                rateControl: candidate.rateControl
            )
        )
        arguments.append(contentsOf: ["-f", "matroska", outputURL.path])
        return CommandRequest(
            executableURL: ffmpegURL,
            arguments: arguments,
            timeout: 90,
            outputLimit: 262_144
        )
    }

    private func averagePSNR(
        preset: VideoPreset,
        sourceURL: URL,
        outputURL: URL
    ) async throws -> Double? {
        var arguments = [
            "-hide_banner", "-nostdin", "-loglevel", "info",
            "-f", "rawvideo", "-pixel_format", "p010le",
            "-video_size", "\(Self.sourceWidth)x\(Self.sourceHeight)",
            "-framerate", String(Self.sourceFrameRate), "-i", sourceURL.path,
        ]
        if preset == .av1Quality {
            arguments.append(contentsOf: ["-c:v", "libdav1d"])
        }
        arguments.append(contentsOf: [
            "-i", outputURL.path,
            "-filter_complex", "[0:v:0][1:v:0]psnr",
            "-frames:v", String(Self.sourceFrameCount),
            "-f", "null", "-",
        ])
        let result: CommandResult
        do {
            result = try await runner.run(
                CommandRequest(
                    executableURL: ffmpegURL,
                    arguments: arguments,
                    timeout: 60,
                    outputLimit: 262_144
                )
            )
        } catch let error as CommandRunnerError where error == .cancelled {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        guard result.exitCode == 0, !result.standardOutput.wasTruncated,
            !result.standardError.wasTruncated
        else {
            return nil
        }
        return Self.parseAveragePSNR(result.standardError.text)
    }

    private func failedAttempt(
        _ candidate: Candidate,
        outcome: EncodingBenchmarkOutcome
    ) -> EncodingBenchmarkAttempt {
        EncodingBenchmarkAttempt(
            preset: candidate.preset,
            encoder: candidate.encoder,
            outcome: outcome,
            metrics: nil
        )
    }

    private static func candidates(
        capabilities: FFmpegEncodingCapabilities
    ) -> [Candidate] {
        var result = [Candidate]()
        if let encoder = capabilities.verifiedEncoder(for: .av1Quality) {
            result.append(
                Candidate(
                    preset: .av1Quality,
                    encoder: encoder,
                    rateControl: .constantQuality(30)
                )
            )
        }
        if let encoder = capabilities.verifiedEncoder(for: .hevcCompatibility) {
            result.append(
                Candidate(
                    preset: .hevcCompatibility,
                    encoder: encoder,
                    rateControl: .averageBitrate(1_000_000)
                )
            )
        }
        return result
    }

    private static func valid(environment: EncodingBenchmarkEnvironment) -> Bool {
        environment.ffmpegSHA256.range(
            of: "^[a-f0-9]{64}$",
            options: .regularExpression
        ) != nil
            && ["arm64", "x86_64"].contains(environment.architecture)
            && (1...1_024).contains(environment.activeProcessorCount)
    }

    private static func validatedOutputSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
            let size = values.fileSize, (1...268_435_456).contains(size)
        else {
            throw FFmpegEncodingBenchmarkError.fixtureCreationFailed
        }
        return Int64(size)
    }

    private static func parseAveragePSNR(_ text: String) -> Double? {
        guard let marker = text.range(of: "average:", options: .backwards) else { return nil }
        let suffix = text[marker.upperBound...]
        let token = suffix.prefix { character in
            character.isNumber || character == "." || character == "-"
                || character == "+" || character == "e" || character == "E"
        }
        guard !token.isEmpty, let value = Double(token), value.isFinite,
            (0...120).contains(value)
        else {
            return nil
        }
        return value
    }

    private static func writeFixture(to url: URL) throws {
        guard
            FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        else {
            throw FFmpegEncodingBenchmarkError.fixtureCreationFailed
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let lumaSampleCount = sourceWidth * sourceHeight
        let sampleCount = lumaSampleCount + lumaSampleCount / 2
        let cycleLength = 12
        var cycle = [Data]()
        cycle.reserveCapacity(cycleLength)
        for frameIndex in 0..<cycleLength {
            try Task.checkCancellation()
            var frame = Data(count: sampleCount * MemoryLayout<UInt16>.size)
            frame.withUnsafeMutableBytes { rawBuffer in
                let samples = rawBuffer.bindMemory(to: UInt16.self)
                for y in 0..<sourceHeight {
                    for x in 0..<sourceWidth {
                        let ramp = (x * 5 + y * 3 + frameIndex * 11) % 877
                        samples[y * sourceWidth + x] = UInt16((64 + ramp) << 6).littleEndian
                    }
                }
                var index = lumaSampleCount
                for y in 0..<(sourceHeight / 2) {
                    for x in 0..<(sourceWidth / 2) {
                        let wave = (x * 7 + y * 9 + frameIndex * 13) % 385
                        let u = 320 + wave
                        let v = 704 - wave
                        samples[index] = UInt16(u << 6).littleEndian
                        samples[index + 1] = UInt16(v << 6).littleEndian
                        index += 2
                    }
                }
            }
            cycle.append(frame)
        }
        for frameIndex in 0..<sourceFrameCount {
            try Task.checkCancellation()
            try handle.write(contentsOf: cycle[frameIndex % cycleLength])
        }
        try handle.synchronize()
    }

    private struct Candidate: Sendable {
        let preset: VideoPreset
        let encoder: String
        let rateControl: JoinVideoRateControl
    }
}
