import DustWaveDiagnostics
import Foundation
import MKVMagicReporting
import MKVMagicSystem

/// This adapter is linked only into the sandboxed reporting XPC executable.
final class ReportTransport: Sendable {
    static var endpoint: URL {
        URLComponents(string: "https://crash.dustwave.xyz/v1/mkv-magic/reports")!.url!
    }

    func send(_ data: Data, configuration: URLSessionConfiguration = .ephemeral) async throws
        -> Data
    {
        let report = try DiagnosticIssueReport.validated(data)
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://crash.dustwave.xyz", forHTTPHeaderField: "Origin")
        request.httpBody = try report.encoded()
        let body: Data
        do {
            (body, _) = try await BoundedReportTransport().send(
                request,
                maximumResponseBytes: 4096, configuration: configuration
            ) { response in
                guard response.url == Self.endpoint, (200...299).contains(response.statusCode),
                    response.expectedContentLength <= 4096
                else { throw ReportSubmissionError.rejected }
            }
        } catch ReportTransportError.responseTooLarge {
            throw ReportSubmissionError.invalidReceipt
        } catch ReportTransportError.invalidResponse { throw ReportSubmissionError.rejected }
        _ = try MKVMagicReporting.ReportReceipt.validated(body, for: report.id)
        return body
    }
}
