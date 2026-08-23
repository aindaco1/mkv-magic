import Foundation
import MKVMagicCore
import MKVMagicSystem

public enum FFmpegCapabilityStatus: String, Codable, Hashable, Sendable {
    case unavailable
    case declared
    case verified
}

public enum FFmpegCapabilityProbeError: Error, Equatable, Sendable {
    case toolFailed(arguments: [String], exitCode: Int32)
    case truncatedListing
}

extension FFmpegCapabilityProbeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .toolFailed:
            "Bundled FFmpeg could not report its encoding capabilities."
        case .truncatedListing:
            "Bundled FFmpeg returned an incomplete capability listing."
        }
    }
}

public struct FFmpegEncodingCapabilities: Equatable, Sendable {
    public static let unavailable = FFmpegEncodingCapabilities(
        softwareAV1: .unavailable,
        softwareAV1Encoder: nil,
        hevc10VideoToolbox: .unavailable,
        h264VideoToolbox: .unavailable,
        proRes: .unavailable,
        proResEncoder: nil,
        aac: .unavailable,
        aacEncoder: nil,
        availableFilters: []
    )

    public static let requiredJoinFilters: Set<String> = [
        "aformat", "anullsrc", "aresample", "asetpts", "atrim", "channelmap", "concat",
        "format", "pad", "scale", "setpts", "setsar",
    ]

    public let softwareAV1: FFmpegCapabilityStatus
    public let softwareAV1Encoder: String?
    public let hevc10VideoToolbox: FFmpegCapabilityStatus
    public let h264VideoToolbox: FFmpegCapabilityStatus
    public let proRes: FFmpegCapabilityStatus
    public let proResEncoder: String?
    public let aac: FFmpegCapabilityStatus
    public let aacEncoder: String?
    public let availableFilters: Set<String>

    public init(
        softwareAV1: FFmpegCapabilityStatus,
        softwareAV1Encoder: String?,
        hevc10VideoToolbox: FFmpegCapabilityStatus,
        h264VideoToolbox: FFmpegCapabilityStatus,
        proRes: FFmpegCapabilityStatus,
        proResEncoder: String?,
        aac: FFmpegCapabilityStatus,
        aacEncoder: String?,
        availableFilters: Set<String>
    ) {
        self.softwareAV1 = softwareAV1
        self.softwareAV1Encoder = softwareAV1Encoder
        self.hevc10VideoToolbox = hevc10VideoToolbox
        self.h264VideoToolbox = h264VideoToolbox
        self.proRes = proRes
        self.proResEncoder = proResEncoder
        self.aac = aac
        self.aacEncoder = aacEncoder
        self.availableFilters = availableFilters
    }

    public var missingJoinFilters: [String] {
        Self.requiredJoinFilters.subtracting(availableFilters).sorted()
    }

    public var availableVideoPresets: [VideoPreset] {
        var presets = [VideoPreset]()
        if softwareAV1 == .verified { presets.append(.av1Quality) }
        if hevc10VideoToolbox == .verified { presets.append(.hevcCompatibility) }
        if h264VideoToolbox == .verified { presets.append(.h264Compatibility) }
        if proRes == .verified { presets.append(.proRes) }
        return presets
    }

    public var recommendedVideoPreset: VideoPreset? {
        availableVideoPresets.first
    }

    public func verifiedEncoder(for preset: VideoPreset) -> String? {
        switch preset {
        case .av1Quality:
            softwareAV1 == .verified ? softwareAV1Encoder : nil
        case .hevcCompatibility:
            hevc10VideoToolbox == .verified ? "hevc_videotoolbox" : nil
        case .h264Compatibility:
            h264VideoToolbox == .verified ? "h264_videotoolbox" : nil
        case .proRes:
            proRes == .verified ? proResEncoder : nil
        }
    }
}

public struct FFmpegCapabilityProbe<Runner: CommandRunning>: Sendable {
    private let ffmpegURL: URL
    private let runner: Runner

    public init(ffmpegURL: URL, runner: Runner) {
        self.ffmpegURL = ffmpegURL
        self.runner = runner
    }

