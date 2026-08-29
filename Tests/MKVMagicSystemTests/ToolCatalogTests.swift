import CryptoKit
import Foundation
import XCTest

@testable import MKVMagicSystem

final class ToolCatalogTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-tool-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryRoot.appendingPathComponent("universal", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if temporaryRoot != nil {
            try FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testValidExactToolTreeLoads() throws {
        try writeToolTree()
        let catalog = try ToolCatalog(rootURL: temporaryRoot, architecture: .arm64)
        XCTAssertEqual(try catalog.url(for: .ffprobe).lastPathComponent, "ffprobe")
        XCTAssertEqual(
            try catalog.url(for: .ffprobe).deletingLastPathComponent().lastPathComponent,
            "universal")
        XCTAssertEqual(catalog.architecture, .arm64)
        XCTAssertEqual(catalog.manifest.architecture, .universal)
    }

    func testIntelExecutionUsesTheSameUniversalRuntime() throws {
        try writeToolTree()
        let catalog = try ToolCatalog(rootURL: temporaryRoot, architecture: .x86_64)

        XCTAssertEqual(catalog.architecture, .x86_64)
        XCTAssertEqual(
            try catalog.url(for: .mkvmerge).path,
            temporaryRoot.appendingPathComponent("universal/mkvmerge").path
        )
    }

    func testLegacySplitRuntimeManifestFailsClosed() throws {
        try writeToolTree(schema: "mkv-magic-tool-manifest-v1")

        XCTAssertThrowsError(
            try ToolCatalog(rootURL: temporaryRoot, architecture: .arm64)
        ) { error in
            XCTAssertEqual(error as? ToolCatalogError, .wrongManifestIdentity)
        }
    }

    func testHashMismatchFailsClosed() throws {
        try writeToolTree()
        try Data("changed".utf8).write(
            to: temporaryRoot.appendingPathComponent("universal/ffprobe")
        )
        XCTAssertThrowsError(
            try ToolCatalog(rootURL: temporaryRoot, architecture: .arm64)
        ) { error in
            XCTAssertEqual(error as? ToolCatalogError, .hashMismatch(.ffprobe))
        }
    }

    func testUnexpectedManifestFieldFailsClosed() throws {
        try writeToolTree(extraManifestField: true)
        XCTAssertThrowsError(
            try ToolCatalog(rootURL: temporaryRoot, architecture: .arm64)
        ) { error in
            XCTAssertEqual(error as? ToolCatalogError, .unexpectedManifestFields)
        }
    }

    func testSymlinkedToolFailsClosed() throws {
        try writeToolTree()
        let tool = temporaryRoot.appendingPathComponent("universal/ffprobe")
        try FileManager.default.removeItem(at: tool)
        try FileManager.default.createSymbolicLink(
            atPath: tool.path, withDestinationPath: "/usr/bin/true")
        XCTAssertThrowsError(
            try ToolCatalog(rootURL: temporaryRoot, architecture: .arm64, verifyHashes: false)
        )
    }

    private func writeToolTree(
        extraManifestField: Bool = false,
        schema: String = ToolManifest.currentSchema
    ) throws {
        let architectureRoot = temporaryRoot.appendingPathComponent("universal", isDirectory: true)
        var entries: [[String: Any]] = []
        for tool in BundledTool.allCases {
            let toolURL = architectureRoot.appendingPathComponent(tool.rawValue)
            let bytes = Data("#!/bin/sh\nexit 0\n".utf8)
            try bytes.write(to: toolURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: toolURL.path
            )
            entries.append([
                "name": tool.rawValue,
                "path": tool.rawValue,
                "version": "test",
                "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                "license": "test",
                "source": "https://example.invalid/\(tool.rawValue)",
            ])
        }
        var manifest: [String: Any] = [
            "schema": schema,
            "platform": "macos",
            "architecture": "universal",
            "tools": entries,
            "libraries": [],
        ]
        if extraManifestField { manifest["unexpected"] = true }
        let data = try JSONSerialization.data(
            withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(
            to: architectureRoot.appendingPathComponent("manifest.json"),
            options: .withoutOverwriting
        )
    }
}
