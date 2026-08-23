import Foundation
import XCTest

@testable import MKVMagicSystem

final class MediaFileDiscoveryTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if rootURL != nil { try FileManager.default.removeItem(at: rootURL) }
    }

    func testDirectoryScanIsRecursiveFilteredSortedAndSymlinkSafe() async throws {
        let nested = rootURL.appendingPathComponent("Season 1", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let movie = nested.appendingPathComponent("Episode 2.mkv")
        let subtitle = nested.appendingPathComponent("Episode 1.srt")
        let notes = nested.appendingPathComponent("notes.txt")
        let hidden = nested.appendingPathComponent(".hidden.mkv")
        for file in [movie, subtitle, notes, hidden] {
            try Data("fixture".utf8).write(to: file)
        }
        try FileManager.default.createSymbolicLink(
            at: nested.appendingPathComponent("Linked.mkv"),
            withDestinationURL: movie
        )

        let files = try await LocalMediaFileDiscovery().discover([rootURL])

        XCTAssertEqual(files, [subtitle, movie])
    }

    func testExplicitRegularFileIsAcceptedRegardlessOfExtension() async throws {
        let file = rootURL.appendingPathComponent("unusual.media")
        try Data("fixture".utf8).write(to: file)
        let files = try await LocalMediaFileDiscovery().discover([file])

        XCTAssertEqual(files, [file])
    }

    func testSymlinkRootFailsClosed() async throws {
        let file = rootURL.appendingPathComponent("Movie.mkv")
        let link = rootURL.appendingPathComponent("Linked.mkv")
        try Data("fixture".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        do {
            _ = try await LocalMediaFileDiscovery().discover([link])
            XCTFail("Expected unsafe root")
        } catch {
            XCTAssertEqual(error as? MediaFileDiscoveryError, .unsafeRoot)
        }
    }

    func testFileLimitFailsClosed() async throws {
        for index in 0..<2 {
            try Data("fixture".utf8).write(
                to: rootURL.appendingPathComponent("Movie \(index).mkv"))
        }

        do {
            _ = try await LocalMediaFileDiscovery(fileLimit: 1).discover([rootURL])
            XCTFail("Expected file limit")
        } catch {
            XCTAssertEqual(error as? MediaFileDiscoveryError, .tooManyFiles(limit: 1))
        }
    }
}
