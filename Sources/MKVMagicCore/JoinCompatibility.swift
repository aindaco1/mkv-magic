import Foundation

public struct JoinTrackLane: Equatable, Hashable, Sendable {
    public let kind: MediaTrackKind
    public let trackIDsBySource: [Int?]

    public init(kind: MediaTrackKind, trackIDsBySource: [Int?]) {
        self.kind = kind
        self.trackIDsBySource = trackIDsBySource
    }
}

public struct JoinTrackMapping: Equatable, Hashable, Sendable {
    public let lanes: [JoinTrackLane]

    public init(lanes: [JoinTrackLane]) {
        self.lanes = lanes
    }
}

public struct JoinTrackMappingAmbiguity: Equatable, Hashable, Sendable {
    public let sourceIndex: Int
    public let kind: MediaTrackKind
    public let trackIDs: [Int]
    public let candidateLaneIndices: [Int]

    public init(
        sourceIndex: Int,
        kind: MediaTrackKind,
        trackIDs: [Int],
        candidateLaneIndices: [Int]
    ) {
        self.sourceIndex = sourceIndex
        self.kind = kind
        self.trackIDs = trackIDs
        self.candidateLaneIndices = candidateLaneIndices
    }
}

public struct JoinTrackMappingProposal: Equatable, Sendable {
    public let mapping: JoinTrackMapping
    public let ambiguities: [JoinTrackMappingAmbiguity]

    public init(mapping: JoinTrackMapping, ambiguities: [JoinTrackMappingAmbiguity]) {
        self.mapping = mapping
        self.ambiguities = ambiguities
    }
}

public enum JoinAppendDisposition: String, Equatable, Hashable, Sendable {
    case losslessCandidate
    case confirmationRequired
    case normalizationRequired
    case unsupported
}

public enum JoinCompatibilityIssueSeverity: String, Equatable, Hashable, Sendable {
    case confirmationRequired
    case normalizationRequired
    case unsupported
}

public enum JoinCompatibilityIssueReason: String, Equatable, Hashable, Sendable {
    case nonMatroskaSource
    case attachmentSelection
    case unsupportedTrackKind
    case missingTrack
    case codec
    case profile
    case level
    case dimensions
    case displayDimensions
    case pixelFormat
    case bitDepth
    case frameRate
    case color
    case hdr
    case sampleRate
    case channels
    case channelLayout
    case language
    case role
    case title
    case flags
    case incompleteParameters
}

public struct JoinCompatibilityIssue: Equatable, Hashable, Sendable {
    public let severity: JoinCompatibilityIssueSeverity
    public let reason: JoinCompatibilityIssueReason
    public let laneIndex: Int?
    public let referenceSourceIndex: Int?
    public let sourceIndex: Int
    public let trackID: Int?

    public init(
        severity: JoinCompatibilityIssueSeverity,
        reason: JoinCompatibilityIssueReason,
        laneIndex: Int? = nil,
        referenceSourceIndex: Int? = nil,
        sourceIndex: Int,
        trackID: Int? = nil
    ) {
        self.severity = severity
        self.reason = reason
        self.laneIndex = laneIndex
        self.referenceSourceIndex = referenceSourceIndex
        self.sourceIndex = sourceIndex
        self.trackID = trackID
    }
}

public struct JoinCompatibilityReport: Equatable, Sendable {
    public let mapping: JoinTrackMapping
    public let disposition: JoinAppendDisposition
    public let issues: [JoinCompatibilityIssue]
    /// Static inspection cannot reproduce every codec-specific packetizer check.
    public let requiresAuthoritativeMKVToolNixValidation: Bool

    public init(
        mapping: JoinTrackMapping,
        disposition: JoinAppendDisposition,
        issues: [JoinCompatibilityIssue],
        requiresAuthoritativeMKVToolNixValidation: Bool
    ) {
        self.mapping = mapping
        self.disposition = disposition
        self.issues = issues
        self.requiresAuthoritativeMKVToolNixValidation =
            requiresAuthoritativeMKVToolNixValidation
    }
}

