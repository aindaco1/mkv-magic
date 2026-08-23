import Foundation
import MKVMagicCore
import MKVMagicPlanning

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

public struct LosslessJoinOutputVerifier: Sendable {
    public init() {}

    public func verify(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        chapters: JoinedChapterComposition,
        output: MediaAsset
    ) throws {
        guard let firstSource = sources.first else {
            throw OutputVerificationError.tracksChanged
        }
        guard output.fileSize ?? 0 > 0 else { throw OutputVerificationError.emptyOutput }
        guard output.container.localizedCaseInsensitiveContains("matroska") else {
            throw OutputVerificationError.containerChanged
        }
        guard let outputDuration = output.duration else {
            throw OutputVerificationError.durationChanged
        }
        let toleranceResult = Int64(sources.count).multipliedReportingOverflow(by: 50_000_000)
        let durationDifference = outputDuration.nanoseconds.subtractingReportingOverflow(
            chapters.duration.nanoseconds
        )
        guard !toleranceResult.overflow,
            !durationDifference.overflow,
            outputDuration.nanoseconds >= 0,
            durationDifference.partialValue.magnitude
                <= UInt64(max(50_000_000, toleranceResult.partialValue))
        else {
            throw OutputVerificationError.durationChanged
        }

        let expectedTracks = try mapping.lanes.map { lane -> MediaTrack in
            guard let firstTrackID = lane.trackIDsBySource.first,
                let trackID = firstTrackID,
                let track = firstSource.tracks.first(where: { $0.id == trackID })
            else {
                throw OutputVerificationError.tracksChanged
            }
            return track
        }
        let outputTracks = output.tracks.filter { $0.kind != .attachment }
        guard
            outputTracks.map(RemuxTrackSnapshot.init)
                == expectedTracks.map(RemuxTrackSnapshot.init)
        else {
            throw OutputVerificationError.tracksChanged
        }
        guard output.attachments.isEmpty else {
            throw OutputVerificationError.attachmentsChanged
        }
        let expectedTopLevelChapterCount = chapters.document.editions.reduce(0) {
            $0 + $1.chapters.count
        }
        guard output.chapterEntryCount == expectedTopLevelChapterCount else {
            throw OutputVerificationError.chaptersChanged
        }
        guard
            output.metadata.removingRemuxProvenance
                == firstSource.metadata.removingRemuxProvenance,
            output.globalTagCount == firstSource.globalTagCount,
            output.trackTagCount == firstSource.trackTagCount
        else {
            throw OutputVerificationError.tagsChanged
        }
        let sourceSegmentUIDs = Set(sources.compactMap(\.segmentUID))
        guard let outputUID = output.segmentUID, !sourceSegmentUIDs.contains(outputUID) else {
            throw OutputVerificationError.segmentIdentityChanged
        }
    }
}

public enum FastTrimVerificationError: Error, Equatable, Sendable {
    case emptyOutput
    case wrongContainer
    case wrongDuration
    case tracksChanged
    case attachmentsChanged
    case metadataChanged
    case chaptersChanged
    case segmentIdentityChanged
}

extension FastTrimVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyOutput: "The trimmed MKV is empty."
        case .wrongContainer: "Fast Trim did not create a Matroska MKV."
        case .wrongDuration: "The trimmed duration does not match the reviewed keyframes."
        case .tracksChanged: "A stream changed during the lossless trim."
        case .attachmentsChanged: "An attachment changed during the lossless trim."
        case .metadataChanged: "Metadata or tags changed outside the reviewed trim."
        case .chaptersChanged: "The trimmed chapter count does not match the reviewed tree."
        case .segmentIdentityChanged: "The trimmed MKV did not receive a new segment identity."
        }
    }
}

public struct FastTrimOutputVerifier: Sendable {
    public init() {}

