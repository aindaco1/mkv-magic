import Foundation
import MKVMagicCore
import MKVMagicPlanning

struct CommonMediaSubtitleRemuxPair: Equatable {
    let media: MediaAsset
    let subtitle: MediaAsset
}

enum CommonMediaSubtitleRemuxPresentation {
    static let reviewedWorkflowRecipe = SavedWorkflow(
        id: BuiltInWorkflowCatalog.remuxToMKV,
        name: "Remux video with external subtitle",
        steps: [
            SavedWorkflowStep(
                id: UUID(uuidString: "E7E2F1B5-3393-43A1-8A9E-508E02403B6F")!,
                action: .remuxToMKV
            ),
            SavedWorkflowStep(
                id: UUID(uuidString: "769CA18B-2964-4CDD-AAD4-2B8E2288EBC9")!,
                action: .addExternalSubtitle
            ),
        ]
    )

    static func pair(in assets: [MediaAsset]) -> CommonMediaSubtitleRemuxPair? {
        guard assets.count == 2 else { return nil }
        let media = assets.filter { MKVRemuxPlanner().canOffer(for: $0) }
        let subtitles = assets.filter {
            ["srt", "ass", "ssa"].contains($0.sourceURL.pathExtension.lowercased())
        }
        guard media.count == 1, subtitles.count == 1,
            media[0].id != subtitles[0].id
        else { return nil }
        return CommonMediaSubtitleRemuxPair(media: media[0], subtitle: subtitles[0])
    }

    static func defaultAudioLanguages(for media: MediaAsset) -> [Int: String] {
        let filenameLanguage = FilenameLanguageInference.language(in: media.sourceURL)
        return Dictionary(
            uniqueKeysWithValues: media.tracks.filter { $0.kind == .audio }.map { track in
                let existing = track.language?.trimmingCharacters(in: .whitespacesAndNewlines)
                let language =
                    existing.flatMap { value in
                        value.isEmpty || value.caseInsensitiveCompare("und") == .orderedSame
                            ? nil : value
                    } ?? filenameLanguage ?? "und"
                return (track.id, language)
            }
        )
    }

    static func reviewedWorkflow(
        for media: MediaAsset,
        externalSubtitle: SavedWorkflowExternalSubtitleInput,
        sourceTrackLanguageOverrides: [Int: String]
    ) throws -> (recipe: SavedWorkflow, compiled: CompiledSavedWorkflow) {
        let recipe = reviewedWorkflowRecipe
        return (
            recipe,
            try SavedWorkflowCompiler().compile(
                recipe,
                for: media,
                inputs: SavedWorkflowResolvedInputs(
                    externalSubtitle: externalSubtitle,
                    sourceTrackLanguageOverrides: sourceTrackLanguageOverrides
                )
            )
        )
    }
}
