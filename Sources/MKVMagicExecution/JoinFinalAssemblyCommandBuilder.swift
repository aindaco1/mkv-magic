import Foundation
import MKVMagicCore
import MKVMagicPlanning

public enum JoinFinalAssemblyCommandError: Error, Equatable, Sendable {
    case reportChanged
    case invalidPath
    case existingOutput
    case invalidChapters
    case normalizedBundleMismatch
    case unsupportedSubtitleLane(laneIndex: Int)
    case unsupportedSubtitleGap(laneIndex: Int)
    case unsupportedTagPreservation(sourceIndex: Int)
    case unsupportedContainerMetadata(sourceIndex: Int)
    case invalidTrackMetadata(laneIndex: Int)
    case inconsistentPlan
    case commandTooLarge
}

extension JoinFinalAssemblyCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .reportChanged:
            "The inspected join facts changed before final assembly was compiled."
        case .invalidPath:
            "Every final-assembly input and output needs a safe absolute file path."
        case .existingOutput:
            "Final assembly refuses to overwrite an existing output."
        case .invalidChapters:
            "The chapter file does not exactly match the reviewed joined chapter tree."
        case .normalizedBundleMismatch:
            "The normalized stream bundle no longer matches the reviewed encoded lanes."
        case .unsupportedSubtitleLane(let laneIndex):
            "Subtitle lane \(laneIndex + 1) still needs text conversion before final assembly."
        case .unsupportedSubtitleGap(let laneIndex):
            "Subtitle lane \(laneIndex + 1) still needs an explicit empty timeline section."
        case .unsupportedTagPreservation(let sourceIndex):
            "Part \(sourceIndex + 1) contains global or track tags that final assembly cannot preserve yet."
        case .unsupportedContainerMetadata(let sourceIndex):
            "Part \(sourceIndex + 1) contains container metadata that final assembly cannot preserve yet."
        case .invalidTrackMetadata(let laneIndex):
            "The chosen metadata for lane \(laneIndex + 1) is not safe to render."
        case .inconsistentPlan:
            "The encoded and packet-copy lanes do not form one complete reviewed output."
        case .commandTooLarge:
            "The final Matroska assembly command exceeds the bounded command size."
        }
    }
}

public enum JoinFinalLaneMechanism: String, Equatable, Sendable {
    case normalized
    case packetCopy
}

public struct JoinFinalLaneInput: Equatable, Sendable {
    public let laneIndex: Int
    public let mechanism: JoinFinalLaneMechanism
    public let inputFileID: Int
    public let inputTrackID: Int
    public let metadataSourceIndex: Int

    public init(
        laneIndex: Int,
        mechanism: JoinFinalLaneMechanism,
        inputFileID: Int,
        inputTrackID: Int,
        metadataSourceIndex: Int
    ) {
        self.laneIndex = laneIndex
        self.mechanism = mechanism
        self.inputFileID = inputFileID
        self.inputTrackID = inputTrackID
        self.metadataSourceIndex = metadataSourceIndex
    }
}

public struct JoinFinalAssemblyCommand: Equatable, Sendable {
    public let arguments: [String]
    public let outputURL: URL
    public let lanes: [JoinFinalLaneInput]
    public let retainedAttachmentIDsBySource: [Int: Set<Int>]

    public init(
        arguments: [String],
        outputURL: URL,
        lanes: [JoinFinalLaneInput],
        retainedAttachmentIDsBySource: [Int: Set<Int>]
    ) {
        self.arguments = arguments
        self.outputURL = outputURL
        self.lanes = lanes
        self.retainedAttachmentIDsBySource = retainedAttachmentIDsBySource
    }
}

/// Compiles one final mkvmerge invocation. Encoded tracks are read from the
/// already verified normalization bundle; compatible source tracks are appended
/// directly in the same invocation, so packet-copy lanes do not need a second
/// intermediate remux.
public struct JoinFinalAssemblyCommandBuilder: Sendable {
    public init() {}

    public func build(
        sources: [MediaAsset],
        resolvedPlan: ResolvedJoinNormalizationPlan,
        normalizedBundle: MediaAsset,
        chapters: JoinedChapterComposition,
        chaptersURL rawChaptersURL: URL,
        outputURL rawOutputURL: URL
    ) throws -> JoinFinalAssemblyCommand {
        let mapping = resolvedPlan.proposal.report.mapping
        let currentReport = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: mapping
        )
        guard
            JoinCompatibilityReportSnapshot(currentReport, sources: sources)
                == resolvedPlan.proposal.report
        else {
            throw JoinFinalAssemblyCommandError.reportChanged
        }

