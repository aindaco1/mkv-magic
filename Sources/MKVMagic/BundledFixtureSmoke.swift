import CryptoKit
import Foundation
import MKVMagicExecution
import MKVMagicMedia
import MKVMagicSystem

struct BundledFixtureSmokeReport: Codable, Equatable, Sendable {
    static let schema = "mkv-magic-bundled-fixture-smoke-v1"

    let schema: String
    let architecture: String
    let sourceBytes: Int
    let outputBytes: Int
    let extractedTrackBytes: Int
    let trackCount: Int
    let originalPreserved: Bool

    init(
        architecture: String,
        sourceBytes: Int,
        outputBytes: Int,
        extractedTrackBytes: Int,
        trackCount: Int,
        originalPreserved: Bool
    ) {
        schema = Self.schema
        self.architecture = architecture
        self.sourceBytes = sourceBytes
        self.outputBytes = outputBytes
        self.extractedTrackBytes = extractedTrackBytes
        self.trackCount = trackCount
        self.originalPreserved = originalPreserved
    }
}

enum BundledFixtureSmokeError: Error, Equatable {
    case invalidFixture(String)
    case toolFailed(BundledTool, Int32)
}

struct BundledFixtureSmoke<Runner: CommandRunning> {
    private let runner: Runner

    init(runner: Runner) {
        self.runner = runner
    }

    func run(toolRoot: URL) async throws -> BundledFixtureSmokeReport {
        let catalog = try ToolCatalog(rootURL: toolRoot)
        return try await PrivateTemporaryDirectory.withDirectory(
            prefix: "mkv-magic-signed-fixture"
        ) { fixtureRoot in
            let rawAudio = fixtureRoot.appendingPathComponent("silence.pcm")
            let source = fixtureRoot.appendingPathComponent("source.mkv")
            let output = fixtureRoot.appendingPathComponent("edited.mkv")
            let extractedTrack = fixtureRoot.appendingPathComponent("audio.aac")
            try Data(repeating: 0, count: 96_000).write(to: rawAudio, options: .atomic)

            try await requireSuccess(
                tool: .ffmpeg,
                arguments: [
                    "-nostdin", "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-c:a", "aac", "-metadata", "title=Signed Fixture Source",
                    "-metadata:s:a:0", "language=eng",
                    "-metadata:s:a:0", "title=Main Audio", source.path,
                ],
                catalog: catalog
            )
            let sourceData = try Data(contentsOf: source, options: [.mappedIfSafe])
            guard !sourceData.isEmpty else {
                throw BundledFixtureSmokeError.invalidFixture("empty source")
            }
            let sourceDigest = SHA256.hash(data: sourceData)

            let inspector = UnifiedMediaInspector(
                ffprobeURL: try catalog.url(for: .ffprobe),
                mkvmergeURL: try catalog.url(for: .mkvmerge),
                runner: runner
            )
            let sourceAsset = try await inspector.inspect(source)
            guard sourceAsset.container.lowercased().contains("matroska"),
                sourceAsset.metadata["title"] == "Signed Fixture Source",
                sourceAsset.tracks.count == 1,
                sourceAsset.tracks.first?.kind == .audio,
                sourceAsset.tracks.first?.codecID == "A_AAC",
                sourceAsset.tracks.first?.language == "eng"
            else {
                throw BundledFixtureSmokeError.invalidFixture("source inspection")
            }

            let outputAsset = try await SegmentTitleEditExecutor(
                mkvpropeditURL: try catalog.url(for: .mkvpropedit),
                runner: runner,
                inspector: inspector
            ).execute(
                source: sourceAsset,
                title: "Signed Fixture Edited",
                destinationURL: output
            )
            let sourceAfter = try await inspector.inspect(source)
            let sourceDigestAfter = SHA256.hash(
                data: try Data(contentsOf: source, options: [.mappedIfSafe])
            )
            guard outputAsset.metadata["title"] == "Signed Fixture Edited",
                sourceAfter.metadata["title"] == "Signed Fixture Source",
                sourceDigestAfter == sourceDigest,
                outputAsset.tracks == sourceAsset.tracks,
                let trackID = outputAsset.tracks.first?.id
            else {
                throw BundledFixtureSmokeError.invalidFixture("verified edit")
            }

            try await requireSuccess(
                tool: .mkvextract,
                arguments: ["tracks", output.path, "\(trackID):\(extractedTrack.path)"],
                catalog: catalog
            )
            let sourceBytes = try regularFileSize(source)
            let outputBytes = try regularFileSize(output)
            let extractedTrackBytes = try regularFileSize(extractedTrack)
            return BundledFixtureSmokeReport(
                architecture: catalog.architecture.rawValue,
                sourceBytes: sourceBytes,
                outputBytes: outputBytes,
                extractedTrackBytes: extractedTrackBytes,
                trackCount: outputAsset.tracks.count,
                originalPreserved: true
            )
        }
    }

    private func requireSuccess(
        tool: BundledTool,
        arguments: [String],
        catalog: ToolCatalog
    ) async throws {
        let result = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: tool),
                arguments: arguments,
                timeout: 60,
                outputLimit: 262_144
            )
        )
        guard result.exitCode == 0 else {
            throw BundledFixtureSmokeError.toolFailed(tool, result.exitCode)
        }
    }

    private func regularFileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
            let size = values.fileSize, size > 0
        else {
            throw BundledFixtureSmokeError.invalidFixture("unsafe output")
        }
        return size
    }
}

extension BundledFixtureSmoke where Runner == FoundationCommandRunner {
    init() {
        self.init(runner: FoundationCommandRunner())
    }
}
