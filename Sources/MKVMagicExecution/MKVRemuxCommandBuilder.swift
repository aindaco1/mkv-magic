import Foundation
import MKVMagicCore
import MKVMagicPlanning

public enum MKVRemuxCommandError: Error, Equatable, Sendable {
    case unsafePath
    case unsupportedDestination
    case destinationExists
    case inconsistentPlan
}

extension MKVRemuxCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafePath: "Remux to MKV requires safe absolute source and output paths."
        case .unsupportedDestination: "Remux to MKV creates one .mkv output."
        case .destinationExists: "The temporary MKV output already exists."
        case .inconsistentPlan: "The remux command no longer matches the reviewed track order."
        }
    }
}

public struct MKVRemuxCommandBuilder: Sendable {
    public init() {}

    public func build(
        plan: ResolvedMKVRemuxPlan,
        outputURL: URL,
        reviewedChaptersURL: URL? = nil,
        trackLanguageOverrides: [Int: String] = [:],
        externalSubtitle: (url: URL, metadata: ExternalSubtitleTrackMetadata)? = nil,
        additionalExternalSubtitles: [(url: URL, metadata: ExternalSubtitleTrackMetadata)] = []
    ) throws -> [String] {
        let subtitles = (externalSubtitle.map { [$0] } ?? []) + additionalExternalSubtitles
        guard subtitles.count <= ExternalSubtitleBatchPolicy.maximumSubtitlesPerVideo,
            Set(subtitles.map { $0.url.standardizedFileURL }).count == subtitles.count
        else { throw MKVRemuxCommandError.inconsistentPlan }
        let sourceURL = plan.source.sourceURL.standardizedFileURL
        let outputURL = outputURL.standardizedFileURL
        guard safeAbsoluteFilePath(sourceURL), safeAbsoluteFilePath(outputURL),
            sourceURL != outputURL
        else {
            throw MKVRemuxCommandError.unsafePath
        }
        guard outputURL.pathExtension.lowercased() == "mkv" else {
            throw MKVRemuxCommandError.unsupportedDestination
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw MKVRemuxCommandError.destinationExists
        }
        let mediaTrackIDs = plan.source.tracks.filter {
            $0.kind == .video || $0.kind == .audio || $0.kind == .subtitle
        }.map(\.id)
        let chapterCarrierTrackIDs = plan.source.tracks.filter {
            $0.kind == .data
                && $0.codec.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "bin_data"
                && !plan.source.chapters.isEmpty
        }.map(\.id)
        guard !plan.trackIDsInOutputOrder.isEmpty,
            plan.trackIDsInOutputOrder == mediaTrackIDs,
            plan.chapterCarrierTrackIDs == chapterCarrierTrackIDs,
            Set(mediaTrackIDs).count == mediaTrackIDs.count,
            mediaTrackIDs.allSatisfy({ $0 >= 0 })
        else {
            throw MKVRemuxCommandError.inconsistentPlan
        }
        let reviewedChaptersURL = try validatedReviewedChaptersURL(
            reviewedChaptersURL,
            plan: plan,
            sourceURL: sourceURL,
            outputURL: outputURL
        )
        let audioTrackIDs = Set(plan.source.tracks.filter { $0.kind == .audio }.map(\.id))
        guard Set(trackLanguageOverrides.keys).isSubset(of: audioTrackIDs) else {
            throw MKVRemuxCommandError.inconsistentPlan
        }
        var arguments = [
            "--output", outputURL.path,
            "--abort-on-warnings",
            "--flush-on-close",
            "--normalize-language-ietf", "canonical",
            "--disable-track-statistics-tags",
            "--no-buttons",
        ]
        if let reviewedChaptersURL {
            arguments.append(contentsOf: ["--chapters", reviewedChaptersURL.path])
        }
        let trackOrder =
            (plan.trackIDsInOutputOrder.map { "0:\($0)" }
            + subtitles.indices.map { "\($0 + 1):0" }).joined(separator: ",")
        arguments.append(contentsOf: ["--track-order", trackOrder])
        for trackID in plan.trackIDsInOutputOrder where trackLanguageOverrides[trackID] != nil {
            guard let rawLanguage = trackLanguageOverrides[trackID] else { continue }
            let language: String
            do {
                language = try TrackLanguageTag.canonical(rawLanguage)
            } catch {
                throw MKVRemuxCommandError.inconsistentPlan
            }
            arguments.append(contentsOf: ["--language", "\(trackID):\(language)"])
        }
        if reviewedChaptersURL != nil {
            arguments.append("--no-chapters")
        }
        arguments.append(sourceURL.path)
        for externalSubtitle in subtitles {
            let subtitleURL = externalSubtitle.url.standardizedFileURL
            guard safeAbsoluteFilePath(subtitleURL), subtitleURL != sourceURL,
                subtitleURL != outputURL
            else {
                throw MKVRemuxCommandError.unsafePath
            }
            arguments.append(
                contentsOf: try ExternalSubtitleTrackArgumentBuilder.arguments(
                    metadata: externalSubtitle.metadata
                )
            )
            arguments.append(subtitleURL.path)
        }
        return arguments
    }

    private func safeAbsoluteFilePath(_ url: URL) -> Bool {
        let path = url.path
        return url.isFileURL && path.hasPrefix("/") && !path.contains("\0")
            && (1...4_096).contains(path.utf8.count)
    }

    private func validatedReviewedChaptersURL(
        _ candidate: URL?,
        plan: ResolvedMKVRemuxPlan,
        sourceURL: URL,
        outputURL: URL
    ) throws -> URL? {
        guard !plan.source.chapters.isEmpty else {
            guard candidate == nil else { throw MKVRemuxCommandError.inconsistentPlan }
            return nil
        }
        guard let duration = plan.source.duration, let candidate else {
            throw MKVRemuxCommandError.inconsistentPlan
        }
        let url = candidate.standardizedFileURL
        guard safeAbsoluteFilePath(url), url != sourceURL, url != outputURL,
            url.pathExtension.lowercased() == "xml",
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let size = values.fileSize,
            size > 0,
            size <= MatroskaChapterXMLCodec.maximumInputBytes,
            let data = try? Data(contentsOf: url, options: .mappedIfSafe),
            let expected = try? MatroskaChapterDocument.importingInspectedChapters(
                plan.source.chapters,
                sourceID: plan.source.id,
                mediaDuration: duration
            ),
            let parsed = try? MatroskaChapterXMLCodec().parse(data),
            let actualCanonical = try? MatroskaChapterXMLCodec().serialize(parsed),
            let expectedCanonical = try? MatroskaChapterXMLCodec().serialize(expected),
            actualCanonical == expectedCanonical
        else {
            throw MKVRemuxCommandError.inconsistentPlan
        }
        return url
    }
}
