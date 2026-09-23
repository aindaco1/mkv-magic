import Foundation
import MKVMagicCore

/// A closed vocabulary: no messages, paths, arguments, or document content can
/// enter the retained log. Add context here, not free-form string dictionaries.
public enum DiagnosticAction: String, Codable, Sendable {
    case application, importFiles, remuxWithSubtitle, verifyAndRun, addToQueue, automaticQueue
}

public enum DiagnosticStage: String, Codable, Sendable {
    case requested, selection, subtitlePreview, review, destination, queueAdmission
    case execution, tool, verifying, committing, finished
}

public enum DiagnosticOutcome: String, Codable, Sendable {
    case started, succeeded, failed, blocked, cancelled
}

public enum DiagnosticFailure: String, Codable, Sendable {
    case selectionChanged, missingReview, sourceUnavailable, sourceChanged
    case destinationUnavailable, bookmarkUnavailable, staleBookmark, queueUnavailable
    case queueUnsafePath, queueOversized, queueFull, queueInvalidSchema, queueInvalidData,
        queueJobMissing
    case toolUnavailable, toolLaunchFailed, toolTimedOut, toolExited, invalidData
    case permissionDenied, diskFull, readOnlyFilesystem, cancelled, unknown

    public static func classify(_ error: Error) -> Self {
        classify(error, remainingDepth: 3)
    }

    private static func classify(_ error: Error, remainingDepth: Int) -> Self {
        if let error = error as? DiagnosticPreparationError { return error.failure }
        if error is CancellationError { return .cancelled }
        if let error = error as? CommandRunnerError {
            return switch error {
            case .cancelled: .cancelled
            case .timedOut: .toolTimedOut
            case .unsafeExecutable: .toolUnavailable
            case .launchFailed: .toolLaunchFailed
            case .invalidTimeout, .invalidOutputLimit: .invalidData
            }
        }
        if let error = error as? SecurityScopedBookmarkError {
            return switch error {
            case .stale: .staleBookmark
            case .changedSinceReview: .sourceChanged
            case .unsafeURL, .wrongResourceType: .bookmarkUnavailable
            }
        }
        if let error = error as? JobQueueStoreError {
            return switch error {
            case .unsafePath: .queueUnsafePath
            case .oversizedDocument: .queueOversized
            case .tooManyJobs: .queueFull
            case .unsupportedSchema: .queueInvalidSchema
            case .unexpectedFields, .malformedQueue, .duplicateJob: .queueInvalidData
            case .jobNotFound: .queueJobMissing
            }
        }
        if error is MediaFileRevisionReaderError { return .sourceUnavailable }
        if error is DecodingError { return .invalidData }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return .sourceUnavailable
            case NSUserCancelledError: return .cancelled
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .permissionDenied
            case NSFileWriteOutOfSpaceError: return .diskFull
            case NSFileWriteVolumeReadOnlyError: return .readOnlyFilesystem
            default: break
            }
        }
        if ns.domain == NSPOSIXErrorDomain {
            switch ns.code {
            case 1, 13: return .permissionDenied
            case 28: return .diskFull
            case 30: return .readOnlyFilesystem
            default: break
            }
        }
        if remainingDepth > 0, let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            return classify(underlying, remainingDepth: remainingDepth - 1)
        }
        return .unknown
    }
}

/// Retain the concrete boundary when Foundation gives a generic bookmark error.
/// The underlying error is for local UI only, never serialized into diagnostics.
public struct DiagnosticPreparationError: Error, LocalizedError {
    public let stage: DiagnosticStage
    public let failure: DiagnosticFailure
    private let underlying: Error

    public static func perform<Value>(
        stage: DiagnosticStage, fallback: DiagnosticFailure,
        _ operation: () throws -> Value
    ) throws -> Value {
        do { return try operation() } catch {
            let classified = DiagnosticFailure.classify(error)
            throw Self(
                stage: stage, failure: classified == .unknown ? fallback : classified,
                underlying: error)
        }
    }

    public var errorDescription: String? { underlying.localizedDescription }
}

public struct DiagnosticEvent: Codable, Hashable, Sendable {
    public let schema: String
    public let sessionID: UUID
    public let attemptID: UUID
    public let version: String
    public let build: String
    public let action: DiagnosticAction
    public let stage: DiagnosticStage
    public let outcome: DiagnosticOutcome
    public let failure: DiagnosticFailure?
    public let tool: BundledTool?
    public let exitCode: Int32?
    public let operatingSystem: String?
    public let architecture: ToolArchitecture?
    public let elapsedMilliseconds: Int?