    public func verify(
        original: MediaAsset,
        plan: FastTrimPlan,
        chapters: MatroskaChapterDocument,
        output: MediaAsset
    ) throws {
        guard output.fileSize ?? 0 > 0 else { throw FastTrimVerificationError.emptyOutput }
        guard output.container.localizedCaseInsensitiveContains("matroska") else {
            throw FastTrimVerificationError.wrongContainer
        }
        guard let duration = output.duration, duration.nanoseconds >= 0 else {
            throw FastTrimVerificationError.wrongDuration
        }
        let difference = duration.nanoseconds.subtractingReportingOverflow(
            plan.adjusted.duration.nanoseconds
        )
        guard !difference.overflow, difference.partialValue.magnitude <= 100_000_000 else {
            throw FastTrimVerificationError.wrongDuration
        }
        let originalTracks = original.tracks.filter { $0.kind != .attachment }
        let outputTracks = output.tracks.filter { $0.kind != .attachment }
        guard
            outputTracks.map(RemuxTrackSnapshot.init)
                == originalTracks.map(RemuxTrackSnapshot.init)
        else {
            throw FastTrimVerificationError.tracksChanged
        }
        guard output.attachments == original.attachments else {
            throw FastTrimVerificationError.attachmentsChanged
        }
        guard
            output.metadata.removingRemuxProvenance
                == original.metadata.removingRemuxProvenance,
            output.globalTagCount == original.globalTagCount,
            output.trackTagCount == original.trackTagCount
        else {
            throw FastTrimVerificationError.metadataChanged
        }
        let expectedTopLevelCount = chapters.editions.reduce(0) {
            $0 + $1.chapters.count
        }
        guard output.chapterEntryCount == expectedTopLevelCount else {
            throw FastTrimVerificationError.chaptersChanged
        }
        guard let outputUID = output.segmentUID,
            original.segmentUID == nil || outputUID != original.segmentUID
        else {
            throw FastTrimVerificationError.segmentIdentityChanged
        }
    }
}

public enum ExactTrimVerificationError: Error, Equatable, Sendable {
    case emptyOutput
    case wrongContainer
    case wrongDuration
    case wrongTrackCount
    case wrongTrackOrder
    case videoMismatch
    case audioMismatch(trackID: Int)
    case trackMetadataMismatch(trackID: Int)
    case attachmentsChanged
    case metadataChanged
    case chaptersChanged
    case segmentIdentityChanged
}

extension ExactTrimVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyOutput: "The exact-trimmed MKV is empty."
        case .wrongContainer: "Exact Trim did not create a Matroska MKV."
        case .wrongDuration: "The exact-trimmed duration does not match the requested range."
        case .wrongTrackCount: "Exact Trim added or removed a media track."
        case .wrongTrackOrder: "Exact Trim changed the reviewed media-track order."
        case .videoMismatch: "The exact-trimmed video does not match its encoding choice."
        case .audioMismatch(let trackID):
            "The exact-trimmed audio for source track \(trackID) changed unexpectedly."
        case .trackMetadataMismatch(let trackID):
            "Track \(trackID) lost reviewed language, name, or disposition metadata."
        case .attachmentsChanged: "Exact Trim did not preserve every attachment."
        case .metadataChanged: "Exact Trim changed unreviewed metadata or tags."
        case .chaptersChanged: "The exact-trimmed chapter count does not match the review."
        case .segmentIdentityChanged:
            "The exact-trimmed MKV did not receive a new segment identity."
        }
    }
}

public struct ExactTrimOutputVerifier: Sendable {
    public init() {}

