import Foundation
import XCTest

@testable import MKVMagicSystem

final class SecurityScopedBookmarkCodecTests: XCTestCase {
    private var rootURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-bookmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        fileURL = rootURL.appendingPathComponent("Input.mkv")
        try Data([1, 2, 3]).write(to: fileURL)
    }

    override func tearDownWithError() throws {
        if rootURL != nil { try FileManager.default.removeItem(at: rootURL) }
    }

    func testCreatesAndResolvesNarrowFileAndDirectoryBookmarks() throws {
        let codec = SecurityScopedBookmarkCodec()
        let input = try codec.makeReference(for: fileURL, access: .readOnlyFile)
        let destination = try codec.makeReference(
            for: rootURL,
            access: .readWriteDirectory
        )

        XCTAssertEqual(input.displayName, "Input.mkv")
        XCTAssertFalse(input.securityScopedBookmark.isEmpty)
        XCTAssertEqual(
            try codec.resolve(input, access: .readOnlyFile),
            fileURL.standardizedFileURL
        )
        XCTAssertEqual(
            try codec.resolve(destination, access: .readWriteDirectory),
            rootURL.standardizedFileURL
        )
        XCTAssertThrowsError(try codec.resolve(input, access: .readWriteDirectory)) {
            XCTAssertEqual($0 as? SecurityScopedBookmarkError, .wrongResourceType)
        }
    }

    func testRejectsSymlinksAndWrongResourceTypesBeforeBookmarking() throws {
        let codec = SecurityScopedBookmarkCodec()
        let link = rootURL.appendingPathComponent("Linked.mkv")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fileURL)

        XCTAssertThrowsError(try codec.makeReference(for: link, access: .readOnlyFile)) {
            XCTAssertEqual($0 as? SecurityScopedBookmarkError, .unsafeURL)
        }
        XCTAssertThrowsError(
            try codec.makeReference(for: rootURL, access: .readOnlyFile)
        ) {
            XCTAssertEqual($0 as? SecurityScopedBookmarkError, .wrongResourceType)
        }
        XCTAssertThrowsError(
            try codec.makeReference(for: fileURL, access: .readWriteDirectory)
        ) {
            XCTAssertEqual($0 as? SecurityScopedBookmarkError, .wrongResourceType)
        }
    }
}
