import Foundation
import XCTest

@testable import MKVMagicCore

final class MediaQueueReviewedEditTests: XCTestCase {
    private let digest = Data(repeating: 4, count: 32)

    func testReviewIntentsRoundTripAndRejectMalformedContracts() throws {
        let document = MatroskaChapterDocument(editions: [
            .init(chapters: [
                .init(start: .zero, displays: [.init(title: "Opening")])
            ])
        ])
        let reviews: [MediaQueueReviewedEdit] = [
            .trackMetadata(
                sourceSHA256: digest,
                edits: [
                    try TrackMetadataEdit(
                        track: MediaTrack(id: 0, kind: .audio, codec: "aac", uid: 1))
                ]),
            .subtitleExtraction(trackUID: 42, format: .ass, outputSHA256: digest),
            .fastTrim(
                requested: MediaTrimRange(start: .zero, end: MediaTime(nanoseconds: 5)),
                adjusted: MediaTrimRange(start: .zero, end: MediaTime(nanoseconds: 6)),
                sourceChapterSHA256: digest),
            .tagRemoval(sourceSHA256: digest, tagCount: 3),
            .chapters(sourceSHA256: digest, desired: document),
            .subtitleCleanup(
                format: .subRip, sourceSHA256: digest, outputSHA256: digest, restoringIDs: [1, 3]),
            .subtitleCleanup(
                format: .ass, sourceSHA256: digest, outputSHA256: digest, restoringIDs: []),
            .subtitleCleanup(
                format: .ssa, sourceSHA256: digest, outputSHA256: digest, restoringIDs: []),
        ]
        for review in reviews {
            XCTAssertTrue(review.hasCanonicalStructure)
            let intent = MediaQueueWorkflowIntent.reviewedEdit(review)
            XCTAssertEqual(
                try JSONDecoder().decode(
                    MediaQueueWorkflowIntent.self, from: JSONEncoder().encode(intent)), intent)
            XCTAssertNil(intent.savedWorkflow)
            XCTAssertTrue(intent.externalSubtitleReviews.isEmpty)
            XCTAssertEqual(intent.id, review.workflowID)
            XCTAssertEqual(intent.name, review.name)
        }
        for ids in [[-1], [1, 1], [2, 1]] {
            XCTAssertFalse(
                MediaQueueReviewedEdit.subtitleCleanup(
                    format: .subRip, sourceSHA256: digest, outputSHA256: digest, restoringIDs: ids
                ).hasCanonicalStructure)
        }
        XCTAssertFalse(
            MediaQueueReviewedEdit.tagRemoval(sourceSHA256: Data(), tagCount: 1)
                .hasCanonicalStructure)
        XCTAssertFalse(
            MediaQueueReviewedEdit.tagRemoval(sourceSHA256: digest, tagCount: 0)
                .hasCanonicalStructure)
        var invalid = document
        invalid.editions[0].chapters[0].start = MediaTime(nanoseconds: -1)
        XCTAssertFalse(
            MediaQueueReviewedEdit.chapters(sourceSHA256: digest, desired: invalid)
                .hasCanonicalStructure)
        XCTAssertFalse(
            MediaQueueReviewedEdit.subtitleCleanup(
                format: .subRip, sourceSHA256: digest, outputSHA256: Data(), restoringIDs: []
            ).hasCanonicalStructure)
    }

    func testNewReviewContractsRejectMissingIdentityAndUnsafeBounds() throws {
        let edit = try TrackMetadataEdit(
            track: MediaTrack(id: 0, kind: .audio, codec: "aac", uid: 1))
        XCTAssertFalse(
            MediaQueueReviewedEdit.trackMetadata(sourceSHA256: digest, edits: [])
                .hasCanonicalStructure)
        XCTAssertFalse(
            MediaQueueReviewedEdit.trackMetadata(sourceSHA256: digest, edits: [edit, edit])
                .hasCanonicalStructure)
        XCTAssertFalse(
            MediaQueueReviewedEdit.subtitleExtraction(
                trackUID: 0, format: .ass, outputSHA256: digest
            ).hasCanonicalStructure)
        XCTAssertFalse(
            MediaQueueReviewedEdit.subtitleExtraction(
                trackUID: 1, format: .ass, outputSHA256: Data()
            ).hasCanonicalStructure)
        XCTAssertFalse(
            MediaQueueReviewedEdit.fastTrim(
                requested: MediaTrimRange(start: .zero, end: MediaTime(nanoseconds: 5)),
                adjusted: MediaTrimRange(start: .zero, end: MediaTime(nanoseconds: 4)),
                sourceChapterSHA256: digest
            ).hasCanonicalStructure)
    }

    func testAutomaticPolicyRejectsDestructiveOrMismatchedReviewedEdits() {
        let review = MediaQueueReviewedEdit.subtitleCleanup(
            format: .subRip, sourceSHA256: digest, outputSHA256: digest, restoringIDs: [])
        let reference = MediaQueueFileReference(
            displayName: "Source.srt", securityScopedBookmark: Data([1]))
        func job(
            extension ext: String = "srt", disposition: MediaQueueSourceDisposition = .keepOriginal,
            inputs: Int = 1, encodes: Int = 0
        ) -> MediaQueueJob {
            MediaQueueJob(
                createdAt: Date(), workflow: .reviewedEdit(review),
                inputs: Array(repeating: reference, count: inputs),
                destinationDirectory: reference, outputDisplayName: "Output.\(ext)",
                sourceDisposition: disposition,
                reviewedPlan: ExecutionPlan(
                    stages: [],
                    impact: PlanImpact(
                        videoEncodeCount: encodes, audioEncodeCount: 0, copiesVideo: false)))
        }
        XCTAssertTrue(MediaQueueAutomaticWorkflowPolicy.supports(job()))
        XCTAssertFalse(MediaQueueAutomaticWorkflowPolicy.supports(job(extension: "mkv")))
        XCTAssertFalse(
            MediaQueueAutomaticWorkflowPolicy.supports(job(disposition: .trashAfterVerifiedSuccess))
        )
        XCTAssertFalse(MediaQueueAutomaticWorkflowPolicy.supports(job(inputs: 2)))
        XCTAssertFalse(MediaQueueAutomaticWorkflowPolicy.supports(job(encodes: 1)))
    }
}