public enum JoinTrackMappingError: Error, Equatable, Sendable {
    case invalidSourceCount
    case tooManyTracks
    case duplicateTrackID(sourceIndex: Int, trackID: Int)
    case emptyMapping
    case emptyLane(laneIndex: Int)
    case invalidLaneWidth(laneIndex: Int)
    case unsupportedLaneKind(laneIndex: Int)
    case missingTrack(sourceIndex: Int, trackID: Int)
    case kindMismatch(sourceIndex: Int, trackID: Int)
    case duplicateAssignment(sourceIndex: Int, trackID: Int)
    case unmappedTrack(sourceIndex: Int, trackID: Int)
}

extension JoinTrackMappingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidSourceCount: "A joined group needs between 2 and 1,000 sources."
        case .tooManyTracks: "The joined group has too many tracks to map safely."
        case .duplicateTrackID: "A source contains duplicate track identifiers."
        case .emptyMapping: "Map at least one video, audio, or subtitle track."
        case .emptyLane: "A track lane cannot be empty for every source."
        case .invalidLaneWidth: "Every track lane must have one position per source."
        case .unsupportedLaneKind: "Only video, audio, and subtitle tracks can be appended."
        case .missingTrack: "A mapped track does not exist in its source."
        case .kindMismatch: "A mapped track does not match its lane type."
        case .duplicateAssignment: "A source track cannot be assigned to multiple lanes."
        case .unmappedTrack: "Every video, audio, and subtitle track needs an explicit lane."
        }
    }
}

/// Proposes a complete mapping without guessing between indistinguishable tracks.
/// Unresolved tracks receive their own lane so they remain visible for review.
public struct JoinTrackMappingProposer: Sendable {
    public init() {}

    public func propose(sources: [MediaAsset]) throws -> JoinTrackMappingProposal {
        let indexedTracks = try JoinTrackSourceIndex.make(sources: sources)
        var lanes = sources[0].tracks.compactMap { track -> MutableJoinTrackLane? in
            guard JoinTrackPolicy.appendableKinds.contains(track.kind) else { return nil }
            return MutableJoinTrackLane(kind: track.kind, trackIDsBySource: [track.id])
        }
        var ambiguities = [JoinTrackMappingAmbiguity]()

        for sourceIndex in sources.indices.dropFirst() {
            for laneIndex in lanes.indices {
                lanes[laneIndex].trackIDsBySource.append(nil)
            }
            var remainingTrackIDs = Set(
                sources[sourceIndex].tracks
                    .filter { JoinTrackPolicy.appendableKinds.contains($0.kind) }
                    .map(\.id)
            )

            assignUniqueFullMatches(
                sourceIndex: sourceIndex,
                indexedTracks: indexedTracks,
                lanes: &lanes,
                remainingTrackIDs: &remainingTrackIDs
            )
            assignUniqueSemanticMatches(
                sourceIndex: sourceIndex,
                indexedTracks: indexedTracks,
                lanes: &lanes,
                remainingTrackIDs: &remainingTrackIDs
            )
            assignOnlyRemainingKindMatches(
                sourceIndex: sourceIndex,
                indexedTracks: indexedTracks,
                lanes: &lanes,
                remainingTrackIDs: &remainingTrackIDs
            )

            for kind in [MediaTrackKind.video, .audio, .subtitle] {
                let unresolved = sources[sourceIndex].tracks.filter {
                    $0.kind == kind && remainingTrackIDs.contains($0.id)
                }
                guard !unresolved.isEmpty else { continue }
                let candidates = lanes.indices.filter {
                    lanes[$0].kind == kind
                        && lanes[$0].trackIDsBySource[sourceIndex] == nil
                }
                if !candidates.isEmpty {
                    ambiguities.append(
                        JoinTrackMappingAmbiguity(
                            sourceIndex: sourceIndex,
                            kind: kind,
                            trackIDs: unresolved.map(\.id),
                            candidateLaneIndices: candidates
                        )
                    )
                }
                for track in unresolved {
                    var trackIDs = [Int?](repeating: nil, count: sourceIndex)
                    trackIDs.append(track.id)
                    lanes.append(
                        MutableJoinTrackLane(kind: track.kind, trackIDsBySource: trackIDs))
                }
            }
        }

        guard !lanes.isEmpty else { throw JoinTrackMappingError.emptyMapping }
        let mapping = JoinTrackMapping(
            lanes: lanes.map { JoinTrackLane(kind: $0.kind, trackIDsBySource: $0.trackIDsBySource) }
        )
        // Reuse the strict analyzer validator so proposals and hand-edited mappings
        // enforce the same exhaustive, exactly-once assignment contract.
        _ = try JoinCompatibilityAnalyzer().analyze(sources: sources, mapping: mapping)
        return JoinTrackMappingProposal(mapping: mapping, ambiguities: ambiguities)
    }