    public func verify(
        resolvedPlan: ResolvedExactTrimPlan,
        chapters: MatroskaChapterDocument,
        output: MediaAsset
    ) throws {
        let original = resolvedPlan.source
        guard output.fileSize ?? 0 > 0 else { throw ExactTrimVerificationError.emptyOutput }
        guard output.container.localizedCaseInsensitiveContains("matroska") else {
            throw ExactTrimVerificationError.wrongContainer
        }
        let expectedDuration = resolvedPlan.range.end.nanoseconds.subtractingReportingOverflow(
            resolvedPlan.range.start.nanoseconds
        )
        guard !expectedDuration.overflow,
            let actualDuration = output.duration,
            actualDuration.nanoseconds >= 0
        else {
            throw ExactTrimVerificationError.wrongDuration
        }
        let difference = actualDuration.nanoseconds.subtractingReportingOverflow(
            expectedDuration.partialValue
        )
        guard !difference.overflow, difference.partialValue.magnitude <= 100_000_000 else {
            throw ExactTrimVerificationError.wrongDuration
        }

        let originalTracks = original.tracks.filter { $0.kind != .attachment }
        let outputTracks = output.tracks.filter { $0.kind != .attachment }
        guard outputTracks.count == originalTracks.count else {
            throw ExactTrimVerificationError.wrongTrackCount
        }
        guard outputTracks.map(\.kind) == originalTracks.map(\.kind) else {
            throw ExactTrimVerificationError.wrongTrackOrder
        }
        for (sourceTrack, outputTrack) in zip(originalTracks, outputTracks) {
            guard trackMetadataMatches(outputTrack, sourceTrack) else {
                throw ExactTrimVerificationError.trackMetadataMismatch(
                    trackID: sourceTrack.id
                )
            }
            switch sourceTrack.kind {
            case .video:
                guard
                    videoMatches(
                        outputTrack,
                        source: sourceTrack,
                        preset: resolvedPlan.choice.videoPreset
                    )
                else {
                    throw ExactTrimVerificationError.videoMismatch
                }
            case .audio:
                guard
                    audioMatches(
                        outputTrack,
                        source: sourceTrack,
                        policy: resolvedPlan.choice.audioPolicy
                    )
                else {
                    throw ExactTrimVerificationError.audioMismatch(trackID: sourceTrack.id)
                }
            default:
                throw ExactTrimVerificationError.wrongTrackOrder
            }
        }
        try verifyAttachments(original.attachments, output.attachments)
        guard
            output.metadata.removingRemuxProvenance
                == original.metadata.removingRemuxProvenance,
            output.globalTagCount == 0,
            output.trackTagCount == 0
        else {
            throw ExactTrimVerificationError.metadataChanged
        }
        let expectedTopLevelCount = chapters.editions.reduce(0) {
            $0 + $1.chapters.count
        }
        guard output.chapterEntryCount == expectedTopLevelCount else {
            throw ExactTrimVerificationError.chaptersChanged
        }
        guard let outputUID = output.segmentUID,
            original.segmentUID == nil || outputUID != original.segmentUID
        else {
            throw ExactTrimVerificationError.segmentIdentityChanged
        }
    }

    private func videoMatches(
        _ actual: MediaTrack,
        source: MediaTrack,
        preset: VideoPreset
    ) -> Bool {
        let expectedCodec: String
        let expectedBitDepth: Int
        switch preset {
        case .av1Quality:
            expectedCodec = "av1"
            expectedBitDepth = 10
        case .hevcCompatibility:
            expectedCodec = "hevc"
            expectedBitDepth = 10
        case .h264Compatibility:
            expectedCodec = "h264"
            expectedBitDepth = 8
        case .proRes:
            expectedCodec = "prores"
            expectedBitDepth = 10
        }
        return normalized(actual.codec) == expectedCodec
            && actual.dimensions == source.dimensions
            && actual.bitDepth == expectedBitDepth
            && actual.hdrFormats.isEmpty
            && isBT709SDR(actual)
    }

    private func audioMatches(
        _ actual: MediaTrack,
        source: MediaTrack,
        policy: ExactTrimAudioPolicy
    ) -> Bool {
        switch policy {
        case .packetCopy:
            return ExactTrimCopiedAudioSnapshot(actual)
                == ExactTrimCopiedAudioSnapshot(source)
        case .aacPreserveLayout:
            return normalized(actual.codec) == "aac"
                && actual.channels == source.channels
                && actual.sampleRate == source.sampleRate
                && normalized(actual.channelLayout) == normalized(source.channelLayout)
        }
    }

    private func trackMetadataMatches(_ actual: MediaTrack, _ expected: MediaTrack) -> Bool {
        let actualLanguage = try? TrackLanguageTag.canonical(actual.language ?? "und")
        let expectedLanguage = try? TrackLanguageTag.canonical(expected.language ?? "und")
        return actualLanguage == expectedLanguage
            && (actual.title ?? "") == (expected.title ?? "")
            && actual.isDefault == expected.isDefault
            && actual.isForced == expected.isForced
            && actual.isEnabled == expected.isEnabled
            && actual.isCommentary == expected.isCommentary
            && actual.isHearingImpaired == expected.isHearingImpaired
            && actual.isVisualImpaired == expected.isVisualImpaired
            && actual.isOriginal == expected.isOriginal
            && actual.isTextDescription == expected.isTextDescription
    }

    private func verifyAttachments(
        _ expected: [MediaAttachment],
        _ actual: [MediaAttachment]
    ) throws {
        var unmatched = actual
        for attachment in expected {
            guard
                let index = unmatched.firstIndex(where: {
                    $0.filename == attachment.filename
                        && $0.mimeType == attachment.mimeType
                        && $0.size == attachment.size
                        && $0.description == attachment.description
                })
            else {
                throw ExactTrimVerificationError.attachmentsChanged
            }
            unmatched.remove(at: index)
        }
        guard unmatched.isEmpty else {
            throw ExactTrimVerificationError.attachmentsChanged
        }
    }

