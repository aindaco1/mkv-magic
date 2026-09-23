import Foundation
import MKVMagicCore
import MKVMagicSystem

enum MKVHeaderNormalizedLosslessPolicy {
    static func laneIndices(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        report: JoinCompatibilityReport,
        afterExplicitReview: Bool
    ) -> [Int] {
        guard afterExplicitReview,
            ReviewedMKVToolNixLosslessAppendPolicy.canOffer(for: report),
            (try? JoinFinalAssemblySourcePolicy().validate(sources)) != nil
        else { return [] }

        let mismatched = Set(
            report.issues.compactMap { issue -> Int? in
                guard issue.severity == .normalizationRequired,
                    issue.reason == .codecInitialization
                else { return nil }
                return issue.laneIndex
            }
        )
        guard !mismatched.isEmpty else { return [] }
        let supported = mismatched.filter { laneIndex in
            guard mapping.lanes.indices.contains(laneIndex),
                mapping.lanes[laneIndex].kind == .video,
                mapping.lanes[laneIndex].trackIDsBySource.count == sources.count
            else { return false }
            return sources.indices.allSatisfy { sourceIndex in
                guard let trackID = mapping.lanes[laneIndex].trackIDsBySource[sourceIndex],
                    let track = sources[sourceIndex].tracks.first(where: { $0.id == trackID })
                else { return false }
                let codec = track.codec.lowercased()
                let codecID = track.codecID?.lowercased() ?? ""
                let isH264 = codec == "h264" || codec == "avc" || codecID.contains("avc")
                return isH264
            }
        }
        guard supported.count == mismatched.count else { return [] }
        return supported.sorted()
    }
}

struct MKVHeaderNormalizedLosslessJoiner<Runner: CommandRunning>: Sendable {
    private let ffmpegURL: URL
    private let mkvmergeURL: URL
    private let mkvpropeditURL: URL
    private let runner: Runner

    init(
        ffmpegURL: URL,
        mkvmergeURL: URL,
        mkvpropeditURL: URL,
        runner: Runner
    ) {
        self.ffmpegURL = ffmpegURL
        self.mkvmergeURL = mkvmergeURL
        self.mkvpropeditURL = mkvpropeditURL
        self.runner = runner
    }