    private func assignUniqueFullMatches(
        sourceIndex: Int,
        indexedTracks: [[Int: MediaTrack]],
        lanes: inout [MutableJoinTrackLane],
        remainingTrackIDs: inout Set<Int>
    ) {
        var tracksByFingerprint = [JoinTrackFullFingerprint: [Int]]()
        for trackID in remainingTrackIDs {
            let track = indexedTracks[sourceIndex][trackID]!
            tracksByFingerprint[JoinTrackPolicy.fullFingerprint(track), default: []].append(trackID)
        }
        var lanesByFingerprint = [JoinTrackFullFingerprint: [Int]]()
        for laneIndex in lanes.indices where lanes[laneIndex].trackIDsBySource[sourceIndex] == nil {
            guard
                let reference = referenceTrack(for: lanes[laneIndex], indexedTracks: indexedTracks)
            else { continue }
            lanesByFingerprint[JoinTrackPolicy.fullFingerprint(reference), default: []].append(
                laneIndex)
        }
        assignMutuallyUnique(
            tracksByKey: tracksByFingerprint,
            lanesByKey: lanesByFingerprint,
            sourceIndex: sourceIndex,
            lanes: &lanes,
            remainingTrackIDs: &remainingTrackIDs
        )
    }

    private func assignUniqueSemanticMatches(
        sourceIndex: Int,
        indexedTracks: [[Int: MediaTrack]],
        lanes: inout [MutableJoinTrackLane],
        remainingTrackIDs: inout Set<Int>
    ) {
        var tracksByFingerprint = [JoinTrackSemanticFingerprint: [Int]]()
        for trackID in remainingTrackIDs {
            let track = indexedTracks[sourceIndex][trackID]!
            tracksByFingerprint[JoinTrackPolicy.semanticFingerprint(track), default: []].append(
                trackID)
        }
        var lanesByFingerprint = [JoinTrackSemanticFingerprint: [Int]]()
        for laneIndex in lanes.indices where lanes[laneIndex].trackIDsBySource[sourceIndex] == nil {
            guard
                let reference = referenceTrack(for: lanes[laneIndex], indexedTracks: indexedTracks)
            else { continue }
            lanesByFingerprint[JoinTrackPolicy.semanticFingerprint(reference), default: []].append(
                laneIndex)
        }
        assignMutuallyUnique(
            tracksByKey: tracksByFingerprint,
            lanesByKey: lanesByFingerprint,
            sourceIndex: sourceIndex,
            lanes: &lanes,
            remainingTrackIDs: &remainingTrackIDs
        )
    }

    private func assignMutuallyUnique<Key: Hashable>(
        tracksByKey: [Key: [Int]],
        lanesByKey: [Key: [Int]],
        sourceIndex: Int,
        lanes: inout [MutableJoinTrackLane],
        remainingTrackIDs: inout Set<Int>
    ) {
        for (key, trackIDs) in tracksByKey {
            guard trackIDs.count == 1, let laneIndices = lanesByKey[key], laneIndices.count == 1,
                let trackID = trackIDs.first, let laneIndex = laneIndices.first
            else { continue }
            lanes[laneIndex].trackIDsBySource[sourceIndex] = trackID
            remainingTrackIDs.remove(trackID)
        }
    }

    private func assignOnlyRemainingKindMatches(
        sourceIndex: Int,
        indexedTracks: [[Int: MediaTrack]],
        lanes: inout [MutableJoinTrackLane],
        remainingTrackIDs: inout Set<Int>
    ) {
        for kind in [MediaTrackKind.video, .audio, .subtitle] {
            let trackIDs = remainingTrackIDs.filter { indexedTracks[sourceIndex][$0]?.kind == kind }
            let laneIndices = lanes.indices.filter {
                lanes[$0].kind == kind && lanes[$0].trackIDsBySource[sourceIndex] == nil
            }
            guard trackIDs.count == 1, laneIndices.count == 1,
                let trackID = trackIDs.first, let laneIndex = laneIndices.first
            else { continue }
            lanes[laneIndex].trackIDsBySource[sourceIndex] = trackID
            remainingTrackIDs.remove(trackID)
        }
    }

