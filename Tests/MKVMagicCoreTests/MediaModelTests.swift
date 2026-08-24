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
                .removeTracksByUID(TrackRemoval(trackUIDs: [42, 84])),
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

    func testPrivateBetaFactsRetainCapabilitiesWithoutPersonalMediaMetadata() throws {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Users/private/Secret Movie.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 7_500_000_000_000),
            fileSize: 2_000_000_000,
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: "hevc",
                    title: "Secret Camera",
                    hdrFormats: ["HDR10"]
                ),
                MediaTrack(id: 1, kind: .audio, codec: "eac3", channels: 6),
                MediaTrack(id: 2, kind: .subtitle, codec: "hdmv_pgs_subtitle"),
                MediaTrack(id: 3, kind: .audio, codec: "A_MPEG/L3", channels: 2),
            ],
            chapters: [
                ChapterNode(title: "Secret Chapter", start: .zero),
                ChapterNode(
                    title: "Secret Parent",
                    start: MediaTime(nanoseconds: 1_000_000_000),
                    children: [
                        ChapterNode(
                            title: "Secret Child",
                            start: MediaTime(nanoseconds: 2_000_000_000)
                        )
                    ]
                ),
            ],
            attachments: [
                MediaAttachment(id: 3, filename: "Secret Font.ttf")
            ],
            metadata: ["title": "Secret Title"],
            warnings: ["Secret warning text"]
        )

        let facts = MediaJobInputFacts(asset: asset)

        XCTAssertEqual(facts.container, .matroska)
        XCTAssertEqual(facts.size, .from1GiBTo10GiB)
        XCTAssertEqual(facts.duration, .over120Minutes)
        XCTAssertEqual(facts.tracks.video, 1)
        XCTAssertEqual(facts.tracks.audio, 2)
        XCTAssertEqual(facts.tracks.subtitle, 1)
        XCTAssertEqual(facts.codecs, [.eac3, .hevc, .mp3, .pgs])
        XCTAssertEqual(MediaCodecFamily(codec: "A_VORBIS", kind: .audio), .vorbis)
        XCTAssertEqual(facts.maximumAudioChannels, 6)
        XCTAssertTrue(facts.hasHDR)
        XCTAssertEqual(facts.chapterCount, 3)
        XCTAssertEqual(facts.attachmentCount, 1)
        XCTAssertTrue(facts.hasTags)
        XCTAssertEqual(facts.warningCount, 1)

        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(facts), encoding: .utf8))
        for secret in ["Secret", "/Users", "Movie.mkv", "HDR10"] {
            XCTAssertFalse(encoded.contains(secret))
        }
    }

    func testOlderHistoryWithoutPrivateBetaFieldsStillDecodes() throws {
        let input = MediaJobInput(displayName: "Movie.mkv")
        let record = MediaJobRecord(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            workflowID: BuiltInWorkflowCatalog.trackRemoval,
            workflowName: "Remove tracks",
            inputs: [input]
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        )
        object.removeValue(forKey: "privacySafePlan")
        var inputs = try XCTUnwrap(object["inputs"] as? [[String: Any]])
        inputs[0].removeValue(forKey: "privacySafeFacts")
        object["inputs"] = inputs

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MediaJobRecord.self, from: oldData)

        XCTAssertNil(decoded.privacySafePlan)
        XCTAssertNil(decoded.inputs.first?.privacySafeFacts)
        XCTAssertEqual(
            BuiltInWorkflowCatalog.kind(for: decoded.workflowID),
            .trackRemoval
        )
        XCTAssertEqual(
            BuiltInWorkflowCatalog.kind(for: BuiltInWorkflowCatalog.advancedSubtitleCleanup),
            .subtitleCleanup
        )
        XCTAssertEqual(
            BuiltInWorkflowCatalog.kind(for: BuiltInWorkflowCatalog.videoTranscode),
            .videoTranscode
        )
        XCTAssertEqual(
            BuiltInWorkflowCatalog.kind(for: BuiltInWorkflowCatalog.remuxToMKV),
            .remuxToMKV
        )
        XCTAssertEqual(
            BuiltInWorkflowCatalog.kind(
                for: BuiltInWorkflowCatalog.timedTextSubtitleConversion
            ),
            .timedTextSubtitleConversion
        )
    }

    func testEnglishLibraryCleanupSuggestionsPreserveAudioCommentaryAndOnlyUsefulSubtitle() {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Movie.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10),
                MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 20, language: "ja"),
                MediaTrack(id: 2, kind: .subtitle, codec: "subrip", uid: 30, language: "eng"),
                MediaTrack(
                    id: 3, kind: .subtitle, codec: "subrip", uid: 40, language: "en",
                    title: "English SDH", isHearingImpaired: true),
                MediaTrack(id: 4, kind: .subtitle, codec: "subrip", uid: 50, language: "fr"),
                MediaTrack(
                    id: 5, kind: .subtitle, codec: "subrip", uid: 60, language: "de",
                    title: "Director Commentary", isCommentary: true),
                MediaTrack(
                    id: 6, kind: .subtitle, codec: "subrip", uid: 70, language: "qaa",
                    title: "Local language"),
                MediaTrack(
                    id: 7, kind: .subtitle, codec: "subrip", uid: 80, language: "it",
                    title: "Signs & Songs"),
            ]
        )

        XCTAssertEqual(
            EnglishLibraryCleanupPolicy.trackSuggestions(for: asset),
            [
                CleanMKVTrackSuggestion(trackUID: 40, reason: .redundantSDH),
                CleanMKVTrackSuggestion(
                    trackUID: 50, reason: .nonEnglishSubtitle(language: "fr")),
            ]
        )
    }

    func testEnglishLibraryCleanupPreservesSoleEnglishSDHSubtitle() {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Movie.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1", uid: 10),
                MediaTrack(
                    id: 1, kind: .subtitle, codec: "subrip", uid: 20, language: "en",
                    title: "English SDH", isHearingImpaired: true),
            ]
        )

        XCTAssertTrue(EnglishLibraryCleanupPolicy.trackSuggestions(for: asset).isEmpty)
    }
}
