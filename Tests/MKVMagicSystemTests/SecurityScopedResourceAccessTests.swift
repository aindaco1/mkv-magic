import Foundation
import XCTest

@testable import MKVMagicSystem

final class SecurityScopedResourceAccessTests: XCTestCase {
    func testAccessRetainsExactURLAndBalancesStartStopAtEndOfLifetime() throws {
        let probe = AccessProbe()
        let url = URL(fileURLWithPath: "/Media/Reviewed Subtitle.srt")
        var access: SecurityScopedResourceAccess? = SecurityScopedResourceAccess(
            url: url,
            startAccessing: {
                probe.record($0)
                return true
            },
            stopAccessing: { probe.record($0) })
        XCTAssertEqual(access?.url, url)
        XCTAssertEqual(probe.urls, [url])
        access = nil
        XCTAssertEqual(probe.urls, [url, url])
    }

    func testDeniedAccessIsNotStopped() {
        let probe = AccessProbe()
        let access = SecurityScopedResourceAccess(
            url: URL(fileURLWithPath: "/Media/Denied.srt"), startAccessing: { _ in false },
            stopAccessing: { probe.record($0) })
        XCTAssertNil(access)
        XCTAssertTrue(probe.urls.isEmpty)
    }
}

private final class AccessProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = [URL]()
    var urls: [URL] { lock.withLock { recorded } }
    func record(_ url: URL) { lock.withLock { recorded.append(url) } }
}