        let chaptersURL = rawChaptersURL.standardizedFileURL
        let outputURL = rawOutputURL.standardizedFileURL
        guard safeExistingRegularFile(chaptersURL),
            safeExistingRegularFile(normalizedBundle.sourceURL),
            safeOutput(outputURL), outputURL.pathExtension.lowercased() == "mkv",
            sources.allSatisfy({ safeExistingRegularFile($0.sourceURL) }),
            !sources.contains(where: { $0.sourceURL.standardizedFileURL == outputURL }),
            normalizedBundle.sourceURL.standardizedFileURL != outputURL
        else {
            throw JoinFinalAssemblyCommandError.invalidPath
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw JoinFinalAssemblyCommandError.existingOutput
        }
        try verifyChapters(chapters, at: chaptersURL)
        do {
            try JoinNormalizationOutputVerifier().verify(
                sources: sources,
                resolvedPlan: resolvedPlan,
                output: normalizedBundle
            )
        } catch {
            throw JoinFinalAssemblyCommandError.normalizedBundleMismatch
        }
        try validatePreservableSourceMetadata(sources)

        var indexedTracks = [[Int: MediaTrack]]()
        for source in sources {
            var tracksByID = [Int: MediaTrack]()
            for track in source.tracks {
                guard track.id >= 0, tracksByID.updateValue(track, forKey: track.id) == nil
                else {
                    throw JoinFinalAssemblyCommandError.inconsistentPlan
                }
            }
            indexedTracks.append(tracksByID)
        }
        let normalizedVideoLaneIndices = resolvedPlan.proposal.videoLanes
            .filter(\.encodesVideo).map(\.laneIndex).sorted()
        let normalizedAudioLaneIndices = resolvedPlan.proposal.audioLanes
            .filter(\.encodesAudio).map(\.laneIndex).sorted()
        let normalizedLaneIndices = normalizedVideoLaneIndices + normalizedAudioLaneIndices
        let normalizedTracks = normalizedBundle.tracks.filter { $0.kind != .attachment }
        guard normalizedTracks.count == normalizedLaneIndices.count else {
            throw JoinFinalAssemblyCommandError.normalizedBundleMismatch
        }
        let normalizedLaneSet = Set(normalizedLaneIndices)
        guard normalizedLaneSet.count == normalizedLaneIndices.count else {
            throw JoinFinalAssemblyCommandError.inconsistentPlan
        }
        let normalizedTrackByLane = Dictionary(
            uniqueKeysWithValues: zip(normalizedLaneIndices, normalizedTracks).map {
                ($0.0, $0.1)
            }
        )

        var copyLaneIndices = [Int]()
        for (laneIndex, lane) in mapping.lanes.enumerated()
        where !normalizedLaneSet.contains(laneIndex) {
            switch lane.kind {
            case .video:
                guard
                    let proposal = resolvedPlan.proposal.videoLanes.first(where: {
                        $0.laneIndex == laneIndex
                    }), !proposal.encodesVideo
                else {
                    throw JoinFinalAssemblyCommandError.inconsistentPlan
                }
            case .audio:
                guard
                    let proposal = resolvedPlan.proposal.audioLanes.first(where: {
                        $0.laneIndex == laneIndex
                    }), !proposal.encodesAudio
                else {
                    throw JoinFinalAssemblyCommandError.inconsistentPlan
                }
            case .subtitle:
                guard
                    let proposal = resolvedPlan.proposal.subtitleLanes.first(where: {
                        $0.laneIndex == laneIndex
                    })
                else {
                    throw JoinFinalAssemblyCommandError.inconsistentPlan
                }
                guard proposal.mechanism == .packetTimeline else {
                    throw JoinFinalAssemblyCommandError.unsupportedSubtitleLane(
                        laneIndex: laneIndex
                    )
                }
                guard !proposal.sourceActions.contains(.emptyTimeline) else {
                    throw JoinFinalAssemblyCommandError.unsupportedSubtitleGap(
                        laneIndex: laneIndex
                    )
                }
            default:
                throw JoinFinalAssemblyCommandError.inconsistentPlan
            }
            guard lane.trackIDsBySource.count == sources.count,
                lane.trackIDsBySource.allSatisfy({ ($0 ?? -1) >= 0 })
            else {
                throw JoinFinalAssemblyCommandError.inconsistentPlan
            }
            copyLaneIndices.append(laneIndex)
        }

        guard normalizedLaneSet.count == normalizedLaneIndices.count,
            normalizedLaneSet.union(copyLaneIndices).count == mapping.lanes.count
        else {
            throw JoinFinalAssemblyCommandError.inconsistentPlan
        }

