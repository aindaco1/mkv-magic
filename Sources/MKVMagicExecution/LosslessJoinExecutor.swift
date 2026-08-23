import Foundation
import MKVMagicCore
import MKVMagicMedia
import MKVMagicSystem

public enum LosslessJoinExecutionError: Error, Equatable, Sendable {
    case unsupportedDestination
    case invalidPath
    case requiresReview(JoinAppendDisposition)
    case invalidChapterTimeline
    case missingStableTrackIdentity
    case staleSource
    case unsafeChapterOutput
    case chapterVerificationFailed
    case toolFailed(tool: String, exitCode: Int32, message: String)
    case committedOutputAuditFailed(outputURL: URL, reason: String)
}

extension LosslessJoinExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedDestination:
            "Lossless joining currently creates one Matroska MKV output."
        case .invalidPath:
            "Every join input, chapter document, and output needs a safe absolute file path."
        case .requiresReview(let disposition):
            "This joined group is classified as \(disposition.rawValue) and cannot use the "
                + "lossless executor yet."
        case .invalidChapterTimeline:
            "The reviewed chapter timeline does not match the full joined source duration."
        case .missingStableTrackIdentity:
            "Every output lane needs a unique stable Matroska track identity before joining."
        case .staleSource:
            "A source changed after the lossless join preview was created."
        case .unsafeChapterOutput:
            "mkvextract did not create a safe, bounded chapter document."
        case .chapterVerificationFailed:
            "The output chapters do not exactly match the reviewed joined chapter document."
        case .toolFailed(let tool, let exitCode, let message):
            "\(tool) could not complete the lossless join (code \(exitCode)): \(message)"
        case .committedOutputAuditFailed(let outputURL, let reason):
            "The verified MKV was saved as \(outputURL.lastPathComponent), but its final reopen "
                + "audit failed: \(reason)"
        }
    }
}

public struct LosslessJoinSourceRevision: Equatable, Sendable {
    public let fileSize: Int64
    public let modificationDate: Date
    public let fileNumber: UInt64?
    public let systemNumber: UInt64?

    public init(
        fileSize: Int64,
        modificationDate: Date,
        fileNumber: UInt64? = nil,
        systemNumber: UInt64? = nil
    ) {
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.fileNumber = fileNumber
        self.systemNumber = systemNumber
    }

    static func read(_ rawURL: URL) throws -> Self {
        let url = rawURL.standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/"),
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true, values.isSymbolicLink != true
        else {
            throw LosslessJoinExecutionError.invalidPath
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            throw LosslessJoinExecutionError.invalidPath
        }
        return Self(
            fileSize: size,
            modificationDate: modificationDate,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            systemNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value
        )
    }
}

public struct LosslessJoinPreview: Equatable, Sendable {
    public let sources: [MediaAsset]
    public let mapping: JoinTrackMapping
    public let chapters: JoinedChapterComposition
    public let sourceRevisions: [LosslessJoinSourceRevision]

    init(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        chapters: JoinedChapterComposition,
        sourceRevisions: [LosslessJoinSourceRevision]
    ) {
        self.sources = sources
        self.mapping = mapping
        self.chapters = chapters
        self.sourceRevisions = sourceRevisions
    }
}

public struct MKVLosslessJoiner<Runner: CommandRunning>: Sendable {
    private let executableURL: URL
    private let runner: Runner

    public init(executableURL: URL, runner: Runner) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public func join(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        chaptersURL: URL,
        outputURL: URL
    ) async throws {
        let arguments = try Self.arguments(
            sources: sources,
            mapping: mapping,
            chaptersURL: chaptersURL,
            outputURL: outputURL
        )
        let result = try await runner.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: arguments,
                timeout: 24 * 60 * 60,
                outputLimit: 1_048_576
            )
        )
        guard result.exitCode == 0 else {
            throw LosslessJoinExecutionError.toolFailed(
                tool: "mkvmerge",
                exitCode: result.exitCode,
                message: Self.conciseMessage(result)
            )
        }
    }

    public static func arguments(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        chaptersURL: URL,
        outputURL: URL
    ) throws -> [String] {
        try LosslessJoinPolicy.validate(sources: sources, mapping: mapping)
        guard safeAbsoluteFileURL(chaptersURL), safeAbsoluteFileURL(outputURL) else {
            throw LosslessJoinExecutionError.invalidPath
        }

        let appendTo = mapping.lanes.flatMap { lane in
            sources.indices.dropFirst().map { sourceIndex in
                let sourceTrackID = lane.trackIDsBySource[sourceIndex]!
                let destinationTrackID = lane.trackIDsBySource[sourceIndex - 1]!
                return "\(sourceIndex):\(sourceTrackID):\(sourceIndex - 1):\(destinationTrackID)"
            }
        }.joined(separator: ",")
        let trackOrder = mapping.lanes.map { "0:\($0.trackIDsBySource[0]!)" }
            .joined(separator: ",")

        var arguments = [
            "--output", outputURL.standardizedFileURL.path,
            "--abort-on-warnings",
            "--flush-on-close",
            "--normalize-language-ietf", "canonical",
            "--disable-track-statistics-tags",
            "--append-mode", "file",
            "--append-to", appendTo,
            "--track-order", trackOrder,
            "--chapters", chaptersURL.standardizedFileURL.path,
        ]
        for sourceIndex in sources.indices {
            arguments.append(
                contentsOf: trackSelectionArguments(
                    mapping: mapping,
                    sourceIndex: sourceIndex
                ))
            arguments.append(contentsOf: [
                "--no-buttons", "--no-attachments", "--no-chapters",
            ])
            if sourceIndex > 0 {
                arguments.append(contentsOf: ["--no-track-tags", "--no-global-tags"])
            }
            let path = sources[sourceIndex].sourceURL.standardizedFileURL.path
            arguments.append(sourceIndex == 0 ? path : "+\(path)")
        }
        return arguments
    }

    private static func trackSelectionArguments(
        mapping: JoinTrackMapping,
        sourceIndex: Int
    ) -> [String] {
        var arguments = [String]()
        for (kind, some, none) in [
            (MediaTrackKind.video, "--video-tracks", "--no-video"),
            (.audio, "--audio-tracks", "--no-audio"),
            (.subtitle, "--subtitle-tracks", "--no-subtitles"),
        ] {
            let ids = mapping.lanes.filter { $0.kind == kind }
                .compactMap { $0.trackIDsBySource[sourceIndex] }
            if ids.isEmpty {
                arguments.append(none)
            } else {
                arguments.append(contentsOf: [some, ids.map(String.init).joined(separator: ",")])
            }
        }
        return arguments
    }

    private static func conciseMessage(_ result: CommandResult) -> String {
        let message =
            [result.standardError.text, result.standardOutput.text]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Unknown tool error"
        return String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }
}