    private func referenceTrack(
        for lane: MutableJoinTrackLane,
        indexedTracks: [[Int: MediaTrack]]
    ) -> MediaTrack? {
        for (sourceIndex, trackID) in lane.trackIDsBySource.enumerated() {
            if let trackID, let track = indexedTracks[sourceIndex][trackID] { return track }
        }
        return nil
    }
}

/// Conservatively checks an explicit mapping. A lossless candidate still has to
/// pass bundled mkvmerge's codec-specific checks and output verification.
public struct JoinCompatibilityAnalyzer: Sendable {
    public static let maximumSources = 1_000
    public static let maximumTracks = 1_000

    public init() {}

    public func analyze(
        sources: [MediaAsset],
        mapping: JoinTrackMapping
    ) throws -> JoinCompatibilityReport {
        let indexedTracks = try validate(sources: sources, mapping: mapping)
        var issues = globalIssues(sources: sources)

        for (laneIndex, lane) in mapping.lanes.enumerated() {
            let mapped = lane.trackIDsBySource.enumerated().compactMap { sourceIndex, trackID in
                trackID.map { (sourceIndex, indexedTracks[sourceIndex][$0]!) }
            }
            guard let reference = mapped.first else {
                throw JoinTrackMappingError.emptyLane(laneIndex: laneIndex)
            }
            for sourceIndex in sources.indices where lane.trackIDsBySource[sourceIndex] == nil {
                issues.append(
                    JoinCompatibilityIssue(
                        severity: lane.kind == .video
                            ? .normalizationRequired : .confirmationRequired,
                        reason: .missingTrack,
                        laneIndex: laneIndex,
                        referenceSourceIndex: reference.0,
                        sourceIndex: sourceIndex
                    )
                )
            }
            for candidate in mapped.dropFirst() {
                issues.append(
                    contentsOf: compare(
                        reference: reference,
                        candidate: candidate,
                        laneIndex: laneIndex
                    )
                )
            }
        }

        return JoinCompatibilityReport(
            mapping: mapping,
            disposition: disposition(for: issues),
            issues: issues,
            requiresAuthoritativeMKVToolNixValidation: true
        )
    }

    private func validate(
        sources: [MediaAsset],
        mapping: JoinTrackMapping
    ) throws -> [[Int: MediaTrack]] {
        let indexedTracks = try JoinTrackSourceIndex.make(sources: sources)
        guard !mapping.lanes.isEmpty else { throw JoinTrackMappingError.emptyMapping }
        guard mapping.lanes.count <= Self.maximumTracks else {
            throw JoinTrackMappingError.tooManyTracks
        }

        var assigned = Set<TrackAssignment>()
        for (laneIndex, lane) in mapping.lanes.enumerated() {
            guard lane.trackIDsBySource.count == sources.count else {
                throw JoinTrackMappingError.invalidLaneWidth(laneIndex: laneIndex)
            }
            guard JoinTrackPolicy.appendableKinds.contains(lane.kind) else {
                throw JoinTrackMappingError.unsupportedLaneKind(laneIndex: laneIndex)
            }
            guard lane.trackIDsBySource.contains(where: { $0 != nil }) else {
                throw JoinTrackMappingError.emptyLane(laneIndex: laneIndex)
            }
            for (sourceIndex, trackID) in lane.trackIDsBySource.enumerated() {
                guard let trackID else { continue }
                guard let track = indexedTracks[sourceIndex][trackID] else {
                    throw JoinTrackMappingError.missingTrack(
                        sourceIndex: sourceIndex,
                        trackID: trackID
                    )
                }
                guard track.kind == lane.kind else {
                    throw JoinTrackMappingError.kindMismatch(
                        sourceIndex: sourceIndex,
                        trackID: trackID
                    )
                }
                guard assigned.insert(TrackAssignment(sourceIndex, trackID)).inserted else {
                    throw JoinTrackMappingError.duplicateAssignment(
                        sourceIndex: sourceIndex,
                        trackID: trackID
                    )
                }
            }
        }

        for (sourceIndex, source) in sources.enumerated() {
            for track in source.tracks where JoinTrackPolicy.appendableKinds.contains(track.kind) {
                guard assigned.contains(TrackAssignment(sourceIndex, track.id)) else {
                    throw JoinTrackMappingError.unmappedTrack(
                        sourceIndex: sourceIndex,
                        trackID: track.id
                    )
                }
            }
        }
        return indexedTracks
    }

