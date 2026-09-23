import CryptoKit
import Foundation
import MKVMagicCore
import MKVMagicExecution
import MKVMagicSystem

struct ReviewedTrackMetadata {
    let source: MediaAsset
    let edits: [TrackMetadataEdit]
    let sourceRevision: MediaFileRevision

    func intent() throws -> MediaQueueReviewedEdit {
        guard MatroskaEditingPolicy.supports(source), !edits.isEmpty,
            Set(edits.map(\.trackUID)).count == edits.count
        else { throw MKVPropertyEditError.noChanges }
        for edit in edits {
            guard source.tracks.filter({ $0.uid == edit.trackUID }).count == 1,
                let track = source.tracks.first(where: { $0.uid == edit.trackUID }),
                try TrackMetadataEdit(track: track) != edit
            else { throw MKVPropertyEditError.missingTrack }
            _ = try TrackLanguageTag.canonical(edit.language)
        }
        let originals = try source.tracks.filter { $0.uid != nil }.map(TrackMetadataEdit.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return .trackMetadata(
            sourceSHA256: Data(SHA256.hash(data: try encoder.encode(originals))), edits: edits)
    }

    var detail: String {
        edits.compactMap { edit in
            guard let track = source.tracks.first(where: { $0.uid == edit.trackUID }),
                let original = try? TrackMetadataEdit(track: track)
            else { return nil }
            var changes = [String]()
            if edit.name != original.name {
                changes.append("Name: \(original.name ?? "(empty)") → \(edit.name ?? "(empty)")")
            }
            if edit.language != original.language {
                changes.append("Language: \(original.language) → \(edit.language)")
            }
            for flag in TrackMetadataFlag.allCases
            where flag.value(in: edit) != flag.value(in: original) {
                changes.append("\(flag.title): \(flag.value(in: edit) ? "Yes" : "No")")
            }
            return "\(TrackEditorPresentation.label(track))\n  " + changes.joined(separator: "\n  ")
        }.joined(separator: "\n\n")
            + "\n\nEvery unlisted field and track is preserved. No encoding."
    }
}
