import Foundation
import MKVMagicCore
import XCTest

final class MatroskaTagTests: XCTestCase {
    func testPolicyRequiresMatroskaKnownNonzeroCounts() throws {
        let supported = asset(global: 2, track: 3)
        XCTAssertEqual(
            try MatroskaTagPolicy.counts(in: supported),
            MatroskaTagCounts(global: 2, track: 3)
        )
        XCTAssertTrue(MatroskaTagPolicy.canOffer(for: supported))

        for (candidate, expected) in [
            (asset(path: "/Media/Movie.mp4", global: 1, track: 0), .unsupportedSource),
            (asset(global: nil, track: 0), .unavailableCounts),
            (asset(global: -1, track: 0), .unavailableCounts),
            (asset(global: 0, track: 0), .noTags),
        ] as [(MediaAsset, MatroskaTagPolicyError)] {
            XCTAssertThrowsError(try MatroskaTagPolicy.counts(in: candidate)) { error in
                XCTAssertEqual(error as? MatroskaTagPolicyError, expected)
            }
            XCTAssertFalse(MatroskaTagPolicy.canOffer(for: candidate))
        }
    }

    func testPolicyRecognizesMKVToolNix101FlattenedTrackStatistics() throws {
        let statistics = [
            "BPS": "548260",
            "_STATISTICS_WRITING_APP": "mkvmerge v101.0",
            "_STATISTICS_TAGS": "BPS DURATION NUMBER_OF_FRAMES NUMBER_OF_BYTES",
        ]
        let supported = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska,webm",
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1", tags: statistics),
                MediaTrack(id: 1, kind: .audio, codec: "aac", tags: statistics),
                MediaTrack(
                    id: 2,
                    kind: .subtitle,
                    codec: "subrip",
                    tags: ["language": "eng"]
                ),
            ],
            globalTagCount: 1,
            trackTagCount: 0
        )

        XCTAssertEqual(
            try MatroskaTagPolicy.counts(in: supported),
            MatroskaTagCounts(global: 1, track: 2)
        )
    }

    func testTagDocumentPreservesExactBytesAndClassifiesTrackTargets() throws {
        let data = tagXML(globalValue: "Film", trackValue: "Lead")
        let document = try MatroskaTagXMLDocument(
            data: data,
            expectedCounts: MatroskaTagCounts(global: 1, track: 1)
        )

        XCTAssertEqual(document.data, data)
        XCTAssertEqual(document.counts, MatroskaTagCounts(global: 1, track: 1))
    }

    func testNestedSimpleTagsDoNotChangeEntryCounts() throws {
        let data = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <Tags>
              <Tag>
                <Targets />
                <Simple><Name>COLLECTION</Name><String>Set</String>
                  <Simple><Name>PART_NUMBER</Name><String>1</String></Simple>
                </Simple>
              </Tag>
            </Tags>
            """.utf8
        )

        XCTAssertEqual(
            try MatroskaTagXMLDocument(data: data).counts,
            MatroskaTagCounts(global: 1, track: 0)
        )
    }

    func testTagDocumentRejectsUnsafeMalformedAndMismatchedInput() {
        let unsafe = Data(
            "<!DOCTYPE Tags [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><Tags>&x;</Tags>".utf8
        )
        let wrongRoot = Data("<Chapters />".utf8)
        let unsupportedRootChild = Data("<Tags><Unknown /></Tags>".utf8)
        let valid = tagXML(globalValue: "Film", trackValue: "Lead")

        assertError(unsafe, .unsafeXML)
        assertError(wrongRoot, .unexpectedRoot)
        assertError(unsupportedRootChild, .unsupportedRootElement("Unknown"))
        XCTAssertThrowsError(
            try MatroskaTagXMLDocument(
                data: valid,
                expectedCounts: MatroskaTagCounts(global: 2, track: 0)
            )
        ) { error in
            XCTAssertEqual(error as? MatroskaTagXMLDocumentError, .countMismatch)
        }
        XCTAssertThrowsError(
            try MatroskaTagXMLDocument(
                data: Data(repeating: 65, count: MatroskaTagXMLDocument.maximumInputBytes + 1)
            )
        ) { error in
            XCTAssertEqual(error as? MatroskaTagXMLDocumentError, .oversizedInput)
        }
    }

    private func assertError(
        _ data: Data,
        _ expected: MatroskaTagXMLDocumentError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try MatroskaTagXMLDocument(data: data), file: file, line: line) {
            error in
            XCTAssertEqual(error as? MatroskaTagXMLDocumentError, expected, file: file, line: line)
        }
    }

    private func asset(
        path: String = "/Media/Movie.mkv",
        global: Int?,
        track: Int?
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: path),
            container: path.hasSuffix(".mkv") ? "matroska,webm" : "mov,mp4,m4a,3gp,3g2,mj2",
            globalTagCount: global,
            trackTagCount: track
        )
    }

    private func tagXML(globalValue: String, trackValue: String) -> Data {
        Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE Tags SYSTEM "matroskatags.dtd">
            <Tags>
              <Tag>
                <Targets />
                <Simple><Name>TITLE</Name><String>\(globalValue)</String></Simple>
              </Tag>
              <Tag>
                <Targets><TrackUID>42</TrackUID></Targets>
                <Simple><Name>TITLE</Name><String>\(trackValue)</String></Simple>
              </Tag>
            </Tags>
            """.utf8
        )
    }
}
