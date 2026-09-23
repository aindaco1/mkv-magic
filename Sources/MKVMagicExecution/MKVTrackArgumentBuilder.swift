import Foundation
import MKVMagicCore

enum MKVTrackArgumentError: Error, Equatable, Sendable {
    case invalidTrackID
    case invalidMetadata
}

/// One renderer for mkvmerge's per-track metadata and selection arguments.
/// Final assembly and lossless header normalization must preserve the same
/// language, name, and playback-role contract.
enum MKVTrackArgumentBuilder {
    static func metadata(trackID: Int, track: MediaTrack) throws -> [String] {
        guard trackID >= 0, isSafeText(track.title ?? "") else {
            throw MKVTrackArgumentError.invalidMetadata
        }
        let language: String
        do {
            language = try TrackLanguageTag.canonical(track.language ?? "und")
        } catch {
            throw MKVTrackArgumentError.invalidMetadata
        }
        return [
            "--track-name", "\(trackID):\(track.title ?? "")",
            "--language", "\(trackID):\(language)",
            "--default-track-flag", "\(trackID):\(flag(track.isDefault))",
            "--forced-display-flag", "\(trackID):\(flag(track.isForced))",
            "--track-enabled-flag", "\(trackID):\(flag(track.isEnabled))",
            "--commentary-flag", "\(trackID):\(flag(track.isCommentary))",
            "--hearing-impaired-flag", "\(trackID):\(flag(track.isHearingImpaired))",
            "--visual-impaired-flag", "\(trackID):\(flag(track.isVisualImpaired))",
            "--original-flag", "\(trackID):\(flag(track.isOriginal))",
            "--text-descriptions-flag", "\(trackID):\(flag(track.isTextDescription))",
        ]
    }

    static func selection(tracks: [MediaTrack]) throws -> [String] {
        guard tracks.allSatisfy({ $0.id >= 0 }) else {
            throw MKVTrackArgumentError.invalidTrackID
        }
        var arguments = [String]()
        for (kind, some, none) in [
            (MediaTrackKind.video, "--video-tracks", "--no-video"),
            (.audio, "--audio-tracks", "--no-audio"),
            (.subtitle, "--subtitle-tracks", "--no-subtitles"),
        ] {
            let ids = tracks.filter { $0.kind == kind }.map(\.id)
            if ids.isEmpty {
                arguments.append(none)
            } else {
                arguments.append(contentsOf: [some, ids.map(String.init).joined(separator: ",")])
            }
        }
        return arguments
    }

    static func isSafeText(_ value: String) -> Bool {
        !value.contains("\0") && value.utf8.count <= 4_096
    }

    private static func flag(_ value: Bool) -> String { value ? "1" : "0" }
}