    private func globalIssues(sources: [MediaAsset]) -> [JoinCompatibilityIssue] {
        var issues = [JoinCompatibilityIssue]()
        for (sourceIndex, source) in sources.enumerated() {
            if !JoinTrackPolicy.normalized(source.container).contains("matroska") {
                issues.append(
                    JoinCompatibilityIssue(
                        severity: .confirmationRequired,
                        reason: .nonMatroskaSource,
                        sourceIndex: sourceIndex
                    )
                )
            }
            if !source.attachments.isEmpty {
                issues.append(
                    JoinCompatibilityIssue(
                        severity: .confirmationRequired,
                        reason: .attachmentSelection,
                        sourceIndex: sourceIndex
                    )
                )
            }
            for track in source.tracks where !JoinTrackPolicy.appendableKinds.contains(track.kind) {
                issues.append(
                    JoinCompatibilityIssue(
                        severity: .unsupported,
                        reason: .unsupportedTrackKind,
                        sourceIndex: sourceIndex,
                        trackID: track.id
                    )
                )
            }
        }
        return issues
    }

    private func compare(
        reference: (Int, MediaTrack),
        candidate: (Int, MediaTrack),
        laneIndex: Int
    ) -> [JoinCompatibilityIssue] {
        let referenceTrack = reference.1
        let candidateTrack = candidate.1
        var reasons = [(JoinCompatibilityIssueSeverity, JoinCompatibilityIssueReason)]()

        compareCodec(referenceTrack, candidateTrack, into: &reasons)
        if knownMismatch(referenceTrack.profile, candidateTrack.profile) {
            reasons.append((.normalizationRequired, .profile))
        }
        if JoinTrackPolicy.normalizedLanguage(referenceTrack.language)
            != JoinTrackPolicy.normalizedLanguage(candidateTrack.language)
        {
            reasons.append((.confirmationRequired, .language))
        }
        if JoinTrackPolicy.roleSignature(referenceTrack)
            != JoinTrackPolicy.roleSignature(candidateTrack)
        {
            reasons.append((.confirmationRequired, .role))
        }
        if JoinTrackPolicy.normalized(referenceTrack.title)
            != JoinTrackPolicy.normalized(candidateTrack.title)
        {
            reasons.append((.confirmationRequired, .title))
        }
        if flagSignature(referenceTrack) != flagSignature(candidateTrack) {
            reasons.append((.confirmationRequired, .flags))
        }

        switch referenceTrack.kind {
        case .video:
            compareVideo(referenceTrack, candidateTrack, into: &reasons)
        case .audio:
            compareAudio(referenceTrack, candidateTrack, into: &reasons)
        case .subtitle:
            break
        default:
            reasons.append((.unsupported, .unsupportedTrackKind))
        }

        var seen = Set<String>()
        let uniqueReasons = reasons.filter { severity, reason in
            seen.insert("\(severity.rawValue)\u{0}\(reason.rawValue)").inserted
        }
        return uniqueReasons.map { severity, reason in
            JoinCompatibilityIssue(
                severity: severity,
                reason: reason,
                laneIndex: laneIndex,
                referenceSourceIndex: reference.0,
                sourceIndex: candidate.0,
                trackID: candidateTrack.id
            )
        }
    }

    private func compareVideo(
        _ reference: MediaTrack,
        _ candidate: MediaTrack,
        into reasons: inout [(JoinCompatibilityIssueSeverity, JoinCompatibilityIssueReason)]
    ) {
        if let referenceDimensions = reference.dimensions,
            let candidateDimensions = candidate.dimensions
        {
            if referenceDimensions != candidateDimensions {
                reasons.append((.normalizationRequired, .dimensions))
            }
            let referenceDisplay = reference.displayDimensions ?? referenceDimensions
            let candidateDisplay = candidate.displayDimensions ?? candidateDimensions
            if referenceDisplay != candidateDisplay {
                reasons.append((.normalizationRequired, .displayDimensions))
            }
        } else {
            reasons.append((.confirmationRequired, .incompleteParameters))
        }
        compareRequiredParameter(
            normalizedNonempty(reference.pixelFormat),
            normalizedNonempty(candidate.pixelFormat),
            reason: .pixelFormat,
            into: &reasons
        )
        compareRequiredParameter(
            reference.bitDepth,
            candidate.bitDepth,
            reason: .bitDepth,
            into: &reasons
        )
        compareRequiredParameter(
            reference.level,
            candidate.level,
            reason: .level,
            into: &reasons
        )
        if let referenceRate = frameRate(reference.frameRate),
            let candidateRate = frameRate(candidate.frameRate),
            abs(referenceRate - candidateRate) > 0.0005
        {
            reasons.append((.confirmationRequired, .frameRate))
        }
        if colorSignature(reference.colorInfo) != colorSignature(candidate.colorInfo) {
            if reference.colorInfo == nil || candidate.colorInfo == nil {
                reasons.append((.confirmationRequired, .incompleteParameters))
            } else {
                reasons.append((.normalizationRequired, .color))
            }
        }
        if normalizedSet(reference.hdrFormats) != normalizedSet(candidate.hdrFormats) {
            reasons.append((.normalizationRequired, .hdr))
        }
    }

