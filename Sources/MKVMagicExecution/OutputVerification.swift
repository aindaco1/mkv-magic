import Foundation
import MKVMagicCore

public enum OutputVerificationError: Error, Equatable, Sendable {
    case emptyOutput
    case titleMismatch
    case trackMetadataMismatch
    case containerChanged
    case durationChanged
    case tracksChanged
    case chaptersChanged
    case attachmentsChanged
    case tagsChanged
    case segmentIdentityChanged
}

extension OutputVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyOutput: "The output is empty."
        case .titleMismatch: "The output segment title does not match the preview."
        case .trackMetadataMismatch: "The edited track metadata does not match the preview."
        case .containerChanged: "The output container changed unexpectedly."
        case .durationChanged: "The output duration changed during a metadata-only edit."
        case .tracksChanged: "One or more tracks changed during a metadata-only edit."
        case .chaptersChanged: "The chapters changed during a metadata-only edit."
        case .attachmentsChanged: "The attachments changed during a metadata-only edit."
        case .tagsChanged: "Unrelated tags changed during a metadata-only edit."
        case .segmentIdentityChanged: "The Matroska segment identity changed unexpectedly."
        }
    }
}

public struct SegmentTitleOutputVerifier: Sendable {
    public init() {}

    public func verify(original: MediaAsset, output: MediaAsset, expectedTitle: String?) throws {
        guard output.metadata.titleValue == expectedTitle else {
            throw OutputVerificationError.titleMismatch
        }
        guard output.tracks == original.tracks else {
            throw OutputVerificationError.tracksChanged
        }
        guard output.metadata.removingTitle == original.metadata.removingTitle,
            output.globalTagCount == original.globalTagCount,
            output.trackTagCount == original.trackTagCount
        else {
            throw OutputVerificationError.tagsChanged
        }
        try verifyPreservedStructure(original: original, output: output)
    }
}

public struct TrackMetadataOutputVerifier: Sendable {
    public init() {}

    public func verify(
        original: MediaAsset,
        output: MediaAsset,
        expectedEdit edit: TrackMetadataEdit
    ) throws {
        guard output.metadata == original.metadata,
            output.globalTagCount == original.globalTagCount,
            output.trackTagCount == original.trackTagCount
        else {
            throw OutputVerificationError.tagsChanged
        }
        guard let originalTrack = original.tracks.first(where: { $0.uid == edit.trackUID }),
            let outputTrack = output.tracks.first(where: { $0.uid == edit.trackUID }),
            original.tracks.filter({ $0.uid == edit.trackUID }).count == 1,
            output.tracks.filter({ $0.uid == edit.trackUID }).count == 1
        else {
            throw OutputVerificationError.tracksChanged
        }
        let unchangedOriginal = original.tracks.filter { $0.uid != edit.trackUID }
        let unchangedOutput = output.tracks.filter { $0.uid != edit.trackUID }
        guard unchangedOutput == unchangedOriginal,
            TrackTechnicalSnapshot(originalTrack) == TrackTechnicalSnapshot(outputTrack)
        else {
            throw OutputVerificationError.tracksChanged
        }
        let expectedLanguage = try TrackLanguageTag.canonical(edit.language)
        let outputLanguage = try TrackLanguageTag.canonical(outputTrack.language ?? "und")
        guard outputTrack.title == edit.name,
            outputLanguage == expectedLanguage,
            outputTrack.isDefault == edit.isDefault,
            outputTrack.isForced == edit.isForced,
            outputTrack.isEnabled == edit.isEnabled,
            outputTrack.isCommentary == edit.isCommentary,
            outputTrack.isHearingImpaired == edit.isHearingImpaired,
            outputTrack.isVisualImpaired == edit.isVisualImpaired,
            outputTrack.isOriginal == edit.isOriginal,
            outputTrack.isTextDescription == edit.isTextDescription
        else {
            throw OutputVerificationError.trackMetadataMismatch
        }
        try verifyPreservedStructure(original: original, output: output)
    }
}

public struct TrackRemovalOutputVerifier: Sendable {
    public init() {}