    private func isBT709SDR(_ track: MediaTrack) -> Bool {
        guard let color = track.colorInfo else { return false }
        return normalized(color.range) == "tv"
            && normalized(color.primaries) == "bt709"
            && normalized(color.transfer) == "bt709"
            && normalized(color.matrix) == "bt709"
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

public enum JoinFinalAssemblyVerificationError: Error, Equatable, Sendable {
    case emptyOutput
    case wrongContainer
    case wrongDuration
    case wrongTracks
    case wrongTrackMetadata(laneIndex: Int)
    case wrongAttachments
    case wrongChapters
    case wrongTitle
    case unexpectedTags
    case invalidSegmentIdentity
    case inconsistentPreview
}

extension JoinFinalAssemblyVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyOutput: "The assembled MKV is empty."
        case .wrongContainer: "The assembled output is not Matroska."
        case .wrongDuration: "The assembled timeline does not match the reviewed join."
        case .wrongTracks: "The assembled track order or stream facts changed."
        case .wrongTrackMetadata(let laneIndex):
            "The assembled metadata for lane \(laneIndex + 1) does not match its reviewed source."
        case .wrongAttachments: "The assembled attachments do not match the reviewed selection."
        case .wrongChapters: "The assembled chapter count does not match the reviewed tree."
        case .wrongTitle: "The assembled segment title does not match the reviewed title."
        case .unexpectedTags: "The assembled MKV contains unreviewed global or track tags."
        case .invalidSegmentIdentity: "The assembled MKV did not receive a new segment identity."
        case .inconsistentPreview: "The final assembly preview is internally inconsistent."
        }
    }
}

public struct JoinFinalAssemblyOutputVerifier: Sendable {
    public init() {}

    public func verify(
        sources: [MediaAsset],
        normalizedBundle: MediaAsset,
        commandLanes: [JoinFinalLaneInput],
        retainedAttachmentIDsBySource: [Int: Set<Int>],
        chapters: JoinedChapterComposition,
        output: MediaAsset
    ) throws {
        guard output.fileSize ?? 0 > 0 else {
            throw JoinFinalAssemblyVerificationError.emptyOutput
        }
        guard output.container.localizedCaseInsensitiveContains("matroska") else {
            throw JoinFinalAssemblyVerificationError.wrongContainer
        }
        try verifyDuration(sources: sources, chapters: chapters, output: output)

        let outputTracks = output.tracks.filter { $0.kind != .attachment }
        guard outputTracks.count == commandLanes.count else {
            throw JoinFinalAssemblyVerificationError.wrongTracks
        }
        for (outputTrack, lane) in zip(outputTracks, commandLanes) {
            let streamSource: MediaTrack
            switch lane.mechanism {
            case .normalized:
                guard
                    let track = normalizedBundle.tracks.first(where: {
                        $0.kind != .attachment && $0.id == lane.inputTrackID
                    })
                else {
                    throw JoinFinalAssemblyVerificationError.inconsistentPreview
                }
                streamSource = track
            case .packetCopy:
                guard let source = sources.first,
                    lane.sourceTrackIDs.first == lane.inputTrackID,
                    let track = source.tracks.first(where: { $0.id == lane.inputTrackID })
                else {
                    throw JoinFinalAssemblyVerificationError.inconsistentPreview
                }
                streamSource = track
            }
            guard
                JoinFinalTrackTechnicalSnapshot(outputTrack)
                    == JoinFinalTrackTechnicalSnapshot(streamSource)
            else {
                throw JoinFinalAssemblyVerificationError.wrongTracks
            }
            guard sources.indices.contains(lane.metadataSourceIndex),
                let metadataTrack = sourceTrack(
                    for: lane.laneIndex,
                    sourceIndex: lane.metadataSourceIndex,
                    sources: sources,
                    commandLanes: commandLanes
                ),
                trackMetadataMatches(outputTrack, metadataTrack)
            else {
                throw JoinFinalAssemblyVerificationError.wrongTrackMetadata(
                    laneIndex: lane.laneIndex
                )
            }
        }

        try verifyAttachments(
            sources: sources,
            retainedIDs: retainedAttachmentIDsBySource,
            output: output
        )
        let expectedTopLevelChapterCount = chapters.document.editions.reduce(0) {
            $0 + $1.chapters.count
        }
        guard output.chapterEntryCount == expectedTopLevelChapterCount else {
            throw JoinFinalAssemblyVerificationError.wrongChapters
        }
        guard let firstSource = sources.first,
            output.metadata.removingRemuxProvenance
                == firstSource.metadata.removingRemuxProvenance
        else {
            throw JoinFinalAssemblyVerificationError.wrongTitle
        }
        guard output.globalTagCount == 0, output.trackTagCount == 0 else {
            throw JoinFinalAssemblyVerificationError.unexpectedTags
        }
        let inputSegmentUIDs = Set(
            (sources + [normalizedBundle]).compactMap(\.segmentUID)
        )
        guard let outputUID = output.segmentUID, !inputSegmentUIDs.contains(outputUID) else {
            throw JoinFinalAssemblyVerificationError.invalidSegmentIdentity
        }
    }

