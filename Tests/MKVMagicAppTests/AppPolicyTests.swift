import AppKit
import MKVMagicCore
import MKVMagicSystem
import XCTest

@testable import MKVMagic

@MainActor
private final class FakeUpdateChecker: UpdateChecking {
    private(set) var checks = 0

    func checkForUpdates() {
        checks += 1
    }
}

final class AppPolicyTests: XCTestCase {
    @MainActor
    func testAppDelegateAcceptsNarrowUpdateAdapter() {
        let checker = FakeUpdateChecker()
        _ = AppDelegate(updateController: checker)
        XCTAssertEqual(checker.checks, 0)
    }

    func testBundledToolVerificationUsesOnlyVersionArguments() {
        XCTAssertEqual(
            BundledToolVerification.arguments(for: .ffmpeg),
            ["-hide_banner", "-version"]
        )
        XCTAssertEqual(BundledToolVerification.arguments(for: .mkvmerge), ["--version"])
    }

    func testFirstInspectedAssetIsSelectedAutomatically() {
        XCTAssertEqual(AssetSelectionPolicy.rowToSelect(currentRow: -1, assetCount: 1), 0)
        XCTAssertNil(AssetSelectionPolicy.rowToSelect(currentRow: 0, assetCount: 2))
        XCTAssertNil(AssetSelectionPolicy.rowToSelect(currentRow: -1, assetCount: 0))
    }

    func testEditedOutputNamePreservesContainerExtension() {
        XCTAssertEqual(
            OutputNamingPolicy.suggestedFilename(
                for: URL(fileURLWithPath: "/Media/Movie.mkv")),
            "Movie — Edited.mkv"
        )
        XCTAssertEqual(
            OutputNamingPolicy.suggestedFilename(
                for: URL(fileURLWithPath: "/Media/Untitled")),
            "Untitled — Edited.mkv"
        )
    }

    func testInspectorSeparatesAttachmentsAndAvoidsDecodedAudioBitDepth() {
        let audio = MediaTrack(id: 0, kind: .audio, codec: "aac", bitDepth: 32)
        let attachment = MediaTrack(id: 1, kind: .attachment, codec: "unknown")
        let video = MediaTrack(id: 2, kind: .video, codec: "av1", bitDepth: 10)

        XCTAssertEqual(
            InspectorPresentationPolicy.playableTracks(in: [audio, attachment, video]),
            [audio, video]
        )
        XCTAssertNil(InspectorPresentationPolicy.displayedBitDepth(for: audio))
        XCTAssertEqual(InspectorPresentationPolicy.displayedBitDepth(for: video), 10)
    }

    func testHistoryLocationCreatesPrivateAppSupportDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-history-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try AppHistoryLocation.makeStore(applicationSupportURL: root)
        try await store.save([])

        let appDirectory = root.appendingPathComponent("com.dustwave.mkvmagic")
        let attributes = try FileManager.default.attributesOfItem(atPath: appDirectory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appDirectory.appendingPathComponent("job-history.json").path
            )
        )
    }

    func testHistoryLocationRejectsSymlinkedAppDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-history-\(UUID().uuidString)",
            isDirectory: true
        )
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-history-target-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("com.dustwave.mkvmagic"),
            withDestinationURL: target
        )

        XCTAssertThrowsError(
            try AppHistoryLocation.makeStore(applicationSupportURL: root)
        ) {
            XCTAssertEqual(
                $0 as? AppHistoryLocationError,
                .unsafeApplicationSupport
            )
        }
    }

    @MainActor
    func testMainWindowContentKeepsUsableWidthAfterLayout() throws {
        let controller = MainViewController(model: AppModel())
        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_080, height: 680)
        controller.view.layoutSubtreeIfNeeded()

        let splitView = try XCTUnwrap(
            controller.view.subviews.compactMap { $0 as? NSSplitView }.first)
        let footer = try XCTUnwrap(
            controller.view.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        XCTAssertGreaterThan(splitView.frame.width, 1_000)
        XCTAssertGreaterThan(splitView.frame.height, 600)
        XCTAssertGreaterThan(footer.frame.width, 1_000)
        XCTAssertEqual(footer.frame.height, 52, accuracy: 0.5)
        XCTAssertEqual(splitView.arrangedSubviews.count, 3)
        XCTAssertTrue(splitView.arrangedSubviews.allSatisfy { $0.frame.width > 0 })
    }
}
