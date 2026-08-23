import Foundation
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

    private func result(exitCode: Int32) -> CommandResult {
        CommandResult(
            exitCode: exitCode,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}
