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
                .setTrackLanguage(trackID: 2, language: "eng"),
                .removeTracks([7, 8]),
            ]
        )
        let data = try JSONEncoder().encode(workflow)
        XCTAssertEqual(try JSONDecoder().decode(WorkflowDefinition.self, from: data), workflow)
    }
}
