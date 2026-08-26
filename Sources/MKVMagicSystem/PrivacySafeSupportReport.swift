import Foundation
import MKVMagicCore

public struct SupportApplicationIdentity: Codable, Hashable, Sendable {
    public let version: String
    public let build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }
}

public struct SupportSystemIdentity: Codable, Hashable, Sendable {
    public let operatingSystem: String
    public let architecture: ToolArchitecture

    public init(operatingSystem: String, architecture: ToolArchitecture) {
        self.operatingSystem = operatingSystem
        self.architecture = architecture
    }
}

public struct SupportToolIdentity: Codable, Hashable, Sendable {
    public let name: BundledTool
    public let version: String
    public let sha256: String

    public init(name: BundledTool, version: String, sha256: String) {
        self.name = name
        self.version = version
        self.sha256 = sha256
    }
}

public enum SupportWorkflowKind: String, Codable, CaseIterable, Hashable, Sendable {
    case segmentTitle
    case trackMetadata
    case trackRemoval
    case englishLibraryCleanup
    case subtitleCleanup
    case externalSubtitleMux
    case embeddedSubtitleCleanup
    case chapterEdit
    case losslessJoin
    case commonFormatJoin
    case fastTrim
    case exactTrim
    case videoTranscode
    case remuxToMKV
    case timedTextSubtitleConversion
    case textSubtitleExtraction
    case attachmentExtraction
    case attachmentRemoval
    case tagExport
    case tagRemoval
    case savedOrUnknown

    init(workflowID: UUID) {
        guard let kind = BuiltInWorkflowCatalog.kind(for: workflowID) else {
            self = .savedOrUnknown
            return
        }
        switch kind {
        case .segmentTitle: self = .segmentTitle
        case .trackMetadata: self = .trackMetadata
        case .trackRemoval: self = .trackRemoval
        case .englishLibraryCleanup: self = .englishLibraryCleanup
        case .subtitleCleanup: self = .subtitleCleanup
        case .externalSubtitleMux: self = .externalSubtitleMux
        case .embeddedSubtitleCleanup: self = .embeddedSubtitleCleanup
        case .chapterEdit: self = .chapterEdit
        case .losslessJoin: self = .losslessJoin
        case .commonFormatJoin: self = .commonFormatJoin
        case .fastTrim: self = .fastTrim
        case .exactTrim: self = .exactTrim
        case .videoTranscode: self = .videoTranscode
        case .remuxToMKV: self = .remuxToMKV
        case .timedTextSubtitleConversion: self = .timedTextSubtitleConversion
        case .textSubtitleExtraction: self = .textSubtitleExtraction
        case .attachmentExtraction: self = .attachmentExtraction
        case .attachmentRemoval: self = .attachmentRemoval
        case .tagExport: self = .tagExport
        case .tagRemoval: self = .tagRemoval
        }
    }
}

public enum SupportElapsedTimeBucket: String, Codable, CaseIterable, Hashable, Sendable {
    case unknown
    case under10Seconds
    case from10SecondsTo1Minute
    case from1To10Minutes
    case from10To60Minutes
    case over1Hour

    init(interval: TimeInterval) {
        guard interval.isFinite, interval >= 0 else {
            self = .unknown
            return
        }
        switch interval {
        case ..<10: self = .under10Seconds
        case ..<60: self = .from10SecondsTo1Minute
        case ..<600: self = .from1To10Minutes
        case ..<3_600: self = .from10To60Minutes
        default: self = .over1Hour
        }
    }
}

public enum SupportFailureCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case sourceChanged
    case toolFailed
    case emptyOutput
    case containerMismatch
    case durationMismatch
    case trackMismatch
    case trackMetadataMismatch
    case chapterMismatch
    case titleMismatch
    case attachmentMismatch
    case segmentIdentityMismatch
    case packetCopyMismatch
    case committedOutputAuditFailed
    case verificationFailed
    case executionFailed

    init?(record: MediaJobRecord) {
        guard record.state == .failed else { return nil }
        let message = record.events.last?.message?.lowercased() ?? ""
        if message.contains("source changed") {
            self = .sourceChanged
        } else if message.contains("tool could not") || message.contains("mkvmerge could not") {
            self = .toolFailed
        } else if message.contains("output was empty") || message.contains("mkv is empty") {
            self = .emptyOutput
        } else if message.contains("container did not match")
            || message.contains("did not create a matroska")
        {
            self = .containerMismatch
        } else if message.contains("duration did not match") {
            self = .durationMismatch
        } else if message.contains("track metadata did not match") {
            self = .trackMetadataMismatch
        } else if message.contains("track structure did not match") {
            self = .trackMismatch
        } else if message.contains("chapter timing or titles did not match") {
            self = .chapterMismatch
        } else if message.contains("segment title did not match") {
            self = .titleMismatch
        } else if message.contains("attachment set did not match") {
            self = .attachmentMismatch
        } else if message.contains("segment identity was invalid") {
            self = .segmentIdentityMismatch
        } else if message.contains("packet-copy audit did not match") {
            self = .packetCopyMismatch
        } else if message.contains("final reopen audit failed") {
            self = .committedOutputAuditFailed
        } else if record.events.dropLast().last?.state == .verifying {
            self = .verificationFailed
        } else {
            self = .executionFailed
        }
    }
}

