import Foundation
import MKVMagicCore
import MKVMagicSystem
import XCTest

@testable import MKVMagicExecution

private actor TrackRemovalRequestRecorder {
    private(set) var requests = [CommandRequest]()

    func append(_ request: CommandRequest) {
        requests.append(request)
    }
}

private struct TrackRemovalStubRunner: CommandRunning {
    let recorder: TrackRemovalRequestRecorder

    func run(_ request: CommandRequest) async throws -> CommandResult {
        await recorder.append(request)
        return CommandResult(
            exitCode: 0,
            standardOutput: CommandOutput(data: Data(), wasTruncated: false),
            standardError: CommandOutput(data: Data(), wasTruncated: false)
        )
    }
}

final class MKVTrackRemoverTests: XCTestCase {
    func testRemovalUsesExactShellFreeSelectorsAndPreservesTrackOrder() async throws {
        let recorder = TrackRemovalRequestRecorder()
        let remover = MKVTrackRemover(
            executableURL: URL(fileURLWithPath: "/tools/mkvmerge"),
            runner: TrackRemovalStubRunner(recorder: recorder)
        )
        let source = asset(
            url: URL(fileURLWithPath: "/media/Movie; $(touch nope).mkv"),
            tracks: [
                track(id: 0, kind: .video, uid: 10),
                track(id: 1, kind: .audio, uid: 20),
                track(id: 2, kind: .subtitle, uid: 30),
                track(id: 3, kind: .audio, uid: 40),
            ]
        )
        let output = URL(fileURLWithPath: "/private/working-copy.mkv")

        try await remover.removeTracks(
            from: source,
            removal: TrackRemoval(trackUIDs: [20, 30]),
            outputURL: output
        )

        let requests = await recorder.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.executableURL.path, "/tools/mkvmerge")
        XCTAssertEqual(
            request.arguments,
            [
                "--output", output.path,
                "--abort-on-warnings",
                "--normalize-language-ietf", "canonical",
                "--audio-tracks", "3",
                "--no-subtitles",
                "--track-order", "0:0,0:3",
                source.sourceURL.path,
            ]
        )
    }

    func testRemovalRefusesMissingUnstableAndLastTrack() throws {
        let source = asset(
            tracks: [
                track(id: 0, kind: .video, uid: 10),
                track(id: 1, kind: .audio, uid: 20),
            ]
        )
        XCTAssertThrowsError(
            try MKVTrackRemover<TrackRemovalStubRunner>.arguments(
                source: source,
                removal: TrackRemoval(trackUIDs: [99]),
                outputURL: URL(fileURLWithPath: "/output.mkv")
            )
        ) { error in
            XCTAssertEqual(error as? MKVTrackRemovalError, .trackNotFound)
        }
        XCTAssertThrowsError(
            try MKVTrackRemover<TrackRemovalStubRunner>.arguments(
                source: source,
                removal: TrackRemoval(trackUIDs: [10, 20]),
                outputURL: URL(fileURLWithPath: "/output.mkv")
            )
        ) { error in
            XCTAssertEqual(error as? MKVTrackRemovalError, .allTracksRemoved)
        }
        let unstable = asset(tracks: [track(id: 0, kind: .video, uid: nil)])
        XCTAssertThrowsError(
            try MKVTrackRemover<TrackRemovalStubRunner>.arguments(
                source: unstable,
                removal: TrackRemoval(trackUIDs: [10]),
                outputURL: URL(fileURLWithPath: "/output.mkv")
            )
        ) { error in
            XCTAssertEqual(error as? MKVTrackRemovalError, .unstableTrackIdentity)
        }
    }

    func testTrackAndImageAttachmentRemovalShareOneRemuxSelection() throws {
        let source = asset(
            tracks: [
                track(id: 0, kind: .video, uid: 10),
                track(id: 1, kind: .subtitle, uid: 20),
            ],
            attachments: [
                MediaAttachment(
                    id: 2,
                    filename: "Poster.jpg",
                    mimeType: "image/jpeg",
                    uid: 22
                ),
                MediaAttachment(
                    id: 4,
                    filename: "Subtitle.ttf",
                    mimeType: "font/ttf",
                    uid: 44
                ),
            ]
        )

        let arguments = try MKVTrackRemover<TrackRemovalStubRunner>.arguments(
            source: source,
            removal: TrackRemoval(trackUIDs: [20]),
            attachmentRemoval: MatroskaAttachmentRemoval(attachmentUIDs: [22]),
            outputURL: URL(fileURLWithPath: "/output.mkv")
        )

        XCTAssertEqual(arguments.filter { $0 == "--output" }.count, 1)
        XCTAssertTrue(containsPair("--no-subtitles", "--attachments", in: arguments))
        XCTAssertTrue(containsPair("--attachments", "4", in: arguments))
        XCTAssertTrue(containsPair("--track-order", "0:0", in: arguments))
    }

    private func asset(
        url: URL = URL(fileURLWithPath: "/media/Movie.mkv"),
        tracks: [MediaTrack],
        attachments: [MediaAttachment] = []
    ) -> MediaAsset {
        MediaAsset(
            sourceURL: url,
            container: "matroska",
            tracks: tracks,
            attachments: attachments
        )
    }

    private func track(id: Int, kind: MediaTrackKind, uid: UInt64?) -> MediaTrack {
        MediaTrack(id: id, kind: kind, codec: "fixture", uid: uid)
    }
}

private func containsPair(_ first: String, _ second: String, in values: [String]) -> Bool {
    values.indices.dropLast().contains { values[$0] == first && values[$0 + 1] == second }
}
