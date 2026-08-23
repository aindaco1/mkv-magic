import Foundation
import MKVMagicSystem
import XCTest

@testable import MKVMagicMedia

final class RealToolInspectionTests: XCTestCase {
    func testBundledToolsCreateAndInspectRepresentativeMatroska() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["MKV_MAGIC_TOOL_ROOT"] else {
            throw XCTSkip("Set MKV_MAGIC_TOOL_ROOT to run bundled-tool integration")
        }
        let catalog = try ToolCatalog(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        let runner = FoundationCommandRunner()
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkv-magic-real-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let rawAudio = fixtureRoot.appendingPathComponent("silence.pcm")
        let media = fixtureRoot.appendingPathComponent("fixture.mkv")
        try Data(repeating: 0, count: 96_000).write(to: rawAudio)

        let createResult = try await runner.run(
            CommandRequest(
                executableURL: try catalog.url(for: .ffmpeg),
                arguments: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", rawAudio.path,
                    "-c:a", "aac",
                    "-metadata", "title=Inspector Fixture",
                    "-metadata:s:a:0", "language=eng",
                    "-metadata:s:a:0", "title=Main Audio",
                    media.path,
                ],
                timeout: 60
            )
        )
        XCTAssertEqual(createResult.exitCode, 0, createResult.standardError.text)

        let inspector = UnifiedMediaInspector(
            ffprobeURL: try catalog.url(for: .ffprobe),
            mkvmergeURL: try catalog.url(for: .mkvmerge),
            runner: runner
        )
        let asset = try await inspector.inspect(media)

        XCTAssertEqual(asset.container, "matroska")
        XCTAssertEqual(asset.metadata["title"], "Inspector Fixture")
        XCTAssertEqual(asset.tracks.count, 1)
        XCTAssertEqual(asset.tracks.first?.kind, .audio)
        XCTAssertEqual(asset.tracks.first?.codecID, "A_AAC")
        XCTAssertEqual(asset.tracks.first?.language, "eng")
        XCTAssertEqual(asset.tracks.first?.title, "Main Audio")
        XCTAssertGreaterThan(asset.duration?.nanoseconds ?? 0, 0)
    }
}