    public func verify(
        original: MediaAsset,
        output: MediaAsset,
        removal: TrackRemoval,
        segmentTitle: SegmentTitleExpectation = .preserve
    ) throws {
        guard output.fileSize ?? 0 > 0 else { throw OutputVerificationError.emptyOutput }
        guard output.container == original.container else {
            throw OutputVerificationError.containerChanged
        }
        guard remuxDurationsMatch(original.duration, output.duration) else {
            throw OutputVerificationError.durationChanged
        }
        guard output.globalTagCount == original.globalTagCount else {
            throw OutputVerificationError.tagsChanged
        }
        switch segmentTitle {
        case .preserve:
            guard
                output.metadata.removingRemuxProvenance
                    == original.metadata.removingRemuxProvenance
            else {
                throw OutputVerificationError.tagsChanged
            }
        case .set(let expectedTitle):
            guard output.metadata.titleValue == expectedTitle else {
                throw OutputVerificationError.titleMismatch
            }
            guard
                output.metadata.removingTitle.removingRemuxProvenance
                    == original.metadata.removingTitle.removingRemuxProvenance
            else {
                throw OutputVerificationError.tagsChanged
            }
        }
        if let originalTrackTags = original.trackTagCount,
            let outputTrackTags = output.trackTagCount,
            outputTrackTags > originalTrackTags
        {
            throw OutputVerificationError.tagsChanged
        }
        guard output.chapters.chapterSnapshots == original.chapters.chapterSnapshots,
            output.chapterEntryCount == original.chapterEntryCount
        else {
            throw OutputVerificationError.chaptersChanged
        }
        guard output.attachments == original.attachments else {
            throw OutputVerificationError.attachmentsChanged
        }
        guard output.segmentUID != nil,
            original.segmentUID == nil || output.segmentUID != original.segmentUID
        else {
            throw OutputVerificationError.segmentIdentityChanged
        }

        let originalTracks = original.tracks.filter { $0.kind != .attachment }
        let outputTracks = output.tracks.filter { $0.kind != .attachment }
        let expectedTracks = originalTracks.filter { track in
            guard let uid = track.uid else { return true }
            return !removal.trackUIDs.contains(uid)
        }
        guard expectedTracks.count + removal.trackUIDs.count == originalTracks.count,
            outputTracks.compactMap(\.uid) == expectedTracks.compactMap(\.uid),
            outputTracks.map(RemuxTrackSnapshot.init) == expectedTracks.map(RemuxTrackSnapshot.init)
        else {
            throw OutputVerificationError.tracksChanged
        }
    }
}

public struct ExternalSubtitleMuxOutputVerifier: Sendable {
    public init() {}

    public func verify(
        original: MediaAsset,
        output: MediaAsset,
        expectedMetadata: ExternalSubtitleTrackMetadata,
        expectedFormat: ExternalTextSubtitleFormat = .subRip,
        subtitleEnd: SubRipTimestamp
    ) throws {
        guard output.fileSize ?? 0 > 0 else { throw OutputVerificationError.emptyOutput }
        guard output.container.localizedCaseInsensitiveContains("matroska") else {
            throw OutputVerificationError.containerChanged
        }
        guard muxedDurationsMatch(original.duration, output.duration, subtitleEnd: subtitleEnd)
        else {
            throw OutputVerificationError.durationChanged
        }
        guard
            output.metadata.removingRemuxProvenance
                == original.metadata.removingRemuxProvenance,
            output.globalTagCount == original.globalTagCount
        else {
            throw OutputVerificationError.tagsChanged
        }
        guard output.trackTagCount == original.trackTagCount else {
            throw OutputVerificationError.tagsChanged
        }
        guard output.chapters.chapterSnapshots == original.chapters.chapterSnapshots,
            output.chapterEntryCount == original.chapterEntryCount
        else {
            throw OutputVerificationError.chaptersChanged
        }
        guard output.attachments == original.attachments else {
            throw OutputVerificationError.attachmentsChanged
        }
        guard output.segmentUID != nil,
            original.segmentUID == nil || output.segmentUID != original.segmentUID
        else {
            throw OutputVerificationError.segmentIdentityChanged
        }

        let originalTracks = original.tracks.filter { $0.kind != .attachment }
        let outputTracks = output.tracks.filter { $0.kind != .attachment }
        guard outputTracks.count == originalTracks.count + 1,
            outputTracks.dropLast().map(RemuxTrackSnapshot.init)
                == originalTracks.map(RemuxTrackSnapshot.init),
            let added = outputTracks.last,
            added.kind == .subtitle,
            Self.matches(added, expectedFormat: expectedFormat)
        else {
            throw OutputVerificationError.tracksChanged
        }
        let expectedLanguage = try TrackLanguageTag.canonical(expectedMetadata.language)
        let outputLanguage = try TrackLanguageTag.canonical(added.language ?? "und")
        guard outputLanguage == expectedLanguage,
            added.title == expectedMetadata.name,
            added.isDefault == expectedMetadata.isDefault,
            added.isForced == expectedMetadata.isForced,
            added.isHearingImpaired == expectedMetadata.isHearingImpaired,
            added.isEnabled,
            !added.isCommentary,
            !added.isVisualImpaired,
            !added.isOriginal,
            !added.isTextDescription
        else {
            throw OutputVerificationError.trackMetadataMismatch
        }
    }