public struct PrivacySafeSupportJob: Codable, Hashable, Sendable {
    public let caseNumber: Int
    public let workflow: SupportWorkflowKind
    public let result: MediaJobState
    public let lastActiveStage: MediaJobState?
    public let elapsedTime: SupportElapsedTimeBucket
    public let lifecycle: [MediaJobState]
    public let inputs: [MediaJobInputFacts?]
    public let plan: MediaJobPlanFacts?
    public let failureCategory: SupportFailureCategory?

    init(caseNumber: Int, record: MediaJobRecord) {
        self.caseNumber = caseNumber
        workflow = SupportWorkflowKind(workflowID: record.workflowID)
        result = record.state
        lastActiveStage =
            record.state.isTerminal
            ? record.events.dropLast().last?.state
            : record.events.last?.state
        elapsedTime = SupportElapsedTimeBucket(
            interval: record.updatedAt.timeIntervalSince(record.createdAt)
        )
        lifecycle = record.events.map(\.state)
        inputs = record.inputs.map(\.privacySafeFacts)
        plan = record.privacySafePlan
        failureCategory = SupportFailureCategory(record: record)
    }
}

public struct PrivacySafeSupportHistory: Codable, Hashable, Sendable {
    public let totalJobCount: Int
    public let includedJobCount: Int
    public let omittedOlderJobCount: Int
    public let jobs: [PrivacySafeSupportJob]
}

public struct PrivacySafeSupportReport: Codable, Hashable, Sendable {
    public static let currentSchema = "mkv-magic-privacy-safe-support-v2"
    public static let maximumIncludedJobs = 500

    public let schema: String
    public let application: SupportApplicationIdentity
    public let system: SupportSystemIdentity
    public let tools: [SupportToolIdentity]
    public let history: PrivacySafeSupportHistory

    public static func make(
        applicationVersion: String,
        applicationBuild: String,
        operatingSystem: String,
        catalog: ToolCatalog,
        records: [MediaJobRecord]
    ) -> Self {
        let sorted = records.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.updatedAt > $1.updatedAt
        }
        let included = Array(sorted.prefix(maximumIncludedJobs))
        return Self(
            schema: currentSchema,
            application: SupportApplicationIdentity(
                version: safeVersion(applicationVersion),
                build: safeVersion(applicationBuild)
            ),
            system: SupportSystemIdentity(
                operatingSystem: safeVersion(operatingSystem),
                architecture: catalog.architecture
            ),
            tools: catalog.manifest.tools
                .map {
                    SupportToolIdentity(
                        name: $0.name,
                        version: safeVersion($0.version),
                        sha256: safeDigest($0.sha256)
                    )
                }
                .sorted { $0.name.rawValue < $1.name.rawValue },
            history: PrivacySafeSupportHistory(
                totalJobCount: records.count,
                includedJobCount: included.count,
                omittedOlderJobCount: records.count - included.count,
                jobs: included.enumerated().map {
                    PrivacySafeSupportJob(caseNumber: $0.offset + 1, record: $0.element)
                }
            )
        )
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private static func safeVersion(_ rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            value.range(
                of: "^[A-Za-z0-9 ._+()\\-]{1,120}$",
                options: .regularExpression
            ) != nil
        else {
            return "unknown"
        }
        return value
    }

    private static func safeDigest(_ rawValue: String) -> String {
        let digest = rawValue.lowercased()
        return digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) == nil
            ? "unverified"
            : digest
    }
}

public enum PrivacySafeSupportReportWriterError: Error, Equatable, Sendable {
    case unsafeDestination
    case oversizedReport
    case writeFailed
}

extension PrivacySafeSupportReportWriterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafeDestination:
            "Choose a regular local JSON file in an existing folder."
        case .oversizedReport:
            "The privacy-safe report exceeded its one-megabyte safety limit."
        case .writeFailed:
            "MKV Magic could not write the privacy-safe report."
        }
    }
}

public enum PrivacySafeSupportReportWriter {
    public static let maximumDocumentBytes = 1_048_576

    public static func write(
        _ report: PrivacySafeSupportReport,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let destination = destinationURL.standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        guard destination.isFileURL,
            destination.path.hasPrefix("/"),
            destination.pathExtension.lowercased() == "json",
            destination.lastPathComponent.count > 5,
            try isSafeDirectory(parent)
        else {
            throw PrivacySafeSupportReportWriterError.unsafeDestination
        }
        if fileManager.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw PrivacySafeSupportReportWriterError.unsafeDestination
            }
        }
        let data = try report.encoded()
        guard data.count <= maximumDocumentBytes else {
            throw PrivacySafeSupportReportWriterError.oversizedReport
        }
        do {
            try data.write(to: destination, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        } catch {
            throw PrivacySafeSupportReportWriterError.writeFailed
        }
    }

    private static func isSafeDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}