    private func verifyDuration(
        sources: [MediaAsset],
        chapters: JoinedChapterComposition,
        output: MediaAsset
    ) throws {
        var expected: Int64 = 0
        for source in sources {
            guard let duration = source.duration, duration.nanoseconds > 0 else {
                throw JoinFinalAssemblyVerificationError.inconsistentPreview
            }
            let addition = expected.addingReportingOverflow(duration.nanoseconds)
            guard !addition.overflow else {
                throw JoinFinalAssemblyVerificationError.inconsistentPreview
            }
            expected = addition.partialValue
        }
        guard expected == chapters.duration.nanoseconds,
            let actual = output.duration,
            actual.nanoseconds >= 0
        else {
            throw JoinFinalAssemblyVerificationError.wrongDuration
        }
        let difference = actual.nanoseconds.subtractingReportingOverflow(expected)
        let tolerance = Int64(sources.count).multipliedReportingOverflow(by: 50_000_000)
        guard !difference.overflow, !tolerance.overflow,
            difference.partialValue.magnitude
                <= UInt64(max(50_000_000, tolerance.partialValue))
        else {
            throw JoinFinalAssemblyVerificationError.wrongDuration
        }
    }

    private func sourceTrack(
        for laneIndex: Int,
        sourceIndex: Int,
        sources: [MediaAsset],
        commandLanes: [JoinFinalLaneInput]
    ) -> MediaTrack? {
        guard let lane = commandLanes.first(where: { $0.laneIndex == laneIndex }),
            sources.indices.contains(sourceIndex),
            lane.sourceTrackIDs.indices.contains(sourceIndex),
            let trackID = lane.sourceTrackIDs[sourceIndex]
        else { return nil }
        return sources[sourceIndex].tracks.first {
            $0.id == trackID && $0.kind == lane.kind
        }
    }

    private func trackMetadataMatches(_ actual: MediaTrack, _ expected: MediaTrack) -> Bool {
        let actualLanguage = try? TrackLanguageTag.canonical(actual.language ?? "und")
        let expectedLanguage = try? TrackLanguageTag.canonical(expected.language ?? "und")
        return actualLanguage == expectedLanguage
            && (actual.title ?? "") == (expected.title ?? "")
            && actual.isDefault == expected.isDefault
            && actual.isForced == expected.isForced
            && actual.isEnabled == expected.isEnabled
            && actual.isCommentary == expected.isCommentary
            && actual.isHearingImpaired == expected.isHearingImpaired
            && actual.isVisualImpaired == expected.isVisualImpaired
            && actual.isOriginal == expected.isOriginal
            && actual.isTextDescription == expected.isTextDescription
    }

    private func verifyAttachments(
        sources: [MediaAsset],
        retainedIDs: [Int: Set<Int>],
        output: MediaAsset
    ) throws {
        var expected = [MediaAttachment]()
        for (sourceIndex, ids) in retainedIDs {
            guard sources.indices.contains(sourceIndex) else {
                throw JoinFinalAssemblyVerificationError.inconsistentPreview
            }
            for id in ids {
                guard
                    let attachment = sources[sourceIndex].attachments.first(where: {
                        $0.id == id
                    })
                else {
                    throw JoinFinalAssemblyVerificationError.inconsistentPreview
                }
                expected.append(attachment)
            }
        }
        var unmatched = output.attachments
        for attachment in expected {
            guard
                let index = unmatched.firstIndex(where: {
                    $0.filename == attachment.filename
                        && $0.mimeType == attachment.mimeType
                        && $0.size == attachment.size
                        && $0.description == attachment.description
                        && (attachment.uid == nil || $0.uid == attachment.uid)
                })
            else {
                throw JoinFinalAssemblyVerificationError.wrongAttachments
            }
            unmatched.remove(at: index)
        }
        guard unmatched.isEmpty else {
            throw JoinFinalAssemblyVerificationError.wrongAttachments
        }
    }
}

