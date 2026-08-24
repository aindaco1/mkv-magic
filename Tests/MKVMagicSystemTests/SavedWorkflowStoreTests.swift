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

    func testPortableFileRoundTripsGranularConditionalCleanupActions() throws {
        let workflow = SavedWorkflow(
            name: "Selective cleanup",
            steps: [
                SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                SavedWorkflowStep(action: .removeRedundantEnglishSDH),
            ]
        )

        let encoded = try JSONSavedWorkflowStore.encodePortableFile(workflow)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("removeNonEnglishSubtitles"))
        XCTAssertTrue(json.contains("removeRedundantEnglishSDH"))
        XCTAssertEqual(try JSONSavedWorkflowStore.decodePortableFile(encoded), workflow)
    }

    func testPortableFileRoundTripsInputSlotIntentWithoutAnInputPath() throws {
        let workflow = SavedWorkflow(
            name: "Add a subtitle",
            steps: [
                SavedWorkflowStep(action: .addExternalSubtitle),
                SavedWorkflowStep(action: .cleanExternalSubtitleText),
            ]
        )

        let encoded = try JSONSavedWorkflowStore.encodePortableFile(workflow)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("addExternalSubtitle"))
        XCTAssertTrue(json.contains("cleanExternalSubtitleText"))
        XCTAssertFalse(json.contains("sourceURL"))
        XCTAssertFalse(json.contains("restoringIDs"))
        XCTAssertFalse(json.contains("subtitleText"))
        XCTAssertFalse(json.contains("/private/"))
        XCTAssertEqual(try JSONSavedWorkflowStore.decodePortableFile(encoded), workflow)
    }

    func testPortableFileRoundTripsFilenamePolicyWithoutAConcreteFilename() throws {
        let workflow = SavedWorkflow(
            name: "Jellyfin naming",
            steps: [SavedWorkflowStep(action: .normalizeFilename)]
        )

        let encoded = try JSONSavedWorkflowStore.encodePortableFile(workflow)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("normalizeFilename"))
        XCTAssertFalse(json.contains("suggestedOutputFilename"))
        XCTAssertFalse(json.contains("Movie (2025)"))
        XCTAssertEqual(try JSONSavedWorkflowStore.decodePortableFile(encoded), workflow)
    }

    func testPortableFileStoresConversionIntentWithoutLocalProbeOrEncodingDetails() throws {
        let workflow = SavedWorkflow(
            name: "Recommended conversion",
            steps: [
                SavedWorkflowStep(action: .convertVideoIfNotAV1OrHEVC),
                SavedWorkflowStep(action: .convertAudioFLAC),
            ]
        )

        let encoded = try JSONSavedWorkflowStore.encodePortableFile(workflow)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("convertVideoIfNotAV1OrHEVC"))
        XCTAssertTrue(json.contains("convertAudioFLAC"))
        XCTAssertFalse(json.contains("availableVideoPresets"))
        XCTAssertFalse(json.contains("videoRateControl"))
        XCTAssertFalse(json.contains("encoderTuning"))
        XCTAssertFalse(json.contains("ffmpeg"))
        XCTAssertEqual(try JSONSavedWorkflowStore.decodePortableFile(encoded), workflow)
    }

    func testPortableFileStoresRemuxIntentWithoutResolvedStreamsOrToolDetails() throws {
        let workflow = SavedWorkflow(
            name: "Make an MKV",
            steps: [SavedWorkflowStep(action: .remuxToMKV)]
        )

        let encoded = try JSONSavedWorkflowStore.encodePortableFile(workflow)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("remuxToMKV"))
        XCTAssertFalse(json.contains("trackIDsInOutputOrder"))
        XCTAssertFalse(json.contains("chapterCarrierTrackIDs"))
        XCTAssertFalse(json.contains("mkvmerge"))
        XCTAssertFalse(json.contains("ffmpeg"))
        XCTAssertEqual(try JSONSavedWorkflowStore.decodePortableFile(encoded), workflow)
    }

    func testVersionEightMigratesButCannotClaimVersionNineRemuxAction() throws {
        let valid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":8,"name":"Audio conversion","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"transcodeAllAudioFLAC"}]}"#
                .utf8
        )
        XCTAssertEqual(
            try JSONSavedWorkflowStore.decodePortableFile(valid).schemaVersion,
            SavedWorkflow.currentSchemaVersion
        )

        let invalid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":8,"name":"Invalid remux backport","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"remuxToMKV"}]}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(invalid)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unsupportedSchema)
        }
    }

    func testVersionFiveMigratesButCannotClaimVersionSixAudioAction() throws {
        let valid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":5,"name":"Convert video","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"convertVideoAV1"}]}"#
                .utf8
        )
        XCTAssertEqual(
            try JSONSavedWorkflowStore.decodePortableFile(valid).schemaVersion,
            SavedWorkflow.currentSchemaVersion
        )

        let invalid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":5,"name":"Invalid audio backport","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"convertAudioAAC"}]}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(invalid)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unsupportedSchema)
        }
    }

    func testVersionSixMigratesButCannotClaimVersionSevenConditionalVideoAction() throws {
        let valid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":6,"name":"Convert media","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"convertAudioAAC"}]}"#
                .utf8
        )
        XCTAssertEqual(
            try JSONSavedWorkflowStore.decodePortableFile(valid).schemaVersion,
            SavedWorkflow.currentSchemaVersion
        )

        let invalid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":6,"name":"Invalid condition backport","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"convertVideoIfNotAV1OrHEVC"}]}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(invalid)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unsupportedSchema)
        }
    }

    func testVersionSevenMigratesButCannotClaimVersionEightStandaloneAudioAction() throws {
        let valid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":7,"name":"Conditional video","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"convertVideoIfNotAV1OrHEVC"}]}"#
                .utf8
        )
        XCTAssertEqual(
            try JSONSavedWorkflowStore.decodePortableFile(valid).schemaVersion,
            SavedWorkflow.currentSchemaVersion
        )

        let invalid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":7,"name":"Invalid audio backport","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"transcodeAllAudioFLAC"}]}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(invalid)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unsupportedSchema)
        }
    }

    func testPortableFileRoundTripsStandaloneAudioIntentWithoutEncoderDetails() throws {
        let workflow = SavedWorkflow(
            name: "Lossless audio",
            steps: [SavedWorkflowStep(action: .transcodeAllAudioFLAC)]
        )

        let encoded = try JSONSavedWorkflowStore.encodePortableFile(workflow)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("transcodeAllAudioFLAC"))
        XCTAssertFalse(json.contains("audioCapabilities"))
        XCTAssertFalse(json.contains("encoder"))
        XCTAssertFalse(json.contains("ffmpeg"))
        XCTAssertEqual(try JSONSavedWorkflowStore.decodePortableFile(encoded), workflow)
    }

    func testVersionFourMigratesButCannotClaimVersionFiveConversionAction() throws {
        let valid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":4,"name":"Clean name","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"normalizeFilename"}]}"#
                .utf8
        )
        XCTAssertEqual(
            try JSONSavedWorkflowStore.decodePortableFile(valid).schemaVersion,
            SavedWorkflow.currentSchemaVersion
        )

        let invalid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":4,"name":"Invalid backport","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"convertVideoAV1"}]}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(invalid)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unsupportedSchema)
        }
    }

    func testVersionThreeMigratesButCannotClaimVersionFourFilenameAction() throws {
        let valid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":3,"name":"Clean subtitle","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"cleanExternalSubtitleText"}]}"#
                .utf8
        )
        XCTAssertEqual(
            try JSONSavedWorkflowStore.decodePortableFile(valid).schemaVersion,
            SavedWorkflow.currentSchemaVersion
        )

        let invalid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":3,"name":"Invalid backport","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"normalizeFilename"}]}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(invalid)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unsupportedSchema)
        }
    }

    func testVersionTwoWorkflowMigratesButCannotClaimVersionThreeCleanupAction() throws {
        let valid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":2,"name":"Add subtitle","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"addExternalSubtitle"}]}"#
                .utf8
        )
        XCTAssertEqual(
            try JSONSavedWorkflowStore.decodePortableFile(valid).schemaVersion,
            SavedWorkflow.currentSchemaVersion
        )

        let invalid = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":2,"name":"Invalid backport","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"cleanExternalSubtitleText"}]}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(invalid)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unsupportedSchema)
        }
    }

    func testVersionOnePortableWorkflowMigratesWithoutChangingIntentOrIdentity() throws {
        let data = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":1,"name":"Legacy cleanup","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"removeNonEnglishSubtitles"}]}"#
                .utf8
        )

        let migrated = try JSONSavedWorkflowStore.decodePortableFile(data)

        XCTAssertEqual(migrated.schemaVersion, SavedWorkflow.currentSchemaVersion)
        XCTAssertEqual(
            migrated.id,
            UUID(uuidString: "B989848F-887B-4861-AF7E-ADE3E6E64883")
        )
        XCTAssertEqual(
            migrated.steps.map(\.id),
            [UUID(uuidString: "22D43583-1382-4778-A4EC-D8618D3A6A4B")!]
        )
        XCTAssertEqual(migrated.steps.map(\.action), [.removeNonEnglishSubtitles])
    }

    func testVersionOneCannotClaimTheVersionTwoRuntimeInputAction() {
        let data = Data(
            #"{"id":"B989848F-887B-4861-AF7E-ADE3E6E64883","schemaVersion":1,"name":"Invalid backport","steps":[{"id":"22D43583-1382-4778-A4EC-D8618D3A6A4B","isEnabled":true,"action":"addExternalSubtitle"}]}"#
                .utf8
        )

        XCTAssertThrowsError(try JSONSavedWorkflowStore.decodePortableFile(data)) {
            XCTAssertEqual($0 as? SavedWorkflowStoreError, .unsupportedSchema)
        }
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