    private func compareAudio(
        _ reference: MediaTrack,
        _ candidate: MediaTrack,
        into reasons: inout [(JoinCompatibilityIssueSeverity, JoinCompatibilityIssueReason)]
    ) {
        compareRequiredParameter(
            reference.sampleRate,
            candidate.sampleRate,
            reason: .sampleRate,
            into: &reasons
        )
        compareRequiredParameter(
            reference.channels,
            candidate.channels,
            reason: .channels,
            into: &reasons
        )
        compareRequiredParameter(
            normalizedNonempty(reference.channelLayout),
            normalizedNonempty(candidate.channelLayout),
            reason: .channelLayout,
            into: &reasons
        )
    }

    private func compareCodec(
        _ reference: MediaTrack,
        _ candidate: MediaTrack,
        into reasons: inout [(JoinCompatibilityIssueSeverity, JoinCompatibilityIssueReason)]
    ) {
        let referenceID = JoinTrackPolicy.usableCodecID(reference.codecID)
        let candidateID = JoinTrackPolicy.usableCodecID(candidate.codecID)
        if let referenceID, let candidateID {
            if referenceID != candidateID {
                reasons.append((.normalizationRequired, .codec))
            }
            return
        }
        if JoinTrackPolicy.normalized(reference.codec)
            != JoinTrackPolicy.normalized(candidate.codec)
        {
            reasons.append((.normalizationRequired, .codec))
        } else {
            reasons.append((.confirmationRequired, .incompleteParameters))
        }
    }

    private func compareRequiredParameter<T: Equatable>(
        _ reference: T?,
        _ candidate: T?,
        reason: JoinCompatibilityIssueReason,
        into reasons: inout [(JoinCompatibilityIssueSeverity, JoinCompatibilityIssueReason)]
    ) {
        guard let reference, let candidate else {
            reasons.append((.confirmationRequired, .incompleteParameters))
            return
        }
        if reference != candidate {
            reasons.append((.normalizationRequired, reason))
        }
    }

    private func disposition(for issues: [JoinCompatibilityIssue]) -> JoinAppendDisposition {
        if issues.contains(where: { $0.severity == .unsupported }) { return .unsupported }
        if issues.contains(where: { $0.severity == .normalizationRequired }) {
            return .normalizationRequired
        }
        if issues.contains(where: { $0.severity == .confirmationRequired }) {
            return .confirmationRequired
        }
        return .losslessCandidate
    }

    private func normalizedNonempty(_ value: String?) -> String? {
        let value = JoinTrackPolicy.normalized(value)
        return value.isEmpty ? nil : value
    }

    private func knownMismatch(_ reference: String?, _ candidate: String?) -> Bool {
        let reference = JoinTrackPolicy.normalized(reference)
        let candidate = JoinTrackPolicy.normalized(candidate)
        return !reference.isEmpty && !candidate.isEmpty && reference != candidate
    }

    private func normalizedSet(_ values: [String]) -> Set<String> {
        Set(values.map { JoinTrackPolicy.normalized($0) }.filter { !$0.isEmpty })
    }

    private func frameRate(_ value: String?) -> Double? {
        guard let value else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]),
            denominator != 0
        {
            return numerator / denominator
        }
        return Double(value)
    }

    private func colorSignature(_ color: MediaColorInfo?) -> [String]? {
        guard let color else { return nil }
        return [color.range, color.primaries, color.transfer, color.matrix].map {
            JoinTrackPolicy.normalized($0)
        }
    }

    private func flagSignature(_ track: MediaTrack) -> [Bool] {
        [track.isDefault, track.isEnabled]
    }

}

