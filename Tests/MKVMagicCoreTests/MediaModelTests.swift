import Foundation
import XCTest

@testable import MKVMagicCore

final class MediaModelTests: XCTestCase {
    func testMediaTimeUsesNanosecondRoundTrip() throws {
        let time = try XCTUnwrap(MediaTime(seconds: 12.345_678_901))
        XCTAssertEqual(time.nanoseconds, 12_345_678_901)
        XCTAssertEqual(time.seconds, 12.345_678_901, accuracy: 0.000_000_001)
    }

    func testMediaTimeRejectsNonFiniteSeconds() {
        XCTAssertNil(MediaTime(seconds: .infinity))
        XCTAssertNil(MediaTime(seconds: .nan))
    }

    func testPortableWorkflowRoundTrips() throws {
        let workflow = WorkflowDefinition(
            id: UUID(uuidString: "F3604102-3985-44FC-AD8A-97A8796D3D14")!,
            name: "Library cleanup",
            operations: [
                .editSegmentTitle(nil),
                .editTrackMetadata(
                    TrackMetadataEdit(
                        trackUID: 42,
                        name: "English Commentary",
                        language: "en",
                        isDefault: false,
                        isForced: false,
                        isEnabled: true,
                        isCommentary: true,
                        isHearingImpaired: false,
                        isVisualImpaired: false,
                        isOriginal: true,
                        isTextDescription: false
                    )),
                .setTrackLanguage(trackID: 2, language: "eng"),
                .removeTracks([7, 8]),
            ]
        )
        let data = try JSONEncoder().encode(workflow)
        XCTAssertEqual(try JSONDecoder().decode(WorkflowDefinition.self, from: data), workflow)
    }

    func testMediaJobStateMachineRequiresVerifiedCommitBeforeSuccess() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        var job = MediaJobRecord(
            createdAt: created,
            workflowID: UUID(uuidString: "E1D5D2AD-31D5-4AF0-A490-9D6F25E7C8F7")!,
            workflowName: "Clean MKV",
            inputs: [
                MediaJobInput(
                    displayName: "Movie.mkv",
                    bookmarkID: UUID(uuidString: "1050CCB1-5C27-4344-B5DF-837976B7317D")!
                )
            ]
        )
        for (offset, state) in [
            MediaJobState.inspecting, .planned, .ready, .running, .verifying, .committing,
            .succeeded,
        ].enumerated() {
            try job.transition(
                to: state,
                at: created.addingTimeInterval(Double(offset + 1)))
        }

        XCTAssertEqual(job.state, .succeeded)
        XCTAssertTrue(job.state.isTerminal)
        XCTAssertThrowsError(
            try job.transition(to: .running, at: created.addingTimeInterval(10))
        ) {
            XCTAssertEqual(
                $0 as? MediaJobTransitionError,
                .terminalState(.succeeded)
            )
        }
        XCTAssertEqual(
            try JSONDecoder().decode(MediaJobRecord.self, from: JSONEncoder().encode(job)), job)
    }

    func testMediaJobCannotSkipVerification() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        var job = MediaJobRecord(
            createdAt: created,
            workflowID: UUID(),
            workflowName: "Clean MKV",
            inputs: [MediaJobInput(displayName: "Movie.mkv", bookmarkID: UUID())]
        )

        XCTAssertThrowsError(
            try job.transition(to: .succeeded, at: created.addingTimeInterval(1))
        ) {
            XCTAssertEqual(
                $0 as? MediaJobTransitionError,
                .invalidTransition(from: .queued, to: .succeeded)
            )
        }
    }

    func testJobInputCanTruthfullyOmitUnavailableSecurityBookmark() throws {
        let input = MediaJobInput(displayName: "Movie.mkv")

        XCTAssertNil(input.bookmarkID)
        XCTAssertEqual(
            try JSONDecoder().decode(MediaJobInput.self, from: JSONEncoder().encode(input)),
            input
        )
    }
}
