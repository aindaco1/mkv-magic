import Foundation
import MKVMagicCore

public enum MKVRemuxPlanningError: Error, Equatable, Sendable {
    case unsupportedContainer
    case alreadyMatroskaMKV
    case invalidDuration
    case missingVideo
    case multipleVideoTracks
    case chapteredWebMRequiresExactHierarchyAudit
    case unsupportedStructure
    case unstableTrackIdentity
    case unsupportedTrack(trackID: Int, codec: String)
}

extension MKVRemuxPlanningError: LocalizedError {
    public var errorDescription: String? { userFacingReason }

    public var userFacingReason: String {
        switch self {
        case .unsupportedContainer:
            "Remux to MKV currently accepts inspected MP4, M4V, MOV, or WebM files."
        case .alreadyMatroskaMKV:
            "This file is already an MKV; choose an MKV editing or cleanup action instead."
        case .invalidDuration:
            "Remux to MKV needs a known positive source duration."
        case .missingVideo:
            "Remux to MKV currently requires one video track."
        case .multipleVideoTracks:
            "Remux to MKV currently requires exactly one video track so cover-art and alternate-video tracks are never guessed."
        case .chapteredWebMRequiresExactHierarchyAudit:
            "Chaptered WebM input needs an exact nested-chapter audit that is not available in this remux path yet."
        case .unsupportedStructure:
            "This file contains data, unknown, or attachment tracks that the zero-encode MKV path cannot preserve safely yet."
        case .unstableTrackIdentity:
            "Every copied media track needs a unique non-negative stream index."
        case .unsupportedTrack(let trackID, let codec):
            MediaCodecFamily(codec: codec, kind: .subtitle) == .timedText
                ? "Subtitle track \(trackID) uses MP4 timed text (TX3G), which needs an explicit text conversion before MKV muxing."
                : "Track \(trackID) uses \(codec), which has not passed the zero-encode MKV compatibility contract."
        }
    }
}

public struct ResolvedMKVRemuxPlan: Hashable, Sendable {
    public let source: MediaAsset
    public let trackIDsInOutputOrder: [Int]
    public let chapterCarrierTrackIDs: [Int]

    public init(
        source: MediaAsset,
        trackIDsInOutputOrder: [Int],
        chapterCarrierTrackIDs: [Int] = []
    ) {
        self.source = source
        self.trackIDsInOutputOrder = trackIDsInOutputOrder
        self.chapterCarrierTrackIDs = chapterCarrierTrackIDs
    }

    public var copiedTrackCount: Int { trackIDsInOutputOrder.count }
    public var videoEncodeCount: Int { 0 }
    public var audioEncodeCount: Int { 0 }
}

public struct MKVRemuxPlanner: Sendable {
    private static let supportedInputExtensions = Set(["mp4", "m4v", "mov", "webm"])

    public init() {}

    public func canOffer(for source: MediaAsset) -> Bool {
        (try? resolve(source: source)) != nil
    }

    public func resolve(source: MediaAsset) throws -> ResolvedMKVRemuxPlan {
        let sourceExtension = source.sourceURL.pathExtension.lowercased()
        guard Self.supportedInputExtensions.contains(sourceExtension) else {
            if sourceExtension == "mkv" { throw MKVRemuxPlanningError.alreadyMatroskaMKV }
            throw MKVRemuxPlanningError.unsupportedContainer
        }
        let container = source.container.lowercased()
        let containerMatchesExtension =
            sourceExtension == "webm"
            ? container.contains("webm")
            : (container.contains("mov") || container.contains("mp4"))
        guard containerMatchesExtension else {
            throw MKVRemuxPlanningError.unsupportedContainer
        }
        guard let duration = source.duration, duration > .zero else {
            throw MKVRemuxPlanningError.invalidDuration
        }
        guard
            sourceExtension != "webm"
                || (source.chapters.isEmpty && (source.chapterEntryCount ?? 0) == 0)
        else {
            throw MKVRemuxPlanningError.chapteredWebMRequiresExactHierarchyAudit
        }
        let chapterCarrierTracks = source.tracks.filter {
            $0.kind == .data
                && $0.codec.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "bin_data"
                && !source.chapters.isEmpty
        }
        let mediaTracks = source.tracks.filter {
            $0.kind == .video || $0.kind == .audio || $0.kind == .subtitle
        }
        let videos = mediaTracks.filter { $0.kind == .video }
        guard !videos.isEmpty else { throw MKVRemuxPlanningError.missingVideo }
        guard videos.count == 1 else { throw MKVRemuxPlanningError.multipleVideoTracks }
        guard source.attachments.isEmpty,
            mediaTracks.count + chapterCarrierTracks.count == source.tracks.count
        else {
            throw MKVRemuxPlanningError.unsupportedStructure
        }
        let allTrackIDs = source.tracks.map(\.id)
        guard allTrackIDs.allSatisfy({ $0 >= 0 }),
            Set(allTrackIDs).count == allTrackIDs.count
        else {
            throw MKVRemuxPlanningError.unstableTrackIdentity
        }
        for track in mediaTracks {
            guard MatroskaPacketCopyPolicy.supports(track) else {
                throw MKVRemuxPlanningError.unsupportedTrack(
                    trackID: track.id,
                    codec: track.codec
                )
            }
        }
        return ResolvedMKVRemuxPlan(
            source: source,
            trackIDsInOutputOrder: mediaTracks.map(\.id),
            chapterCarrierTrackIDs: chapterCarrierTracks.map(\.id)
        )
    }
}