        var laneInputs = [JoinFinalLaneInput]()
        for laneIndex in mapping.lanes.indices {
            let metadataSourceIndex = try metadataSourceIndex(
                laneIndex: laneIndex,
                mapping: mapping,
                choices: resolvedPlan.choices
            )
            if let normalizedTrack = normalizedTrackByLane[laneIndex] {
                guard normalizedTrack.id >= 0 else {
                    throw JoinFinalAssemblyCommandError.normalizedBundleMismatch
                }
                laneInputs.append(
                    JoinFinalLaneInput(
                        laneIndex: laneIndex,
                        mechanism: .normalized,
                        inputFileID: 0,
                        inputTrackID: normalizedTrack.id,
                        metadataSourceIndex: metadataSourceIndex
                    )
                )
            } else {
                guard let trackID = mapping.lanes[laneIndex].trackIDsBySource[0], trackID >= 0
                else {
                    throw JoinFinalAssemblyCommandError.inconsistentPlan
                }
                laneInputs.append(
                    JoinFinalLaneInput(
                        laneIndex: laneIndex,
                        mechanism: .packetCopy,
                        inputFileID: 1,
                        inputTrackID: trackID,
                        metadataSourceIndex: metadataSourceIndex
                    )
                )
            }
        }

        var arguments = [
            "--output", outputURL.path,
            "--abort-on-warnings",
            "--flush-on-close",
            "--normalize-language-ietf", "canonical",
            "--disable-track-statistics-tags",
            "--append-mode", "file",
        ]
        if !copyLaneIndices.isEmpty {
            arguments.append(contentsOf: [
                "--append-to",
                try appendMapping(
                    sources: sources,
                    mapping: mapping,
                    copyLaneIndices: copyLaneIndices
                ),
            ])
        }
        let title = segmentTitle(sources[0]) ?? ""
        guard safeUserText(title) else {
            throw JoinFinalAssemblyCommandError.unsupportedContainerMetadata(
                sourceIndex: 0
            )
        }
        arguments.append(contentsOf: [
            "--track-order",
            laneInputs.map { "\($0.inputFileID):\($0.inputTrackID)" }
                .joined(separator: ","),
            "--title", title,
            "--chapters", chaptersURL.path,
        ])

        for lane in laneInputs where lane.mechanism == .normalized {
            let metadata = try selectedTrack(
                laneIndex: lane.laneIndex,
                sourceIndex: lane.metadataSourceIndex,
                mapping: mapping,
                indexedTracks: indexedTracks
            )
            arguments.append(
                contentsOf: try trackMetadataArguments(
                    inputTrackID: lane.inputTrackID,
                    metadata: metadata,
                    laneIndex: lane.laneIndex
                )
            )
        }
        arguments.append(
            contentsOf: trackSelectionArguments(
                tracks: normalizedTracks
            ))
        arguments.append(contentsOf: [
            "--no-buttons", "--no-attachments", "--no-chapters",
            "--no-track-tags", "--no-global-tags",
            normalizedBundle.sourceURL.standardizedFileURL.path,
        ])

        if !copyLaneIndices.isEmpty {
            for sourceIndex in sources.indices {
                if sourceIndex == 0 {
                    for lane in laneInputs where lane.mechanism == .packetCopy {
                        let metadata = try selectedTrack(
                            laneIndex: lane.laneIndex,
                            sourceIndex: lane.metadataSourceIndex,
                            mapping: mapping,
                            indexedTracks: indexedTracks
                        )
                        arguments.append(
                            contentsOf: try trackMetadataArguments(
                                inputTrackID: lane.inputTrackID,
                                metadata: metadata,
                                laneIndex: lane.laneIndex
                            )
                        )
                    }
                }
                let copyTracks = copyLaneIndices.compactMap { laneIndex -> MediaTrack? in
                    guard let trackID = mapping.lanes[laneIndex].trackIDsBySource[sourceIndex]
                    else { return nil }
                    return indexedTracks[sourceIndex][trackID]
                }
                guard copyTracks.count == copyLaneIndices.count,
                    copyTracks.allSatisfy({ $0.id >= 0 })
                else {
                    throw JoinFinalAssemblyCommandError.inconsistentPlan
                }
                arguments.append(contentsOf: trackSelectionArguments(tracks: copyTracks))
                arguments.append(
                    contentsOf: try attachmentArguments(
                        sourceIndex: sourceIndex,
                        choices: resolvedPlan.choices
                    ))
                arguments.append(contentsOf: [
                    "--no-buttons", "--no-chapters", "--no-track-tags", "--no-global-tags",
                ])
                let path = sources[sourceIndex].sourceURL.standardizedFileURL.path
                arguments.append(sourceIndex == 0 ? path : "+\(path)")
            }
        } else {
            for sourceIndex in sources.indices
            where !(resolvedPlan.choices.retainedAttachmentIDsBySource[sourceIndex] ?? [])
                .isEmpty
            {
                arguments.append(contentsOf: [
                    "--no-video", "--no-audio", "--no-subtitles",
                ])
                arguments.append(
                    contentsOf: try attachmentArguments(
                        sourceIndex: sourceIndex,
                        choices: resolvedPlan.choices
                    ))
                arguments.append(contentsOf: [
                    "--no-buttons", "--no-chapters", "--no-track-tags", "--no-global-tags",
                    sources[sourceIndex].sourceURL.standardizedFileURL.path,
                ])
            }
        }

