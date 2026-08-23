import Foundation
import MKVMagicCore
import MKVMagicSystem

public struct UnifiedMediaInspector<Runner: CommandRunning>: MediaInspecting {
    private let ffprobeInspector: FFprobeInspector<Runner>
    private let mkvToolNixInspector: MKVToolNixInspector<Runner>

    public init(ffprobeURL: URL, mkvmergeURL: URL, runner: Runner) {
        ffprobeInspector = FFprobeInspector(ffprobeURL: ffprobeURL, runner: runner)
        mkvToolNixInspector = MKVToolNixInspector(mkvmergeURL: mkvmergeURL, runner: runner)
    }

    public func inspect(_ inputURL: URL) async throws -> MediaAsset {
        let base = try await ffprobeInspector.inspect(inputURL)
        guard Self.isMatroska(base) else { return base }
        let details = try await mkvToolNixInspector.inspect(inputURL)
        guard details.recognized, details.supported else {
            throw MediaInspectionError.malformedResponse(tool: "mkvmerge")
        }
        return base.merging(details)
    }

    private static func isMatroska(_ asset: MediaAsset) -> Bool {
        let extensions = Set(["mkv", "mka", "mks", "mk3d", "webm"])
        let container = asset.container.lowercased()
        return extensions.contains(asset.sourceURL.pathExtension.lowercased())
            || container.contains("matroska") || container.contains("webm")
    }
}

extension MediaAsset {
    fileprivate func merging(_ details: MKVToolNixInspection) -> MediaAsset {
        var matchedDetailIDs = Set<Int>()
        let sourceTracks = tracks.filter { $0.kind != .attachment }
        let mergedTracks =
            sourceTracks.map { track in
                guard
                    let detail = details.tracks.first(where: {
                        $0.id == track.id && $0.kind == track.kind
                    })
                else {
                    return track
                }
                matchedDetailIDs.insert(detail.id)
                return track.merging(detail)
            } + details.tracks.filter { !matchedDetailIDs.contains($0.id) }

        var mergedMetadata = metadata
        if let title = details.title { mergedMetadata["title"] = title }
        return MediaAsset(
            id: id,
            sourceURL: sourceURL,
            container: container,
            formatLongName: formatLongName ?? details.containerType,
            duration: details.duration ?? duration,
            fileSize: fileSize,
            bitrate: bitrate,
            tracks: mergedTracks,
            chapters: chapters,
            attachments: details.attachments,
            metadata: mergedMetadata,
            chapterEntryCount: details.chapterEntryCount,
            globalTagCount: details.globalTagCount,
            trackTagCount: details.trackTagCount,
            segmentUID: details.segmentUID,
            muxingApplication: details.muxingApplication,
            writingApplication: details.writingApplication,
            warnings: (warnings + details.warnings).uniqued()
        )
    }
}

extension MediaTrack {
    fileprivate func merging(_ detail: MediaTrack) -> MediaTrack {
        MediaTrack(
            id: id,
            kind: kind,
            codec: codec == "unknown" ? detail.codec : codec,
            codecLongName: codecLongName,
            codecID: detail.codecID ?? codecID,
            profile: profile,
            level: level,
            uid: detail.uid ?? uid,
            language: detail.language ?? language,
            title: detail.title ?? title,
            isDefault: detail.isDefault,
            isForced: detail.isForced,
            isEnabled: detail.isEnabled,
            isCommentary: detail.isCommentary || isCommentary,
            isHearingImpaired: detail.isHearingImpaired || isHearingImpaired,
            isVisualImpaired: detail.isVisualImpaired || isVisualImpaired,
            isOriginal: detail.isOriginal || isOriginal,
            isTextDescription: detail.isTextDescription || isTextDescription,
            bitrate: bitrate,
            channels: channels ?? detail.channels,
            channelLayout: channelLayout,
            sampleRate: sampleRate ?? detail.sampleRate,
            dimensions: dimensions ?? detail.dimensions,
            displayDimensions: detail.displayDimensions ?? displayDimensions,
            pixelFormat: pixelFormat,
            bitDepth: bitDepth ?? detail.bitDepth,
            frameRate: frameRate,
            colorInfo: colorInfo,
            hdrFormats: hdrFormats,
            tags: tags
        )
    }
}

extension Array where Element: Hashable {
    fileprivate func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
