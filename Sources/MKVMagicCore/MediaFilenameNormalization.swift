import Foundation

/// A conservative, local-only output naming policy for common release-style
/// movie filenames. It never renames a source and returns `nil` when it cannot
/// make a meaningful suggestion.
public enum MediaFilenameNormalizationPolicy {
    public static func suggestedFilename(for sourceURL: URL) -> String? {
        let originalStem = sourceURL.deletingPathExtension().lastPathComponent
        guard !originalStem.isEmpty, !originalStem.hasPrefix(".") else { return nil }

        let normalizedStem = normalizeStem(originalStem)
        guard !normalizedStem.isEmpty, normalizedStem != originalStem else { return nil }

        let fileExtension = sourceURL.pathExtension
        return fileExtension.isEmpty ? normalizedStem : "\(normalizedStem).\(fileExtension)"
    }

    private static func normalizeStem(_ originalStem: String) -> String {
        var stem = originalStem
        if stem.lowercased().hasSuffix(".clean") {
            stem.removeLast(".clean".count)
        }

        if let existingYear = firstMatch(
            in: stem,
            pattern: #"^(.*?)\((\d{4})\)"#
        ), let year = validYear(existingYear[2]) {
            let title = cleanTitle(existingYear[1])
            return title.isEmpty ? cleanTitle(originalStem) : "\(title) (\(year))"
        }

        if let releaseYear = lastReleaseYear(in: stem) {
            let title = cleanTitle(releaseYear.title)
            return title.isEmpty
                ? cleanTitle(originalStem) : "\(title) (\(releaseYear.year))"
        }

        return cleanTitle(stem)
    }

    private static func cleanTitle(_ value: String) -> String {
        value
            .trimmingCharacters(
                in: CharacterSet(charactersIn: " .-_").union(.whitespacesAndNewlines)
            )
            .replacingOccurrences(of: #"[._]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validYear(_ value: String) -> String? {
        guard let year = Int(value), (1900...2100).contains(year) else { return nil }
        return value
    }

    private static func lastReleaseYear(in value: String) -> (title: String, year: String)? {
        guard
            let expression = try? NSRegularExpression(
                pattern: #"(?:^|[.\s_-])((?:19|20)\d{2}|2100)(?=$|[.\s_-])"#
            )
        else { return nil }
        let searchRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.matches(in: value, range: searchRange).last,
            let fullRange = Range(match.range(at: 0), in: value),
            let yearRange = Range(match.range(at: 1), in: value)
        else { return nil }
        return (String(value[..<fullRange.lowerBound]), String(value[yearRange]))
    }

    private static func firstMatch(in value: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let matchRange = match.range(at: index)
            guard matchRange.location != NSNotFound,
                let range = Range(matchRange, in: value)
            else { return "" }
            return String(value[range])
        }
    }
}