    public func probe() async throws -> FFmpegEncodingCapabilities {
        let encoderNames = try await listing(arguments: ["-hide_banner", "-encoders"])
        let filterNames = try await listing(arguments: ["-hide_banner", "-filters"])
        return try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-capability"
        ) { directory in
            let yuv420 = directory.appendingPathComponent("yuv420p.raw")
            let p010 = directory.appendingPathComponent("p010le.raw")
            let yuv422 = directory.appendingPathComponent("yuv422p10le.raw")
            let audio = directory.appendingPathComponent("s16le.raw")
            try Data(repeating: 0, count: 6_144).write(to: yuv420, options: .atomic)
            try Data(repeating: 0, count: 12_288).write(to: p010, options: .atomic)
            try Data(repeating: 0, count: 16_384).write(to: yuv422, options: .atomic)
            try Data(repeating: 0, count: 9_600).write(to: audio, options: .atomic)

            let av1Encoder = Self.firstAvailable(
                ["libsvtav1", "libaom-av1", "librav1e", "av1"],
                in: encoderNames
            )
            let proResEncoder = Self.firstAvailable(
                ["prores_ks", "prores_videotoolbox", "prores_aw", "prores"],
                in: encoderNames
            )
            let aacEncoder = Self.firstAvailable(["aac_at", "aac"], in: encoderNames)

            let av1 = try await status(name: av1Encoder) { encoder in
                try await smokeVideo(
                    inputURL: p010,
                    pixelFormat: "p010le",
                    encoder: encoder,
                    outputArguments: ["-pix_fmt", "yuv420p10le"]
                )
            }
            let hevc = try await status(
                name: encoderNames.contains("hevc_videotoolbox")
                    ? "hevc_videotoolbox" : nil
            ) { encoder in
                try await smokeVideo(
                    inputURL: p010,
                    pixelFormat: "p010le",
                    encoder: encoder,
                    outputArguments: ["-profile:v", "main10"]
                )
            }
            let h264 = try await status(
                name: encoderNames.contains("h264_videotoolbox")
                    ? "h264_videotoolbox" : nil
            ) { encoder in
                try await smokeVideo(
                    inputURL: yuv420,
                    pixelFormat: "yuv420p",
                    encoder: encoder,
                    outputArguments: []
                )
            }
            let proRes = try await status(name: proResEncoder) { encoder in
                try await smokeVideo(
                    inputURL: yuv422,
                    pixelFormat: "yuv422p10le",
                    encoder: encoder,
                    outputArguments: ["-profile:v", "3"]
                )
            }
            let aac = try await status(name: aacEncoder) { encoder in
                try await smokeAudio(inputURL: audio, encoder: encoder)
            }
            return FFmpegEncodingCapabilities(
                softwareAV1: av1,
                softwareAV1Encoder: av1Encoder,
                hevc10VideoToolbox: hevc,
                h264VideoToolbox: h264,
                proRes: proRes,
                proResEncoder: proResEncoder,
                aac: aac,
                aacEncoder: aacEncoder,
                availableFilters: filterNames
            )
        }
    }

    private func listing(arguments: [String]) async throws -> Set<String> {
        let result = try await runner.run(
            CommandRequest(
                executableURL: ffmpegURL,
                arguments: arguments,
                timeout: 30,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0 else {
            throw FFmpegCapabilityProbeError.toolFailed(
                arguments: arguments,
                exitCode: result.exitCode
            )
        }
        guard !result.standardOutput.wasTruncated, !result.standardError.wasTruncated else {
            throw FFmpegCapabilityProbeError.truncatedListing
        }
        return Self.tableNames(
            result.standardOutput.text + "\n" + result.standardError.text
        )
    }

    private func status(
        name: String?,
        smoke: (String) async throws -> Bool
    ) async throws -> FFmpegCapabilityStatus {
        guard let name else { return .unavailable }
        do {
            return try await smoke(name) ? .verified : .declared
        } catch let error as CommandRunnerError where error == .cancelled {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .declared
        }
    }

    private func smokeVideo(
        inputURL: URL,
        pixelFormat: String,
        encoder: String,
        outputArguments: [String]
    ) async throws -> Bool {
        try await smoke(
            [
                "-hide_banner", "-loglevel", "error",
                "-f", "rawvideo", "-pixel_format", pixelFormat,
                "-video_size", "64x64", "-framerate", "1", "-i", inputURL.path,
                "-frames:v", "1", "-c:v", encoder,
            ] + outputArguments + ["-f", "null", "-"])
    }

    private func smokeAudio(inputURL: URL, encoder: String) async throws -> Bool {
        try await smoke([
            "-hide_banner", "-loglevel", "error",
            "-f", "s16le", "-ar", "48000", "-ac", "2", "-i", inputURL.path,
            "-frames:a", "1", "-c:a", encoder, "-f", "null", "-",
        ])
    }

    private func smoke(_ arguments: [String]) async throws -> Bool {
        let result = try await runner.run(
            CommandRequest(
                executableURL: ffmpegURL,
                arguments: arguments,
                timeout: 30,
                outputLimit: 65_536
            )
        )
        return result.exitCode == 0 && !result.standardOutput.wasTruncated
            && !result.standardError.wasTruncated
    }

    private static func firstAvailable(_ preferred: [String], in names: Set<String>) -> String? {
        preferred.first(where: names.contains)
    }

    private static func tableNames(_ text: String) -> Set<String> {
        Set(
            text.split(whereSeparator: \.isNewline).compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 2 else { return nil }
                let name = fields[1]
                guard (1...64).contains(name.utf8.count),
                    name.utf8.allSatisfy({ byte in
                        (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
                            || (byte >= 97 && byte <= 122) || byte == 95 || byte == 45
                    })
                else {
                    return nil
                }
                return String(name)
            }
        )
    }
}
