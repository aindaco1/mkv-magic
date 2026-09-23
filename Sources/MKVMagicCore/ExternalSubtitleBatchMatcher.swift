import Foundation

public struct ExternalSubtitleAssociation: Equatable, Sendable {
    public let subtitleID: UUID
    public let suggestedMediaID: UUID?
    public let candidateMediaIDs: [UUID]
    public let confidence: ExternalSubtitleMatchConfidence
}

/// Pure filename association. The UI must still parse each chosen sidecar,
/// display its timing/metadata warnings, and require explicit batch approval.
public enum ExternalSubtitleBatchMatcher {
    public static let maximumInputCount = 500

    public static func associate(media: [MediaAsset], subtitles: [MediaAsset])
        -> [ExternalSubtitleAssociation]
    {
        let matcher = ExternalSubtitleMatcher()
        // Index title words once. Matching a folder must not normalize every
        // unrelated video/subtitle pair (quadratic work for ordinary libraries).
        func words(_ url: URL) -> Set<String> {
            Set(
                FilenameLanguageInference.tokens(url.deletingPathExtension().lastPathComponent)
                    .filter {
                        $0.count >= 3 && Int($0) == nil
                            && !["the", "and", "for"].contains($0)
                            && !FilenameLanguageInference.technicalSuffixTokens.contains($0)
                            && FilenameLanguageInference.languageTokens[$0] == nil
                    })
        }
        var index = [String: Set<Int>]()
        let inputs = media.map { MediaAsset(sourceURL: $0.sourceURL, container: $0.container) }
        for (offset, video) in media.enumerated() {
            for word in words(video.sourceURL) { index[word, default: []].insert(offset) }
        }
        return subtitles.map { subtitle in
            let terms = words(subtitle.sourceURL)
            let candidateIndices =
                terms.isEmpty
                ? Set(media.indices)
                : terms.reduce(into: Set<Int>()) { $0.formUnion(index[$1] ?? []) }
            let ranked = candidateIndices.compactMap { offset -> (UUID, Int, Bool)? in
                let video = media[offset]
                let match = matcher.match(
                    media: inputs[offset],
                    subtitleURL: subtitle.sourceURL, subtitleEnd: SubRipTimestamp(milliseconds: 0))
                guard match.score >= 40 else { return nil }
                let sameFolder =
                    video.sourceURL.deletingLastPathComponent().standardizedFileURL
                    == subtitle.sourceURL.deletingLastPathComponent().standardizedFileURL
                let strong =
                    match.reasons.contains(.exactBasename)
                    || match.reasons.contains(.normalizedTitleAndYear)
                return (video.id, match.score + (sameFolder ? 10 : 0), strong)
            }.sorted { $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1 }
            let best = ranked.first
            // A small ranking difference is not permission to choose between
            // duplicate titles/cuts. Preserve all candidates for manual review.
            let unambiguous =
                best.map { first in
                    first.2 && (ranked.count == 1 || first.1 - ranked[1].1 >= 20)
                } ?? false
            return ExternalSubtitleAssociation(
                subtitleID: subtitle.id,
                suggestedMediaID: unambiguous ? best?.0 : nil,
                candidateMediaIDs: ranked.map(\.0),
                confidence: unambiguous ? .high : (ranked.isEmpty ? .low : .medium))
        }
    }
}
