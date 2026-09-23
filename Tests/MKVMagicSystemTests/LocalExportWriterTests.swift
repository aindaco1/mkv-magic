import Foundation
import MKVMagicSystem
import XCTest

final class LocalExportWriterTests: XCTestCase {
    func testLateCollisionAndDanglingSymlinkNeverReplaceUserData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("report.json")
        let original = Data("original".utf8)
        try LocalExportWriter.write(original, to: output)
        XCTAssertThrowsError(try LocalExportWriter.write(Data("replacement".utf8), to: output))
        XCTAssertEqual(try Data(contentsOf: output), original)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: output.path)[.posixPermissions]
                as? Int, 0o600)
        let link = directory.appendingPathComponent("dangling.xml")
        let missing = directory.appendingPathComponent("missing.xml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)
        XCTAssertThrowsError(try LocalExportWriter.write(original, to: link))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: link.path), missing.path)
    }
}