    public init(
        sessionID: UUID, attemptID: UUID, version: String, build: String,
        action: DiagnosticAction, stage: DiagnosticStage, outcome: DiagnosticOutcome,
        failure: DiagnosticFailure? = nil, tool: BundledTool? = nil, exitCode: Int32? = nil,
        operatingSystem: String? = nil, architecture: ToolArchitecture? = nil,
        elapsedMilliseconds: Int? = nil
    ) {
        schema = "mkv-magic-diagnostic-event-v1"
        self.sessionID = sessionID
        self.attemptID = attemptID
        self.version = Self.safeVersion(version)
        self.build = Self.safeVersion(build)
        self.action = action
        self.stage = stage
        self.outcome = outcome
        self.failure = failure
        self.tool = tool
        self.exitCode = exitCode.map { min(255, max(-1, $0)) }
        self.operatingSystem = operatingSystem.map(Self.safeOperatingSystem)
        self.architecture = architecture
        self.elapsedMilliseconds = elapsedMilliseconds.map { min(604_800_000, max(0, $0)) }
    }

    static func safeOperatingSystem(_ value: String) -> String {
        value.range(of: "^[0-9]{1,3}(\\.[0-9]{1,3}){1,2}$", options: .regularExpression) == nil
            ? "unknown" : value
    }

    static func safeVersion(_ value: String) -> String {
        value.range(of: "^[0-9][0-9A-Za-z.+-]{0,63}$", options: .regularExpression) != nil
            ? value : "unknown"
    }

    static func decodeLine(_ data: Data) -> Self? {
        guard data.count <= 1_024,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys).isSubset(of: [
                "schema", "sessionID", "attemptID", "version", "build", "action", "stage",
                "outcome", "failure", "tool", "exitCode", "operatingSystem", "architecture",
                "elapsedMilliseconds",
            ]),
            let event = try? JSONDecoder().decode(Self.self, from: data),
            event.schema == "mkv-magic-diagnostic-event-v1",
            event.version == "unknown" || safeVersion(event.version) == event.version,
            event.build == "unknown" || safeVersion(event.build) == event.build,
            event.exitCode.map({ (-1...255).contains($0) }) ?? true,
            event.elapsedMilliseconds.map({ (0...604_800_000).contains($0) }) ?? true,
            event.operatingSystem.map({ $0 == "unknown" || safeOperatingSystem($0) == $0 }) ?? true
        else { return nil }
        return event
    }
}

public struct DiagnosticSnapshot: Codable, Hashable, Sendable {
    public let events: [DiagnosticEvent]
    public let droppedEventCount: Int
    public let skippedInvalidRecordCount: Int
    public let omittedEventCount: Int
    public let storageUnavailable: Bool
}

/// Task-local correlation follows child tasks without a mutable global logger.
public struct DiagnosticContext: Sendable {
    @TaskLocal public static var current: DiagnosticContext?
    public let journal: DiagnosticJournal
    public let sessionID: UUID
    public let attemptID: UUID
    public let version: String
    public let build: String
    public let action: DiagnosticAction
    private let startedAt: TimeInterval
    private let operatingSystem: String

    public init(
        journal: DiagnosticJournal, sessionID: UUID, attemptID: UUID = UUID(),
        version: String, build: String, action: DiagnosticAction
    ) {
        self.journal = journal
        self.sessionID = sessionID
        self.attemptID = attemptID
        self.version = version
        self.build = build
        self.action = action
        startedAt = ProcessInfo.processInfo.systemUptime
        let os = ProcessInfo.processInfo.operatingSystemVersion
        operatingSystem = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    public func record(
        _ stage: DiagnosticStage, _ outcome: DiagnosticOutcome,
        failure: DiagnosticFailure? = nil, tool: BundledTool? = nil,
        exitCode: Int32? = nil
    ) async {
        await journal.record(
            DiagnosticEvent(
                sessionID: sessionID, attemptID: attemptID, version: version, build: build,
                action: action, stage: stage, outcome: outcome, failure: failure,
                tool: tool, exitCode: exitCode, operatingSystem: operatingSystem,
                architecture: ToolArchitecture.current,
                elapsedMilliseconds: Int(
                    min(
                        604_800_000,
                        max(
                            0,
                            (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)))
            ))
    }

    static func observingTool<Result: Sendable>(
        _ request: CommandRequest,
        operation: () async throws -> Result,
        exitCode: (Result) -> Int32
    ) async throws -> Result {
        let context = current
        let tool = BundledTool(rawValue: request.executableURL.lastPathComponent)
        await context?.record(.tool, .started, tool: tool)
        do {
            let result = try await operation()
            let code = exitCode(result)
            // mkvmerge code 1 is a successful operation with warnings.
            let succeeded = code == 0 || (tool == .mkvmerge && code == 1)
            await context?.record(
                .tool, succeeded ? .succeeded : .failed,
                failure: succeeded ? nil : .toolExited, tool: tool, exitCode: code)
            return result
        } catch {
            let failure = DiagnosticFailure.classify(error)
            await context?.record(
                .tool, failure == .cancelled ? .cancelled : .failed,
                failure: failure, tool: tool)
            throw error
        }
    }
}
