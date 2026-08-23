import Foundation
import XCTest

@testable import MKVMagicExecution

final class VerifiedOutputTransactionTests: XCTestCase {
    private var rootURL: URL!
    private var sourceURL: URL!
    private var destinationURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-transaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        sourceURL = rootURL.appendingPathComponent("Source.mkv")
        destinationURL = rootURL.appendingPathComponent("Output.mkv")
        try Data("original".utf8).write(to: sourceURL)
    }

    override func tearDownWithError() throws {
        if rootURL != nil { try FileManager.default.removeItem(at: rootURL) }
    }

    func testCommitIsImpossibleBeforeVerification() async throws {
        let transaction = VerifiedOutputTransaction(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )
        _ = try await transaction.prepareClone()

        do {
            _ = try await transaction.commit()
            XCTFail("Expected invalid transaction state")
        } catch {
            XCTAssertEqual(error as? OutputTransactionError, .invalidState)
        }

        await transaction.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), Data("original".utf8))
    }

    func testVerifiedWorkingCloneCommitsExclusivelyWithoutChangingSource() async throws {
        let transaction = VerifiedOutputTransaction(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )
        let temporaryOutput = try await transaction.prepareClone()
        try Data("edited".utf8).write(to: temporaryOutput)

        try await transaction.markVerified()
        let committed = try await transaction.commit()

        XCTAssertEqual(committed, destinationURL)
        XCTAssertEqual(try Data(contentsOf: sourceURL), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("edited".utf8))
    }

    func testWorkingCloneUsesToolSafeNameForUnicodeDestination() async throws {
        destinationURL = rootURL.appendingPathComponent("Output — Edited.mkv")
        let transaction = VerifiedOutputTransaction(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )

        let temporaryOutput = try await transaction.prepareClone()

        XCTAssertEqual(temporaryOutput.lastPathComponent, "working-copy.mkv")
        XCTAssertFalse(temporaryOutput.path.contains("—"))
        await transaction.cancel()
    }

    func testExistingDestinationFailsBeforeCreatingWorkingCopy() async throws {
        try Data("existing".utf8).write(to: destinationURL)
        let transaction = VerifiedOutputTransaction(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )

        do {
            _ = try await transaction.prepareClone()
            XCTFail("Expected existing destination refusal")
        } catch {
            XCTAssertEqual(error as? OutputTransactionError, .destinationExists)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("existing".utf8))
    }

    func testSymbolicLinkSourceFailsClosed() async throws {
        let link = rootURL.appendingPathComponent("Linked.mkv")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sourceURL)
        let transaction = VerifiedOutputTransaction(
            sourceURL: link,
            destinationURL: destinationURL
        )

        do {
            _ = try await transaction.prepareClone()
            XCTFail("Expected unsafe source refusal")
        } catch {
            XCTAssertEqual(error as? OutputTransactionError, .unsafeSource)
        }
    }
}
