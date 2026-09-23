import Foundation
import MKVMagicSystem
import Security

@objc public protocol ReportServiceProtocol {
    func submit(_ report: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
}

public enum ReportSubmissionError: String, Error, Sendable {
    case invalidReport, serviceUnavailable, unavailable, rejected, invalidReceipt
}

public struct ReportReceipt: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case created, updated, duplicate }
    public let ok: Bool
    public let reportId: UUID
    public let issueNumber: Int
    public let action: Action

    public static func validated(_ data: Data, for id: UUID) throws -> Self {
        guard data.count <= 4_096,
            let receipt = try? JSONDecoder().decode(Self.self, from: data),
            receipt.ok, receipt.reportId == id,
            (1...9_007_199_254_740_991).contains(receipt.issueNumber)
        else { throw ReportSubmissionError.invalidReceipt }
        return receipt
    }

    public var issueURL: URL {
        URLComponents(string: "https://github.com/aindaco1/mkv-magic/issues/\(issueNumber)")!.url!
    }
}

public enum ReportServiceIdentity {
    public static let identifier = "com.dustwave.mkvmagic.reporter"

    /// The reporting sandbox cannot read the containing app's Info.plist.
    /// Trust the fixed host identifier signed by this service's own Team ID,
    /// enforced by XPC on the actual peer, not by inspecting a caller-supplied path.
    public static func hostRequirement() throws -> String {
        var ownCode: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode,
            SecCodeCopyStaticCode(ownCode, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let information = information as? [String: Any],
            information[kSecCodeInfoIdentifier as String] as? String == identifier
        else { throw ReportSubmissionError.serviceUnavailable }
        return try hostRequirement(
            teamIdentifier: information[kSecCodeInfoTeamIdentifier as String] as? String)
    }

    static func hostRequirement(teamIdentifier: String?) throws -> String {
        guard let teamIdentifier,
            teamIdentifier.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil
        else { throw ReportSubmissionError.serviceUnavailable }
        return
            "anchor apple generic and identifier \"com.dustwave.mkvmagic\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    /// Derive the exact packaged peer requirement, including ad-hoc CDHash in
    /// disposable package tests. Never accept an unsigned or arbitrary peer.
    public static func requirement(for bundleURL: URL) throws -> String {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess,
            let code,
            SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil)
                == errSecSuccess,
            SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess,
            let requirement,
            SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
            let text
        else { throw ReportSubmissionError.serviceUnavailable }
        return text as String
    }
}

@MainActor
public final class ReportSubmissionClient {
    public init() {}

    public func send(_ report: DiagnosticIssueReport) async throws -> ReportReceipt {
        let data = try report.encoded()
        _ = try DiagnosticIssueReport.validated(data)
        return try await request(data, id: report.id)
    }

    /// Packaged acceptance checks peer signing and IPC with an invalid payload.
    /// The service must reject it before networking; this never submits a report.
    public func checkAvailability() async throws {
        do { _ = try await request(Data(), id: UUID()) } catch ReportSubmissionError.invalidReport {
            return
        }
        throw ReportSubmissionError.serviceUnavailable
    }

    private func request(_ data: Data, id: UUID) async throws -> ReportReceipt {
        let service = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/XPCServices/MKVMagicReportService.xpc")
        let requirement = try ReportServiceIdentity.requirement(for: service)
        let connection = NSXPCConnection(serviceName: ReportServiceIdentity.identifier)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: ReportServiceProtocol.self)
        let pending = PendingReportReply()
        defer { connection.invalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            pending.continuation = continuation
            connection.interruptionHandler = pending.onFailure(.unavailable)
            connection.invalidationHandler = pending.onFailure(.serviceUnavailable)
            connection.resume()
            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler(pending.onProxyError)
                    as? ReportServiceProtocol
            else {
                pending.finish(.failure(ReportSubmissionError.serviceUnavailable))
                return
            }
            proxy.submit(data) { receipt, failure in
                Task { @MainActor in
                    do {
                        guard let receipt, failure == nil else {
                            throw failure.flatMap(ReportSubmissionError.init(rawValue:))
                                ?? .unavailable
                        }
                        pending.finish(.success(try ReportReceipt.validated(receipt, for: id)))
                    } catch { pending.finish(.failure(error)) }
                }
            }
            pending.timeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                pending.finish(.failure(ReportSubmissionError.unavailable))
            }
        }
    }
}

@MainActor
final class PendingReportReply {
    var continuation: CheckedContinuation<ReportReceipt, Error>?
    var timeout: Task<Void, Never>?
    // Objective-C XPC callbacks run off the main actor. Creating them in a
    // MainActor closure without Sendable would trap under Swift 6 isolation.
    nonisolated func onFailure(_ failure: ReportSubmissionError) -> @Sendable () -> Void {
        { Task { @MainActor in self.finish(.failure(failure)) } }
    }
    nonisolated var onProxyError: @Sendable (Error) -> Void {
        { _ in self.onFailure(.unavailable)() }
    }
    func finish(_ result: Result<ReportReceipt, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }
}
