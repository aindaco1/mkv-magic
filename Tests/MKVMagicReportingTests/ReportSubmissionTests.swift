import Foundation
import MKVMagicSystem
import XCTest

import class DustWaveDiagnostics.BoundedReportTransport

@testable import MKVMagicReportService
@testable import MKVMagicReporting

final class ReportSubmissionTests: XCTestCase {
    func testHostIdentityPinsProductAndOwnTeamWithoutParentFileAccess() throws {
        let requirement = try ReportServiceIdentity.hostRequirement(teamIdentifier: "ABCDEFGHIJ")
        XCTAssertTrue(requirement.contains("identifier \"com.dustwave.mkvmagic\""))
        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains("\"ABCDEFGHIJ\""))
        XCTAssertThrowsError(try ReportServiceIdentity.hostRequirement(teamIdentifier: nil))
        XCTAssertThrowsError(
            try ReportServiceIdentity.hostRequirement(teamIdentifier: "evil\" or true"))
    }
    @MainActor
    func testXPCFailureCallbacksHopToMainActorAndResumeOnlyOnce() async {
        let pending = PendingReportReply()
        do {
            let _: ReportReceipt = try await withCheckedThrowingContinuation { continuation in
                pending.continuation = continuation
                let callback = pending.onProxyError
                let invalidated = pending.onFailure(.serviceUnavailable)
                Task.detached {
                    callback(ReportSubmissionError.unavailable)
                    invalidated()
                }
            }
            XCTFail("Disconnected service must fail, not crash or claim success")
        } catch {
            XCTAssertNotNil(error as? ReportSubmissionError)
        }
    }
    private func report() -> DiagnosticIssueReport {
        DiagnosticIssueReport(
            id: UUID(), kind: .operationFailure, version: "0.3.0", build: "20",
            operatingSystem: "15.7.4", architecture: .x86_64, action: .verifyAndRun,
            stage: .destination, failure: .destinationUnavailable)
    }

    func testUploadRejectsUnknownFieldsInvalidBoundsAndUntrustedSignature() throws {
        let original = report()
        XCTAssertEqual(try DiagnosticIssueReport.validated(original.encoded()), original)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: original.encoded()) as? [String: Any])
        object["filename"] = "private movie.mkv"
        XCTAssertThrowsError(
            try DiagnosticIssueReport.validated(JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "filename")
        object["exitCode"] = 1000
        XCTAssertThrowsError(
            try DiagnosticIssueReport.validated(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try DiagnosticIssueReport.validated(Data(repeating: 32, count: 4097)))
        XCTAssertThrowsError(
            try ReportServiceIdentity.requirement(
                for: URL(fileURLWithPath: "/missing-report-service.xpc")))
    }

    func testReceiptMustMatchAttemptAndCannotSupplyAnExternalLink() throws {
        let id = UUID()
        let data = Data(
            "{\"ok\":true,\"reportId\":\"\(id)\",\"issueNumber\":2,\"action\":\"duplicate\",\"url\":\"https://evil.invalid\"}"
                .utf8)
        let receipt = try ReportReceipt.validated(data, for: id)
        XCTAssertEqual(receipt.issueURL.host, "github.com")
        XCTAssertEqual(receipt.issueURL.path, "/aindaco1/mkv-magic/issues/2")
        XCTAssertThrowsError(try ReportReceipt.validated(data, for: UUID()))
        XCTAssertThrowsError(try ReportReceipt.validated(Data(repeating: 32, count: 4097), for: id))
    }

    func testTransportUsesFixedAnonymousEndpointAndBoundedReceipt() async throws {
        let report = report()
        let data = try report.encoded()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReportStubProtocol.self]
        ReportStubProtocol.state.set { request in
            XCTAssertEqual(request.url, ReportTransport.endpoint)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Origin"), "https://crash.dustwave.xyz")
            return (
                200,
                Data(
                    "{\"ok\":true,\"reportId\":\"\(report.id)\",\"issueNumber\":2,\"action\":\"created\"}"
                        .utf8)
            )
        }
        let response = try await ReportTransport().send(data, configuration: config)
        XCTAssertEqual(try ReportReceipt.validated(response, for: report.id).issueNumber, 2)
        ReportStubProtocol.state.set { _ in (200, Data(repeating: 32, count: 4097)) }
        do {
            _ = try await ReportTransport().send(data, configuration: config)
            XCTFail("Oversized response must fail")
        } catch {}
        ReportStubProtocol.state.set { _ in (503, Data()) }
        do {
            _ = try await ReportTransport().send(data, configuration: config)
            XCTFail("Provider failure must not appear sent")
        } catch {}
    }

    func testRedirectIsNeverFollowed() async {
        let transport = DustWaveDiagnostics.BoundedReportTransport()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: ReportTransport.endpoint)
        let response = HTTPURLResponse(
            url: ReportTransport.endpoint, statusCode: 307,
            httpVersion: nil, headerFields: nil)!
        transport.urlSession(
            session, task: session.dataTask(with: request),
            willPerformHTTPRedirection: response, newRequest: request
        ) { redirected in
            XCTAssertNil(redirected)
        }
    }
}

private final class ReportStubProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        let lock = NSLock()
        var handler: (@Sendable (URLRequest) -> (Int, Data))?
        func set(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
            lock.lock()
            defer { lock.unlock() }
            self.handler = handler
        }
        func response(_ request: URLRequest) -> (Int, Data) {
            lock.lock()
            defer { lock.unlock() }
            return handler!(request)
        }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.state.response(request)
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!,
            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
