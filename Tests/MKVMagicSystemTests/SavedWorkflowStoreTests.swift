import Foundation
import MKVMagicCore
import XCTest

@testable import MKVMagicSystem

final class SavedWorkflowStoreTests: XCTestCase {
    private var rootURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-workflows-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        fileURL = rootURL.appendingPathComponent("workflows.json")
    }

    override func tearDownWithError() throws {
        if rootURL != nil { try FileManager.default.removeItem(at: rootURL) }
    }

    func testRoundTripsVersionedLibraryWithPrivatePermissions() async throws {
        let store = try JSONSavedWorkflowStore(fileURL: fileURL)
        let workflow = makeWorkflow()

        try await store.save([workflow])
        let loaded = try await store.load()

        XCTAssertEqual(loaded, [workflow])
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        let json = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(json.contains(JSONSavedWorkflowStore.librarySchema))
        XCTAssertFalse(json.contains("/private/media"))
    }

    func testPortableFileIsHumanReadableAndRoundTripsWithoutMediaIdentity() throws {
        let workflow = makeWorkflow()

        let data = try JSONSavedWorkflowStore.encodePortableFile(workflow)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("englishLibraryCleanup"))
        XCTAssertTrue(json.contains("schemaVersion"))
        XCTAssertFalse(json.contains("sourceURL"))
        XCTAssertFalse(json.contains("trackUID"))
        XCTAssertEqual(try JSONSavedWorkflowStore.decodePortableFile(data), workflow)
    }

    func testUnexpectedFieldsAtEveryLevelFailClosed() throws {
        let unexpectedWorkflow = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":1,"name":"Clean","steps":[],"sourceURL":"/private/media/Movie.mkv"}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(unexpectedWorkflow)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unexpectedFields)
        }

        let unexpectedStep = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":1,"name":"Clean","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"englishLibraryCleanup","trackUID":42}]}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(unexpectedStep)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unexpectedFields)
        }
    }

    func testDuplicateIdentifiersAndOversizedStepListsFailClosed() async throws {
        let store = try JSONSavedWorkflowStore(fileURL: fileURL)
        let workflow = makeWorkflow()
        do {
            try await store.save([workflow, workflow])
            XCTFail("Expected duplicate workflow refusal")
        } catch {
            XCTAssertEqual(error as? SavedWorkflowStoreError, .duplicateWorkflowIdentifier)
        }

        let repeatedStep = workflow.steps[0]
        var invalid = workflow
        invalid.steps = [repeatedStep, repeatedStep]
        do {
            try await store.save([invalid])
            XCTFail("Expected duplicate step refusal")
        } catch {
            XCTAssertEqual(error as? SavedWorkflowStoreError, .duplicateStepIdentifier)
        }

        invalid.steps = [
            SavedWorkflowStep(action: .removeSegmentTitle),
            SavedWorkflowStep(action: .removeSegmentTitle),
        ]
        do {
            try await store.save([invalid])
            XCTFail("Expected duplicate action refusal")
        } catch {
            XCTAssertEqual(error as? SavedWorkflowStoreError, .duplicateAction)
        }

        invalid.steps = (0...JSONSavedWorkflowStore.maximumStepsPerWorkflow).map { _ in
            SavedWorkflowStep(action: .removeSegmentTitle)
        }
        do {
            try await store.save([invalid])
            XCTFail("Expected step limit refusal")
        } catch {
            XCTAssertEqual(error as? SavedWorkflowStoreError, .tooManySteps)
        }
    }

    func testSymlinkedLibraryFailsClosed() async throws {
        let target = rootURL.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: target)
        let store = try JSONSavedWorkflowStore(fileURL: fileURL)

        do {
            _ = try await store.load()
            XCTFail("Expected unsafe path")
        } catch {
            XCTAssertEqual(error as? SavedWorkflowStoreError, .unsafePath)
        }
    }

    func testPortablePathImportRejectsSymlinkAndExportRoundTrips() throws {
        let target = rootURL.appendingPathComponent("target.mkvmagic-workflow")
        try JSONSavedWorkflowStore.writePortableFile(makeWorkflow(), to: target)
        XCTAssertEqual(try JSONSavedWorkflowStore.loadPortableFile(at: target), makeWorkflow())

        let link = rootURL.appendingPathComponent("link.mkvmagic-workflow")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try JSONSavedWorkflowStore.loadPortableFile(at: link)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unsafePath)
        }
    }

    func testMalformedPortableJSONHasStableError() {
        XCTAssertThrowsError(
            try JSONSavedWorkflowStore.decodePortableFile(Data("not json".utf8))
        ) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .malformedWorkflow)
        }
        let unknownAction = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":1,"name":"Clean","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"runAnything"}]}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(unknownAction)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .malformedWorkflow)
        }
    }

    private func makeWorkflow() -> SavedWorkflow {
        SavedWorkflow(
            id: UUID(uuidString: "B989848F-887B-4861-AF7E-ADE3E6E64883")!,
            name: "English library",
            steps: [
                SavedWorkflowStep(
                    id: UUID(uuidString: "22D43583-1382-4778-A4EC-D8618D3A6A4B")!,
                    action: .englishLibraryCleanup
                ),
                SavedWorkflowStep(
                    id: UUID(uuidString: "9F100997-107B-45E7-8F67-A38F740980E4")!,
                    isEnabled: false,
                    action: .removeSegmentTitle
                ),
            ]
        )
    }
}
