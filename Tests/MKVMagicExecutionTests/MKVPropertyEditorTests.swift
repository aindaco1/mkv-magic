import Foundation
import MKVMagicCore
import MKVMagicPlanning
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor PropertyEditRequestRecorder {
    private(set) var requests: [CommandRequest] = []

    func append(_ request: CommandRequest) {
        requests.append(request)
    }
}

private struct PropertyEditStubRunner: CommandRunning {
    let result: CommandResult
    let recorder: PropertyEditRequestRecorder

    func run(_ request: CommandRequest) async throws -> CommandResult {
        await recorder.append(request)
        return result
    }
}

final class MKVPropertyEditorTests: XCTestCase {
    func testSegmentTitleUsesExactArgumentsWithoutShell() async throws {
        let recorder = PropertyEditRequestRecorder()
        let editor = MKVPropertyEditor(
            executableURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: PropertyEditStubRunner(result: result(exitCode: 0), recorder: recorder)
        )
        let file = URL(fileURLWithPath: "/media/Movie; touch nope.mkv")

        try await editor.editSegmentTitle(at: file, title: "A title; $(touch nope)")

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].executableURL.path, "/tools/mkvpropedit")
        XCTAssertEqual(
            requests[0].arguments,
            [file.path, "--edit", "info", "--set", "title=A title; $(touch nope)"]
        )
    }

    func testNilTitleUsesDeleteAction() async throws {
        let recorder = PropertyEditRequestRecorder()
        let editor = MKVPropertyEditor(
            executableURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: PropertyEditStubRunner(result: result(exitCode: 0), recorder: recorder)
        )

        try await editor.editSegmentTitle(
            at: URL(fileURLWithPath: "/media/Movie.mkv"),
            title: nil
        )

        let requests = await recorder.requests
        XCTAssertEqual(
            requests.first?.arguments,
            ["/media/Movie.mkv", "--edit", "info", "--delete", "title"]
        )
    }

    func testTitleRemovalAndTagClearingShareOneFailClosedInvocation() async throws {
        let recorder = PropertyEditRequestRecorder()
        let editor = MKVPropertyEditor(
            executableURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: PropertyEditStubRunner(result: result(exitCode: 0), recorder: recorder)
        )
        let file = URL(fileURLWithPath: "/media/Movie.mkv")

        try await editor.editSegmentTitle(
            at: file,
            title: nil,
            clearAllTags: true
        )

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            [
                "--abort-on-warnings", file.path,
                "--edit", "info", "--delete", "title",
                "--tags", "all:",
            ]
        )
    }

    func testClearAllTagsUsesNoShellAndRejectsTruncatedDiagnostics() async throws {
        let file = URL(fileURLWithPath: "/media/Movie; touch nope.mkv")
        let successRecorder = PropertyEditRequestRecorder()
        let success = MKVPropertyEditor(
            executableURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: PropertyEditStubRunner(
                result: result(exitCode: 0),
                recorder: successRecorder
            )
        )

        try await success.clearAllTags(at: file)

        let successRequests = await successRecorder.requests
        XCTAssertEqual(
            successRequests.first?.arguments,
            ["--abort-on-warnings", file.path, "--tags", "all:"]
        )

        let truncatedRecorder = PropertyEditRequestRecorder()
        let truncated = MKVPropertyEditor(
            executableURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: PropertyEditStubRunner(
                result: CommandResult(
                    exitCode: 0,
                    standardOutput: CommandOutput(
                        data: Data("incomplete".utf8),
                        wasTruncated: true
                    ),
                    standardError: CommandOutput(data: Data(), wasTruncated: false)
                ),
                recorder: truncatedRecorder
            )
        )
        do {
            try await truncated.clearAllTags(at: file)
            XCTFail("Expected truncated diagnostics to fail closed")
        } catch {
            XCTAssertEqual(
                error as? MKVPropertyEditError,
                .toolFailed(exitCode: 0, message: "incomplete")
            )
        }
    }

    func testOversizedTitleFailsBeforeToolExecution() async throws {
        let recorder = PropertyEditRequestRecorder()
        let editor = MKVPropertyEditor(
            executableURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: PropertyEditStubRunner(result: result(exitCode: 0), recorder: recorder)
        )

        do {
            try await editor.editSegmentTitle(
                at: URL(fileURLWithPath: "/media/Movie.mkv"),
                title: String(repeating: "x", count: 4_097)
            )
            XCTFail("Expected invalid title")
        } catch {
            XCTAssertEqual(error as? MKVPropertyEditError, .invalidTitle)
        }
        let requests = await recorder.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testTrackEditUsesStableUIDCanonicalLanguageAndExactArguments() async throws {
        let recorder = PropertyEditRequestRecorder()
        let editor = MKVPropertyEditor(
            executableURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: PropertyEditStubRunner(result: result(exitCode: 0), recorder: recorder)
        )
        let file = URL(fileURLWithPath: "/media/Movie; touch nope.mkv")
        let original = MediaTrack(
            id: 0,
            kind: .audio,
            codec: "aac",
            uid: 42,
            language: "en",
            title: "Main",
            isDefault: true
        )
        let edit = TrackMetadataEdit(
            trackUID: 42,
            name: "Spanish; $(touch nope)",
            language: "SPA",
            isDefault: false,
            isForced: true,
            isEnabled: true,
            isCommentary: true,
            isHearingImpaired: false,
            isVisualImpaired: false,
            isOriginal: false,
            isTextDescription: false
        )

        try await editor.editTrackMetadata(at: file, originalTrack: original, edit: edit)

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            [
                file.path,
                "--normalize-language-ietf", "canonical",
                "--abort-on-warnings",
                "--edit", "track:=42",
                "--set", "name=Spanish; $(touch nope)",
                "--set", "language=es",
                "--set", "flag-default=0",
                "--set", "flag-forced=1",
                "--set", "flag-commentary=1",
            ]
        )
    }

    func testWorkflowPropertiesFuseMultipleTrackFlagsTitleAndTagsWithoutShell() async throws {
        let recorder = PropertyEditRequestRecorder()
        let editor = MKVPropertyEditor(
            executableURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: PropertyEditStubRunner(result: result(exitCode: 0), recorder: recorder)
        )
        let file = URL(fileURLWithPath: "/media/Movie; touch nope.mkv")
        let tracks = [
            MediaTrack(
                id: 1,
                kind: .audio,
                codec: "aac",
                uid: 11,
                language: "en",
                title: "Director Commentary Audio Description"
            ),
            MediaTrack(
                id: 2,
                kind: .subtitle,
                codec: "subrip",
                uid: 12,
                language: "en",
                title: "Forced SDH Commentary"
            ),
        ]
        let edits = try SavedWorkflowCompiler().compile(
            SavedWorkflow(
                name: "Track roles",
                steps: [
                    SavedWorkflowStep(action: .markCommentaryTracks),
                    SavedWorkflowStep(action: .normalizeCommentaryNames),
                    SavedWorkflowStep(action: .markForcedSubtitles),
                    SavedWorkflowStep(action: .markSDHSubtitles),
                    SavedWorkflowStep(action: .markAudioDescriptionTracks),
                ]
            ),
            for: MediaAsset(sourceURL: file, container: "matroska", tracks: tracks)
        ).trackMetadataEdits

        try await editor.editWorkflowProperties(
            at: file,
            originalTracks: tracks,
            edits: edits,
            removesSegmentTitle: true,
            clearAllTags: true
        )

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            [
                file.path,
                "--normalize-language-ietf", "canonical",
                "--abort-on-warnings",
                "--edit", "info", "--delete", "title",
                "--tags", "all:",
                "--edit", "track:=11", "--set", "name=Commentary",
                "--set", "flag-commentary=1",
                "--set", "flag-visual-impaired=1",
                "--edit", "track:=12", "--set", "name=Commentary",
                "--set", "flag-forced=1", "--set", "flag-commentary=1",
                "--set", "flag-hearing-impaired=1",
            ]
        )
    }

    func testTrackEditRejectsNoopBeforeToolExecution() async throws {
        let recorder = PropertyEditRequestRecorder()
        let editor = MKVPropertyEditor(
            executableURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: PropertyEditStubRunner(result: result(exitCode: 0), recorder: recorder)
        )
        let original = MediaTrack(
            id: 0,
            kind: .subtitle,
            codec: "subrip",
            uid: 42,
            language: "en",
            title: "English"
        )
        let edit = try TrackMetadataEdit(track: original)

        do {
            try await editor.editTrackMetadata(
                at: URL(fileURLWithPath: "/media/Movie.mkv"),
                originalTrack: original,
                edit: edit
            )
            XCTFail("Expected no-op refusal")
        } catch {
            XCTAssertEqual(error as? MKVPropertyEditError, .noChanges)
        }
        let requests = await recorder.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testTrackEditDoesNotRewriteSemanticallyEquivalentLegacyLanguage() async throws {
        let recorder = PropertyEditRequestRecorder()
        let editor = MKVPropertyEditor(
            executableURL: URL(fileURLWithPath: "/tools/mkvpropedit"),
            runner: PropertyEditStubRunner(result: result(exitCode: 0), recorder: recorder)
        )
        let original = MediaTrack(
            id: 0,
            kind: .audio,
            codec: "aac",
            uid: 42,
            language: "eng",
            title: "Main"
        )
        let edit = TrackMetadataEdit(
            trackUID: 42,
            name: "Renamed",
            language: "en",
            isDefault: false,
            isForced: false,
            isEnabled: true,
            isCommentary: false,
            isHearingImpaired: false,
            isVisualImpaired: false,
            isOriginal: false,
            isTextDescription: false
        )

        try await editor.editTrackMetadata(
            at: URL(fileURLWithPath: "/media/Movie.mkv"),
            originalTrack: original,
            edit: edit
        )

        let requests = await recorder.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertFalse(request.arguments.contains("language=en"))
        XCTAssertTrue(request.arguments.contains("name=Renamed"))
    }

    func testLanguageTagCanonicalizationPreservesUsefulBCP47Detail() throws {
        XCTAssertEqual(try TrackLanguageTag.canonical("EN-us"), "en-US")
        XCTAssertEqual(try TrackLanguageTag.canonical("zh-hant-tw"), "zh-Hant-TW")
        XCTAssertEqual(try TrackLanguageTag.canonical("ces"), "cs")
        XCTAssertEqual(try TrackLanguageTag.canonical("cze"), "cs")
        XCTAssertEqual(try TrackLanguageTag.canonical("fil"), "fil")
        XCTAssertEqual(try TrackLanguageTag.canonical("und"), "und")
        XCTAssertThrowsError(try TrackLanguageTag.canonical("en_US"))
        XCTAssertThrowsError(try TrackLanguageTag.canonical("123"))
    }

    private func result(exitCode: Int32) -> CommandResult {
        CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}