public struct LosslessJoinExecutor<Runner: CommandRunning, Inspector: MediaInspecting>: Sendable {
    private let joiner: MKVLosslessJoiner<Runner>
    private let mkvextractURL: URL
    private let runner: Runner
    private let inspector: Inspector
    private let codec = MatroskaChapterXMLCodec()
    private let verifier = LosslessJoinOutputVerifier()

    public init(
        mkvmergeURL: URL,
        mkvextractURL: URL,
        runner: Runner,
        inspector: Inspector
    ) {
        joiner = MKVLosslessJoiner(executableURL: mkvmergeURL, runner: runner)
        self.mkvextractURL = mkvextractURL
        self.runner = runner
        self.inspector = inspector
    }

    public func preview(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        chapters: JoinedChapterComposition
    ) throws -> LosslessJoinPreview {
        try LosslessJoinPolicy.validate(
            sources: sources,
            mapping: mapping,
            chapters: chapters
        )
        let revisions = try sources.map { try LosslessJoinSourceRevision.read($0.sourceURL) }
        for (source, revision) in zip(sources, revisions) {
            if let inspectedSize = source.fileSize, inspectedSize != revision.fileSize {
                throw LosslessJoinExecutionError.staleSource
            }
        }
        return LosslessJoinPreview(
            sources: sources,
            mapping: mapping,
            chapters: chapters,
            sourceRevisions: revisions
        )
    }

    public func execute(
        preview: LosslessJoinPreview,
        destinationURL: URL,
        onStage: @escaping @Sendable (VerifiedOutputExecutionStage) async throws -> Void = { _ in }
    ) async throws -> MediaAsset {
        guard destinationURL.pathExtension.lowercased() == "mkv" else {
            throw LosslessJoinExecutionError.unsupportedDestination
        }
        try LosslessJoinPolicy.validate(
            sources: preview.sources,
            mapping: preview.mapping,
            chapters: preview.chapters
        )
        try Task.checkCancellation()
        try validateCurrent(preview)

        let transaction = VerifiedOutputTransaction(
            sourceURL: preview.sources[0].sourceURL,
            destinationURL: destinationURL
        )
        do {
            let temporaryOutput = try await transaction.prepareEmptyOutput()
            let expectedChapters = try codec.serialize(preview.chapters.document)
            let output = try await withPrivateDirectory { directory in
                let chaptersURL = directory.appendingPathComponent(
                    "joined-chapters.xml",
                    isDirectory: false
                )
                try expectedChapters.write(to: chaptersURL, options: .atomic)
                try await joiner.join(
                    sources: preview.sources,
                    mapping: preview.mapping,
                    chaptersURL: chaptersURL,
                    outputURL: temporaryOutput
                )
                try Task.checkCancellation()
                try validateCurrent(preview)
                return temporaryOutput
            }

            try Task.checkCancellation()
            try await onStage(.verifying)
            try Task.checkCancellation()
            let temporaryAsset = try await inspector.inspect(output)
            try verifier.verify(
                sources: preview.sources,
                mapping: preview.mapping,
                chapters: preview.chapters,
                output: temporaryAsset
            )
            try await verifyChapters(in: output, expectedCanonical: expectedChapters)
            try Task.checkCancellation()
            try validateCurrent(preview)
            try await transaction.markVerified()
            try await onStage(.committing)
            try Task.checkCancellation()
            let committedURL = try await transaction.commit()
            do {
                let committedAsset = try await inspector.inspect(committedURL)
                try verifier.verify(
                    sources: preview.sources,
                    mapping: preview.mapping,
                    chapters: preview.chapters,
                    output: committedAsset
                )
                try await verifyChapters(
                    in: committedURL,
                    expectedCanonical: expectedChapters
                )
                try validateCurrent(preview)
                return committedAsset
            } catch {
                throw LosslessJoinExecutionError.committedOutputAuditFailed(
                    outputURL: committedURL,
                    reason: error.localizedDescription
                )
            }
        } catch {
            await transaction.cancel()
            throw error
        }
    }