public struct EmbeddedSubtitleReplacementOutputVerifier: Sendable {
    public init() {}

    public func verify(
        original: MediaAsset,
        output: MediaAsset,
        replacedTrackUID: UInt64,
        expectedFormat: ExternalTextSubtitleFormat
    ) throws {
        guard output.fileSize ?? 0 > 0 else { throw OutputVerificationError.emptyOutput }
        guard output.container.localizedCaseInsensitiveContains("matroska") else {
            throw OutputVerificationError.containerChanged
        }
        guard remuxDurationsMatch(original.duration, output.duration) else {
            throw OutputVerificationError.durationChanged
        }
        guard
            output.metadata.removingRemuxProvenance
                == original.metadata.removingRemuxProvenance,
            output.globalTagCount == original.globalTagCount,
            output.trackTagCount == original.trackTagCount
        else {
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
        guard originalTracks.filter({ $0.uid == replacedTrackUID }).count == 1,
            outputTracks.filter({ $0.uid == replacedTrackUID }).count == 1,
            let replaced = outputTracks.first(where: { $0.uid == replacedTrackUID }),
            EmbeddedTextSubtitlePolicy.format(for: replaced) == expectedFormat,
            outputTracks.map(RemuxTrackSnapshot.init)
                == originalTracks.map(RemuxTrackSnapshot.init)
        else {
            throw OutputVerificationError.tracksChanged
        }
    }
}

public struct ChapterReplacementOutputVerifier: Sendable {
    public init() {}

    /// Chapter contents are audited independently through a fresh `mkvextract` round trip.
    public func verify(original: MediaAsset, output: MediaAsset) throws {
        guard output.fileSize ?? 0 > 0 else { throw OutputVerificationError.emptyOutput }
        guard output.container == original.container else {
            throw OutputVerificationError.containerChanged
        }
        guard durationsMatch(original.duration, output.duration) else {
            throw OutputVerificationError.durationChanged
        }
        guard output.tracks == original.tracks else {
            throw OutputVerificationError.tracksChanged
        }
        guard output.metadata == original.metadata,
            output.globalTagCount == original.globalTagCount,
            output.trackTagCount == original.trackTagCount
        else {
            throw OutputVerificationError.tagsChanged
        }
        guard output.attachments == original.attachments else {
            throw OutputVerificationError.attachmentsChanged
        }
        guard output.segmentUID == original.segmentUID else {
            throw OutputVerificationError.segmentIdentityChanged
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

private struct JoinFinalTrackTechnicalSnapshot: Equatable {
    let kind: MediaTrackKind
    let codec: String
    let codecID: String?
    let profile: String?
    let level: Int?
    let uid: UInt64?
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

    init(_ track: MediaTrack) {
        kind = track.kind
        codec = track.codec.lowercased()
        codecID = track.codecID?.lowercased()
        profile = track.profile
        level = track.level
        uid = track.uid
        channels = track.channels
        channelLayout = track.channelLayout?.lowercased()
        sampleRate = track.sampleRate
        dimensions = track.dimensions
        displayDimensions = track.displayDimensions
        pixelFormat = track.pixelFormat?.lowercased()
        bitDepth = track.bitDepth
        frameRate = track.frameRate
        colorInfo = track.colorInfo
        hdrFormats = track.hdrFormats.map { $0.lowercased() }
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

private struct ExactTrimCopiedAudioSnapshot: Equatable {
    let codec: String
    let codecID: String?
    let profile: String?
    let level: Int?
    let channels: Int?
    let channelLayout: String?
    let sampleRate: Int?
    let bitDepth: Int?

    init(_ track: MediaTrack) {
        codec = track.codec.lowercased()
        codecID = track.codecID?.lowercased()
        profile = track.profile
        level = track.level
        channels = track.channels
        channelLayout = track.channelLayout?.lowercased()
        sampleRate = track.sampleRate
        bitDepth = track.bitDepth
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
