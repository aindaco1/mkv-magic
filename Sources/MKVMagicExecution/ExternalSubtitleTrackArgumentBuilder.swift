import Foundation
import MKVMagicCore

enum ExternalSubtitleTrackArgumentBuilder {
    static func arguments(
        metadata: ExternalSubtitleTrackMetadata,
        trackID: Int = 0
    ) throws -> [String] {
        let language = try TrackLanguageTag.canonical(metadata.language)
        if let name = metadata.name {
            guard !name.contains("\0"), name.utf8.count <= 4_096 else {
                throw ExternalSubtitleMuxError.invalidTrackName
            }
        }
        var arguments = [
            "--language", "\(trackID):\(language)",
            "--default-track-flag", "\(trackID):\(metadata.isDefault ? "yes" : "no")",
            "--forced-display-flag", "\(trackID):\(metadata.isForced ? "yes" : "no")",
            "--hearing-impaired-flag",
            "\(trackID):\(metadata.isHearingImpaired ? "yes" : "no")",
        ]
        if let name = metadata.name {
            arguments.append(contentsOf: ["--track-name", "\(trackID):\(name)"])
        }
        return arguments
    }
}