    private static func matches(
        _ track: MediaTrack,
        expectedFormat: ExternalTextSubtitleFormat
    ) -> Bool {
        let codec = track.codec.lowercased()
        let codecID = track.codecID?.lowercased() ?? ""
        switch expectedFormat {
        case .subRip:
            return codec.contains("subrip") || codec == "srt" || codecID == "s_text/utf8"
        case .ass:
            return codecID == "s_text/ass" || codec == "ass"
        case .ssa:
            return codecID == "s_text/ssa" || codec == "ssa"
        }
    }
}

public enum SegmentTitleExpectation: Equatable, Sendable {
    case preserve
    case set(String?)
}

private func verifyPreservedStructure(original: MediaAsset, output: MediaAsset) throws {
    guard output.fileSize ?? 0 > 0 else { throw OutputVerificationError.emptyOutput }
    guard output.container == original.container else {
        throw OutputVerificationError.containerChanged
    }
    guard durationsMatch(original.duration, output.duration) else {
        throw OutputVerificationError.durationChanged
    }
    guard output.chapters.chapterSnapshots == original.chapters.chapterSnapshots,
        output.chapterEntryCount == original.chapterEntryCount
    else {
        throw OutputVerificationError.chaptersChanged
    }
    guard output.attachments == original.attachments else {
        throw OutputVerificationError.attachmentsChanged
    }
    guard output.segmentUID == original.segmentUID else {
        throw OutputVerificationError.segmentIdentityChanged
    }
}

private func durationsMatch(_ lhs: MediaTime?, _ rhs: MediaTime?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case (.some(let lhs), .some(let rhs)):
        abs(lhs.nanoseconds - rhs.nanoseconds) <= 1_000_000
    default: false
    }
}

private func remuxDurationsMatch(_ lhs: MediaTime?, _ rhs: MediaTime?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case (.some(let lhs), .some(let rhs)):
        // Container duration can move by a final encoded packet during a stream-copy remux.
        abs(lhs.nanoseconds - rhs.nanoseconds) <= 50_000_000
    default: false
    }
}

private func muxedDurationsMatch(
    _ original: MediaTime?,
    _ output: MediaTime?,
    subtitleEnd: SubRipTimestamp
) -> Bool {
    guard let output else { return original == nil && subtitleEnd.milliseconds == 0 }
    let subtitleNanoseconds = subtitleEnd.milliseconds.multipliedReportingOverflow(by: 1_000_000)
    guard !subtitleNanoseconds.overflow else { return false }
    let expected = max(original?.nanoseconds ?? 0, subtitleNanoseconds.partialValue)
    return abs(output.nanoseconds - expected) <= 50_000_000
}

private struct TrackTechnicalSnapshot: Equatable {
    let id: Int
    let kind: MediaTrackKind
    let codec: String
    let codecLongName: String?
    let codecID: String?
    let profile: String?
    let level: Int?
    let uid: UInt64?
    let bitrate: Int64?
    let channels: Int?
    let channelLayout: String?
    let sampleRate: Int?
    let dimensions: MediaDimensions?
    let displayDimensions: MediaDimensions?
    let pixelFormat: String?
    let bitDepth: Int?
    let frameRate: String?
    let colorInfo: MediaColorInfo?
    let hdrFormats: [String]
    let tags: [String: String]

