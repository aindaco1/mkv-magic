import Foundation
import MKVMagicCore
import XCTest

final class AttachmentRemovalTests: XCTestCase {
    private let font = MediaAttachment(
        id: 4,
        filename: "Subtitle Font.ttf",
        mimeType: "font/ttf",
        size: nil,
        uid: 44
    )
    private let poster = MediaAttachment(
        id: 2,
        filename: "Poster.jpg",
        mimeType: "image/jpeg",
        size: 900_000_000,
        uid: 22
    )

    func testResolvesStableUIDSelectionAndRetainsAttachmentOrder() throws {
        let source = asset(attachments: [font, poster])

        XCTAssertEqual(
            MatroskaAttachmentRemovalPolicy.removableAttachments(in: source),
            [poster, font]
        )
        let resolution = try MatroskaAttachmentRemovalPolicy.resolve(
            MatroskaAttachmentRemoval(attachmentUIDs: [22]),
            in: source
        )

        XCTAssertEqual(resolution.removedAttachments, [poster])
        XCTAssertEqual(resolution.retainedAttachments, [font])
    }

    func testAllowsRemovingEveryAttachmentWhenMediaRemains() throws {
        let source = asset(attachments: [font, poster])
        let resolution = try MatroskaAttachmentRemovalPolicy.resolve(
            MatroskaAttachmentRemoval(attachmentUIDs: [22, 44]),
            in: source
        )

        XCTAssertEqual(resolution.removedAttachments, [poster, font])
        XCTAssertTrue(resolution.retainedAttachments.isEmpty)
    }

    func testRejectsUnsupportedAndUnstableAttachmentTables() {
        let nonMatroska = asset(
            path: "/Media/Movie.mp4",
            attachments: [font]
        )
        let duplicateIDs = asset(
            attachments: [font, MediaAttachment(id: 4, filename: "dup", uid: 45)]
        )
        let duplicateUIDs = asset(
            attachments: [font, MediaAttachment(id: 5, filename: "dup", uid: 44)]
        )
        let missingUID = asset(
            attachments: [font, MediaAttachment(id: 5, filename: "unknown", uid: nil)]
        )
        let negativeID = asset(
            attachments: [MediaAttachment(id: -1, filename: "negative", uid: 1)]
        )

        for source in [nonMatroska, duplicateIDs, duplicateUIDs, missingUID, negativeID] {
            XCTAssertTrue(
                MatroskaAttachmentRemovalPolicy.removableAttachments(in: source).isEmpty
            )
        }
    }

    func testRejectsEmptyMissingAndContentEmptyingSelections() {
        let source = asset(attachments: [font])
        XCTAssertThrowsError(
            try MatroskaAttachmentRemovalPolicy.resolve(
                MatroskaAttachmentRemoval(attachmentUIDs: []),
                in: source
            )
        ) { error in
            XCTAssertEqual(error as? MatroskaAttachmentRemovalPolicyError, .emptySelection)
        }
        XCTAssertThrowsError(
            try MatroskaAttachmentRemovalPolicy.resolve(
                MatroskaAttachmentRemoval(attachmentUIDs: [999]),
                in: source
            )
        ) { error in
            XCTAssertEqual(error as? MatroskaAttachmentRemovalPolicyError, .attachmentNotFound)
        }
        let attachmentOnly = asset(attachments: [font], tracks: [])
        XCTAssertThrowsError(
            try MatroskaAttachmentRemovalPolicy.resolve(
                MatroskaAttachmentRemoval(attachmentUIDs: [44]),
                in: attachmentOnly
            )
        ) { error in
            XCTAssertEqual(error as? MatroskaAttachmentRemovalPolicyError, .allContentRemoved)
        }
    }

    private func asset(
        path: String = "/Media/Movie.mkv",
        attachments: [MediaAttachment],
        tracks: [MediaTrack] = [
            MediaTrack(id: 0, kind: .video, codec: "h264", uid: 100)
        ]
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: URL(fileURLWithPath: path),
            container: path.hasSuffix(".mkv") ? "matroska,webm" : "mov,mp4,m4a,3gp,3g2,mj2",
            tracks: tracks,
            attachments: attachments
        )
    }
}
