import Foundation
import MKVMagicReporting
import MKVMagicSystem
import OSLog

private final class ReportService: NSObject, ReportServiceProtocol, Sendable {
    private let transport = ReportTransport()
    func submit(_ report: Data, reply: @escaping @Sendable (Data?, String?) -> Void) {
        guard (try? DiagnosticIssueReport.validated(report)) != nil else {
            reply(nil, ReportSubmissionError.invalidReport.rawValue)
            return
        }
        Task {
            do { reply(try await transport.send(report), nil) } catch {
                reply(nil, (error as? ReportSubmissionError ?? .unavailable).rawValue)
            }
        }
    }
}

private final class ReportListener: NSObject, NSXPCListenerDelegate {
    private let logger = Logger(subsystem: "com.dustwave.mkvmagic", category: "report-service")
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
        -> Bool
    {
        guard let requirement = try? ReportServiceIdentity.hostRequirement() else {
            logger.error("Reporting peer rejected: signed service identity unavailable")
            return false
        }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: ReportServiceProtocol.self)
        connection.exportedObject = ReportService()
        connection.resume()
        return true
    }
}

@main
enum ReportingServiceMain {
    static func main() {
        let delegate = ReportListener()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        withExtendedLifetime(delegate) { listener.resume() }
    }
}