        let commandBytes = arguments.reduce(0) { $0 + $1.utf8.count + 1 }
        guard arguments.count <= Self.maximumArguments,
            commandBytes <= Self.maximumCommandBytes
        else {
            throw JoinFinalAssemblyCommandError.commandTooLarge
        }
        return JoinFinalAssemblyCommand(
            arguments: arguments,
            outputURL: outputURL,
            lanes: laneInputs,
            retainedAttachmentIDsBySource: resolvedPlan.choices.retainedAttachmentIDsBySource
        )
    }

    private func verifyChapters(
        _ chapters: JoinedChapterComposition,
        at chaptersURL: URL
    ) throws {
        do {
            let values = try chaptersURL.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize,
                size > 0,
                size <= MatroskaChapterXMLCodec.maximumInputBytes
            else {
                throw JoinFinalAssemblyCommandError.invalidChapters
            }
            let codec = MatroskaChapterXMLCodec()
            let data = try Data(contentsOf: chaptersURL, options: .mappedIfSafe)
            let actual = try codec.serialize(codec.parse(data))
            let expected = try codec.serialize(chapters.document)
            guard actual == expected else {
                throw JoinFinalAssemblyCommandError.invalidChapters
            }
            _ = try chapters.document.validated(mediaDuration: chapters.duration)
        } catch let error as JoinFinalAssemblyCommandError {
            throw error
        } catch {
            throw JoinFinalAssemblyCommandError.invalidChapters
        }
    }

    private func validatePreservableSourceMetadata(_ sources: [MediaAsset]) throws {
        let allowedContainerKeys: Set<String> = ["title", "encoder", "creation_time"]
        for (sourceIndex, source) in sources.enumerated() {
            guard source.globalTagCount == 0, source.trackTagCount == 0 else {
                throw JoinFinalAssemblyCommandError.unsupportedTagPreservation(
                    sourceIndex: sourceIndex
                )
            }
            guard
                source.metadata.keys.allSatisfy({
                    allowedContainerKeys.contains($0.lowercased())
                })
            else {
                throw JoinFinalAssemblyCommandError.unsupportedContainerMetadata(
                    sourceIndex: sourceIndex
                )
            }
        }
    }

    private func metadataSourceIndex(
        laneIndex: Int,
        mapping: JoinTrackMapping,
        choices: JoinNormalizationChoices
    ) throws -> Int {
        if let chosen = choices.metadataSourceByLane[laneIndex] {
            guard mapping.lanes.indices.contains(laneIndex),
                mapping.lanes[laneIndex].trackIDsBySource.indices.contains(chosen),
                mapping.lanes[laneIndex].trackIDsBySource[chosen] != nil
            else {
                throw JoinFinalAssemblyCommandError.inconsistentPlan
            }
            return chosen
        }
        guard
            let first = mapping.lanes[laneIndex].trackIDsBySource.firstIndex(where: {
                $0 != nil
            })
        else {
            throw JoinFinalAssemblyCommandError.inconsistentPlan
        }
        return first
    }

    private func selectedTrack(
        laneIndex: Int,
        sourceIndex: Int,
        mapping: JoinTrackMapping,
        indexedTracks: [[Int: MediaTrack]]
    ) throws -> MediaTrack {
        guard indexedTracks.indices.contains(sourceIndex),
            mapping.lanes.indices.contains(laneIndex),
            mapping.lanes[laneIndex].trackIDsBySource.indices.contains(sourceIndex),
            let trackID = mapping.lanes[laneIndex].trackIDsBySource[sourceIndex],
            let track = indexedTracks[sourceIndex][trackID]
        else {
            throw JoinFinalAssemblyCommandError.inconsistentPlan
        }
        return track
    }

    private func trackMetadataArguments(
        inputTrackID: Int,
        metadata: MediaTrack,
        laneIndex: Int
    ) throws -> [String] {
        let title = metadata.title ?? ""
        guard inputTrackID >= 0, safeUserText(title) else {
            throw JoinFinalAssemblyCommandError.invalidTrackMetadata(
                laneIndex: laneIndex
            )
        }
        let language: String
        do {
            language = try TrackLanguageTag.canonical(metadata.language ?? "und")
        } catch {
            throw JoinFinalAssemblyCommandError.invalidTrackMetadata(
                laneIndex: laneIndex
            )
        }
        return [
            "--track-name", "\(inputTrackID):\(title)",
            "--language", "\(inputTrackID):\(language)",
            "--default-track-flag", "\(inputTrackID):\(flag(metadata.isDefault))",
            "--forced-display-flag", "\(inputTrackID):\(flag(metadata.isForced))",
            "--track-enabled-flag", "\(inputTrackID):\(flag(metadata.isEnabled))",
            "--commentary-flag", "\(inputTrackID):\(flag(metadata.isCommentary))",
            "--hearing-impaired-flag", "\(inputTrackID):\(flag(metadata.isHearingImpaired))",
            "--visual-impaired-flag", "\(inputTrackID):\(flag(metadata.isVisualImpaired))",
            "--original-flag", "\(inputTrackID):\(flag(metadata.isOriginal))",
            "--text-descriptions-flag", "\(inputTrackID):\(flag(metadata.isTextDescription))",
        ]
    }

    private func trackSelectionArguments(tracks: [MediaTrack]) -> [String] {
        var arguments = [String]()
        for (kind, some, none) in [
            (MediaTrackKind.video, "--video-tracks", "--no-video"),
            (.audio, "--audio-tracks", "--no-audio"),
            (.subtitle, "--subtitle-tracks", "--no-subtitles"),
        ] {
            let ids = tracks.filter { $0.kind == kind }.map(\.id)
            if ids.isEmpty {
                arguments.append(none)
            } else {
                arguments.append(contentsOf: [some, ids.map(String.init).joined(separator: ",")])
            }
        }
        return arguments
    }

    private func attachmentArguments(
        sourceIndex: Int,
        choices: JoinNormalizationChoices
    ) throws -> [String] {
        let ids = (choices.retainedAttachmentIDsBySource[sourceIndex] ?? []).sorted()
        guard ids.allSatisfy({ $0 >= 0 }) else {
            throw JoinFinalAssemblyCommandError.inconsistentPlan
        }
        return ids.isEmpty
            ? ["--no-attachments"]
            : ["--attachments", ids.map(String.init).joined(separator: ",")]
    }

    private func appendMapping(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        copyLaneIndices: [Int]
    ) throws -> String {
        var mappings = [String]()
        for laneIndex in copyLaneIndices {
            guard mapping.lanes.indices.contains(laneIndex) else {
                throw JoinFinalAssemblyCommandError.inconsistentPlan
            }
            for sourceIndex in sources.indices.dropFirst() {
                guard
                    let sourceTrackID = mapping.lanes[laneIndex]
                        .trackIDsBySource[sourceIndex],
                    let destinationTrackID = mapping.lanes[laneIndex]
                        .trackIDsBySource[sourceIndex - 1]
                else {
                    throw JoinFinalAssemblyCommandError.inconsistentPlan
                }
                mappings.append(
                    "\(sourceIndex + 1):\(sourceTrackID):\(sourceIndex):\(destinationTrackID)"
                )
            }
        }
        guard !mappings.isEmpty else {
            throw JoinFinalAssemblyCommandError.inconsistentPlan
        }
        return mappings.joined(separator: ",")
    }

    private func segmentTitle(_ source: MediaAsset) -> String? {
        source.metadata.first {
            $0.key.caseInsensitiveCompare("title") == .orderedSame
        }?.value
    }

    private func flag(_ value: Bool) -> String { value ? "1" : "0" }

    private func safeUserText(_ value: String) -> Bool {
        !value.contains("\0") && value.utf8.count <= 4_096
    }

    private func safeExistingRegularFile(_ rawURL: URL) -> Bool {
        let url = rawURL.standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0"),
            (1...4_096).contains(url.path.utf8.count),
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func safeOutput(_ url: URL) -> Bool {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0"),
            (1...4_096).contains(url.path.utf8.count),
            let values = try? url.deletingLastPathComponent().resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey,
            ])
        else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static let maximumArguments = 25_000
    private static let maximumCommandBytes = 2_097_152
}
