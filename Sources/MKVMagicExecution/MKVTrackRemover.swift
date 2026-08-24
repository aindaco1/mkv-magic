import Foundation
import MKVMagicCore
import MKVMagicSystem

public enum MKVTrackRemovalError: Error, Equatable, Sendable {
    case emptySelection
    case trackNotFound
    case unstableTrackIdentity
    case unsupportedTrackType
    case allTracksRemoved
    case toolFailed(exitCode: Int32, message: String)
}

extension MKVTrackRemovalError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            "Select at least one track to remove."
        case .trackNotFound:
            "A selected track is no longer present in the inspected file."
        case .unstableTrackIdentity:
            "Every track must have a stable Matroska UID for verified removal."
        case .unsupportedTrackType:
            "This Matroska track type cannot be removed safely yet."
        case .allTracksRemoved:
            "At least one playable track must remain in the output."
        case .toolFailed(let exitCode, let message):
            "mkvmerge could not create the temporary output (code \(exitCode)): \(message)"
        }
    }
}

public struct MKVTrackRemover<Runner: CommandRunning>: Sendable {
    private let executableURL: URL
    private let runner: Runner

    public init(executableURL: URL, runner: Runner) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public func removeTracks(
        from source: MediaAsset,
        removal: TrackRemoval,
        outputURL: URL
    ) async throws {
        let arguments = try Self.arguments(
            source: source,
            removal: removal,
            outputURL: outputURL
        )
        let result = try await runner.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: arguments,
                timeout: 24 * 60 * 60,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0 else {
            let message =
                result.standardError.text.isEmpty
                ? result.standardOutput.text : result.standardError.text
            throw MKVTrackRemovalError.toolFailed(
                exitCode: result.exitCode,
                message: message
            )
        }
    }

    public static func arguments(
        source: MediaAsset,
        removal: TrackRemoval,
        outputURL: URL
    ) throws -> [String] {
        let selection = try MKVTrackSelection(source: source, removal: removal)

        var arguments = [
            "--output", outputURL.path,
            "--abort-on-warnings",
            "--normalize-language-ietf", "canonical",
        ]
        arguments.append(contentsOf: selection.selectorArguments)
        let trackOrder = selection.retainedTracks.map { "0:\($0.id)" }.joined(separator: ",")
        arguments.append(contentsOf: ["--track-order", trackOrder, source.sourceURL.path])
        return arguments
    }
}

struct MKVTrackSelection: Sendable {
    let retainedTracks: [MediaTrack]
    let selectorArguments: [String]

    init(source: MediaAsset, removal: TrackRemoval) throws {
        guard !removal.trackUIDs.isEmpty else { throw MKVTrackRemovalError.emptySelection }
        let playableTracks = source.tracks.filter { $0.kind != .attachment }
        guard playableTracks.allSatisfy({ $0.uid != nil }),
            Set(playableTracks.compactMap(\.uid)).count == playableTracks.count
        else {
            throw MKVTrackRemovalError.unstableTrackIdentity
        }
        let selectedTracks = playableTracks.filter { track in
            track.uid.map(removal.trackUIDs.contains) ?? false
        }
        guard selectedTracks.count == removal.trackUIDs.count else {
            throw MKVTrackRemovalError.trackNotFound
        }
        guard selectedTracks.allSatisfy({ Self.option(for: $0.kind) != nil }) else {
            throw MKVTrackRemovalError.unsupportedTrackType
        }
        retainedTracks = playableTracks.filter { track in
            !selectedTracks.contains(where: { $0.uid == track.uid })
        }
        guard !retainedTracks.isEmpty else { throw MKVTrackRemovalError.allTracksRemoved }

        var arguments = [String]()
        for kind in [MediaTrackKind.video, .audio, .subtitle, .data] {
            let removed = selectedTracks.filter { $0.kind == kind }
            guard !removed.isEmpty, let option = Self.option(for: kind) else { continue }
            let retainedIDs = retainedTracks.filter { $0.kind == kind }.map(\.id)
            if retainedIDs.isEmpty {
                arguments.append(option.none)
            } else {
                arguments.append(contentsOf: [
                    option.some, retainedIDs.map(String.init).joined(separator: ","),
                ])
            }
        }
        selectorArguments = arguments
    }

    private static func option(for kind: MediaTrackKind) -> (some: String, none: String)? {
        switch kind {
        case .video: ("--video-tracks", "--no-video")
        case .audio: ("--audio-tracks", "--no-audio")
        case .subtitle: ("--subtitle-tracks", "--no-subtitles")
        case .data: ("--button-tracks", "--no-buttons")
        case .attachment, .unknown: nil
        }
    }
}
