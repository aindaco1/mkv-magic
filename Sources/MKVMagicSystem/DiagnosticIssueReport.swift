import CryptoKit
import Foundation

public enum DiagnosticIssueKind: String, Codable, Sendable {
    case operationFailure, interruptedOperation, nativeCrash
}

/// This projection, not the support export or local log file, is reviewed for
/// GitHub. Every field is bounded metadata; no private content is accepted.
public struct DiagnosticIssueReport: Codable, Equatable, Sendable {
    public let schema: String
    public let id: UUID
    public let kind: DiagnosticIssueKind
    public let version: String
    public let build: String
    public let operatingSystem: String
    public let architecture: ToolArchitecture
    public let action: DiagnosticAction
    public let stage: DiagnosticStage
    public let failure: DiagnosticFailure
    public let tool: BundledTool?
    public let exitCode: Int32?
    public let crash: DiagnosticCrashFacts?

    public init(
        id: UUID, kind: DiagnosticIssueKind, version: String, build: String,
        operatingSystem: String, architecture: ToolArchitecture, action: DiagnosticAction,
        stage: DiagnosticStage, failure: DiagnosticFailure, tool: BundledTool? = nil,
        exitCode: Int32? = nil, crash: DiagnosticCrashFacts? = nil
    ) {
        schema = "mkv-magic-issue-report-v1"
        self.id = id
        self.kind = kind
        self.version = DiagnosticEvent.safeVersion(version)
        self.build = DiagnosticEvent.safeVersion(build)
        self.operatingSystem = DiagnosticEvent.safeOperatingSystem(operatingSystem)
        self.architecture = architecture
        self.action = action
        self.stage = stage
        self.failure = failure
        self.tool = tool
        self.exitCode = exitCode.map { min(255, max(-1, $0)) }
        self.crash = crash
    }

    /// Delimiter-separated closed values avoid JSON object-key-order differences
    /// across Swift and the relay. Identity/progress/version don't split symptoms.
    public var fingerprint: String {
        let parts = [
            schema, kind.rawValue, architecture.rawValue, action.rawValue,
            stage.rawValue, failure.rawValue, tool?.rawValue ?? "",
            exitCode.map(String.init) ?? "",
            crash?.exception.rawValue ?? "", crash?.signal?.rawValue ?? "",
            crash?.image?.rawValue ?? "", crash?.imageOffset.map(String.init) ?? "",
            crash == nil ? "" : build, crash == nil ? "" : operatingSystem,
        ]
        return SHA256.hash(data: Data(parts.joined(separator: "|").utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Revalidate at the isolated reporting process boundary. Codable alone
    /// ignores unknown fields, which is inappropriate for a public upload.
    public static func validated(_ data: Data) throws -> Self {
        guard data.count <= 4_096,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys).isSubset(of: [
                "schema", "id", "kind", "version", "build", "operatingSystem", "architecture",
                "action", "stage", "failure", "tool", "exitCode", "crash",
            ])
        else { throw DiagnosticReportError.invalidReport }
        let report = try JSONDecoder().decode(Self.self, from: data)
        guard report.schema == "mkv-magic-issue-report-v1",
            report.version == "unknown"
                || DiagnosticEvent.safeVersion(report.version) == report.version,
            report.build == "unknown" || DiagnosticEvent.safeVersion(report.build) == report.build,
            report.operatingSystem == "unknown"
                || DiagnosticEvent.safeOperatingSystem(report.operatingSystem)
                    == report.operatingSystem,
            report.failure != .cancelled,
            report.exitCode.map({ (-1...255).contains($0) }) ?? true,
            report.crash?.imageOffset.map({ (0...1_000_000_000).contains($0) }) ?? true,
            report.kind == .nativeCrash
                ? report.crash != nil && report.action == .application : report.crash == nil
        else { throw DiagnosticReportError.invalidReport }
        if let crash = object["crash"] as? [String: Any],
            !Set(crash.keys).isSubset(of: ["exception", "signal", "image", "imageOffset"])
        {
            throw DiagnosticReportError.invalidReport
        }
        return report
    }

    /// Fragment data isn't sent in the page request. The browser shows another
    /// explicit Send step; opening the page never submits a report.
    public func reviewURL() throws -> URL {
        let data = try encoded()
        guard data.count <= 4_096 else { throw DiagnosticReportError.invalidReport }
        var url = URLComponents(string: "https://crash.dustwave.xyz/mkv-magic/review")!
        url.fragment = data.base64EncodedString()
        guard let result = url.url else { throw DiagnosticReportError.invalidReport }
        return result
    }

    public static func from(
        _ snapshot: DiagnosticSnapshot, currentSessionID: UUID,
        operatingSystem: String, architecture: ToolArchitecture
    ) -> [Self] {
        var order: [UUID] = []
        var attempts: [UUID: [DiagnosticEvent]] = [:]
        for event in snapshot.events {
            if attempts[event.attemptID] == nil { order.append(event.attemptID) }
            attempts[event.attemptID, default: []].append(event)
        }
        return order.reversed().compactMap { id -> Self? in
            guard let events = attempts[id], let last = events.last else { return nil }
            let event: DiagnosticEvent
            let kind: DiagnosticIssueKind
            // Late stage callbacks cannot resurrect a completed or cancelled attempt.
            if events.contains(where: { $0.outcome == .cancelled || $0.failure == .cancelled }) {
                return nil
            }
            if events.contains(where: { $0.stage == .finished && $0.outcome == .succeeded }) {
                return nil
            }
            if last.sessionID == currentSessionID,
                !events.contains(where: { $0.stage == .finished }),
                last.stage == .tool || ![DiagnosticOutcome.failed, .blocked].contains(last.outcome)
            {
                return nil
            }
            if let failure = events.last(where: { $0.outcome == .failed || $0.outcome == .blocked })
            {
                event = failure
                kind = .operationFailure
            } else if last.sessionID != currentSessionID,
                events.contains(where: { $0.stage == .execution && $0.outcome == .started })
            {
                event = last
                kind = .interruptedOperation
            } else {
                return nil
            }
            // Prefer the concrete failing stage/tool to the generic final UI catch.
            let cause =
                events.last(where: {
                    ($0.outcome == .failed || $0.outcome == .blocked) && $0.stage != .finished
                }) ?? event
            return Self(
                id: id, kind: kind, version: event.version, build: event.build,
                operatingSystem: event.operatingSystem ?? operatingSystem,
                architecture: event.architecture ?? architecture,
                action: event.action, stage: cause.stage, failure: cause.failure ?? .unknown,
                tool: cause.tool, exitCode: cause.exitCode)
        }.prefix(20).map { $0 }
    }
}

public enum DiagnosticReportError: Error, LocalizedError {
    case invalidReport
    public var errorDescription: String? {
        "This is not a supported MKV Magic diagnostic or crash report."
    }
}
