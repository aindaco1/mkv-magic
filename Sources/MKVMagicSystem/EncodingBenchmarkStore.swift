import Foundation
import MKVMagicCore

public enum EncodingBenchmarkStoreError: Error, Equatable, Sendable {
    case unsafePath
    case oversizedDocument
    case unexpectedFields
    case unsupportedSchema
    case malformedReport
}

extension EncodingBenchmarkStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafePath: "The encoding-test path is not a safe regular file location."
        case .oversizedDocument: "The encoding-test report is larger than MKV Magic allows."
        case .unexpectedFields: "The encoding-test report contains unexpected fields."
        case .unsupportedSchema: "The encoding-test report uses an unsupported schema."
        case .malformedReport: "The encoding-test report is malformed."
        }
    }
}

public protocol EncodingBenchmarkPersisting: Sendable {
    func load() async throws -> EncodingBenchmarkReport?
    func save(_ report: EncodingBenchmarkReport) async throws
}

public actor JSONEncodingBenchmarkStore: EncodingBenchmarkPersisting {
    public static let maximumDocumentBytes = 65_536

    private let fileURL: URL

    public init(fileURL: URL) throws {
        let standardized = fileURL.standardizedFileURL
        guard standardized.isFileURL,
            standardized.path.hasPrefix("/"),
            !standardized.path.hasSuffix("/"),
            standardized.lastPathComponent == "encoding-benchmark.json"
        else {
            throw EncodingBenchmarkStoreError.unsafePath
        }
        self.fileURL = standardized
    }

    public func load() async throws -> EncodingBenchmarkReport? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try readRegularFile()
        try Self.validateJSON(data)
        let report: EncodingBenchmarkReport
        do {
            report = try decoder.decode(EncodingBenchmarkReport.self, from: data)
        } catch {
            throw EncodingBenchmarkStoreError.malformedReport
        }
        try Self.validate(report)
        return report
    }

    public func save(_ report: EncodingBenchmarkReport) async throws {
        try Self.validate(report)
        try ensureSafeDirectory(fileURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try readRegularFile()
        }
        let data: Data
        do {
            data = try encoder.encode(report)
        } catch {
            throw EncodingBenchmarkStoreError.malformedReport
        }
        guard data.count <= Self.maximumDocumentBytes else {
            throw EncodingBenchmarkStoreError.oversizedDocument
        }
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static func validate(_ report: EncodingBenchmarkReport) throws {
        guard report.schemaVersion == EncodingBenchmarkReport.currentSchemaVersion else {
            throw EncodingBenchmarkStoreError.unsupportedSchema
        }
        let environment = report.environment
        guard
            environment.ffmpegSHA256.range(
                of: "^[a-f0-9]{64}$",
                options: .regularExpression
            ) != nil,
            ["arm64", "x86_64"].contains(environment.architecture),
            (1...1_024).contains(environment.activeProcessorCount),
            report.completedAt.timeIntervalSinceReferenceDate.isFinite,
            (16...8_192).contains(report.sourceWidth),
            (16...8_192).contains(report.sourceHeight),
            (1...240).contains(report.sourceFrameRate),
            (1...3_600).contains(report.sourceFrameCount),
            (1...2).contains(report.attempts.count),
            Set(report.attempts.map(\.preset)).count == report.attempts.count,
            report.attempts.allSatisfy({
                $0.preset == .av1Quality || $0.preset == .hevcCompatibility
            })
        else {
            throw EncodingBenchmarkStoreError.malformedReport
        }
        for attempt in report.attempts {
            guard (1...64).contains(attempt.encoder.utf8.count),
                attempt.encoder.utf8.allSatisfy({ byte in
                    (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
                        || (byte >= 97 && byte <= 122) || byte == 95 || byte == 45
                })
            else {
                throw EncodingBenchmarkStoreError.malformedReport
            }
            switch (attempt.outcome, attempt.metrics) {
            case (.completed, .some(let metrics)):
                guard metrics.elapsedSeconds.isFinite, metrics.elapsedSeconds > 0,
                    metrics.elapsedSeconds <= 300,
                    metrics.framesPerSecond.isFinite, metrics.framesPerSecond > 0,
                    metrics.framesPerSecond <= 100_000,
                    metrics.sourceRealtimeFactor.isFinite,
                    metrics.sourceRealtimeFactor > 0,
                    metrics.sourceRealtimeFactor <= 10_000,
                    metrics.estimated1080pRealtimeFactor.isFinite,
                    metrics.estimated1080pRealtimeFactor > 0,
                    metrics.estimated1080pRealtimeFactor <= 10_000,
                    (1...1_073_741_824).contains(metrics.outputBytes),
                    (1...2_000_000_000).contains(metrics.outputBitrate),
                    metrics.averagePSNR.map({ $0.isFinite && (0...120).contains($0) }) ?? true
                else {
                    throw EncodingBenchmarkStoreError.malformedReport
                }
            case (.failed, .none), (.timedOut, .none):
                break
            default:
                throw EncodingBenchmarkStoreError.malformedReport
            }
        }
        guard
            report.attempts.contains(where: {
                $0.preset == report.recommendedPreset && $0.outcome == .completed
                    && $0.metrics != nil
            }),
            EncodingBenchmarkRecommendation.choose(from: report.attempts)
                == report.recommendedPreset
        else {
            throw EncodingBenchmarkStoreError.malformedReport
        }
    }

    private static func validateJSON(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw EncodingBenchmarkStoreError.malformedReport
        }
        guard let document = object as? [String: Any] else {
            throw EncodingBenchmarkStoreError.malformedReport
        }
        let documentKeys = Set([
            "schemaVersion", "environment", "completedAt", "sourceWidth", "sourceHeight",
            "sourceFrameRate", "sourceFrameCount", "attempts", "recommendedPreset",
        ])
        guard Set(document.keys) == documentKeys,
            let environment = document["environment"] as? [String: Any],
            Set(environment.keys)
                == Set(["ffmpegSHA256", "architecture", "activeProcessorCount"]),
            let attempts = document["attempts"] as? [[String: Any]]
        else {
            if document["schemaVersion"] as? Int
                != EncodingBenchmarkReport.currentSchemaVersion
            {
                throw EncodingBenchmarkStoreError.unsupportedSchema
            }
            throw EncodingBenchmarkStoreError.unexpectedFields
        }
        let attemptRequired = Set(["preset", "encoder", "outcome"])
        let attemptAllowed = attemptRequired.union(["metrics"])
        let metricRequired = Set([
            "elapsedSeconds", "framesPerSecond", "sourceRealtimeFactor",
            "estimated1080pRealtimeFactor", "outputBytes", "outputBitrate",
        ])
        let metricAllowed = metricRequired.union(["averagePSNR"])
        for attempt in attempts {
            let keys = Set(attempt.keys)
            guard attemptRequired.isSubset(of: keys), keys.isSubset(of: attemptAllowed) else {
                throw EncodingBenchmarkStoreError.unexpectedFields
            }
            if let metrics = attempt["metrics"] as? [String: Any] {
                let metricKeys = Set(metrics.keys)
                guard metricRequired.isSubset(of: metricKeys),
                    metricKeys.isSubset(of: metricAllowed)
                else {
                    throw EncodingBenchmarkStoreError.unexpectedFields
                }
            } else if attempt["metrics"] != nil {
                throw EncodingBenchmarkStoreError.malformedReport
            }
        }
    }

    private func readRegularFile() throws -> Data {
        let values = try fileURL.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw EncodingBenchmarkStoreError.unsafePath
        }
        guard values.fileSize ?? 0 <= Self.maximumDocumentBytes else {
            throw EncodingBenchmarkStoreError.oversizedDocument
        }
        return try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    }

    private func ensureSafeDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw EncodingBenchmarkStoreError.unsafePath
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }
}
