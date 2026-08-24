import Foundation
import MKVMagicCore
import MKVMagicPlanning

public enum MKVRemuxVerificationError: Error, Equatable, Sendable {
    case emptyOutput
    case wrongContainer
    case wrongDuration
    case tracksChanged
    case trackMetadataChanged(trackID: Int)
    case chaptersChanged
    case titleChanged
    case unexpectedAttachment
    case invalidSegmentIdentity
}

extension MKVRemuxVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyOutput: "The remuxed MKV is empty."
        case .wrongContainer: "The remux did not create a Matroska MKV."
        case .wrongDuration: "The remuxed duration does not match the source."
        case .tracksChanged: "The remux added, removed, reordered, or changed a media track."
        case .trackMetadataChanged(let trackID):
            "Copied source track \(trackID) lost its reviewed language, name, or playback role."
        case .chaptersChanged: "The remuxed chapter timing or titles do not match the source."
        case .titleChanged: "The remuxed segment title does not match the source title."
        case .unexpectedAttachment: "The remux unexpectedly added an attachment."
        case .invalidSegmentIdentity: "The remuxed MKV does not have one new segment identity."
        }
    }
}

public struct MKVRemuxOutputVerifier: Sendable {
    public init() {}

    public func verify(plan: ResolvedMKVRemuxPlan, output: MediaAsset) throws {
        let source = plan.source
        guard output.fileSize ?? 0 > 0 else { throw MKVRemuxVerificationError.emptyOutput }
        guard output.container.localizedCaseInsensitiveContains("matroska") else {
            throw MKVRemuxVerificationError.wrongContainer
        }
        guard durationsMatch(source.duration, output.duration) else {
            throw MKVRemuxVerificationError.wrongDuration
        }
        let copiedTrackIDs = Set(plan.trackIDsInOutputOrder)
        let sourceTracks = source.tracks.filter { copiedTrackIDs.contains($0.id) }
        let outputTracks = output.tracks.filter { $0.kind != .attachment }
        guard sourceTracks.count == outputTracks.count,
            sourceTracks.map(\.id) == plan.trackIDsInOutputOrder,
            zip(sourceTracks, outputTracks).allSatisfy({
                CopiedTrackTechnicalSnapshot($0) == CopiedTrackTechnicalSnapshot($1)
            })
        else {
            throw MKVRemuxVerificationError.tracksChanged
        }
        for (sourceTrack, outputTrack) in zip(sourceTracks, outputTracks) {
            guard
                CopiedTrackMetadataSnapshot(sourceTrack)
                    == CopiedTrackMetadataSnapshot(outputTrack)
            else {
                throw MKVRemuxVerificationError.trackMetadataChanged(trackID: sourceTrack.id)
            }
        }
        guard chaptersMatch(source.chapters, output.chapters),
            source.chapterEntryCount == nil
                || output.chapterEntryCount == source.chapterEntryCount
        else {
            throw MKVRemuxVerificationError.chaptersChanged
        }
        guard segmentTitle(source) == segmentTitle(output) else {
            throw MKVRemuxVerificationError.titleChanged
        }
        guard output.attachments.isEmpty,
            output.tracks.allSatisfy({ $0.kind != .attachment })
        else {
            throw MKVRemuxVerificationError.unexpectedAttachment
        }
        guard let outputUID = output.segmentUID, !outputUID.isEmpty,
            source.segmentUID == nil || source.segmentUID != outputUID
        else {
            throw MKVRemuxVerificationError.invalidSegmentIdentity
        }
    }

    private func durationsMatch(_ expected: MediaTime?, _ actual: MediaTime?) -> Bool {
        guard let expected, let actual else { return expected == nil && actual == nil }
        let difference = actual.nanoseconds.subtractingReportingOverflow(expected.nanoseconds)
        return !difference.overflow && difference.partialValue.magnitude <= 100_000_000
    }

    private func segmentTitle(_ asset: MediaAsset) -> String? {
        asset.metadata.first {
            $0.key.caseInsensitiveCompare("title") == .orderedSame
        }?.value
    }

    private func chaptersMatch(_ expected: [ChapterNode], _ actual: [ChapterNode]) -> Bool {
        guard expected.count == actual.count else { return false }
        return zip(expected, actual).allSatisfy { expectedChapter, actualChapter in
            expectedChapter.title == actualChapter.title
                && expectedChapter.start == actualChapter.start
                && optionalTimesMatch(expectedChapter.end, actualChapter.end)
                && chaptersMatch(expectedChapter.children, actualChapter.children)
        }
    }

    private func optionalTimesMatch(_ expected: MediaTime?, _ actual: MediaTime?) -> Bool {
        guard let expected, let actual else { return expected == nil && actual == nil }
        let difference = actual.nanoseconds.subtractingReportingOverflow(expected.nanoseconds)
        return !difference.overflow && difference.partialValue.magnitude <= 100_000_000
    }

}

private struct CopiedTrackTechnicalSnapshot: Equatable {
    let kind: MediaTrackKind
    let codec: String
    let profile: String?
    let level: Int?
    let channels: Int?
    let channelLayout: String?
    let sampleRate: Int?
    let dimensions: MediaDimensions?
    let pixelFormat: String?
    let bitDepth: Int?
    let frameRate: String?
    let colorInfo: MediaColorInfo?
    let masteringDisplayMetadata: MediaMasteringDisplayMetadata?
    let contentLightLevelMetadata: MediaContentLightLevelMetadata?
    let hdrFormats: [String]

    init(_ track: MediaTrack) {
        kind = track.kind
        codec = track.codec.lowercased()
        profile = track.profile?.lowercased()
        level = track.level
        channels = track.channels
        channelLayout = track.channelLayout?.lowercased()
        sampleRate = track.sampleRate
        dimensions = track.dimensions
        pixelFormat = track.pixelFormat?.lowercased()
        bitDepth = track.bitDepth
        frameRate = track.frameRate
        colorInfo = track.colorInfo
        masteringDisplayMetadata = track.masteringDisplayMetadata
        contentLightLevelMetadata = track.contentLightLevelMetadata
        hdrFormats = track.hdrFormats.map { $0.lowercased() }.sorted()
    }
}

private struct CopiedTrackMetadataSnapshot: Equatable {
    let language: String
    let title: String
    let isDefault: Bool
    let isForced: Bool
    let isEnabled: Bool
    let isCommentary: Bool
    let isHearingImpaired: Bool
    let isVisualImpaired: Bool
    let isOriginal: Bool
    let isTextDescription: Bool

    init(_ track: MediaTrack) {
        language =
            (try? TrackLanguageTag.canonical(track.language ?? "und"))
            ?? (track.language ?? "und").lowercased()
        title = track.title ?? ""
        isDefault = track.isDefault
        isForced = track.isForced
        isEnabled = track.isEnabled
        isCommentary = track.isCommentary
        isHearingImpaired = track.isHearingImpaired
        isVisualImpaired = track.isVisualImpaired
        isOriginal = track.isOriginal
        isTextDescription = track.isTextDescription
    }
}
