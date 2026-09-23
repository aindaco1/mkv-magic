import Foundation
import MKVMagicReporting
import MKVMagicSystem

/// The sole application-owned network client, linked only into the sandboxed
/// reporting XPC executable. No URL, credentials, raw logs, or file access API.
final class ReportTransport: NSObject, URLSessionTaskDelegate, Sendable {
    static var endpoint: URL {
        URLComponents(string: "https://crash.dustwave.xyz/v1/mkv-magic/reports")!.url!
    }

    func send(_ data: Data, configuration: URLSessionConfiguration = .ephemeral) async throws
        -> Data
    {
        let report = try DiagnosticIssueReport.validated(data)
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Same fixed intake as the legacy browser; Origin is an abuse signal,
        // not authentication. GitHub credentials exist only on the relay.
        request.setValue("https://crash.dustwave.xyz", forHTTPHeaderField: "Origin")
        request.httpBody = try report.encoded()
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
            response.url == Self.endpoint, (200...299).contains(response.statusCode),
            response.expectedContentLength <= 4_096
        else { throw ReportSubmissionError.rejected }
        var body = Data()
        for try await byte in bytes {
            guard body.count < 4_096 else { throw ReportSubmissionError.invalidReceipt }
            body.append(byte)
        }
        _ = try ReportReceipt.validated(body, for: report.id)
        return body
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
}