    public func validateCurrent(_ preview: LosslessJoinPreview) throws {
        guard preview.sources.count == preview.sourceRevisions.count else {
            throw LosslessJoinExecutionError.staleSource
        }
        for (source, expected) in zip(preview.sources, preview.sourceRevisions) {
            guard try LosslessJoinSourceRevision.read(source.sourceURL) == expected else {
                throw LosslessJoinExecutionError.staleSource
            }
        }
    }

    private func verifyChapters(in fileURL: URL, expectedCanonical: Data) async throws {
        let extracted = try await extractCanonicalChapters(from: fileURL)
        guard extracted == expectedCanonical else {
            throw LosslessJoinExecutionError.chapterVerificationFailed
        }
    }

    private func extractCanonicalChapters(from fileURL: URL) async throws -> Data {
        try await withPrivateDirectory { directory in
            let outputURL = directory.appendingPathComponent("chapters.xml", isDirectory: false)
            let result = try await runner.run(
                CommandRequest(
                    executableURL: mkvextractURL,
                    arguments: [fileURL.path, "chapters", outputURL.path],
                    timeout: 120,
                    outputLimit: 1_048_576
                )
            )
            guard result.exitCode == 0 else {
                throw LosslessJoinExecutionError.toolFailed(
                    tool: "mkvextract",
                    exitCode: result.exitCode,
                    message: conciseMessage(result)
                )
            }
            if !FileManager.default.fileExists(atPath: outputURL.path) {
                return try codec.serialize(MatroskaChapterDocument())
            }
            guard
                let values = try? outputURL.resourceValues(forKeys: [
                    .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
                ]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                let size = values.fileSize,
                size >= 0,
                size <= MatroskaChapterXMLCodec.maximumInputBytes
            else {
                throw LosslessJoinExecutionError.unsafeChapterOutput
            }
            if size == 0 { return try codec.serialize(MatroskaChapterDocument()) }
            let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
            return try codec.serialize(codec.parse(data))
        }
    }

    private func conciseMessage(_ result: CommandResult) -> String {
        let message =
            [result.standardError.text, result.standardOutput.text]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Unknown tool error"
        return String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }

    private func withPrivateDirectory<T: Sendable>(
        _ operation: (URL) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-lossless-join-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await operation(directory)
    }
}

private enum LosslessJoinPolicy {
    static func validate(
        sources: [MediaAsset],
        mapping: JoinTrackMapping,
        chapters: JoinedChapterComposition? = nil
    ) throws {
        for source in sources where !safeAbsoluteFileURL(source.sourceURL) {
            throw LosslessJoinExecutionError.invalidPath
        }
        let report = try JoinCompatibilityAnalyzer().analyze(
            sources: sources,
            mapping: mapping
        )
        guard report.disposition == .losslessCandidate else {
            throw LosslessJoinExecutionError.requiresReview(report.disposition)
        }
        let referenceUIDs = mapping.lanes.compactMap { lane -> UInt64? in
            guard let trackID = lane.trackIDsBySource[0] else { return nil }
            return sources[0].tracks.first { $0.id == trackID }?.uid
        }
        guard referenceUIDs.count == mapping.lanes.count,
            Set(referenceUIDs).count == referenceUIDs.count
        else {
            throw LosslessJoinExecutionError.missingStableTrackIdentity
        }
        guard let chapters else { return }
        let duration = try expectedDuration(sources)
        guard chapters.duration == duration else {
            throw LosslessJoinExecutionError.invalidChapterTimeline
        }
        do {
            _ = try chapters.document.validated(mediaDuration: duration)
        } catch {
            throw LosslessJoinExecutionError.invalidChapterTimeline
        }
    }

    private static func expectedDuration(_ sources: [MediaAsset]) throws -> MediaTime {
        var total: Int64 = 0
        for source in sources {
            guard let duration = source.duration, duration > .zero else {
                throw LosslessJoinExecutionError.invalidChapterTimeline
            }
            let result = total.addingReportingOverflow(duration.nanoseconds)
            guard !result.overflow else {
                throw LosslessJoinExecutionError.invalidChapterTimeline
            }
            total = result.partialValue
        }
        return MediaTime(nanoseconds: total)
    }
}

private func safeAbsoluteFileURL(_ url: URL) -> Bool {
    let standardized = url.standardizedFileURL
    return standardized.isFileURL
        && standardized.path.hasPrefix("/")
        && !standardized.path.contains("/../")
}
