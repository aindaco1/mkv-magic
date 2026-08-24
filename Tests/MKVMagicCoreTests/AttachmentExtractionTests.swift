import Foundation
import XCTest

@testable import MKVMagicCore

final class AttachmentExtractionTests: XCTestCase {
    func testExtractableAttachmentsRequireBoundedStableMatroskaIdentities() {
        let font = MediaAttachment(
            id: 3,
            filename: "Font.otf",
            mimeType: "font/otf",
            size: 4_096,
            uid: 33
        )
        let cover = MediaAttachment(
            id: 1,
            filename: "cover.jpg",
            mimeType: "image/jpeg",
            size: 8_192,
            uid: 31
        )
        func asset(
            path: String = "/Media/Movie.mkv",
            attachments: [MediaAttachment]
        ) -> MediaAsset {
            MediaAsset(
                sourceURL: URL(fileURLWithPath: path),
                container: path.hasSuffix(".mkv") ? "matroska" : "mov,mp4",
                attachments: attachments
            )
        }

        XCTAssertEqual(
            MatroskaAttachmentExtractionPolicy.extractableAttachments(
                in: asset(attachments: [font, cover])
            ).map(\.id),
            [1, 3]
        )
        XCTAssertTrue(
            MatroskaAttachmentExtractionPolicy.extractableAttachments(
                in: asset(path: "/Media/Movie.mp4", attachments: [font])
            ).isEmpty
        )
        XCTAssertTrue(
            MatroskaAttachmentExtractionPolicy.extractableAttachments(
                in: asset(
                    attachments: [font, MediaAttachment(id: 3, filename: "dup", size: 2, uid: 34)]
                )
            ).isEmpty
        )
        XCTAssertEqual(
            MatroskaAttachmentExtractionPolicy.extractableAttachments(
                in: asset(
                    attachments: [
                        font,
                        MediaAttachment(id: 4, filename: "empty.bin", size: 0, uid: 44),
                        MediaAttachment(id: 5, filename: "unstable.bin", size: 1, uid: nil),
                    ]
                )
            ),
            [font]
        )
        XCTAssertTrue(
            MatroskaAttachmentExtractionPolicy.extractableAttachments(
                in: asset(
                    attachments: [font, MediaAttachment(id: 4, filename: "dup", size: 2, uid: 33)]
                )
            ).isEmpty
        )
        XCTAssertTrue(
            MatroskaAttachmentExtractionPolicy.extractableAttachments(
                in: asset(
                    attachments: [
                        MediaAttachment(id: 1, filename: "unknown.bin", size: nil, uid: 1),
                        MediaAttachment(id: 2, filename: "empty.bin", size: 0, uid: 2),
                        MediaAttachment(
                            id: 3,
                            filename: "large.bin",
                            size: MatroskaAttachmentExtractionPolicy.maximumAttachmentBytes + 1,
                            uid: 3
                        ),
                        MediaAttachment(id: 4, filename: "unstable.bin", size: 1, uid: nil),
                    ]
                )
            ).isEmpty
        )
    }
}
