import Foundation
import MKVMagicSystem
import XCTest

final class PrivateTemporaryDirectoryTests: XCTestCase {
    func testWorkspaceIsPrivateAndRemovedAfterSuccess() async throws {
        var observedURL: URL?
        let value = try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-test"
        ) { directory in
            observedURL = directory
            let values = try directory.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey,
            ])
            let permissions = try XCTUnwrap(
                FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions]
                    as? NSNumber
            )
            XCTAssertTrue(directory.isFileURL)
            XCTAssertTrue(directory.path.hasPrefix("/"))
            XCTAssertEqual(values.isDirectory, true)
            XCTAssertNotEqual(values.isSymbolicLink, true)
            XCTAssertEqual(permissions.intValue, 0o700)
            return 42
        }

        XCTAssertEqual(value, 42)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: try XCTUnwrap(observedURL).path)
        )
    }

    func testWorkspaceIsRemovedWhenOperationThrows() async throws {
        enum FixtureError: Error { case stopped }
        var observedURL: URL?
        do {
            _ = try await PrivateTemporaryDirectory.withDirectory(
                prefix: "mkv-magic-failure"
            ) { directory -> Int in
                observedURL = directory
                throw FixtureError.stopped
            }
            XCTFail("Expected the fixture failure")
        } catch FixtureError.stopped {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: try XCTUnwrap(observedURL).path)
        )
    }

    func testUnsafePrefixesAreRejectedBeforeDirectoryCreation() async {
        for prefix in ["", "../escape", "contains space", String(repeating: "a", count: 65)] {
            do {
                _ = try await PrivateTemporaryDirectory.withDirectory(prefix: prefix) { _ in 1 }
                XCTFail("Expected invalid prefix: \(prefix)")
            } catch {
                XCTAssertEqual(error as? PrivateTemporaryDirectoryError, .invalidPrefix)
            }
        }
    }
}