    func join(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        normalizedVideoLaneIndices: [Int],
        chaptersURL: URL,
        outputURL: URL,
        directory: URL,
        onProgress: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void
    ) async throws {
        let operations = normalizedVideoLaneIndices.count * sources.count + 1
        guard operations > 1 else { throw LosslessJoinExecutionError.invalidHeaderNormalization }
        let progress = HeaderNormalizedJoinProgress(totalOperations: operations, emit: onProgress)
        var normalizedVideoURLs = [Int: [URL]]()
        for laneIndex in normalizedVideoLaneIndices {
            var laneURLs = [URL]()
            for sourceIndex in sources.indices {
                guard mapping.lanes.indices.contains(laneIndex),
                    let trackID = mapping.lanes[laneIndex].trackIDsBySource[sourceIndex]
                else { throw LosslessJoinExecutionError.invalidHeaderNormalization }
                let output = directory.appendingPathComponent(
                    "video-l\(laneIndex)-s\(sourceIndex).mkv",
                    isDirectory: false
                )
                let result = try await runner.run(
                    CommandRequest(
                        executableURL: ffmpegURL,
                        arguments: try Self.headerNormalizationArguments(
                            sourceURL: sources[sourceIndex].sourceURL,
                            trackID: trackID,
                            outputURL: output
                        ),
                        timeout: 24 * 60 * 60,
                        outputLimit: 1_048_576
                    )
                )
                guard result.exitCode == 0 else {
                    throw LosslessJoinExecutionError.toolFailed(
                        tool: "ffmpeg",
                        exitCode: result.exitCode,
                        message: result.conciseFailureMessage
                    )
                }
                try validateNormalizedVideo(output, source: sources[sourceIndex])
                laneURLs.append(output)
                await progress.completeOperation()
            }
            normalizedVideoURLs[laneIndex] = laneURLs
        }

        let arguments = try Self.arguments(
            sources: sources,
            mapping: mapping,
            normalizedVideoLaneIndices: normalizedVideoLaneIndices,
            normalizedVideoURLs: normalizedVideoURLs,
            chaptersURL: chaptersURL,
            outputURL: outputURL
        )
        let result = try await runner.run(
            MKVToolNixProgress.request(
                executableURL: mkvmergeURL,
                arguments: arguments,
                timeout: 24 * 60 * 60,
                onProgress: { update in await progress.update(update) }
            )
        )
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw LosslessJoinExecutionError.toolFailed(
                tool: "mkvmerge",
                exitCode: result.exitCode,
                message: result.conciseFailureMessage
            )
        }
        let uidResult = try await runner.run(
            CommandRequest(
                executableURL: mkvpropeditURL,
                arguments: try Self.trackUIDArguments(
                    sources: sources,
                    mapping: mapping,
                    normalizedVideoLaneIndices: normalizedVideoLaneIndices,
                    outputURL: outputURL
                ),
                timeout: 120,
                outputLimit: 1_048_576
            )
        )
        guard uidResult.exitCode == 0 else {
            throw LosslessJoinExecutionError.toolFailed(
                tool: "mkvpropedit",
                exitCode: uidResult.exitCode,
                message: uidResult.conciseFailureMessage
            )
        }
        await progress.completeOperation()
    }

    static func headerNormalizationArguments(
        sourceURL: URL,
        trackID: Int,
        outputURL: URL
    ) throws -> [String] {
        guard trackID >= 0, safeAbsoluteFileURL(sourceURL), safeAbsoluteFileURL(outputURL),
            sourceURL.standardizedFileURL != outputURL.standardizedFileURL,
            outputURL.pathExtension.lowercased() == "mkv",
            !FileManager.default.fileExists(atPath: outputURL.path)
        else { throw LosslessJoinExecutionError.invalidHeaderNormalization }
        return [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-xerror", "-n",
            "-i", sourceURL.standardizedFileURL.path,
            "-map", "0:\(trackID)",
            "-map_metadata", "-1", "-map_chapters", "-1",
            "-c:v", "copy", "-bsf:v", "h264_mp4toannexb",
            "-an", "-sn", "-dn", "-f", "matroska",
            outputURL.standardizedFileURL.path,
        ]
    }

    static func arguments(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        normalizedVideoLaneIndices: [Int],
        normalizedVideoURLs: [Int: [URL]],
        chaptersURL: URL,
        outputURL: URL
    ) throws -> [String] {
        let normalized = normalizedVideoLaneIndices.sorted()
        let normalizedSet = Set(normalized)
        guard sources.count >= 2, normalized.count == normalizedSet.count,
            normalized.allSatisfy({ mapping.lanes.indices.contains($0) }),
            safeAbsoluteFileURL(chaptersURL), safeAbsoluteFileURL(outputURL),
            sources.allSatisfy({ safeAbsoluteFileURL($0.sourceURL) })
        else { throw LosslessJoinExecutionError.invalidHeaderNormalization }
        try JoinFinalAssemblySourcePolicy().validate(sources)

        var indexedTracks = [[Int: MediaTrack]]()
        for source in sources {
            var tracksByID = [Int: MediaTrack]()
            for track in source.tracks {
                guard track.id >= 0, tracksByID.updateValue(track, forKey: track.id) == nil
                else { throw LosslessJoinExecutionError.invalidHeaderNormalization }
            }
            indexedTracks.append(tracksByID)
        }
        for laneIndex in normalized {
            guard mapping.lanes[laneIndex].kind == .video,
                mapping.lanes[laneIndex].trackIDsBySource.count == sources.count,
                normalizedVideoURLs[laneIndex]?.count == sources.count,
                normalizedVideoURLs[laneIndex]?.allSatisfy({ safeAbsoluteFileURL($0) }) == true
            else { throw LosslessJoinExecutionError.invalidHeaderNormalization }
        }

        let copyLaneIndices = mapping.lanes.indices.filter { !normalizedSet.contains($0) }
        let normalizedFileCount = normalized.count * sources.count
        func normalizedFileID(lanePosition: Int, sourceIndex: Int) -> Int {
            lanePosition * sources.count + sourceIndex
        }
        func sourceFileID(_ sourceIndex: Int) -> Int { normalizedFileCount + sourceIndex }

        var appendMappings = [String]()
        for lanePosition in normalized.indices {
            for sourceIndex in sources.indices.dropFirst() {
                appendMappings.append(
                    "\(normalizedFileID(lanePosition: lanePosition, sourceIndex: sourceIndex)):0:"
                        + "\(normalizedFileID(lanePosition: lanePosition, sourceIndex: sourceIndex - 1)):0"
                )
            }
        }
        for laneIndex in copyLaneIndices {
            let lane = mapping.lanes[laneIndex]
            for sourceIndex in sources.indices.dropFirst() {
                guard let sourceTrackID = lane.trackIDsBySource[sourceIndex],
                    let destinationTrackID = lane.trackIDsBySource[sourceIndex - 1]
                else { throw LosslessJoinExecutionError.invalidHeaderNormalization }
                appendMappings.append(
                    "\(sourceFileID(sourceIndex)):\(sourceTrackID):"
                        + "\(sourceFileID(sourceIndex - 1)):\(destinationTrackID)"
                )
            }
        }

        var trackOrder = [String]()
        for laneIndex in mapping.lanes.indices {
            if let lanePosition = normalized.firstIndex(of: laneIndex) {
                trackOrder.append(
                    "\(normalizedFileID(lanePosition: lanePosition, sourceIndex: 0)):0"
                )
            } else {
                guard let trackID = mapping.lanes[laneIndex].trackIDsBySource[0] else {
                    throw LosslessJoinExecutionError.invalidHeaderNormalization
                }
                trackOrder.append("\(sourceFileID(0)):\(trackID)")
            }
        }
        let title =
            sources[0].metadata.first {
                $0.key.caseInsensitiveCompare("title") == .orderedSame
            }?.value ?? ""
        guard MKVTrackArgumentBuilder.isSafeText(title) else {
            throw LosslessJoinExecutionError.invalidHeaderNormalization
        }

        var arguments = [
            "--output", outputURL.standardizedFileURL.path,
            "--flush-on-close",
            "--normalize-language-ietf", "canonical",
            "--disable-track-statistics-tags",
            "--append-mode", "file",
            "--append-to", appendMappings.joined(separator: ","),
            "--track-order", trackOrder.joined(separator: ","),
            "--title", title,
            "--chapters", chaptersURL.standardizedFileURL.path,
        ]

        for laneIndex in normalized {
            guard let sourceTrackID = mapping.lanes[laneIndex].trackIDsBySource[0],
                let metadata = indexedTracks[0][sourceTrackID],
                let laneURLs = normalizedVideoURLs[laneIndex]
            else { throw LosslessJoinExecutionError.invalidHeaderNormalization }
            for sourceIndex in sources.indices {
                if sourceIndex == 0 {
                    do {
                        arguments.append(
                            contentsOf: try MKVTrackArgumentBuilder.metadata(
                                trackID: 0,
                                track: metadata
                            )
                        )
                    } catch {
                        throw LosslessJoinExecutionError.invalidHeaderNormalization
                    }
                }
                arguments.append(contentsOf: [
                    "--no-buttons", "--no-attachments", "--no-chapters",
                    "--no-track-tags", "--no-global-tags",
                ])
                let path = laneURLs[sourceIndex].standardizedFileURL.path
                arguments.append(sourceIndex == 0 ? path : "+\(path)")
            }
        }

        if !copyLaneIndices.isEmpty {
            for sourceIndex in sources.indices {
                let tracks = try copyLaneIndices.map { laneIndex -> MediaTrack in
                    guard let trackID = mapping.lanes[laneIndex].trackIDsBySource[sourceIndex],
                        let track = indexedTracks[sourceIndex][trackID]
                    else { throw LosslessJoinExecutionError.invalidHeaderNormalization }
                    return track
                }
                do {
                    arguments.append(
                        contentsOf: try MKVTrackArgumentBuilder.selection(tracks: tracks))
                } catch {
                    throw LosslessJoinExecutionError.invalidHeaderNormalization
                }
                arguments.append(contentsOf: [
                    "--no-buttons", "--no-attachments", "--no-chapters",
                ])
                if sourceIndex > 0 {
                    arguments.append(contentsOf: ["--no-track-tags", "--no-global-tags"])
                }
                let path = sources[sourceIndex].sourceURL.standardizedFileURL.path
                arguments.append(sourceIndex == 0 ? path : "+\(path)")
            }
        }

        let commandBytes = arguments.reduce(0) { $0 + $1.utf8.count + 1 }
        guard arguments.count <= 20_000, commandBytes <= 1_048_576 else {
            throw LosslessJoinExecutionError.invalidHeaderNormalization
        }
        return arguments
    }

    static func trackUIDArguments(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        normalizedVideoLaneIndices: [Int],
        outputURL: URL
    ) throws -> [String] {
        let normalized = normalizedVideoLaneIndices.sorted()
        guard !normalized.isEmpty, Set(normalized).count == normalized.count,
            safeAbsoluteFileURL(outputURL), outputURL.pathExtension.lowercased() == "mkv"
        else { throw LosslessJoinExecutionError.invalidHeaderNormalization }
        var arguments = [outputURL.standardizedFileURL.path, "--abort-on-warnings"]
        for laneIndex in normalized {
            guard mapping.lanes.indices.contains(laneIndex),
                let trackID = mapping.lanes[laneIndex].trackIDsBySource[0],
                let uid = sources[0].tracks.first(where: { $0.id == trackID })?.uid
            else { throw LosslessJoinExecutionError.missingStableTrackIdentity }
            let videoOrdinal = mapping.lanes.prefix(through: laneIndex).filter {
                $0.kind == .video
            }.count
            arguments.append(contentsOf: [
                "--edit", "track:v\(videoOrdinal)",
                "--set", "track-uid=\(uid)",
            ])
        }
        return arguments
    }

    private func validateNormalizedVideo(_ url: URL, source: MediaAsset) throws {
        guard
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            ]), values.isRegularFile == true, values.isSymbolicLink != true,
            let size = values.fileSize, size > 0
        else { throw LosslessJoinExecutionError.unsafeHeaderNormalizedVideo }
        let sourceSize =
            source.fileSize
            ?? Int64((try? source.sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let maximum = sourceSize.multipliedReportingOverflow(by: 2)
        guard sourceSize > 0, !maximum.overflow, Int64(size) <= maximum.partialValue else {
            throw LosslessJoinExecutionError.unsafeHeaderNormalizedVideo
        }
    }
}

private actor HeaderNormalizedJoinProgress {
    private let totalOperations: Int
    private let emit: @Sendable (VerifiedOutputToolProgress) async -> Void
    private var completedOperations = 0

    init(
        totalOperations: Int,
        emit: @escaping @Sendable (VerifiedOutputToolProgress) async -> Void
    ) {
        self.totalOperations = totalOperations
        self.emit = emit
    }

    func update(_ update: VerifiedOutputToolProgress) async {
        let activeFraction = min(update.fractionCompleted, 0.99)
        let fraction = (Double(completedOperations) + activeFraction) / Double(totalOperations)
        await emit(
            VerifiedOutputToolProgress(
                phase: .headerNormalizingJoin,
                percentage: Int((fraction * 100).rounded())
            )
        )
    }

    func completeOperation() async {
        completedOperations = min(totalOperations, completedOperations + 1)
        let fraction = Double(completedOperations) / Double(totalOperations)
        await emit(
            VerifiedOutputToolProgress(
                phase: .headerNormalizingJoin,
                percentage: Int((fraction * 100).rounded())
            )
        )
    }
}