    init(_ track: MediaTrack) {
        id = track.id
        kind = track.kind
        codec = track.codec
        codecLongName = track.codecLongName
        codecID = track.codecID
        profile = track.profile
        level = track.level
        uid = track.uid
        bitrate = track.bitrate
        channels = track.channels
        channelLayout = track.channelLayout
        sampleRate = track.sampleRate
        dimensions = track.dimensions
        displayDimensions = track.displayDimensions
        pixelFormat = track.pixelFormat
        bitDepth = track.bitDepth
        frameRate = track.frameRate
        colorInfo = track.colorInfo
        hdrFormats = track.hdrFormats
        tags = track.tags.removingEditableTrackMetadata
    }
}

private struct RemuxTrackSnapshot: Equatable {
    let kind: MediaTrackKind
    let codec: String
    let codecLongName: String?
    let codecID: String?
    let profile: String?
    let level: Int?
    let uid: UInt64?
    let language: String?
    let title: String?
    let isDefault: Bool
    let isForced: Bool
    let isEnabled: Bool
    let isCommentary: Bool
    let isHearingImpaired: Bool
    let isVisualImpaired: Bool
    let isOriginal: Bool
    let isTextDescription: Bool
    let channels: Int?
    let channelLayout: String?
    let sampleRate: Int?
    let dimensions: MediaDimensions?
    let displayDimensions: MediaDimensions?
    let pixelFormat: String?
    let bitDepth: Int?
    let frameRate: String?
    let colorInfo: MediaColorInfo?
    let hdrFormats: [String]
    let tags: [String: String]

    init(_ track: MediaTrack) {
        kind = track.kind
        codec = track.codec
        codecLongName = track.codecLongName
        codecID = track.codecID
        profile = track.profile
        level = track.level
        uid = track.uid
        language = (try? TrackLanguageTag.canonical(track.language ?? "und")) ?? track.language
        title = track.title
        isDefault = track.isDefault
        isForced = track.isForced
        isEnabled = track.isEnabled
        isCommentary = track.isCommentary
        isHearingImpaired = track.isHearingImpaired
        isVisualImpaired = track.isVisualImpaired
        isOriginal = track.isOriginal
        isTextDescription = track.isTextDescription
        channels = track.channels
        channelLayout = track.channelLayout
        sampleRate = track.sampleRate
        dimensions = track.dimensions
        displayDimensions = track.displayDimensions
        pixelFormat = track.pixelFormat
        bitDepth = track.bitDepth
        frameRate = track.frameRate
        colorInfo = track.colorInfo
        hdrFormats = track.hdrFormats
        tags = track.tags.removingTrackRemuxProvenance
    }
}

private struct ChapterSnapshot: Equatable {
    let title: String
    let start: MediaTime
    let end: MediaTime?
    let language: String?
    let children: [ChapterSnapshot]
}

extension Array where Element == ChapterNode {
    fileprivate var chapterSnapshots: [ChapterSnapshot] {
        map {
            ChapterSnapshot(
                title: $0.title,
                start: $0.start,
                end: $0.end,
                language: $0.language,
                children: $0.children.chapterSnapshots
            )
        }
    }
}

extension Dictionary where Key == String, Value == String {
    fileprivate var titleValue: String? {
        first { $0.key.caseInsensitiveCompare("title") == .orderedSame }?.value
    }

    fileprivate var removingTitle: [String: String] {
        filter { $0.key.caseInsensitiveCompare("title") != .orderedSame }
    }

    fileprivate var removingEditableTrackMetadata: [String: String] {
        filter {
            $0.key.caseInsensitiveCompare("title") != .orderedSame
                && $0.key.caseInsensitiveCompare("language") != .orderedSame
        }
    }

    fileprivate var removingRemuxProvenance: [String: String] {
        filter { key, _ in
            let normalized = key.lowercased()
            return normalized != "encoder"
                && normalized != "creation_time"
        }
    }

    fileprivate var removingTrackRemuxProvenance: [String: String] {
        filter { key, _ in
            let normalized = key.lowercased()
            return normalized != "encoder"
                && normalized != "bps"
                && normalized != "duration"
                && normalized != "number_of_frames"
                && normalized != "number_of_bytes"
                && !normalized.hasPrefix("_statistics_")
        }
    }
}