private enum JoinTrackSourceIndex {
    static func make(sources: [MediaAsset]) throws -> [[Int: MediaTrack]] {
        guard (2...JoinCompatibilityAnalyzer.maximumSources).contains(sources.count) else {
            throw JoinTrackMappingError.invalidSourceCount
        }
        let totalTracks = sources.reduce(0) { partial, source in
            let result = partial.addingReportingOverflow(source.tracks.count)
            return result.overflow ? Int.max : result.partialValue
        }
        guard totalTracks <= JoinCompatibilityAnalyzer.maximumTracks else {
            throw JoinTrackMappingError.tooManyTracks
        }

        var indexedTracks = [[Int: MediaTrack]]()
        indexedTracks.reserveCapacity(sources.count)
        for (sourceIndex, source) in sources.enumerated() {
            var index = [Int: MediaTrack]()
            index.reserveCapacity(source.tracks.count)
            for track in source.tracks {
                guard index.updateValue(track, forKey: track.id) == nil else {
                    throw JoinTrackMappingError.duplicateTrackID(
                        sourceIndex: sourceIndex,
                        trackID: track.id
                    )
                }
            }
            indexedTracks.append(index)
        }
        return indexedTracks
    }
}

private enum JoinTrackPolicy {
    static let appendableKinds: Set<MediaTrackKind> = [.video, .audio, .subtitle]

    static func fullFingerprint(_ track: MediaTrack) -> JoinTrackFullFingerprint {
        JoinTrackFullFingerprint(
            semantic: semanticFingerprint(track),
            codec: usableCodecID(track.codecID) ?? normalized(track.codec),
            profile: normalized(track.profile),
            level: track.level,
            channels: track.channels,
            channelLayout: normalized(track.channelLayout),
            sampleRate: track.sampleRate,
            dimensions: track.dimensions,
            displayDimensions: track.displayDimensions,
            pixelFormat: normalized(track.pixelFormat),
            bitDepth: track.bitDepth,
            frameRate: normalized(track.frameRate),
            color: track.colorInfo.map {
                [$0.range, $0.primaries, $0.transfer, $0.matrix].map(normalized)
            },
            hdrFormats: Set(track.hdrFormats.map(normalized).filter { !$0.isEmpty })
        )
    }

    static func semanticFingerprint(_ track: MediaTrack) -> JoinTrackSemanticFingerprint {
        JoinTrackSemanticFingerprint(
            kind: track.kind,
            language: normalizedLanguage(track.language),
            roles: roleSignature(track)
        )
    }

    static func usableCodecID(_ value: String?) -> String? {
        let value = normalized(value)
        return value.isEmpty || value == "unknown" || value == "[0][0][0][0]" ? nil : value
    }

    static func normalizedLanguage(_ value: String?) -> String {
        guard let value else { return "und" }
        return (try? ChapterLanguage.canonical(value)) ?? normalized(value)
    }

    static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    static func roleSignature(_ track: MediaTrack) -> [Bool] {
        [
            track.isForced,
            track.isCommentary,
            track.isHearingImpaired,
            track.isVisualImpaired,
            track.isOriginal,
            track.isTextDescription,
        ]
    }
}

private struct JoinTrackSemanticFingerprint: Hashable {
    let kind: MediaTrackKind
    let language: String
    let roles: [Bool]
}

private struct JoinTrackFullFingerprint: Hashable {
    let semantic: JoinTrackSemanticFingerprint
    let codec: String
    let profile: String
    let level: Int?
    let channels: Int?
    let channelLayout: String
    let sampleRate: Int?
    let dimensions: MediaDimensions?
    let displayDimensions: MediaDimensions?
    let pixelFormat: String
    let bitDepth: Int?
    let frameRate: String
    let color: [String]?
    let hdrFormats: Set<String>
}

private struct MutableJoinTrackLane {
    let kind: MediaTrackKind
    var trackIDsBySource: [Int?]
}

private struct TrackAssignment: Hashable {
    let sourceIndex: Int
    let trackID: Int

    init(_ sourceIndex: Int, _ trackID: Int) {
        self.sourceIndex = sourceIndex
        self.trackID = trackID
    }
}
