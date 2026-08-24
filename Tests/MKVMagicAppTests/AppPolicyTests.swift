import AppKit
import CryptoKit
import MKVMagicCore
import MKVMagicExecution
import MKVMagicPlanning
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

private struct FixedAppQueueEnvironmentReader: MediaQueueSchedulingEnvironmentReading {
    let environment: MediaQueueSchedulingEnvironment

    func read() -> MediaQueueSchedulingEnvironment { environment }
}

final class AppPolicyTests: XCTestCase {
    @MainActor
    func testAppearanceAwareBorderTracksSemanticSeparatorAcrossAppearances() throws {
        let view = AppearanceAwareBorderStackView(frame: .zero)
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        view.appearance = lightAppearance
        view.viewDidChangeEffectiveAppearance()
        let lightComponents = try XCTUnwrap(view.layer?.borderColor?.components)
        var expectedLightColor: CGColor?
        lightAppearance.performAsCurrentDrawingAppearance {
            expectedLightColor = NSColor.separatorColor.cgColor
        }
        XCTAssertEqual(lightComponents, expectedLightColor?.components)

        view.appearance = darkAppearance
        view.viewDidChangeEffectiveAppearance()
        let darkComponents = try XCTUnwrap(view.layer?.borderColor?.components)
        var expectedDarkColor: CGColor?
        darkAppearance.performAsCurrentDrawingAppearance {
            expectedDarkColor = NSColor.separatorColor.cgColor
        }
        XCTAssertEqual(darkComponents, expectedDarkColor?.components)
        XCTAssertNotEqual(lightComponents, darkComponents)
    }

    @MainActor
    func testKeyboardNavigationPolicyEnablesAutomaticRecalculationAndKeepsInitialResponder() {
        let content = NSViewController()
        let firstResponder = NSButton(title: "Start here", target: nil, action: nil)
        content.view.addSubview(firstResponder)
        let window = NSWindow(contentViewController: content)
        window.autorecalculatesKeyViewLoop = false

        window.configureMKVMagicKeyboardNavigation(startingAt: firstResponder)

        XCTAssertTrue(window.autorecalculatesKeyViewLoop)
        XCTAssertTrue(window.initialFirstResponder === firstResponder)
    }

    @MainActor
    func testAppDelegateAcceptsNarrowUpdateAdapter() {
        let checker = FakeUpdateChecker()
        _ = AppDelegate(updateController: checker)
        XCTAssertEqual(checker.checks, 0)
    }

    @MainActor
    func testAppDelegateCreatesVisibleUsableMainWindow() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-launch-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let queueStore = try JSONJobQueueStore(
            fileURL: root.appendingPathComponent("job-queue.json")
        )
        let model = AppModel(
            queueStoreFactory: { queueStore },
            queueEnvironmentReader: FixedAppQueueEnvironmentReader(
                environment: .init(isOnBattery: false, thermalPressure: .critical)
            )
        )
        let checker = FakeUpdateChecker()
        let delegate = AppDelegate(model: model, updateController: checker)

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "MKV Magic" })
        defer { window.close() }
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(contentView.frame.size.width, 1_080, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 680, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 820)
        XCTAssertEqual(window.minSize.height, 520)
        XCTAssertTrue(window.contentViewController is MainViewController)
        let openItem = try XCTUnwrap(
            NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.title == "File" }?
                .item(withTitle: "Open…")
        )
        XCTAssertEqual(openItem.keyEquivalent, "o")
        XCTAssertEqual(openItem.action, #selector(MainViewController.chooseFiles))
        XCTAssertTrue(openItem.target === window.contentViewController)
        let appMenu = try XCTUnwrap(NSApp.mainMenu?.item(at: 0)?.submenu)
        let servicesItem = try XCTUnwrap(appMenu.item(withTitle: "Services"))
        XCTAssertTrue(NSApp.servicesMenu === servicesItem.submenu)
        let hideOthers = try XCTUnwrap(appMenu.item(withTitle: "Hide Others"))
        XCTAssertEqual(hideOthers.keyEquivalent, "h")
        XCTAssertEqual(hideOthers.keyEquivalentModifierMask, [.command, .option])
        XCTAssertEqual(hideOthers.action, #selector(NSApplication.hideOtherApplications(_:)))
        XCTAssertEqual(
            appMenu.item(withTitle: "Show All")?.action,
            #selector(NSApplication.unhideAllApplications(_:))
        )
        let helpMenu = try XCTUnwrap(
            NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Help" }
        )
        XCTAssertTrue(NSApp.helpMenu === helpMenu)
        let helpItem = try XCTUnwrap(helpMenu.item(withTitle: "MKV Magic Help"))
        XCTAssertEqual(helpItem.keyEquivalent, "?")
        XCTAssertEqual(helpItem.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(helpItem.action, #selector(AppDelegate.showHelp))
        XCTAssertTrue(helpItem.target === delegate)
        XCTAssertTrue(
            NSApp.sendAction(
                try XCTUnwrap(helpItem.action),
                to: helpItem.target,
                from: helpItem
            )
        )
        let helpWindow = try XCTUnwrap(NSApp.windows.first { $0.title == "MKV Magic Help" })
        defer { helpWindow.close() }
        XCTAssertTrue(helpWindow.isVisible)
        XCTAssertEqual(helpWindow.minSize, NSSize(width: 520, height: 420))
        XCTAssertEqual(
            helpWindow.initialFirstResponder?.accessibilityLabel(),
            "MKV Magic help topics"
        )
        let helpText = try XCTUnwrap(
            descendants(in: try XCTUnwrap(helpWindow.contentView))
                .compactMap { $0 as? NSTextView }.first
        )
        XCTAssertTrue(helpText.string.contains("Metadata edits use MKVToolNix without encoding"))
        XCTAssertTrue(helpText.string.contains("Moving originals to Trash is explicit"))
        XCTAssertTrue(helpText.string.contains("has no accounts, analytics, uploads"))
        XCTAssertTrue(helpText.string.contains("Help > Third-Party Software"))
        XCTAssertTrue(helpText.string.contains("reinspect the source"))
        XCTAssertTrue(helpText.string.contains("privacy-safe report"))
        if let capturePath = ProcessInfo.processInfo.environment[
            "MKV_MAGIC_HELP_CAPTURE"
        ], capturePath.hasPrefix("/"), let content = helpWindow.contentView {
            helpWindow.setContentSize(helpWindow.minSize)
            try captureWindow(window: helpWindow, content: content, at: capturePath)
        }
        let thirdPartyItem = try XCTUnwrap(
            helpMenu.item(withTitle: "Third-Party Software…")
        )
        XCTAssertEqual(thirdPartyItem.action, #selector(AppDelegate.showThirdPartySoftware))
        XCTAssertTrue(thirdPartyItem.target === delegate)
        XCTAssertTrue(
            NSApp.sendAction(
                try XCTUnwrap(thirdPartyItem.action),
                to: thirdPartyItem.target,
                from: thirdPartyItem
            )
        )
        let thirdPartyWindow = try XCTUnwrap(
            NSApp.windows.first { $0.title == "Third-Party Software" }
        )
        defer { thirdPartyWindow.close() }
        XCTAssertTrue(thirdPartyWindow.isVisible)
        XCTAssertEqual(thirdPartyWindow.minSize, NSSize(width: 560, height: 420))
        XCTAssertEqual(
            thirdPartyWindow.initialFirstResponder?.accessibilityLabel(),
            "License document"
        )
        XCTAssertTrue(
            descendants(in: try XCTUnwrap(thirdPartyWindow.contentView)).contains {
                $0.accessibilityLabel() == "Selected license text"
            }
        )
        let windowMenu = try XCTUnwrap(
            NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Window" }
        )
        XCTAssertTrue(NSApp.windowsMenu === windowMenu)
        for (title, key, action) in [
            ("Main Window", "0", #selector(MainViewController.showMainWindow)),
            ("Workflows", "1", #selector(MainViewController.showWorkflows)),
            ("Queue", "2", #selector(MainViewController.showQueue)),
            ("History", "3", #selector(MainViewController.showHistory)),
            ("Encoding Test", "4", #selector(MainViewController.showEncodingBenchmark)),
        ] {
            let item = try XCTUnwrap(windowMenu.item(withTitle: title))
            XCTAssertEqual(item.keyEquivalent, key)
            XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
            XCTAssertEqual(item.action, action)
            XCTAssertTrue(item.target === window.contentViewController)
        }
        window.orderOut(nil)
        XCTAssertFalse(window.isVisible)
        let mainWindowItem = try XCTUnwrap(windowMenu.item(withTitle: "Main Window"))
        XCTAssertTrue(
            NSApp.sendAction(
                try XCTUnwrap(mainWindowItem.action),
                to: mainWindowItem.target,
                from: mainWindowItem
            )
        )
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(
            window.initialFirstResponder?.accessibilityLabel(),
            "Choose media files or folders"
        )
        let accessibilityLabels = descendants(in: contentView).compactMap {
            $0.accessibilityLabel()
        }
        XCTAssertTrue(accessibilityLabels.contains("Inspected media files"))
        XCTAssertTrue(accessibilityLabels.contains("Selected media details"))
        XCTAssertTrue(accessibilityLabels.contains("Segment title"))
        XCTAssertTrue(accessibilityLabels.contains("Application status"))
        XCTAssertTrue(accessibilityLabels.contains("Plan impact"))
        await delegate.waitForInitialQueueCycle()
        let queueSnapshot = try await queueStore.load()
        XCTAssertTrue(queueSnapshot.jobs.isEmpty)
    }

    @MainActor
    func testThirdPartyDocumentLoaderAndViewerUseOnlyBoundedPackagedText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-third-party-\(UUID().uuidString)",
            isDirectory: true
        )
        let licenses = root.appendingPathComponent("Licenses", isDirectory: true)
        let toolLicenses = root.appendingPathComponent("Tools/Licenses/Codec", isDirectory: true)
        try FileManager.default.createDirectory(at: licenses, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: toolLicenses, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("Notices body".utf8).write(
            to: root.appendingPathComponent("THIRD_PARTY_NOTICES.md")
        )
        try Data("GPL body".utf8).write(
            to: licenses.appendingPathComponent("MKV-Magic-GPL-3.0.txt")
        )
        try Data("MIT body".utf8).write(
            to: licenses.appendingPathComponent("Sparkle-MIT.txt")
        )
        try Data("Codec body".utf8).write(
            to: toolLicenses.appendingPathComponent("COPYING")
        )

        let documents = try ThirdPartyDocumentLoader.load(from: root)
        XCTAssertEqual(
            documents.map(\.title),
            [
                "Third-Party Notices",
                "MKV Magic — GPL-3.0-or-later",
                "Sparkle — MIT",
                "Bundled Tools — Codec/COPYING",
            ]
        )
        XCTAssertEqual(
            documents.map(\.body), ["Notices body", "GPL body", "MIT body", "Codec body"])

        let controller = ThirdPartySoftwareWindowController(documents: documents)
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()
        let picker = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSPopUpButton }.first
        )
        let text = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextView }.first
        )
        XCTAssertEqual(picker.itemTitles, documents.map(\.title))
        XCTAssertEqual(text.string, "Notices body")
        picker.selectItem(at: 3)
        picker.sendAction(picker.action, to: picker.target)
        XCTAssertEqual(text.string, "Codec body")
        for button in buttons(in: content) where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }
        if let capturePath = ProcessInfo.processInfo.environment[
            "MKV_MAGIC_THIRD_PARTY_CAPTURE"
        ], capturePath.hasPrefix("/") {
            try captureWindow(window: window, content: content, at: capturePath)
        }

        let outside = root.deletingLastPathComponent().appendingPathComponent(
            "mkv-magic-outside-license-\(UUID().uuidString)"
        )
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let unsafeLink = toolLicenses.appendingPathComponent("UNSAFE")
        try FileManager.default.createSymbolicLink(at: unsafeLink, withDestinationURL: outside)
        XCTAssertThrowsError(try ThirdPartyDocumentLoader.load(from: root)) { error in
            XCTAssertEqual(
                error as? ThirdPartyDocumentLoaderError,
                .unsafeDocument("Tools/Licenses/Codec/UNSAFE")
            )
        }
    }

    func testBundledToolVerificationUsesOnlyVersionArguments() {
        XCTAssertEqual(
            BundledToolVerification.arguments(for: .ffmpeg),
            ["-hide_banner", "-version"]
        )
        XCTAssertEqual(BundledToolVerification.arguments(for: .mkvmerge), ["--version"])
    }

    func testBundledFixtureSmokeReportIsVersionedBoundedAndPathFree() throws {
        let report = BundledFixtureSmokeReport(
            architecture: "arm64",
            sourceBytes: 12_000,
            outputBytes: 12_100,
            extractedTrackBytes: 8_000,
            trackCount: 1,
            originalPreserved: true
        )
        let encoded = try JSONEncoder().encode(report)
        let text = String(decoding: encoded, as: UTF8.self)

        XCTAssertEqual(report.schema, "mkv-magic-bundled-fixture-smoke-v1")
        XCTAssertEqual(report.architecture, "arm64")
        XCTAssertTrue(report.originalPreserved)
        XCTAssertFalse(text.contains("/"))
        XCTAssertFalse(text.contains("source.mkv"))
        XCTAssertFalse(text.contains("Signed Fixture"))
    }

    func testNativeReleaseVerificationReportIsConsistentAndPathFree() throws {
        let baseline = AppBaselineSample(
            architecture: "x86_64",
            operatingSystem: AppBaselineOperatingSystem(
                OperatingSystemVersion(majorVersion: 13, minorVersion: 7, patchVersion: 1)
            ),
            activeProcessorCount: 4,
            mainViewReadyNanoseconds: 20_000_000,
            residentMemoryBytes: 32_000_000,
            windowCount: 0,
            rootSubviewCount: 1
        )
        let fixture = BundledFixtureSmokeReport(
            architecture: "x86_64",
            sourceBytes: 12_000,
            outputBytes: 12_100,
            extractedTrackBytes: 8_000,
            trackCount: 1,
            originalPreserved: true
        )
        let report = try NativeReleaseVerificationReport(
            appVersion: "1.2.3",
            appBuild: "42",
            baseline: baseline,
            bundledToolCount: 5,
            fixture: fixture
        )
        let encoded = try JSONEncoder().encode(report)
        let text = String(decoding: encoded, as: UTF8.self)

        XCTAssertEqual(report.schema, "mkv-magic-native-release-verification-v1")
        XCTAssertEqual(report.architecture, "x86_64")
        XCTAssertEqual(report.bundledToolCount, 5)
        XCTAssertTrue(report.fixture.originalPreserved)
        XCTAssertFalse(text.contains("/"))
        XCTAssertFalse(text.contains("source.mkv"))
        XCTAssertThrowsError(
            try NativeReleaseVerificationReport(
                appVersion: "1.2.3",
                appBuild: "42",
                baseline: baseline,
                bundledToolCount: 4,
                fixture: fixture
            )
        )
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

    func testSavedWorkflowFilenameSuggestionRemainsReviewableAndContainerSafe() {
        let source = URL(fileURLWithPath: "/Media/Movie.2025.1080p.WEBM")

        XCTAssertEqual(
            OutputNamingPolicy.savedWorkflowFilename(
                for: source,
                suggestedFilename: "Movie (2025).WEBM",
                requiresMKV: false
            ),
            "Movie (2025).WEBM"
        )
        XCTAssertEqual(
            OutputNamingPolicy.savedWorkflowFilename(
                for: source,
                suggestedFilename: "Movie (2025).WEBM",
                requiresMKV: true
            ),
            "Movie (2025).mkv"
        )
        XCTAssertEqual(
            OutputNamingPolicy.savedWorkflowFilename(
                for: source,
                suggestedFilename: nil,
                requiresMKV: false
            ),
            "Movie.2025.1080p — Edited.WEBM"
        )
    }

    func testCleanedSubtitleOutputNameUsesSRT() {
        XCTAssertEqual(
            OutputNamingPolicy.cleanedSubtitleFilename(
                for: URL(fileURLWithPath: "/Media/Movie.en.SRT")),
            "Movie.en — Clean.srt"
        )
        XCTAssertEqual(
            OutputNamingPolicy.cleanedSubtitleFilename(
                for: URL(fileURLWithPath: "/Media/Movie.en.ASS")),
            "Movie.en — Clean.ass"
        )
        XCTAssertEqual(
            OutputNamingPolicy.cleanedSubtitleFilename(
                for: URL(fileURLWithPath: "/Media/Legacy.SSA")),
            "Legacy — Clean.ssa"
        )
    }

    func testSubtitledOutputNameAlwaysUsesMKV() {
        XCTAssertEqual(
            OutputNamingPolicy.subtitledFilename(
                for: URL(fileURLWithPath: "/Media/Movie.WEBM")),
            "Movie — Subtitled.mkv"
        )
    }

    func testEmbeddedSubtitleCleanupOutputNameAlwaysUsesMKV() {
        XCTAssertEqual(
            OutputNamingPolicy.cleanedMKVFilename(
                for: URL(fileURLWithPath: "/Media/Movie.WEBM")),
            "Movie — Cleaned.mkv"
        )
    }

    func testJoinedOutputNameAlwaysUsesMKV() {
        XCTAssertEqual(
            OutputNamingPolicy.joinedFilename(
                for: URL(fileURLWithPath: "/Media/Part One.WEBM")),
            "Part One — Joined.mkv"
        )
    }

    func testTrimmedOutputNameAlwaysUsesMKV() {
        XCTAssertEqual(
            OutputNamingPolicy.trimmedFilename(
                for: URL(fileURLWithPath: "/Media/Movie.WEBM")),
            "Movie — Trimmed.mkv"
        )
    }

    func testTrimPresentationRequiresOneMKVVideoAndCreatesBoundedOverviewTimes() {
        let duration = MediaTime(nanoseconds: 60_000_000_000)
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska,webm",
            duration: duration,
            tracks: [MediaTrack(id: 0, kind: .video, codec: "h264")]
        )
        XCTAssertTrue(TrimPresentationPolicy.canOfferTrim(for: source))
        XCTAssertFalse(
            TrimPresentationPolicy.canOfferTrim(
                for: MediaAsset(
                    sourceURL: URL(fileURLWithPath: "/Media/Movie.mp4"),
                    container: "mov",
                    duration: duration,
                    tracks: source.tracks
                )
            )
        )
        let times = TrimPresentationPolicy.thumbnailTimes(duration: duration)
        XCTAssertEqual(times.count, 5)
        XCTAssertEqual(times.first, .zero)
        XCTAssertEqual(times.last, MediaTime(nanoseconds: duration.nanoseconds - 1))
        XCTAssertEqual(times, times.sorted())
        XCTAssertEqual(
            TrimPresentationPolicy.presetName(.hevcCompatibility),
            "Fast — HEVC 10-bit"
        )
        XCTAssertEqual(
            TrimPresentationPolicy.encodingSummary(
                ExactTrimChoice(
                    videoPreset: .av1Quality,
                    videoRateControl: .constantQuality(24),
                    encoderTuning: .svtAV1Preset(5)
                )
            ),
            "RF 24 • SVT speed 5"
        )
    }

    func testLosslessJoinReviewBuildsStrictNestedPartPlan() throws {
        let first = losslessJoinOption(
            part: 1,
            duration: 10,
            chapters: [
                MatroskaChapterEdition(
                    chapters: [
                        MatroskaChapterAtom(
                            start: .zero,
                            displays: [ChapterDisplay(title: "Opening")]
                        )
                    ]
                )
            ]
        )
        let second = losslessJoinOption(part: 2, duration: 12)

        let snapshot = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(
                    option: first,
                    editionID: try XCTUnwrap(first.editions.first?.id)
                ),
                LosslessJoinSourceSelection(option: second, editionID: nil),
            ]
        )

        let candidate = try XCTUnwrap(snapshot.candidate)
        XCTAssertTrue(snapshot.blockerSummaries.isEmpty)
        XCTAssertTrue(snapshot.issueSummaries.isEmpty)
        XCTAssertEqual(
            snapshot.normalizationSummaries,
            ["Not needed; every reviewed lane remains a packet copy."]
        )
        XCTAssertEqual(snapshot.laneSummaries.count, 1)
        XCTAssertTrue(snapshot.laneSummaries[0].contains("Part 1: #0 AAC"))
        XCTAssertEqual(candidate.report.disposition, .losslessCandidate)
        XCTAssertEqual(candidate.chapters.duration, MediaTime(nanoseconds: 22_000_000_000))
        XCTAssertEqual(candidate.chapters.document.chapterCount, 4)
        let parents = try XCTUnwrap(candidate.chapters.document.editions.first).chapters
        XCTAssertEqual(parents.map(\.primaryTitle), ["Part 1 — Part 1", "Part 2 — Part 2"])
        XCTAssertEqual(parents[0].children.first?.primaryTitle, "Opening")
        XCTAssertEqual(parents[1].children.first?.primaryTitle, "Chapter 02")
    }

    func testLosslessJoinReviewBlocksOnePassNormalizationMismatch() throws {
        let first = losslessJoinOption(part: 1, duration: 10, sampleRate: 48_000)
        let second = losslessJoinOption(part: 2, duration: 10, sampleRate: 44_100)

        let snapshot = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(option: first, editionID: nil),
                LosslessJoinSourceSelection(option: second, editionID: nil),
            ]
        )

        XCTAssertNil(snapshot.candidate)
        XCTAssertTrue(snapshot.issueSummaries.contains { $0.contains("sample rate") })
        XCTAssertTrue(snapshot.blockerSummaries.contains { $0.contains("normalization") })
        XCTAssertTrue(snapshot.normalizationSummaries.contains { $0.contains("AAC once") })
        XCTAssertTrue(
            snapshot.normalizationSummaries.contains { $0.contains("0 video generation") }
        )
    }

    @MainActor
    func testCommonFormatJoinRequiresExplicitApprovalOfResolvedOnePassChoices() throws {
        let capabilities = FFmpegEncodingCapabilities(
            softwareAV1: .unavailable,
            softwareAV1Encoder: nil,
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .verified,
            proResEncoder: "prores_ks",
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters,
            audioCapabilities: [
                .opusQuality: .init(status: .verified, encoder: "libopus"),
                .ac3Compatibility: .init(status: .verified, encoder: "ac3"),
                .eac3Compatibility: .init(status: .verified, encoder: "eac3"),
                .flacLossless: .init(status: .verified, encoder: "flac"),
            ]
        )
        let snapshot = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(
                    option: losslessJoinOption(part: 1, duration: 10, sampleRate: 48_000),
                    editionID: nil
                ),
                LosslessJoinSourceSelection(
                    option: losslessJoinOption(part: 2, duration: 10, sampleRate: 44_100),
                    editionID: nil
                ),
            ],
            encodingCapabilities: capabilities
        )
        let candidate = try XCTUnwrap(snapshot.commonFormatCandidate)
        XCTAssertNil(snapshot.candidate)
        XCTAssertTrue(snapshot.isReady)
        let resolved = try CommonFormatJoinChoicePolicy.resolveRecommended(for: candidate)
        let audio = try XCTUnwrap(resolved.choices.audioTargetsByLane[0])
        XCTAssertEqual(audio.codec, "AAC")
        XCTAssertEqual(audio.channels, 2)
        XCTAssertEqual(audio.channelLayout, "stereo")
        XCTAssertEqual(audio.sampleRate, 48_000)
        XCTAssertEqual(audio.bitrate, 192_000)
        XCTAssertFalse(audio.allowsSyntheticSilence)

        let controller = try CommonFormatJoinWindowController(candidate: candidate)
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.title, "Review Common Format")
        XCTAssertEqual(window.minSize, NSSize(width: 620, height: 520))
        let controls = buttons(in: content)
        let approval = try XCTUnwrap(
            controls.first { $0.title == "I approve every common-format choice above." }
        )
        let save = try XCTUnwrap(controls.first { $0.title == "Continue to Save…" })
        XCTAssertEqual(
            window.initialFirstResponder?.accessibilityLabel(),
            "Common format audio lane 1 format"
        )
        XCTAssertTrue(approval.accessibilityHelp()?.contains("Required confirmation") == true)
        XCTAssertEqual(
            try XCTUnwrap(controls.first { $0.title == "Cancel" }).keyEquivalent,
            "\u{1b}"
        )
        XCTAssertFalse(save.isEnabled)
        approval.performClick(nil)
        XCTAssertTrue(save.isEnabled)
        let review = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextView }.first
        ).string
        XCTAssertTrue(review.contains("AAC, stereo, 48 kHz, 192 kbps"))
        XCTAssertTrue(review.contains("one fused normalization pass"))
        XCTAssertTrue(review.contains("nested Matroska edition"))
        let audioPopup = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSPopUpButton }.first {
                $0.accessibilityLabel() == "Common format audio lane 1 format"
            }
        )
        XCTAssertEqual(
            audioPopup.itemTitles,
            ["AAC", "Opus", "AC-3", "E-AC-3", "FLAC (Lossless)"]
        )
        audioPopup.selectItem(withTitle: "Opus")
        XCTAssertTrue(audioPopup.sendAction(audioPopup.action, to: audioPopup.target))
        XCTAssertFalse(save.isEnabled)
        XCTAssertEqual(controller.reviewedPlan.choices.audioTargetsByLane[0]?.preset, .opusQuality)
        let updatedReview = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextView }.first
        ).string
        XCTAssertTrue(updatedReview.contains("Opus, stereo, 48 kHz, 160 kbps"))
        for button in controls where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }
        if let capturePath = ProcessInfo.processInfo.environment[
            "MKV_MAGIC_COMMON_JOIN_CAPTURE"
        ], capturePath.hasPrefix("/") {
            controller.showWindow(nil)
            window.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            content.layoutSubtreeIfNeeded()
            let bounds = content.bounds
            let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
            content.cacheDisplay(in: bounds, to: representation)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
        }
    }

    @MainActor
    func testCommonFormatJoinFallsBackToVerifiedOpusForSevenPointOne() throws {
        let capabilities = FFmpegEncodingCapabilities(
            softwareAV1: .unavailable,
            softwareAV1Encoder: nil,
            hevc10VideoToolbox: .unavailable,
            h264VideoToolbox: .unavailable,
            proRes: .unavailable,
            proResEncoder: nil,
            aac: .unavailable,
            aacEncoder: nil,
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters,
            audioCapabilities: [
                .opusQuality: .init(status: .verified, encoder: "libopus"),
                .flacLossless: .init(status: .verified, encoder: "flac"),
            ]
        )
        let snapshot = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(
                    option: losslessJoinOption(
                        part: 1,
                        duration: 10,
                        sampleRate: 48_000,
                        channels: 8,
                        channelLayout: "7.1"
                    ),
                    editionID: nil
                ),
                LosslessJoinSourceSelection(
                    option: losslessJoinOption(
                        part: 2,
                        duration: 10,
                        sampleRate: 44_100,
                        channels: 8,
                        channelLayout: "7.1"
                    ),
                    editionID: nil
                ),
            ],
            encodingCapabilities: capabilities
        )
        let candidate = try XCTUnwrap(snapshot.commonFormatCandidate)
        XCTAssertTrue(snapshot.isReady)
        XCTAssertTrue(snapshot.normalizationSummaries.contains { $0.contains("Opus once") })
        let resolved = try CommonFormatJoinChoicePolicy.resolveRecommended(for: candidate)
        XCTAssertEqual(resolved.choices.audioTargetsByLane[0]?.preset, .opusQuality)
        let controller = try CommonFormatJoinWindowController(candidate: candidate)
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()
        let popup = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSPopUpButton }.first {
                $0.accessibilityLabel() == "Common format audio lane 1 format"
            }
        )
        XCTAssertEqual(popup.itemTitles, ["Opus", "FLAC (Lossless)"])
    }

    func testCommonFormatJoinReviewExplainsUniformStaticHDR10Preservation() throws {
        let capabilities = FFmpegEncodingCapabilities(
            softwareAV1: .unavailable,
            softwareAV1Encoder: nil,
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .unavailable,
            proResEncoder: nil,
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters.union(
                FFmpegEncodingCapabilities.requiredToneMappingFilters
            )
        )
        let snapshot = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(
                    option: losslessJoinHDR10VideoOption(
                        part: 1,
                        width: 1_920,
                        height: 1_080
                    ),
                    editionID: nil
                ),
                LosslessJoinSourceSelection(
                    option: losslessJoinHDR10VideoOption(
                        part: 2,
                        width: 1_280,
                        height: 720
                    ),
                    editionID: nil
                ),
            ],
            encodingCapabilities: capabilities
        )

        let candidate = try XCTUnwrap(snapshot.commonFormatCandidate)
        XCTAssertTrue(snapshot.isReady, "\(snapshot.blockerSummaries)")
        XCTAssertEqual(
            CommonFormatJoinChoicePolicy.availableVideoPresets(
                for: try XCTUnwrap(candidate.proposal.videoLanes.first),
                capabilities: capabilities
            ),
            [.hevcCompatibility]
        )
        let resolved = try CommonFormatJoinChoicePolicy.resolveRecommended(for: candidate)
        XCTAssertEqual(resolved.choices.videoTargetsByLane[0]?.dynamicRange, .hdr10)
        XCTAssertEqual(resolved.choices.videoTargetsByLane[0]?.preset, .hevcCompatibility)
        XCTAssertTrue(
            CommonFormatJoinChoicePolicy.summaries(
                for: candidate,
                resolvedPlan: resolved
            ).contains { $0.contains("HDR10 with static metadata preserved") }
        )
    }

    @MainActor
    func testCommonFormatJoinDefaultsMixedHDR10AndSDRToExplicitToneMappedSDR() throws {
        let capabilities = FFmpegEncodingCapabilities(
            softwareAV1: .verified,
            softwareAV1Encoder: "libsvtav1",
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .verified,
            proResEncoder: "prores_ks",
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters.union(
                FFmpegEncodingCapabilities.requiredToneMappingFilters
            )
        )
        let selections = [
            LosslessJoinSourceSelection(
                option: losslessJoinVideoOption(
                    part: 1,
                    codec: "h264",
                    width: 1_920,
                    height: 1_080
                ),
                editionID: nil
            ),
            LosslessJoinSourceSelection(
                option: losslessJoinHDR10VideoOption(
                    part: 2,
                    width: 1_280,
                    height: 720
                ),
                editionID: nil
            ),
        ]
        let snapshot = LosslessJoinReviewBuilder.make(
            selections: selections,
            encodingCapabilities: capabilities
        )

        let candidate = try XCTUnwrap(snapshot.commonFormatCandidate)
        XCTAssertTrue(snapshot.isReady, "\(snapshot.blockerSummaries)")
        let lane = try XCTUnwrap(candidate.proposal.videoLanes.first)
        XCTAssertEqual(lane.recommendedDynamicRange, .sdr)
        XCTAssertEqual(lane.dynamicRangeChoices, [.sdr])
        XCTAssertEqual(
            CommonFormatJoinChoicePolicy.availableVideoPresets(
                for: lane,
                capabilities: capabilities
            ),
            [.av1Quality, .hevcCompatibility, .h264Compatibility, .proRes]
        )
        let resolved = try CommonFormatJoinChoicePolicy.resolveRecommended(for: candidate)
        XCTAssertEqual(resolved.choices.videoTargetsByLane[0]?.dynamicRange, .sdr)
        XCTAssertTrue(
            CommonFormatJoinChoicePolicy.summaries(
                for: candidate,
                resolvedPlan: resolved
            ).contains { $0.contains("tone-map only the reviewed HDR10 Parts") }
        )

        let controller = try CommonFormatJoinWindowController(candidate: candidate)
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(window.minSize)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let detail = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Common format video lane 1 dynamic range"
            }
        )
        XCTAssertTrue(detail.stringValue.contains("HDR10 Parts are tone-mapped locally"))
        let detailFrame = detail.convert(detail.bounds, to: content)
        XCTAssertGreaterThanOrEqual(detailFrame.minX, content.bounds.minX - 1)
        XCTAssertLessThanOrEqual(detailFrame.maxX, content.bounds.maxX + 1)
        XCTAssertGreaterThanOrEqual(detailFrame.minY, content.bounds.minY - 1)
        XCTAssertLessThanOrEqual(detailFrame.maxY, content.bounds.maxY + 1)
        if let capturePath = ProcessInfo.processInfo.environment[
            "MKV_MAGIC_MIXED_HDR_JOIN_CAPTURE"
        ], capturePath.hasPrefix("/") {
            try captureTrimWindow(window: window, content: content, at: capturePath)
        }

        let missingToneMap = FFmpegEncodingCapabilities(
            softwareAV1: .verified,
            softwareAV1Encoder: "libsvtav1",
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .verified,
            proResEncoder: "prores_ks",
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters
        )
        let blocked = LosslessJoinReviewBuilder.make(
            selections: selections,
            encodingCapabilities: missingToneMap
        )
        XCTAssertFalse(blocked.isReady)
        XCTAssertTrue(blocked.blockerSummaries.contains { $0.contains("tonemap filter") })
    }

    @MainActor
    func testCommonFormatJoinVideoTargetCanChangeCodecTierAndExactValues() throws {
        let capabilities = FFmpegEncodingCapabilities(
            softwareAV1: .verified,
            softwareAV1Encoder: "libsvtav1",
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .verified,
            proResEncoder: "prores_ks",
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters
        )
        let snapshot = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(
                    option: losslessJoinVideoOption(
                        part: 1,
                        codec: "h264",
                        width: 1_920,
                        height: 1_080
                    ),
                    editionID: nil
                ),
                LosslessJoinSourceSelection(
                    option: losslessJoinVideoOption(
                        part: 2,
                        codec: "hevc",
                        width: 3_840,
                        height: 2_160
                    ),
                    editionID: nil
                ),
            ],
            encodingCapabilities: capabilities
        )
        let candidate = try XCTUnwrap(snapshot.commonFormatCandidate)
        let controller = try CommonFormatJoinWindowController(candidate: candidate)
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.minSize, NSSize(width: 620, height: 610))

        let popups = descendants(in: content).compactMap { $0 as? NSPopUpButton }
        let format = try XCTUnwrap(
            popups.first { $0.itemTitles.contains(VideoPreset.av1Quality.displayName) }
        )
        let quality = try XCTUnwrap(
            popups.first { $0.itemTitles.contains(VideoQualityTier.higherQuality.displayName) }
        )
        XCTAssertEqual(format.titleOfSelectedItem, VideoPreset.av1Quality.displayName)
        XCTAssertEqual(quality.titleOfSelectedItem, VideoQualityTier.balanced.displayName)

        format.selectItem(withTitle: VideoPreset.hevcCompatibility.displayName)
        XCTAssertTrue(
            NSApplication.shared.sendAction(
                try XCTUnwrap(format.action),
                to: format.target,
                from: format
            )
        )
        quality.selectItem(withTitle: VideoQualityTier.higherQuality.displayName)
        XCTAssertTrue(
            NSApplication.shared.sendAction(
                try XCTUnwrap(quality.action),
                to: quality.target,
                from: quality
            )
        )
        XCTAssertEqual(
            controller.reviewedPlan.choices.videoTargetsByLane[0]?.preset,
            .hevcCompatibility
        )
        guard
            case .averageBitrate(let tierBitrate) = controller.reviewedPlan.choices
                .videoTargetsByLane[0]?.rateControl
        else { return XCTFail("Expected a reviewed HEVC bitrate") }
        XCTAssertGreaterThan(tierBitrate, 5_000_000)

        let exact = try XCTUnwrap(
            buttons(in: content).first {
                $0.title == "Show exact controls for video lane 1"
            }
        )
        exact.performClick(nil)
        content.layoutSubtreeIfNeeded()
        let rate = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextField }.first {
                $0.isEditable
            }
        )
        rate.stringValue = "12000"
        NotificationCenter.default.post(
            name: NSControl.textDidChangeNotification,
            object: rate
        )
        guard
            case .averageBitrate(let exactBitrate) = controller.reviewedPlan.choices
                .videoTargetsByLane[0]?.rateControl
        else { return XCTFail("Expected the reviewed exact HEVC bitrate") }
        XCTAssertEqual(exactBitrate, 12_000_000)

        let approval = try XCTUnwrap(
            buttons(in: content).first { $0.title == "I approve every common-format choice above." }
        )
        let save = try XCTUnwrap(
            buttons(in: content).first { $0.title == "Continue to Save…" }
        )
        approval.performClick(nil)
        XCTAssertTrue(save.isEnabled)
        rate.stringValue = "0"
        NotificationCenter.default.post(
            name: NSControl.textDidChangeNotification,
            object: rate
        )
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(
            descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }
                .contains { $0.contains("valid bounded rate") }
        )

        format.selectItem(withTitle: VideoPreset.av1Quality.displayName)
        XCTAssertTrue(
            NSApplication.shared.sendAction(
                try XCTUnwrap(format.action),
                to: format.target,
                from: format
            )
        )
        content.layoutSubtreeIfNeeded()
        let av1Fields = descendants(in: content).compactMap { $0 as? NSTextField }.filter {
            $0.isEditable
        }.sorted {
            $0.convert($0.bounds, to: content).minX < $1.convert($1.bounds, to: content).minX
        }
        XCTAssertEqual(av1Fields.count, 2)
        av1Fields[0].stringValue = "24"
        NotificationCenter.default.post(
            name: NSControl.textDidChangeNotification,
            object: av1Fields[0]
        )
        av1Fields[1].stringValue = "5"
        NotificationCenter.default.post(
            name: NSControl.textDidChangeNotification,
            object: av1Fields[1]
        )
        let av1Choice = try XCTUnwrap(controller.reviewedPlan.choices.videoTargetsByLane[0])
        XCTAssertEqual(av1Choice.preset, .av1Quality)
        XCTAssertEqual(av1Choice.rateControl, .constantQuality(24))
        XCTAssertEqual(av1Choice.encoderTuning, .svtAV1Preset(5))
        XCTAssertTrue(
            descendants(in: content).compactMap { $0 as? NSTextView }.first?.string
                .contains("SVT speed preset 5") == true
        )

        if let capturePath = ProcessInfo.processInfo.environment[
            "MKV_MAGIC_COMMON_JOIN_TARGET_CAPTURE"
        ], capturePath.hasPrefix("/") {
            controller.showWindow(nil)
            window.appearance = NSAppearance(named: .aqua)
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.white.cgColor
            window.displayIfNeeded()
            content.layoutSubtreeIfNeeded()
            let representation = try XCTUnwrap(
                content.bitmapImageRepForCachingDisplay(in: content.bounds)
            )
            content.cacheDisplay(in: content.bounds, to: representation)
            let png = try XCTUnwrap(
                representation.representation(using: .png, properties: [:])
            )
            try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
        }

        for control in [format, quality, exact, rate] where !control.isHidden {
            let frame = control.convert(control.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }
    }

    @MainActor
    func testJoinWindowOffersCommonFormatReviewWhenCapabilitiesAreVerified() throws {
        let capabilities = FFmpegEncodingCapabilities(
            softwareAV1: .unavailable,
            softwareAV1Encoder: nil,
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .verified,
            proResEncoder: "prores_ks",
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters
        )
        let controller = LosslessJoinWindowController(
            options: [
                losslessJoinOption(part: 1, duration: 10, sampleRate: 48_000),
                losslessJoinOption(part: 2, duration: 10, sampleRate: 44_100),
            ],
            encodingCapabilities: capabilities
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()
        let review = try XCTUnwrap(
            buttons(in: content).first { $0.title == "Review Common Format…" }
        )
        XCTAssertTrue(review.isEnabled)
    }

    func testLosslessJoinReviewRequiresExplicitChoiceForMultipleEditions() throws {
        let option = losslessJoinOption(
            part: 1,
            duration: 10,
            chapters: [
                MatroskaChapterEdition(chapters: []),
                MatroskaChapterEdition(isDefault: false, chapters: []),
            ]
        )
        let second = losslessJoinOption(part: 2, duration: 10)
        let blocked = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(option: option, editionID: nil),
                LosslessJoinSourceSelection(option: second, editionID: nil),
            ]
        )
        XCTAssertNil(blocked.candidate)
        XCTAssertTrue(blocked.blockerSummaries.contains { $0.contains("Choose") })

        let reviewed = LosslessJoinReviewBuilder.make(
            selections: [
                LosslessJoinSourceSelection(
                    option: option,
                    editionID: try XCTUnwrap(option.editions.last?.id)
                ),
                LosslessJoinSourceSelection(option: second, editionID: nil),
            ]
        )
        XCTAssertNotNil(reviewed.candidate)
    }

    func testManualTrackMappingResolvesAmbiguityAndBindsExactSourceOrder() throws {
        let first = ambiguousSubtitleJoinOption(part: 1, trackIDs: [1, 2])
        let second = ambiguousSubtitleJoinOption(part: 2, trackIDs: [11, 12])
        let selections = [
            LosslessJoinSourceSelection(option: first, editionID: nil),
            LosslessJoinSourceSelection(option: second, editionID: nil),
        ]
        let automatic = LosslessJoinReviewBuilder.make(selections: selections)
        XCTAssertNil(automatic.candidate)
        XCTAssertEqual(automatic.unresolvedAmbiguities.count, 1)
        let proposed = try XCTUnwrap(automatic.reviewedMapping)
        let firstEdit = try JoinTrackMappingEditor().assigning(
            trackID: 11,
            fromSource: 1,
            toLane: 0,
            sources: selections.map(\.option.source),
            mapping: proposed
        )
        let resolved = try JoinTrackMappingEditor().assigning(
            trackID: 12,
            fromSource: 1,
            toLane: 1,
            sources: selections.map(\.option.source),
            mapping: firstEdit
        )
        let manual = LosslessJoinManualMapping(
            sourceIDs: selections.map(\.option.source.id),
            mapping: resolved
        )

        let reviewed = LosslessJoinReviewBuilder.make(
            selections: selections,
            manualMapping: manual
        )
        XCTAssertNotNil(reviewed.candidate)
        XCTAssertTrue(reviewed.usesManualMapping)
        XCTAssertTrue(reviewed.unresolvedAmbiguities.isEmpty)
        XCTAssertTrue(reviewed.blockerSummaries.isEmpty)
        XCTAssertEqual(reviewed.candidate?.mapping.lanes.count, 2)

        let stale = LosslessJoinReviewBuilder.make(
            selections: selections.reversed(),
            manualMapping: manual
        )
        XCTAssertNil(stale.selection)
        XCTAssertTrue(stale.blockerSummaries.contains { $0.contains("source order") })
    }

    @MainActor
    func testAmbiguousJoinOffersExplicitNativeMappingTable() throws {
        let first = ambiguousSubtitleJoinOption(part: 1, trackIDs: [1, 2])
        let second = ambiguousSubtitleJoinOption(part: 2, trackIDs: [11, 12])
        let sources = [first.source, second.source]
        let proposed = try JoinTrackMappingProposer().propose(sources: sources).mapping
        let editor = JoinTrackMappingWindowController(
            sources: sources,
            mapping: proposed,
            requiresResolution: true
        )
        let editorWindow = try XCTUnwrap(editor.window)
        let editorContent = try XCTUnwrap(editorWindow.contentView)
        editorWindow.setContentSize(editorWindow.minSize)
        editorContent.layoutSubtreeIfNeeded()

        XCTAssertEqual(editorWindow.title, "Resolve Track Mapping")
        XCTAssertEqual(editorWindow.minSize, NSSize(width: 700, height: 420))
        let mappingTable = try XCTUnwrap(
            descendants(in: editorContent).compactMap { $0 as? NSTableView }.first
        )
        XCTAssertEqual(mappingTable.numberOfRows, 4)
        XCTAssertEqual(mappingTable.accessibilityLabel(), "Output track mapping")
        XCTAssertTrue(editorWindow.initialFirstResponder === mappingTable)
        let editorButtons = buttons(in: editorContent)
        for title in ["Reset Proposal", "Cancel", "Use This Mapping"] {
            XCTAssertTrue(editorButtons.contains { $0.title == title })
        }
        XCTAssertTrue(
            try XCTUnwrap(editorButtons.first { $0.title == "Use This Mapping" }).isEnabled)
        let helpText = descendants(in: editorContent).compactMap {
            ($0 as? NSTextField)?.stringValue
        }
        .joined(separator: " ")
        XCTAssertTrue(helpText.contains("no source track is duplicated or discarded"))
        XCTAssertTrue(helpText.contains("every source track assigned once"))

        let firstPopup = try XCTUnwrap(
            mappingTable.view(atColumn: 2, row: 0, makeIfNecessary: true) as? NSPopUpButton
        )
        XCTAssertEqual(
            firstPopup.accessibilityLabel(),
            "Part 2 track for output lane 1"
        )
        XCTAssertTrue(
            firstPopup.accessibilityHelp()?.contains("subtitle track") == true
        )
        let track11 = try XCTUnwrap(
            firstPopup.itemArray.first {
                ($0.representedObject as? NSNumber)?.intValue == 11
            }
        )
        firstPopup.select(track11)
        firstPopup.sendAction(firstPopup.action, to: firstPopup.target)
        XCTAssertEqual(mappingTable.numberOfRows, 3)

        let secondPopup = try XCTUnwrap(
            mappingTable.view(atColumn: 2, row: 1, makeIfNecessary: true) as? NSPopUpButton
        )
        let track12 = try XCTUnwrap(
            secondPopup.itemArray.first {
                ($0.representedObject as? NSNumber)?.intValue == 12
            }
        )
        secondPopup.select(track12)
        secondPopup.sendAction(secondPopup.action, to: secondPopup.target)
        XCTAssertEqual(mappingTable.numberOfRows, 2)
        XCTAssertTrue(try XCTUnwrap(editorButtons.first { $0.title == "Reset Proposal" }).isEnabled)
        for button in editorButtons where !button.isHidden {
            let frame = button.convert(button.bounds, to: editorContent)
            XCTAssertGreaterThanOrEqual(frame.minX, editorContent.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, editorContent.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, editorContent.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, editorContent.bounds.maxY + 1)
        }

        let join = LosslessJoinWindowController(options: [first, second])
        let joinContent = try XCTUnwrap(join.window?.contentView)
        joinContent.layoutSubtreeIfNeeded()
        let joinButtons = buttons(in: joinContent)
        XCTAssertTrue(
            try XCTUnwrap(joinButtons.first { $0.title == "Resolve Track Mapping…" }).isEnabled
        )
        XCTAssertFalse(
            try XCTUnwrap(joinButtons.first { $0.title == "Continue to Save…" }).isEnabled
        )
    }

    @MainActor
    func testLosslessJoinWindowKeepsNativeReviewActionsVisibleAtMinimumSize() throws {
        let first = losslessJoinOption(part: 1, duration: 10)
        let second = losslessJoinOption(part: 2, duration: 10)
        let controller = LosslessJoinWindowController(options: [first, second])
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.title, "Join MKV Files")
        XCTAssertEqual(window.minSize, NSSize(width: 720, height: 560))
        let table = try XCTUnwrap(descendants(in: content).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(table.accessibilityLabel(), "Join source order")
        XCTAssertTrue(window.initialFirstResponder === table)
        let reviewText = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextView }.first
        )
        XCTAssertEqual(reviewText.accessibilityLabel(), "Join compatibility review")
        let controls = buttons(in: content)
        for title in ["Move Up", "Move Down", "Cancel", "Continue to Save…"] {
            XCTAssertTrue(controls.contains { $0.title == title }, "Missing join action \(title)")
        }
        XCTAssertTrue(
            try XCTUnwrap(controls.first { $0.title == "Continue to Save…" }).isEnabled
        )
        XCTAssertEqual(
            try XCTUnwrap(controls.first { $0.title == "Cancel" }).keyEquivalent,
            "\u{1b}"
        )
        let include = try XCTUnwrap(
            table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSButton
        )
        XCTAssertTrue(include.accessibilityLabel()?.hasPrefix("Include Part source") == true)
        for button in controls where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }
        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_JOIN_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            controller.showWindow(nil)
            window.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            content.layoutSubtreeIfNeeded()
            let bounds = content.bounds
            let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
            content.cacheDisplay(in: bounds, to: representation)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
        }
    }

    @MainActor
    func testLosslessJoinWindowRendersCommonFormatPreviewWithoutEnablingSave() throws {
        let controller = LosslessJoinWindowController(options: [
            losslessJoinOption(part: 1, duration: 10, sampleRate: 48_000),
            losslessJoinOption(part: 2, duration: 10, sampleRate: 44_100),
        ])
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()

        let review = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextView }.first
        )
        XCTAssertTrue(review.string.contains("COMMON-FORMAT OPTION"))
        XCTAssertTrue(review.string.contains("AAC once"))
        XCTAssertTrue(review.string.contains("0 video generation"))
        XCTAssertTrue(review.string.contains("explicit approval"))
        let save = try XCTUnwrap(
            buttons(in: content).first { $0.title == "Continue to Save…" }
        )
        XCTAssertFalse(save.isEnabled)
    }

    @MainActor
    func testLosslessJoinWindowShowsActivelyVerifiedHEVCFallbackInsteadOfUnavailableAV1()
        throws
    {
        let capabilities = FFmpegEncodingCapabilities(
            softwareAV1: .unavailable,
            softwareAV1Encoder: nil,
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .verified,
            proResEncoder: "prores_ks",
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters
        )
        let controller = LosslessJoinWindowController(
            options: [
                losslessJoinVideoOption(part: 1, codec: "h264", width: 1_920, height: 1_080),
                losslessJoinVideoOption(part: 2, codec: "hevc", width: 3_840, height: 2_160),
            ],
            encodingCapabilities: capabilities
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()

        let review = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextView }.first
        ).string
        XCTAssertTrue(review.contains("one HEVC 10-bit VideoToolbox generation"))
        XCTAssertTrue(review.contains("AV1 remains preferred"))
        XCTAssertTrue(review.contains("verified fallback"))
        XCTAssertFalse(review.contains("one AV1 10-bit generation"))
        XCTAssertTrue(
            try XCTUnwrap(
                buttons(in: content).first { $0.title == "Review Common Format…" }
            ).isEnabled
        )
    }

    @MainActor
    func testLosslessJoinWindowPrefersActivelyVerifiedSoftwareAV1() throws {
        let capabilities = FFmpegEncodingCapabilities(
            softwareAV1: .verified,
            softwareAV1Encoder: "libsvtav1",
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .verified,
            proResEncoder: "prores_ks",
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters
        )
        let controller = LosslessJoinWindowController(
            options: [
                losslessJoinVideoOption(part: 1, codec: "h264", width: 1_920, height: 1_080),
                losslessJoinVideoOption(part: 2, codec: "hevc", width: 3_840, height: 2_160),
            ],
            encodingCapabilities: capabilities
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()

        let review = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextView }.first
        ).string
        XCTAssertTrue(review.contains("one AV1 10-bit generation"))
        XCTAssertFalse(review.contains("verified fallback"))
        XCTAssertTrue(
            try XCTUnwrap(
                buttons(in: content).first { $0.title == "Review Common Format…" }
            ).isEnabled
        )
    }

    func testExternalSubtitleMetadataIsCanonicalAndBounded() throws {
        XCTAssertEqual(
            try ExternalSubtitleMuxPresentation.metadata(
                language: " ENG ",
                name: "  English Forced  ",
                isDefault: false,
                isForced: true,
                isHearingImpaired: false
            ),
            ExternalSubtitleTrackMetadata(
                language: "en",
                name: "English Forced",
                isForced: true
            )
        )
        XCTAssertThrowsError(
            try ExternalSubtitleMuxPresentation.metadata(
                language: "en",
                name: "Bad\0Name",
                isDefault: false,
                isForced: false,
                isHearingImpaired: false
            )
        ) { error in
            XCTAssertEqual(error as? ExternalSubtitleMuxError, .invalidTrackName)
        }
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

    func testTrackEditorUsesHumanReadableOneBasedTrackLabels() {
        let track = MediaTrack(
            id: 0,
            kind: .audio,
            codec: "aac",
            uid: 42,
            language: "en",
            title: "Main Audio"
        )
        XCTAssertEqual(
            TrackEditorPresentation.label(track),
            "#1 Audio — AAC — en — Main Audio"
        )
    }

    func testTrackEditorTreatsLegacyAndCanonicalLanguageCodesAsEquivalent() throws {
        let track = MediaTrack(
            id: 0,
            kind: .audio,
            codec: "aac",
            uid: 42,
            language: "eng",
            title: "Main Audio"
        )

        XCTAssertEqual(try TrackEditorPresentation.normalizedEdit(for: track).language, "en")
    }

    func testTrackRemovalPresentationUsesStableUIDsAndKeepsOneTrack() throws {
        let video = MediaTrack(id: 0, kind: .video, codec: "av1", uid: 42)
        let audio = MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 84)

        XCTAssertTrue(TrackRemovalPresentation.canOfferRemoval(for: [video, audio]))
        XCTAssertEqual(
            try TrackRemovalPresentation.removal(
                tracks: [video, audio],
                selectedIndexes: [1]
            ).trackUIDs,
            [84]
        )
        XCTAssertThrowsError(
            try TrackRemovalPresentation.removal(
                tracks: [video, audio],
                selectedIndexes: [0, 1]
            )
        ) { error in
            XCTAssertEqual(error as? TrackRemovalPresentationError, .allTracksRemoved)
        }
        XCTAssertFalse(TrackRemovalPresentation.canOfferRemoval(for: [video]))
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

    func testWorkflowLocationSharesPrivateAppSupportDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-workflows-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try AppHistoryLocation.makeWorkflowStore(applicationSupportURL: root)
        try await store.save([WorkflowEditorPolicy.newWorkflow()])

        let appDirectory = root.appendingPathComponent("com.dustwave.mkvmagic")
        let attributes = try FileManager.default.attributesOfItem(atPath: appDirectory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appDirectory.appendingPathComponent("workflows.json").path
            )
        )
    }

    func testQueueLocationSharesPrivateAppSupportDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-queue-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try AppHistoryLocation.makeQueueStore(applicationSupportURL: root)
        try await store.save(MediaQueueSnapshot(updatedAt: Date(timeIntervalSince1970: 0)))

        let appDirectory = root.appendingPathComponent("com.dustwave.mkvmagic")
        let attributes = try FileManager.default.attributesOfItem(atPath: appDirectory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appDirectory.appendingPathComponent("job-queue.json").path
            )
        )
    }

    @MainActor
    func testQueueRecoveryRunsOnceAndDoesNotReclassifyCurrentWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-queue-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppHistoryLocation.makeQueueStore(applicationSupportURL: root)
        let model = AppModel(queueStoreFactory: { store })

        let initialQueue = try await model.loadQueue()
        XCTAssertTrue(initialQueue.jobs.isEmpty)
        let now = Date()
        let job = makeQueueJob(createdAt: now)
        _ = try await store.append(job, at: now)
        _ = try await store.transition(
            jobID: job.id,
            to: .running,
            at: now,
            reason: nil
        )

        let visibleQueue = try await model.loadQueue()
        XCTAssertEqual(visibleQueue.jobs.only?.state, .running)
    }

    @MainActor
    func testPendingVerifiedTrashRecoveryPersistsOutcomeAndNeverRepeats() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-trash-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.mkv")
        let sourceMovedBeforeRecord = root.appendingPathComponent("Already Trashed.mkv")
        try Data([1, 2, 3]).write(to: source)
        try Data([4, 5, 6]).write(to: sourceMovedBeforeRecord)
        let codec = SecurityScopedBookmarkCodec()
        let createdAt = Date().addingTimeInterval(-10)
        func makePendingJob(sourceURL: URL, outputName: String) throws -> MediaQueueJob {
            var job = MediaQueueJob(
                createdAt: createdAt,
                workflow: .builtIn(id: UUID(), name: "Verified workflow"),
                inputs: [try codec.makeReference(for: sourceURL, access: .readWriteFile)],
                destinationDirectory: try codec.makeReference(
                    for: root,
                    access: .readWriteDirectory
                ),
                outputDisplayName: outputName,
                sourceDisposition: .trashAfterVerifiedSuccess,
                reviewedPlan: ExecutionPlan(
                    stages: [
                        PlanStage(mechanism: .mkvMerge, summary: "Create one verified output")
                    ],
                    impact: PlanImpact(
                        videoEncodeCount: 0,
                        audioEncodeCount: 0,
                        copiesVideo: true
                    )
                )
            )
            try job.transition(to: .running, at: createdAt.addingTimeInterval(1))
            try job.transition(to: .succeeded, at: createdAt.addingTimeInterval(2))
            return job
        }
        let job = try makePendingJob(sourceURL: source, outputName: "Movie — Prepared.mkv")
        let missingJob = try makePendingJob(
            sourceURL: sourceMovedBeforeRecord,
            outputName: "Already Trashed — Prepared.mkv"
        )
        try FileManager.default.removeItem(at: sourceMovedBeforeRecord)
        let store = try AppHistoryLocation.makeQueueStore(applicationSupportURL: root)
        try await store.save(
            MediaQueueSnapshot(jobs: [job, missingJob], updatedAt: job.updatedAt)
        )
        var trashedSources = [URL]()
        let model = AppModel(
            queueStoreFactory: { store },
            trashSource: { trashedSources.append($0) }
        )

        let recovered = try await model.loadQueue()
        XCTAssertEqual(trashedSources, [source])
        XCTAssertEqual(
            recovered.jobs.map { $0.sourceDispositionResult?.outcome },
            [.applied, .uncertain]
        )
        XCTAssertEqual(
            model.state,
            .completedWithWarnings(
                "Checked 2 pending Trash follow-ups; 1 source outcome could not be confirmed. Check the original and Trash before continuing."
            )
        )

        let reloaded = try await model.loadQueue()
        XCTAssertEqual(trashedSources, [source])
        XCTAssertEqual(reloaded.jobs.map(\.id), recovered.jobs.map(\.id))
        XCTAssertEqual(
            reloaded.jobs.map { $0.sourceDispositionResult?.outcome },
            recovered.jobs.map { $0.sourceDispositionResult?.outcome }
        )
    }

    func testQueuePresentationDistinguishesEveryVerifiedTrashOutcome() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var pending = makeQueueJob(
            createdAt: base,
            sourceDisposition: .trashAfterVerifiedSuccess
        )
        try pending.transition(to: .running, at: base)
        try pending.transition(to: .succeeded, at: base)
        var applied = pending
        var failed = pending
        var uncertain = pending
        try applied.recordSourceDisposition(.applied, at: base)
        try failed.recordSourceDisposition(.failed, at: base)
        try uncertain.recordSourceDisposition(.uncertain, at: base)
        let snapshot = MediaQueueSnapshot(
            jobs: [pending, applied, failed, uncertain],
            updatedAt: base
        )

        XCTAssertEqual(QueuePresentation.stateLabel(pending), "Trash pending")
        XCTAssertEqual(QueuePresentation.stateLabel(applied), "Trashed")
        XCTAssertEqual(QueuePresentation.stateLabel(failed), "Trash failed")
        XCTAssertEqual(QueuePresentation.stateLabel(uncertain), "Check Trash")
        XCTAssertEqual(
            QueuePresentation.summary(snapshot),
            "0 active • 0 pending • 0 need review • 3 Trash follow-ups"
        )
    }

    @MainActor
    func testQueueWindowKeepsNativeControlsReadableAtMinimumSize() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let waiting = makeQueueJob(createdAt: base)
        var running = makeQueueJob(createdAt: base, videoEncodes: 1)
        var failed = makeQueueJob(createdAt: base, audioEncodes: 1)
        try running.transition(to: .running, at: base)
        try failed.transition(to: .running, at: base)
        try failed.transition(to: .failed, at: base, reason: .executionFailed)
        func makeFinishedTrash(
            _ outcome: MediaQueueSourceDispositionOutcome?
        ) throws -> MediaQueueJob {
            var job = makeQueueJob(
                createdAt: base,
                sourceDisposition: .trashAfterVerifiedSuccess
            )
            try job.transition(to: .running, at: base)
            try job.transition(to: .succeeded, at: base)
            if let outcome { try job.recordSourceDisposition(outcome, at: base) }
            return job
        }
        let trashed = try makeFinishedTrash(.applied)
        let trashFailed = try makeFinishedTrash(.failed)
        let trashUncertain = try makeFinishedTrash(.uncertain)
        let trashPending = try makeFinishedTrash(nil)
        let snapshot = MediaQueueSnapshot(
            jobs: [waiting, running, failed, trashed, trashFailed, trashUncertain, trashPending],
            updatedAt: base
        )
        let controller = QueueWindowController(
            snapshot: snapshot,
            onSetPaused: { _ in snapshot },
            onTransition: { _, _, _ in snapshot },
            onReorder: { _ in snapshot },
            onReview: { _ in }
        )
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.title, "MKV Magic Queue")
        XCTAssertEqual(window.minSize, NSSize(width: 700, height: 420))
        let table = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTableView }.first
        )
        XCTAssertEqual(table.accessibilityLabel(), "Production queue jobs")
        XCTAssertTrue(window.initialFirstResponder === table)
        XCTAssertEqual(table.numberOfRows, 7)
        XCTAssertEqual(
            table.tableColumns.map(\.title),
            ["#", "Workflow", "Input", "Work", "Status", "Tries"]
        )
        XCTAssertEqual(
            (table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)?
                .textField?.stringValue,
            "1"
        )
        XCTAssertEqual(
            (table.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTableCellView)?
                .textField?.stringValue,
            "Prepare for Jellyfin"
        )
        XCTAssertEqual(
            (table.view(atColumn: 4, row: 3, makeIfNecessary: true) as? NSTableCellView)?
                .textField?.stringValue,
            "Trashed"
        )
        XCTAssertEqual(
            (table.view(atColumn: 4, row: 4, makeIfNecessary: true) as? NSTableCellView)?
                .textField?.stringValue,
            "Trash failed"
        )
        XCTAssertEqual(
            (table.view(atColumn: 4, row: 5, makeIfNecessary: true) as? NSTableCellView)?
                .textField?.stringValue,
            "Check Trash"
        )
        XCTAssertEqual(
            (table.view(atColumn: 4, row: 6, makeIfNecessary: true) as? NSTableCellView)?
                .textField?.stringValue,
            "Trash pending"
        )
        let controls = buttons(in: content)
        XCTAssertNotNil(controls.first { $0.title == "Pause Automatic Starts" })
        XCTAssertTrue(
            controls.first { $0.title == "Pause Automatic Starts" }?.accessibilityHelp()?
                .contains("without stopping active work") == true
        )
        let labels = descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains { $0.contains("Add to Queue saves a reviewed workflow") })
        XCTAssertTrue(
            labels.contains { $0.contains("Verify & Run remains an explicit immediate start") })
        XCTAssertEqual(QueuePresentation.stateLabel(running.state), "Running")
        XCTAssertEqual(QueuePresentation.resourceLabel(failed.resourceClass), "Audio encode")
        XCTAssertEqual(
            QueuePresentation.summary(snapshot),
            "1 active • 1 pending • 1 need review • 3 Trash follow-ups"
        )
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(try XCTUnwrap(controls.first { $0.title == "Hold" }).isEnabled)
        XCTAssertTrue(try XCTUnwrap(controls.first { $0.title == "Cancel" }).isEnabled)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertFalse(try XCTUnwrap(controls.first { $0.title == "Hold" }).isEnabled)
        XCTAssertTrue(try XCTUnwrap(controls.first { $0.title == "Cancel" }).isEnabled)
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        XCTAssertTrue(
            try XCTUnwrap(controls.first { $0.title == "Review Again…" }).isEnabled
        )
        XCTAssertTrue(try XCTUnwrap(controls.first { $0.title == "Cancel" }).isEnabled)

        XCTAssertTrue(
            QueueExecutionControl.shouldCancelActiveTask(
                jobID: running.id,
                transition: .cancelling,
                activeJobID: running.id
            )
        )
        XCTAssertFalse(
            QueueExecutionControl.shouldCancelActiveTask(
                jobID: waiting.id,
                transition: .cancelling,
                activeJobID: running.id
            )
        )
        XCTAssertFalse(
            QueueExecutionControl.shouldCancelActiveTask(
                jobID: running.id,
                transition: .failed,
                activeJobID: running.id
            )
        )

        for button in controls where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }
        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_QUEUE_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            window.setContentSize(NSSize(width: 840, height: 520))
            content.layoutSubtreeIfNeeded()
            try captureWindow(window: window, content: content, at: capturePath)
        }
    }

    @MainActor
    func testQueueWindowKeepsMutationFailureVisible() async throws {
        struct ExpectedFailure: LocalizedError {
            var errorDescription: String? { "simulated persistence failure" }
        }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = MediaQueueSnapshot(
            jobs: [makeQueueJob(createdAt: base)],
            updatedAt: base
        )
        let attempted = expectation(description: "queue mutation attempted")
        let controller = QueueWindowController(
            snapshot: snapshot,
            onSetPaused: { _ in snapshot },
            onTransition: { _, _, _ in
                attempted.fulfill()
                throw ExpectedFailure()
            },
            onReorder: { _ in snapshot },
            onReview: { _ in }
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        let table = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTableView }.first
        )
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let hold = try XCTUnwrap(buttons(in: content).first { $0.title == "Hold" })

        hold.performClick(nil)
        await fulfillment(of: [attempted], timeout: 1)
        for _ in 0..<10 { await Task.yield() }

        let labels = descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(
            labels.contains {
                $0.contains("Could not update the queue.")
                    && $0.contains("The last confirmed queue remains shown")
                    && $0.contains("Details: simulated persistence failure")
            }
        )
        XCTAssertTrue(controller.window?.firstResponder === table)
    }

    func testUserFacingErrorPresentationIsActionableSingleLineAndBounded() {
        struct NoisyFailure: LocalizedError {
            var errorDescription: String? {
                "first line\nsecond\tline " + String(repeating: "x", count: 500)
            }
        }
        let message = UserFacingErrorPresentation.message(
            failure: "Could not finish the action.",
            recovery: "The original is unchanged; try again.",
            error: NoisyFailure()
        )
        let detail = message.components(separatedBy: "Details: ").last ?? ""

        XCTAssertTrue(message.hasPrefix("Could not finish the action."))
        XCTAssertTrue(message.contains("The original is unchanged; try again."))
        XCTAssertFalse(message.contains("\n"))
        XCTAssertFalse(message.contains("\t"))
        XCTAssertLessThanOrEqual(detail.count, UserFacingErrorPresentation.maximumDetailCharacters)
        XCTAssertTrue(detail.hasSuffix("…"))
    }

    @MainActor
    func testAccessibleStatusPresentationAnnouncesAndReturnsFocusToRecovery() {
        let status = NSTextField(labelWithString: "")
        let retry = NSButton(title: "Try Again", target: nil, action: nil)
        let content = NSView()
        content.addSubview(status)
        content.addSubview(retry)
        let window = NSWindow(contentViewController: NSViewController())
        window.contentView = content
        window.makeFirstResponder(nil)
        var postedElement: AnyObject?
        var postedNotification: NSAccessibility.Notification?

        AccessibleStatusPresentation.present(
            "The action failed safely. Try again.",
            in: status,
            returningFocusTo: retry,
            postNotification: { element, notification in
                postedElement = element as AnyObject
                postedNotification = notification
            }
        )

        XCTAssertEqual(status.stringValue, "The action failed safely. Try again.")
        XCTAssertTrue(window.firstResponder === retry)
        XCTAssertTrue(postedElement === status)
        XCTAssertEqual(postedNotification, .valueChanged)
    }

    @MainActor
    func testWorkflowValidationReturnsFocusToTheInvalidName() throws {
        let controller = WorkflowWindowController(
            workflows: [
                SavedWorkflow(
                    name: "Temporary workflow",
                    steps: [SavedWorkflowStep(action: .removeNonEnglishSubtitles)]
                )
            ],
            hasSelectedAsset: true,
            onSave: { _ in XCTFail("Invalid workflow must not be saved") },
            onUse: { _ in XCTFail("Invalid workflow must not be previewed") }
        )
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        let workflows = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTableView }.first {
                $0.accessibilityLabel() == "Saved workflows"
            }
        )
        workflows.reloadData()
        XCTAssertEqual(workflows.numberOfRows, 1)
        workflows.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertEqual(workflows.selectedRow, 0)
        let name = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Workflow name"
            }
        )
        name.stringValue = "   "
        let nameDelegate = try XCTUnwrap(name.delegate)
        nameDelegate.controlTextDidChange?(
            Notification(name: NSControl.textDidChangeNotification, object: name)
        )
        XCTAssertTrue(
            descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }.contains(
                "Unsaved changes"
            )
        )
        let save = try XCTUnwrap(buttons(in: content).first { $0.title == "Save" })
        let action = try XCTUnwrap(save.action)

        XCTAssertTrue(NSApp.sendAction(action, to: save.target, from: save))

        XCTAssertTrue(window.firstResponder === name.currentEditor())
        XCTAssertTrue(
            descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }.contains(
                "Give the workflow a name before saving."
            )
        )
    }

    @MainActor
    func testSavedWorkflowTrashOptionIsExplicitAndOptIn() throws {
        let off = SourceDispositionPresentation.makeAccessory(selected: false)
        XCTAssertEqual(off.checkbox.title, SourceDispositionPresentation.checkboxTitle)
        XCTAssertEqual(
            SourceDispositionPresentation.disposition(for: off.checkbox),
            .keepOriginal
        )
        XCTAssertTrue(
            SourceDispositionPresentation.explanation.contains(
                "Only after verified success"
            )
        )
        XCTAssertTrue(
            SourceDispositionPresentation.explanation.contains(
                "new output stays safe"
            )
        )
        XCTAssertTrue(SourceDispositionPresentation.explanation.contains("checks the original"))

        let on = SourceDispositionPresentation.makeAccessory(selected: true)
        XCTAssertEqual(
            SourceDispositionPresentation.disposition(for: on.checkbox),
            .trashAfterVerifiedSuccess
        )
        let labels = descendants(in: on.view).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains(SourceDispositionPresentation.explanation))
        on.view.layoutSubtreeIfNeeded()
        for control in descendants(in: on.view) where !control.isHidden {
            let frame = control.convert(control.bounds, to: on.view)
            XCTAssertGreaterThanOrEqual(frame.minX, on.view.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, on.view.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, on.view.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, on.view.bounds.maxY + 1)
        }

        XCTAssertFalse(
            SourceDispositionCommitPolicy.shouldApply(
                .trashAfterVerifiedSuccess,
                afterQueueRecordedSuccess: false
            )
        )
        XCTAssertFalse(
            SourceDispositionCommitPolicy.shouldApply(
                .keepOriginal,
                afterQueueRecordedSuccess: true
            )
        )
        XCTAssertTrue(
            SourceDispositionCommitPolicy.shouldApply(
                .trashAfterVerifiedSuccess,
                afterQueueRecordedSuccess: true
            )
        )
        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_TRASH_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            let desiredSize = on.view.frame.size
            let window = NSWindow(contentViewController: NSViewController())
            window.title = "Save Verified MKV Copy"
            window.contentView = on.view
            window.setContentSize(desiredSize)
            try captureWindow(window: window, content: on.view, at: capturePath)
        }
    }

    @MainActor
    func testVerifiedTrashFailureNeverClaimsAnUnobservedSourceOutcome() throws {
        struct ExpectedFailure: Error {}
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-trash-warning-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.mkv")
        let destination = root.appendingPathComponent("Movie — Verified.mkv")
        try Data([1]).write(to: source)

        let unchanged = AppModel(trashSource: { _ in throw ExpectedFailure() })
        XCTAssertEqual(
            unchanged.applyVerifiedTrash(sourceURL: source, destinationURL: destination),
            .failed
        )
        XCTAssertEqual(
            unchanged.state,
            .completedWithWarnings(
                "Created Movie — Verified.mkv and recorded verified success, but could not move the original to Trash, so it remains unchanged."
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        let uncertain = AppModel(trashSource: { url in
            try FileManager.default.removeItem(at: url)
            throw ExpectedFailure()
        })
        XCTAssertEqual(
            uncertain.applyVerifiedTrash(sourceURL: source, destinationURL: destination),
            .uncertain
        )
        XCTAssertEqual(
            uncertain.state,
            .completedWithWarnings(
                "Created Movie — Verified.mkv and recorded verified success, but could not confirm where macOS moved the original. Check Trash before continuing."
            )
        )
    }

    func testEncodingBenchmarkLocationSharesPrivateAppSupportDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-app-encoding-test-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try AppHistoryLocation.makeEncodingBenchmarkStore(
            applicationSupportURL: root
        )
        try await store.save(makeEncodingBenchmarkReport())

        let appDirectory = root.appendingPathComponent("com.dustwave.mkvmagic")
        let attributes = try FileManager.default.attributesOfItem(atPath: appDirectory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appDirectory.appendingPathComponent("encoding-benchmark.json").path
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

    func testHistoryPresentationSortsNewestAndShowsSanitizedLifecycle() throws {
        let older = try makeHistoryRecord(
            id: UUID(uuidString: "1A0DBEF0-4AF6-4B92-B813-D683D26CB18F")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = try makeHistoryRecord(
            id: UUID(uuidString: "A3E910BC-636E-45EF-BC1A-D865966E2A37")!,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(HistoryPresentation.sorted([older, newer]).map(\.id), [newer.id, older.id])
        XCTAssertEqual(
            HistoryPresentation.columnValue(identifier: "state", record: newer),
            "Succeeded"
        )
        let detail = HistoryPresentation.detail(for: newer)
        XCTAssertTrue(detail.contains("Input: Movie.mkv"))
        XCTAssertTrue(detail.contains("Output: Movie — Edited.mkv"))
        XCTAssertTrue(detail.contains("Verified output committed and reopened."))
        XCTAssertFalse(detail.contains(newer.id.uuidString))
    }

    @MainActor
    func testHistoryWindowUsesCompactNativeLayout() throws {
        let controller = HistoryWindowController(records: [])
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(window.contentViewController is HistoryViewController)
        XCTAssertEqual(contentView.frame.size.width, 760, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 560, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 620)
        XCTAssertEqual(window.minSize.height, 420)
        let table = try XCTUnwrap(
            descendants(in: contentView).compactMap { $0 as? NSTableView }.first
        )
        let detail = try XCTUnwrap(
            descendants(in: contentView).compactMap { $0 as? NSTextView }.first
        )
        XCTAssertEqual(table.accessibilityLabel(), "Verified job history")
        XCTAssertEqual(detail.accessibilityLabel(), "Selected job progress")
        XCTAssertTrue(window.initialFirstResponder === table)
    }

    @MainActor
    func testHistoryWindowExplainsAndEnablesExplicitPrivacySafeExport() throws {
        let controller = HistoryWindowController(records: [], onExport: { _ in })
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let export = try XCTUnwrap(
            buttons(in: contentView).first { $0.title == "Export Privacy-Safe Report…" }
        )
        let labels = descendants(in: contentView).compactMap { ($0 as? NSTextField)?.stringValue }
        contentView.layoutSubtreeIfNeeded()
        let exportFrame = export.convert(export.bounds, to: contentView)

        XCTAssertTrue(export.isEnabled)
        XCTAssertEqual(export.accessibilityLabel(), "Export Privacy-Safe Report")
        XCTAssertTrue(export.accessibilityHelp()?.contains("without media names or paths") == true)
        XCTAssertGreaterThanOrEqual(exportFrame.minY, 0)
        XCTAssertLessThanOrEqual(exportFrame.maxY, contentView.bounds.maxY)
        XCTAssertTrue(labels.contains { $0.contains("excludes filenames, paths, titles") })
        XCTAssertTrue(labels.contains { $0.contains("raw tool output") })
        XCTAssertTrue(labels.contains { $0.contains("exact timestamps") })
    }

    @MainActor
    func testTrackEditorWindowUsesCompactNativeLayout() throws {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Movie.mkv"),
            container: "matroska",
            tracks: [MediaTrack(id: 0, kind: .audio, codec: "aac", uid: 42)]
        )
        let controller = TrackEditorWindowController(asset: asset)
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(window.contentViewController is TrackEditorViewController)
        XCTAssertEqual(contentView.frame.size.width, 560, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 510, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 520)
        XCTAssertEqual(window.minSize.height, 480)
        XCTAssertEqual(
            window.initialFirstResponder?.accessibilityLabel(),
            "Track to edit"
        )
        let labels = descendants(in: contentView).compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Track display name"))
        XCTAssertTrue(labels.contains("Track language tag"))
        XCTAssertTrue(labels.contains("Track edit status"))
        XCTAssertEqual(
            try XCTUnwrap(buttons(in: contentView).first { $0.title == "Cancel" }).keyEquivalent,
            "\u{1b}"
        )
    }

    @MainActor
    func testTrackRemovalWindowUsesCompactNativeLayout() throws {
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Movie.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1", uid: 42),
                MediaTrack(id: 1, kind: .audio, codec: "aac", uid: 84),
            ]
        )
        let controller = TrackRemovalWindowController(asset: asset)
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(window.contentViewController is TrackRemovalViewController)
        XCTAssertEqual(contentView.frame.size.width, 620, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 480, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 540)
        XCTAssertEqual(window.minSize.height, 420)

        let firstTrack = try XCTUnwrap(
            buttons(in: contentView).first { $0.title.contains("#1 Video") }
        )
        XCTAssertTrue(window.initialFirstResponder === firstTrack)
        XCTAssertTrue(firstTrack.accessibilityHelp()?.contains("verified copy") == true)
        XCTAssertEqual(
            try XCTUnwrap(buttons(in: contentView).first { $0.title == "Cancel" }).keyEquivalent,
            "\u{1b}"
        )

        try XCTUnwrap(buttons(in: contentView).first { $0.title == "Preview Removal" })
            .performClick(nil)
        let labels = descendants(in: contentView).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(
            labels.contains {
                $0.contains("Could not prepare track removal.")
                    && $0.contains("No tracks were removed; revise the selection and try again.")
                    && $0.contains("Details: Check at least one track to remove.")
            }
        )
    }

    @MainActor
    func testWorkflowWindowUsesCompactNativeLayout() throws {
        let controller = WorkflowWindowController(
            workflows: [WorkflowEditorPolicy.newWorkflow()],
            hasSelectedAsset: true,
            onSave: { _ in },
            onUse: { _ in }
        )
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(window.contentViewController is WorkflowLibraryViewController)
        XCTAssertEqual(contentView.frame.size.width, 780, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 560, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 680)
        XCTAssertEqual(window.minSize.height, 480)
        let tables = descendants(in: contentView).compactMap { $0 as? NSTableView }
        let workflows = try XCTUnwrap(
            tables.first { $0.accessibilityLabel() == "Saved workflows" }
        )
        let steps = try XCTUnwrap(tables.first { $0.rowHeight == 62 })
        XCTAssertTrue(window.initialFirstResponder === workflows)
        XCTAssertEqual(steps.accessibilityLabel(), "Workflow steps")
        let accessibilityLabels = descendants(in: contentView).compactMap {
            $0.accessibilityLabel()
        }
        XCTAssertTrue(accessibilityLabels.contains("Workflow name"))
        XCTAssertTrue(accessibilityLabels.contains("Workflow status"))
        XCTAssertTrue(accessibilityLabels.contains("Add workflow step"))
        XCTAssertTrue(accessibilityLabels.contains("New workflow"))
        let controls = buttons(in: contentView)
        let save = try XCTUnwrap(controls.first { $0.title == "Save" })
        let preview = try XCTUnwrap(controls.first { $0.title == "Save & Preview" })
        XCTAssertEqual(save.keyEquivalent, "s")
        XCTAssertEqual(save.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(preview.keyEquivalent, "\r")
        XCTAssertTrue(save.accessibilityHelp()?.contains("privately on this Mac") == true)
        XCTAssertTrue(preview.accessibilityHelp()?.contains("selected file") == true)
        XCTAssertEqual(steps.numberOfRows, 3)
        XCTAssertEqual(
            WorkflowEditorPolicy.newWorkflow().steps.map(\.action),
            [
                .removeNonEnglishSubtitles,
                .removeRedundantEnglishSDH,
                .removeSegmentTitle,
            ]
        )
        if let capturePath = ProcessInfo.processInfo.environment[
            "MKV_MAGIC_WORKFLOW_CAPTURE"
        ], capturePath.hasPrefix("/") {
            window.setContentSize(window.minSize)
            try captureTrimWindow(window: window, content: contentView, at: capturePath)
        }
    }

    @MainActor
    func testWorkflowWindowExplainsUnavailablePreviewWithoutSelectedMedia() throws {
        let controller = WorkflowWindowController(
            workflows: [WorkflowEditorPolicy.newWorkflow()],
            hasSelectedAsset: false,
            onSave: { _ in },
            onUse: { _ in }
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        let preview = try XCTUnwrap(
            buttons(in: content).first { $0.title == "Save & Preview" }
        )

        XCTAssertFalse(preview.isEnabled)
        XCTAssertTrue(
            preview.accessibilityHelp()?.contains("Inspect and select a Matroska file") == true
        )
    }

    @MainActor
    func testVerifiedOutputProgressExplainsCancellationAndCommitBoundary() throws {
        var didCancel = false
        let cancellable = VerifiedOutputProgressWindowController.trim(mode: .exact)
        cancellable.onCancel = { didCancel = true }
        let cancellableWindow = try XCTUnwrap(cancellable.window)
        let cancellableContent = try XCTUnwrap(cancellableWindow.contentView)
        let cancel = try XCTUnwrap(
            buttons(in: cancellableContent).first { $0.title == "Cancel" }
        )
        let status = try XCTUnwrap(
            descendants(in: cancellableContent).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Execution status"
            }
        )
        let progress = try XCTUnwrap(
            descendants(in: cancellableContent).compactMap { $0 as? NSProgressIndicator }.first
        )

        XCTAssertTrue(cancellableWindow.initialFirstResponder === cancel)
        XCTAssertEqual(cancel.keyEquivalent, "\u{1b}")
        XCTAssertTrue(cancel.accessibilityHelp()?.contains("original remains unchanged") == true)
        XCTAssertEqual(progress.accessibilityLabel(), "Verified output progress")
        XCTAssertTrue(progress.isIndeterminate)
        cancel.performClick(nil)
        XCTAssertTrue(didCancel)
        XCTAssertFalse(cancel.isEnabled)
        XCTAssertTrue(status.stringValue.contains("Cancelling and removing"))
        XCTAssertTrue(cancel.accessibilityHelp()?.contains("cleanup is in progress") == true)

        let committing = VerifiedOutputProgressWindowController.losslessJoin()
        let committingContent = try XCTUnwrap(committing.window?.contentView)
        let commitCancel = try XCTUnwrap(
            buttons(in: committingContent).first { $0.title == "Cancel" }
        )
        let commitStatus = try XCTUnwrap(
            descendants(in: committingContent).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Execution status"
            }
        )
        committing.update(stage: VerifiedOutputExecutionStage.committing)
        XCTAssertFalse(commitCancel.isEnabled)
        XCTAssertTrue(commitStatus.stringValue.contains("Verification passed"))
        XCTAssertTrue(commitCancel.accessibilityHelp()?.contains("committed atomically") == true)
    }

    @MainActor
    func testWorkflowBuilderAddsAndRemovesAvailableCardsWithoutDuplicates() throws {
        let workflow = SavedWorkflow(
            name: "Custom cleanup",
            steps: [SavedWorkflowStep(action: .removeNonEnglishSubtitles)]
        )
        let controller = WorkflowWindowController(
            workflows: [workflow],
            hasSelectedAsset: true,
            onSave: { _ in },
            onUse: { _ in }
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        let stepTable = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTableView }.first {
                $0.rowHeight == 62
            }
        )
        let addStep = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSPopUpButton }.first
        )
        let removeStep = try XCTUnwrap(
            buttons(in: content).first { $0.title == "Remove Step" }
        )
        let existing = try XCTUnwrap(
            addStep.item(withTitle: SavedWorkflowAction.removeNonEnglishSubtitles.displayName)
        )
        let available = try XCTUnwrap(
            addStep.item(withTitle: SavedWorkflowAction.addExternalSubtitle.displayName)
        )

        XCTAssertEqual(stepTable.numberOfRows, 1)
        XCTAssertFalse(existing.isEnabled)
        XCTAssertTrue(available.isEnabled)
        XCTAssertNil(addStep.item(withTitle: SavedWorkflowAction.englishLibraryCleanup.displayName))
        XCTAssertTrue(
            NSApplication.shared.sendAction(
                try XCTUnwrap(available.action),
                to: available.target,
                from: available
            )
        )
        XCTAssertEqual(stepTable.numberOfRows, 2)
        XCTAssertFalse(available.isEnabled)
        XCTAssertTrue(removeStep.isEnabled)

        removeStep.performClick(nil)
        XCTAssertEqual(stepTable.numberOfRows, 1)
        XCTAssertTrue(available.isEnabled)

        removeStep.performClick(nil)
        XCTAssertEqual(stepTable.numberOfRows, 0)
        XCTAssertTrue(addStep.isEnabled)
        XCTAssertFalse(removeStep.isEnabled)
        XCTAssertTrue(existing.isEnabled)
        XCTAssertFalse(
            try XCTUnwrap(buttons(in: content).first { $0.title == "Save & Preview" }).isEnabled
        )
    }

    func testWorkflowEditorPolicyCatalogAndMutationsAreBounded() {
        var workflow = SavedWorkflow(name: "Blank", steps: [])

        XCTAssertEqual(
            WorkflowEditorPolicy.availableActions(for: workflow),
            [
                .removeNonEnglishSubtitles,
                .removeRedundantEnglishSDH,
                .removeSegmentTitle,
                .normalizeFilename,
                .addExternalSubtitle,
            ]
        )
        XCTAssertTrue(WorkflowEditorPolicy.add(.removeSegmentTitle, to: &workflow))
        XCTAssertFalse(WorkflowEditorPolicy.add(.removeSegmentTitle, to: &workflow))
        XCTAssertFalse(WorkflowEditorPolicy.add(.englishLibraryCleanup, to: &workflow))
        XCTAssertEqual(workflow.steps.map(\.action), [.removeSegmentTitle])
        XCTAssertFalse(WorkflowEditorPolicy.removeStep(at: -1, from: &workflow))
        XCTAssertTrue(WorkflowEditorPolicy.removeStep(at: 0, from: &workflow))
        XCTAssertTrue(workflow.steps.isEmpty)
    }

    func testWorkflowEditorKeepsExternalSubtitleCleanupDependencyIntuitive() {
        var workflow = SavedWorkflow(name: "Subtitle recipe", steps: [])

        XCTAssertFalse(
            WorkflowEditorPolicy.availableActions(for: workflow).contains(
                .cleanExternalSubtitleText
            )
        )
        XCTAssertFalse(
            WorkflowEditorPolicy.add(.cleanExternalSubtitleText, to: &workflow)
        )
        XCTAssertTrue(WorkflowEditorPolicy.add(.addExternalSubtitle, to: &workflow))
        XCTAssertTrue(
            WorkflowEditorPolicy.availableActions(for: workflow).contains(
                .cleanExternalSubtitleText
            )
        )
        XCTAssertTrue(
            WorkflowEditorPolicy.add(.cleanExternalSubtitleText, to: &workflow)
        )
        XCTAssertTrue(
            WorkflowEditorPolicy.setStepEnabled(false, at: 0, in: &workflow)
        )
        XCTAssertEqual(workflow.steps.map(\.isEnabled), [false, false])
        XCTAssertTrue(
            WorkflowEditorPolicy.setStepEnabled(true, at: 1, in: &workflow)
        )
        XCTAssertEqual(workflow.steps.map(\.isEnabled), [true, true])
        XCTAssertTrue(WorkflowEditorPolicy.removeStep(at: 0, from: &workflow))
        XCTAssertTrue(workflow.steps.isEmpty)
    }

    @MainActor
    func testWorkflowPlanReviewShowsAppliedSkippedAndDisabledStepsAtMinimumSize() throws {
        let workflow = SavedWorkflow(
            name: "Prepare for Jellyfin",
            steps: [
                SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                SavedWorkflowStep(action: .removeRedundantEnglishSDH),
                SavedWorkflowStep(isEnabled: false, action: .removeSegmentTitle),
            ]
        )
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Movie.mkv"),
            container: "matroska",
            tracks: [
                MediaTrack(id: 0, kind: .video, codec: "av1", uid: 1),
                MediaTrack(
                    id: 1,
                    kind: .subtitle,
                    codec: "subrip",
                    uid: 2,
                    language: "fr",
                    title: "French"
                ),
            ]
        )
        let preview = try SavedWorkflowCompiler().preview(workflow, for: asset)
        let controller = WorkflowPlanReviewWindowController(
            preview: preview,
            sourceDisplayName: asset.sourceURL.lastPathComponent
        )
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.title, "Workflow Preview")
        XCTAssertEqual(window.minSize.width, 540)
        XCTAssertEqual(window.minSize.height, 420)
        let text = descendants(in: content)
            .compactMap { ($0 as? NSTextField)?.stringValue }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("Review what will change"))
        XCTAssertTrue(text.contains("No transcoding • one MKV remux"))
        XCTAssertTrue(text.contains("Remove 1 explicitly non-English subtitle track"))
        XCTAssertTrue(text.contains("No redundant English SDH subtitle tracks were found."))
        XCTAssertTrue(text.contains("Not included in this run."))
        XCTAssertTrue(buttons(in: content).contains { $0.title == "Use This Plan" })
        let primary = try XCTUnwrap(buttons(in: content).first { $0.title == "Use This Plan" })
        let cancel = try XCTUnwrap(buttons(in: content).first { $0.title == "Cancel" })
        XCTAssertEqual(primary.keyEquivalent, "\r")
        XCTAssertEqual(cancel.keyEquivalent, "\u{1b}")
        XCTAssertTrue(window.initialFirstResponder === primary)
        let accessibilityLabels = descendants(in: content).compactMap {
            $0.accessibilityLabel()
        }
        XCTAssertTrue(accessibilityLabels.contains("Workflow and source"))
        XCTAssertTrue(accessibilityLabels.contains("Encoding impact"))
        XCTAssertTrue(accessibilityLabels.contains("Workflow step outcomes"))
        XCTAssertTrue(accessibilityLabels.contains("Source safety"))

        if let capturePath = ProcessInfo.processInfo.environment[
            "MKV_MAGIC_WORKFLOW_REVIEW_CAPTURE"
        ], capturePath.hasPrefix("/") {
            try captureTrimWindow(window: window, content: content, at: capturePath)
        }
    }

    @MainActor
    func testWorkflowPlanReviewExplainsAlreadySatisfiedRecipeWithoutRunAction() throws {
        let workflow = SavedWorkflow(
            name: "Already clean",
            steps: [
                SavedWorkflowStep(action: .removeNonEnglishSubtitles),
                SavedWorkflowStep(action: .removeRedundantEnglishSDH),
            ]
        )
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Clean.mkv"),
            container: "matroska",
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1", uid: 1)]
        )
        let preview = try SavedWorkflowCompiler().preview(workflow, for: asset)
        let controller = WorkflowPlanReviewWindowController(
            preview: preview,
            sourceDisplayName: asset.sourceURL.lastPathComponent
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()

        XCTAssertNil(preview.compiledWorkflow)
        let text = descendants(in: content)
            .compactMap { ($0 as? NSTextField)?.stringValue }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("This file already matches"))
        XCTAssertTrue(text.contains("No applicable changes • No output"))
        XCTAssertTrue(text.contains("No output will be created."))
        XCTAssertTrue(buttons(in: content).contains { $0.title == "Done" && !$0.isHidden })
        XCTAssertFalse(buttons(in: content).contains { $0.title == "Use This Plan" })
    }

    @MainActor
    func testWorkflowPlanReviewDisclosesFilenameOnlyUnchangedCopy() throws {
        let workflow = SavedWorkflow(
            name: "Jellyfin filename",
            steps: [SavedWorkflowStep(action: .normalizeFilename)]
        )
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Movie.2025.1080p.mkv"),
            container: "matroska",
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1", uid: 1)]
        )
        let preview = try SavedWorkflowCompiler().preview(workflow, for: asset)
        let controller = WorkflowPlanReviewWindowController(
            preview: preview,
            sourceDisplayName: asset.sourceURL.lastPathComponent
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()

        let text = descendants(in: content)
            .compactMap { ($0 as? NSTextField)?.stringValue }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("No transcoding • byte-identical file copy"))
        XCTAssertTrue(text.contains("Suggest the output filename “Movie (2025).mkv”"))
        XCTAssertTrue(buttons(in: content).contains { $0.title == "Use This Plan" })
    }

    @MainActor
    func testWorkflowPlanReviewShowsReviewedExternalSubtitleAndFusedPasses() throws {
        let workflow = SavedWorkflow(
            name: "Add English subtitles",
            steps: [
                SavedWorkflowStep(action: .cleanExternalSubtitleText),
                SavedWorkflowStep(action: .addExternalSubtitle),
                SavedWorkflowStep(action: .removeSegmentTitle),
            ]
        )
        let asset = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/private/media/Movie.mkv"),
            container: "matroska",
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1", uid: 1)],
            metadata: ["title": "Movie"]
        )
        let preview = try SavedWorkflowCompiler().preview(
            workflow,
            for: asset,
            inputs: SavedWorkflowResolvedInputs(
                externalSubtitle: SavedWorkflowExternalSubtitleInput(
                    sourceURL: URL(fileURLWithPath: "/private/media/Movie.en.srt"),
                    metadata: ExternalSubtitleTrackMetadata(
                        language: "en",
                        name: "English"
                    ),
                    format: .subRip,
                    reviewedCleanupChangeCount: 2
                )
            )
        )
        let controller = WorkflowPlanReviewWindowController(
            preview: preview,
            sourceDisplayName: asset.sourceURL.lastPathComponent
        )
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()

        let text = descendants(in: content)
            .compactMap { ($0 as? NSTextField)?.stringValue }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("No transcoding • one MKV remux • one metadata pass"))
        XCTAssertTrue(text.contains("Apply 2 reviewed subtitle text changes inside the same remux"))
        XCTAssertTrue(text.contains("Add one reviewed SRT subtitle as the last track"))
        XCTAssertTrue(text.contains("Remove the segment title"))
        XCTAssertTrue(buttons(in: content).contains { $0.title == "Use This Plan" })

        if let capturePath = ProcessInfo.processInfo.environment[
            "MKV_MAGIC_EXTERNAL_WORKFLOW_REVIEW_CAPTURE"
        ], capturePath.hasPrefix("/") {
            try captureTrimWindow(window: window, content: content, at: capturePath)
        }
    }

    func testWorkflowEditorDuplicatesPortableIntentWithFreshIdentifiers() {
        let original = WorkflowEditorPolicy.newWorkflow()
        let copy = WorkflowEditorPolicy.duplicate(original)

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.name, "New Workflow Copy")
        XCTAssertEqual(copy.steps.map(\.action), original.steps.map(\.action))
        XCTAssertEqual(copy.steps.map(\.isEnabled), original.steps.map(\.isEnabled))
        XCTAssertTrue(Set(copy.steps.map(\.id)).isDisjoint(with: original.steps.map(\.id)))
        XCTAssertEqual(
            WorkflowEditorPolicy.exportFilename(
                for: SavedWorkflow(name: "TV/Film: Clean", steps: original.steps)),
            "TV-Film- Clean.mkvmagic-workflow"
        )
    }

    func testSubtitleCleanupPresentationKeepsOneCueAndFormatsTiming() {
        let advertisement = SubRipCue(
            id: 0,
            start: SubRipTimestamp(milliseconds: 90_061_007),
            end: SubRipTimestamp(milliseconds: 90_062_008),
            lines: ["Downloaded from", "YTS.MX"]
        )
        let document = SubRipDocument(cues: [advertisement])
        let cleanup = SubtitleCleanupPolicy().preview(document)
        let preview = SubtitleCleanupFilePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.srt"),
            sourceSHA256: Data(SHA256.hash(data: Data())),
            encoding: .utf8,
            diagnostics: [],
            cleanup: cleanup,
            normalizationNeeded: false
        )

        XCTAssertFalse(
            SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: [advertisement.id]
            )
        )
        XCTAssertTrue(
            SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: []
            )
        )
        XCTAssertEqual(
            SubtitleCleanupPresentation.time(advertisement.start),
            "25:01:01,007"
        )
        XCTAssertTrue(
            SubtitleCleanupPresentation.selectedByDefault(reasons: [.ocrHighConfidence])
        )
        XCTAssertFalse(
            SubtitleCleanupPresentation.selectedByDefault(reasons: [.spellingSuggestion])
        )
    }

    func testSubtitleCleanupPresentationDistinguishesOCRConfidenceAndLanguagePolicy() {
        let cue = SubRipCue(
            id: 0,
            start: SubRipTimestamp(milliseconds: 0),
            end: SubRipTimestamp(milliseconds: 1_000),
            lines: ["Tbe"]
        )
        let correctedCue = SubRipCue(
            id: cue.id,
            start: cue.start,
            end: cue.end,
            lines: ["The"]
        )
        let change = SubtitleCleanupChange(
            id: cue.id,
            reasons: [.spellingSuggestion],
            before: cue,
            after: correctedCue
        )
        let cleanup = SubtitleCleanupPreview(
            original: SubRipDocument(cues: [cue]),
            cleaned: SubRipDocument(cues: [correctedCue]),
            changes: [change]
        )
        let preview = SubtitleCleanupFilePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.fr.srt"),
            sourceSHA256: Data(),
            encoding: .utf8,
            diagnostics: [],
            cleanup: cleanup,
            normalizationNeeded: false,
            appliesEnglishOCRRules: false
        )

        XCTAssertTrue(SubtitleCleanupPresentation.title(change).contains("possible"))
        XCTAssertTrue(
            SubtitleCleanupPresentation.normalization(preview).contains("skipped")
        )
        XCTAssertTrue(SubtitleCleanupPresentation.summary(preview).contains("0 of 1"))
    }

    func testAdvancedSubtitleCleanupPresentationKeepsOneEventAndDescribesPreservation() throws {
        let preview = try advancedSubtitlePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.ass"),
            text:
                "[Events]\nFormat: Layer, Start, End, Style, Text\n"
                + "Dialogue: 0,0:00:01.00,0:00:02.00,Default,Downloaded from YTS.MX\n"
        )
        let eventID = try XCTUnwrap(preview.cleanup.original.events.first?.id)

        XCTAssertFalse(
            SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: [eventID]
            )
        )
        XCTAssertTrue(
            SubtitleCleanupPresentation.canConfirm(
                preview: preview,
                appliedChangeIDs: []
            )
        )
        XCTAssertTrue(
            SubtitleCleanupPresentation.normalization(preview).contains(
                "script sections and styles preserved"
            )
        )
    }

    @MainActor
    func testSubtitleCleanupWindowUsesCompactNativeLayout() throws {
        let document = SubRipDocument(
            cues: [
                SubRipCue(
                    id: 0,
                    start: SubRipTimestamp(milliseconds: 0),
                    end: SubRipTimestamp(milliseconds: 1_000),
                    lines: [" Text "]
                )
            ]
        )
        let controller = SubtitleCleanupWindowController(
            preview: SubtitleCleanupFilePreview(
                sourceURL: URL(fileURLWithPath: "/Media/Movie.srt"),
                sourceSHA256: Data(SHA256.hash(data: Data())),
                encoding: .utf8,
                diagnostics: [],
                cleanup: SubtitleCleanupPolicy().preview(document),
                normalizationNeeded: true
            )
        )
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(window.contentViewController is SubtitleCleanupViewController)
        XCTAssertEqual(contentView.frame.size.width, 740, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 560, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 640)
        XCTAssertEqual(window.minSize.height, 480)
        let table = try XCTUnwrap(
            descendants(in: contentView).compactMap { $0 as? NSTableView }.first
        )
        XCTAssertEqual(table.accessibilityLabel(), "Subtitle cleanup suggestions")
        XCTAssertTrue(window.initialFirstResponder === table)
        let labels = descendants(in: contentView).compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Subtitle cleanup selection summary"))
        XCTAssertTrue(labels.contains("Subtitle normalization details"))
        XCTAssertTrue(labels.contains("Subtitle cleanup status"))
        XCTAssertEqual(
            try XCTUnwrap(buttons(in: contentView).first { $0.title == "Cancel" }).keyEquivalent,
            "\u{1b}"
        )
    }

    @MainActor
    func testAdvancedSubtitleCleanupUsesSharedCompactReviewWindow() throws {
        let preview = try advancedSubtitlePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.ass"),
            text:
                "[Events]\nFormat: Layer, Start, End, Style, Text\n"
                + "Dialogue: 0,0:00:01.00,0:00:02.00,Default, Text \n"
        )
        let controller = SubtitleCleanupWindowController(preview: preview)
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertEqual(window.title, "Clean ASS/SSA Subtitle")
        XCTAssertTrue(window.contentViewController is SubtitleCleanupViewController)
        XCTAssertEqual(contentView.frame.size.width, 740, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 560, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 640)
        XCTAssertEqual(window.minSize.height, 480)
    }

    @MainActor
    func testEmbeddedSubtitlePickerUsesReadableTrackLabelsAndCompactLayout() throws {
        let tracks = [
            MediaTrack(
                id: 1,
                kind: .subtitle,
                codec: "subrip",
                codecID: "S_TEXT/UTF8",
                uid: 42,
                language: "en",
                title: "English SDH",
                isDefault: true,
                isHearingImpaired: true
            ),
            MediaTrack(
                id: 2,
                kind: .subtitle,
                codec: "PGS",
                codecID: "S_HDMV/PGS",
                uid: 43,
                language: "fr"
            ),
        ]
        XCTAssertEqual(
            EmbeddedSubtitleTrackPickerViewController.title(tracks[0]),
            "#2 • SRT • en • English SDH • default, SDH"
        )
        let controller = EmbeddedSubtitleTrackPickerWindowController(tracks: tracks)
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertEqual(window.title, "Choose Embedded Subtitle")
        XCTAssertTrue(
            window.contentViewController is EmbeddedSubtitleTrackPickerViewController)
        XCTAssertEqual(contentView.frame.size.width, 620, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 280, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 540)
        XCTAssertEqual(window.minSize.height, 260)
        XCTAssertEqual(
            window.initialFirstResponder?.accessibilityLabel(),
            "Embedded subtitle track"
        )
        let labels = descendants(in: contentView).compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Embedded subtitle selection status"))
        XCTAssertEqual(
            try XCTUnwrap(buttons(in: contentView).first { $0.title == "Cancel" }).keyEquivalent,
            "\u{1b}"
        )
    }

    @MainActor
    func testEmbeddedSRTUsesSharedReviewWindowAndTrackLanguageExplanation() throws {
        let cue = SubRipCue(
            id: 0,
            start: SubRipTimestamp(milliseconds: 0),
            end: SubRipTimestamp(milliseconds: 1_000),
            lines: [" y0u "]
        )
        let track = MediaTrack(
            id: 1,
            kind: .subtitle,
            codec: "subrip",
            codecID: "S_TEXT/UTF8",
            uid: 42,
            language: "en",
            title: "English"
        )
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            tracks: [track]
        )
        let preview = EmbeddedSubtitleCleanupPreview.subRip(
            EmbeddedSubRipCleanupPreview(
                source: source,
                track: track,
                sourceRevision: EmbeddedSubtitleSourceRevision(
                    fileSize: 1,
                    modificationDate: Date(timeIntervalSince1970: 0)
                ),
                extractedSHA256: Data(),
                packetTimelineSHA256: Data(),
                encoding: .utf8,
                diagnostics: [],
                cleanup: SubtitleCleanupPolicy().preview(SubRipDocument(cues: [cue])),
                appliesEnglishOCRRules: true
            ))
        let controller = SubtitleCleanupWindowController(preview: preview)
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.title, "Clean Embedded SRT Subtitle")
        XCTAssertTrue(window.contentViewController is SubtitleCleanupViewController)
        XCTAssertTrue(
            SubtitleCleanupPresentation.embeddedNormalization(
                format: .subRip,
                track: track,
                appliesEnglishOCRRules: true,
                diagnosticCount: 0
            ).contains("same position")
        )
    }

    @MainActor
    func testExternalSubtitleMuxWindowUsesCompactNativeLayoutAndExplicitWarnings() throws {
        let cue = SubRipCue(
            id: 0,
            start: SubRipTimestamp(milliseconds: 0),
            end: SubRipTimestamp(milliseconds: 1_000),
            lines: [" Text "]
        )
        let document = SubRipDocument(cues: [cue])
        let preview = SubtitleCleanupFilePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Unrelated.srt"),
            sourceSHA256: Data(SHA256.hash(data: Data())),
            encoding: .utf8,
            diagnostics: [],
            cleanup: SubtitleCleanupPolicy().preview(document),
            normalizationNeeded: false
        )
        let match = ExternalSubtitleMatch(
            subtitleURL: preview.sourceURL,
            score: 0,
            confidence: .low,
            reasons: [],
            suggestedMetadata: ExternalSubtitleTrackMetadata(language: "und"),
            subtitleEnd: cue.end,
            durationDifferenceMilliseconds: -119_000,
            isDurationCompatible: false
        )
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 120),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
        let warnings = ExternalSubtitleMuxPresentation.warnings(
            preview: preview,
            match: match
        )
        XCTAssertEqual(warnings.count, 3)
        XCTAssertTrue(warnings[0].contains("weak match"))
        XCTAssertTrue(warnings[1].contains("shorter"))
        XCTAssertTrue(warnings[2].contains("will not be applied"))

        let controller = ExternalSubtitleMuxWindowController(
            media: media,
            preview: preview,
            match: match
        )
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertTrue(window.contentViewController is ExternalSubtitleMuxViewController)
        XCTAssertEqual(contentView.frame.size.width, 620, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 530, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 560)
        XCTAssertEqual(window.minSize.height, 500)
        XCTAssertEqual(
            window.initialFirstResponder?.accessibilityLabel(),
            "Subtitle language tag"
        )
        let labels = descendants(in: contentView).compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Subtitle track name"))
        XCTAssertTrue(labels.contains("Subtitle match and cleanup warning"))
        XCTAssertTrue(labels.contains("Subtitle track status"))
        XCTAssertEqual(
            try XCTUnwrap(buttons(in: contentView).first { $0.title == "Cancel" }).keyEquivalent,
            "\u{1b}"
        )
    }

    @MainActor
    func testExternalASSMuxUsesSharedConfirmationAndWarnsBeforeDiscardingCleanup() throws {
        let preview = try advancedSubtitlePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.en.ass"),
            text:
                "[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n"
                + "[Events]\nFormat: Layer, Start, End, Style, Text\n"
                + "Dialogue: 0,0:00:00.00,0:00:01.00,Default, Text \n"
        )
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 1),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
        let match = ExternalSubtitleMatcher().match(
            media: media,
            subtitleURL: preview.sourceURL,
            subtitle: preview.cleanup.original
        )

        let warnings = ExternalSubtitleMuxPresentation.warnings(
            preview: preview,
            match: match
        )
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("Clean Subtitle first"))

        let controller = ExternalSubtitleMuxWindowController(
            media: media,
            preview: preview,
            match: match
        )
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertEqual(window.title, "Add External Subtitle")
        XCTAssertTrue(window.contentViewController is ExternalSubtitleMuxViewController)
        XCTAssertEqual(contentView.frame.size.width, 620, accuracy: 1)
        XCTAssertEqual(contentView.frame.size.height, 530, accuracy: 1)
    }

    @MainActor
    func testExternalSubtitleConfirmationExplainsReviewedCleanupWithoutDiscardWarning() throws {
        let preview = try advancedSubtitlePreview(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.en.ass"),
            text:
                "[Events]\nFormat: Layer, Start, End, Style, Text\n"
                + "Dialogue: 0,0:00:00.00,0:00:01.00,Default, Text \n"
        )
        let media = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska",
            duration: MediaTime(seconds: 1),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
        let match = ExternalSubtitleMatcher().match(
            media: media,
            subtitleURL: preview.sourceURL,
            subtitle: preview.cleanup.original
        )

        XCTAssertFalse(
            ExternalSubtitleMuxPresentation.warnings(
                preview: .advanced(preview),
                match: match,
                cleanupWasReviewed: true
            ).contains { $0.contains("will not be applied") }
        )
        let controller = ExternalSubtitleMuxWindowController(
            media: media,
            preview: .advanced(preview),
            match: match,
            reviewedCleanupChangeCount: 1
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        let text = descendants(in: content)
            .compactMap { ($0 as? NSTextField)?.stringValue }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("1 reviewed cleanup change will be applied"))
        XCTAssertFalse(text.contains("Use Clean Subtitle first"))
    }

    @MainActor
    func testSubtitleCleanupPersistsSanitizedVerifiedLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-subtitle-history-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.en.srt")
        let output = root.appendingPathComponent("Movie.en — Clean.srt")
        let sourceData = Data(
            ("1\r\n00:00:00,000 --> 00:00:01,000\r\nDownloaded from\r\nYTS.MX\r\n\r\n"
                + "2\r\n00:00:01,000 --> 00:00:02,000\r\n  Dialogue  \r\n").utf8
        )
        try sourceData.write(to: source)
        let applicationSupport = root.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: false
        )
        let store = try AppHistoryLocation.makeStore(applicationSupportURL: applicationSupport)
        let model = AppModel(historyRecorderFactory: { store })

        let preview = try await model.previewSubtitleCleanup(at: source)
        let result = try await model.cleanSubtitle(
            preview: preview,
            restoringCueIDs: [],
            destinationURL: output
        )

        XCTAssertEqual(result.removedCueCount, 1)
        XCTAssertEqual(result.changedCueCount, 1)
        XCTAssertEqual(try Data(contentsOf: source), sourceData)
        XCTAssertEqual(
            String(decoding: try Data(contentsOf: output), as: UTF8.self),
            "1\n00:00:01,000 --> 00:00:02,000\nDialogue\n"
        )
        XCTAssertEqual(
            model.state,
            .completed("Created Movie.en — Clean.srt; original unchanged.")
        )
        let records = try await store.load()
        let record = try XCTUnwrap(records.only)
        XCTAssertEqual(record.workflowName, "Clean SRT subtitle")
        XCTAssertEqual(record.inputs.map(\.displayName), ["Movie.en.srt"])
        XCTAssertEqual(record.outputDisplayName, "Movie.en — Clean.srt")
        XCTAssertEqual(
            record.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let historyText = record.events.compactMap(\.message).joined(separator: " ")
        XCTAssertFalse(historyText.contains(root.path))
        XCTAssertFalse(historyText.contains("Dialogue"))
        XCTAssertFalse(historyText.contains("YTS.MX"))
    }

    @MainActor
    func testAdvancedSubtitleCleanupPersistsSanitizedVerifiedLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mkv-magic-ass-history-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Movie.en.ass")
        let output = root.appendingPathComponent("Movie.en — Clean.ass")
        let sourceText =
            "[Script Info]\r\nTitle: Movie\r\n"
            + "[V4+ Styles]\r\nFormat: Name, Fontname\r\nStyle: Default,Arial\r\n"
            + "[Events]\r\nFormat: Layer, Start, End, Style, Text\r\n"
            + "Dialogue: 0,0:00:00.00,0:00:01.00,Default,Downloaded from YTS.MX\r\n"
            + "Dialogue: 0,0:00:01.00,0:00:02.00,Default,  Dialogue  \r\n"
        let sourceData = Data(sourceText.utf8)
        try sourceData.write(to: source)
        let applicationSupport = root.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: false
        )
        let store = try AppHistoryLocation.makeStore(applicationSupportURL: applicationSupport)
        let model = AppModel(historyRecorderFactory: { store })

        let preview = try await model.previewAdvancedSubtitleCleanup(at: source)
        let result = try await model.cleanAdvancedSubtitle(
            preview: preview,
            restoringEventIDs: [],
            destinationURL: output
        )

        XCTAssertEqual(result.removedEventCount, 1)
        XCTAssertEqual(result.changedEventCount, 1)
        XCTAssertEqual(try Data(contentsOf: source), sourceData)
        let outputText = String(decoding: try Data(contentsOf: output), as: UTF8.self)
        XCTAssertTrue(outputText.contains("Style: Default,Arial"))
        XCTAssertTrue(outputText.contains("Default,Dialogue"))
        XCTAssertFalse(outputText.contains("YTS.MX"))
        XCTAssertEqual(
            model.state,
            .completed("Created Movie.en — Clean.ass; original unchanged.")
        )
        let records = try await store.load()
        let record = try XCTUnwrap(records.only)
        XCTAssertEqual(record.workflowName, "Clean ASS/SSA subtitle")
        XCTAssertEqual(record.inputs.map(\.displayName), ["Movie.en.ass"])
        XCTAssertEqual(record.outputDisplayName, "Movie.en — Clean.ass")
        XCTAssertEqual(
            record.events.map(\.state),
            [.queued, .inspecting, .planned, .ready, .running, .verifying, .committing, .succeeded]
        )
        let historyText = record.events.compactMap(\.message).joined(separator: " ")
        XCTAssertFalse(historyText.contains(root.path))
        XCTAssertFalse(historyText.contains("Dialogue"))
        XCTAssertFalse(historyText.contains("YTS.MX"))
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
        XCTAssertTrue(buttons(in: controller.view).contains { $0.title == "Trim…" })
        XCTAssertTrue(
            buttons(in: controller.view).contains { $0.title == "Encoding Test…" }
        )
        XCTAssertTrue(
            buttons(in: controller.view).contains { button in
                button.title == "Add to Queue" && !button.isEnabled
            }
        )
        XCTAssertTrue(
            buttons(in: controller.view).contains { button in
                button.title == "Verify & Run" && !button.isEnabled
            }
        )
    }

    @MainActor
    func testEncodingBenchmarkWindowRequiresExplicitConsentAndFitsMinimumSize() throws {
        let report = makeEncodingBenchmarkReport()
        let controller = EncodingBenchmarkWindowController(report: report, onRun: { report })
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.title, "MKV Magic Encoding Test")
        XCTAssertEqual(window.minSize, NSSize(width: 540, height: 440))
        let labels = descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains { $0.contains("never reads your media") })
        let controls = buttons(in: content)
        XCTAssertTrue(controls.contains { $0.title == "Run Again" && $0.isEnabled })
        XCTAssertTrue(controls.contains { $0.title == "Close" && $0.isEnabled })
        XCTAssertTrue(controls.contains { $0.title == "Cancel" && $0.isHidden })
        XCTAssertEqual(
            window.initialFirstResponder?.accessibilityLabel(),
            "Run local encoding test"
        )
        XCTAssertTrue(
            controls.first { $0.title == "Run Again" }?.accessibilityHelp()?
                .contains("without reading private media") == true
        )
        XCTAssertEqual(controls.first { $0.title == "Close" }?.keyEquivalent, "\u{1b}")
        XCTAssertTrue(
            descendants(in: content).contains {
                $0.accessibilityLabel() == "Encoding test status"
            }
        )
        let results = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextView }.first
        ).string
        XCTAssertTrue(results.contains("Recommended: AV1 10-bit"))
        XCTAssertTrue(results.contains("Estimated 1080p speed"))
        XCTAssertTrue(results.contains("Every verified encoder remains available"))
        XCTAssertFalse(results.contains("/private/"))
        for button in controls where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }
        if let capturePath = ProcessInfo.processInfo.environment[
            "MKV_MAGIC_ENCODING_TEST_CAPTURE"
        ], capturePath.hasPrefix("/") {
            try captureTrimWindow(window: window, content: content, at: capturePath)
        }
    }

    @MainActor
    func testTrimWindowKeepsThumbnailsNumericFieldsAndReviewActionsUsableAtMinimumSize()
        throws
    {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Movie.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 60_000_000_000),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: "h264",
                    dimensions: MediaDimensions(width: 1_920, height: 1_080),
                    colorInfo: MediaColorInfo(
                        range: "tv",
                        primaries: "bt709",
                        transfer: "bt709",
                        matrix: "bt709"
                    )
                )
            ]
        )
        let jpeg = try makeThumbnailJPEG()
        let thumbnails = TrimPresentationPolicy.thumbnailTimes(
            duration: try XCTUnwrap(source.duration)
        ).map { ChapterThumbnail(time: $0, imageData: jpeg) }
        let capabilities = FFmpegEncodingCapabilities(
            softwareAV1: .unavailable,
            softwareAV1Encoder: nil,
            hevc10VideoToolbox: .verified,
            h264VideoToolbox: .verified,
            proRes: .unavailable,
            proResEncoder: nil,
            aac: .verified,
            aacEncoder: "aac_at",
            availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters
        )
        let controller = TrimWindowController(
            source: source,
            thumbnails: thumbnails,
            capabilities: capabilities,
            reviewProvider: { _ in
                throw NSError(
                    domain: "TrimReviewFixture",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Fixture review failed."]
                )
            }
        )
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(window.minSize)
        content.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.title, "Trim MKV")
        XCTAssertEqual(window.minSize, NSSize(width: 700, height: 570))
        XCTAssertEqual(window.initialFirstResponder?.accessibilityLabel(), "Trim in point")
        let accessibilityLabels = descendants(in: content).compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(accessibilityLabels.contains("Trim input status"))
        XCTAssertTrue(accessibilityLabels.contains("Trim review summary"))
        XCTAssertEqual(descendants(in: content).compactMap { $0 as? NSImageView }.count, 5)
        XCTAssertEqual(
            descendants(in: content).compactMap { $0 as? NSTextField }.filter {
                $0.isEditable
            }.count, 2)
        let mode = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSSegmentedControl }.first
        )
        XCTAssertEqual(mode.segmentCount, 2)
        XCTAssertEqual(mode.label(forSegment: 0), "Fast (No Encoding)")
        XCTAssertEqual(mode.label(forSegment: 1), "Exact")
        let controls = buttons(in: content)
        XCTAssertEqual(controls.filter { $0.title == "Set In" }.count, 5)
        XCTAssertEqual(controls.filter { $0.title == "Set Out" }.count, 5)
        XCTAssertFalse(try XCTUnwrap(controls.first { $0.title == "Review Trim" }).isEnabled)
        XCTAssertFalse(
            try XCTUnwrap(controls.first { $0.title == "Continue to Save…" }).isEnabled
        )
        try XCTUnwrap(controls.filter { $0.title == "Set In" }.dropFirst().first)
            .performClick(nil)
        XCTAssertTrue(try XCTUnwrap(controls.first { $0.title == "Review Trim" }).isEnabled)
        for button in controls where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }

        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_TRIM_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            try captureTrimWindow(window: window, content: content, at: capturePath)
        }

        mode.selectedSegment = 1
        mode.sendAction(mode.action, to: mode.target)
        content.layoutSubtreeIfNeeded()
        let visiblePopups = descendants(in: content).compactMap { $0 as? NSPopUpButton }.filter {
            !$0.isHiddenOrHasHiddenAncestor
        }
        XCTAssertEqual(visiblePopups.count, 3)
        XCTAssertEqual(
            Set(visiblePopups.compactMap(\.titleOfSelectedItem)),
            [
                "Fast — HEVC 10-bit",
                "Balanced",
                "Preserve Audio Exactly (Packet Copy)",
            ]
        )
        XCTAssertTrue(try XCTUnwrap(controls.first { $0.title == "Review Trim" }).isEnabled)

        let advanced = try XCTUnwrap(
            controls.first { $0.title == "Show exact encoding controls" }
        )
        XCTAssertFalse(advanced.isHiddenOrHasHiddenAncestor)
        advanced.performClick(nil)
        content.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }
                .contains("Video bitrate (kbps)")
        )
        XCTAssertEqual(
            descendants(in: content).compactMap { $0 as? NSTextField }.filter {
                $0.isEditable && !$0.isHiddenOrHasHiddenAncestor
            }.count,
            3
        )
        XCTAssertTrue(try XCTUnwrap(controls.first { $0.title == "Review Trim" }).isEnabled)
        for button in controls where !button.isHiddenOrHasHiddenAncestor {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }
        for subview in descendants(in: content) where !subview.isHiddenOrHasHiddenAncestor {
            let frame = subview.convert(subview.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }
        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_TRIM_EXACT_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            try captureTrimWindow(window: window, content: content, at: capturePath)
        }

        try XCTUnwrap(controls.first { $0.title == "Review Trim" }).performClick(nil)
        XCTAssertTrue(
            waitUntil {
                descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }.contains {
                    $0.contains("Could not confirm this trim.")
                        && $0.contains(
                            "No output was created; review the boundaries and try again.")
                        && $0.contains("Details: Fixture review failed.")
                }
            }
        )
        XCTAssertTrue(try XCTUnwrap(controls.first { $0.title == "Review Trim" }).isEnabled)
        XCTAssertTrue(
            descendants(in: content).compactMap { $0 as? NSTextField }.filter(\.isEditable)
                .allSatisfy(\.isEnabled)
        )
    }

    @MainActor
    func testTrimAdvancedAV1ControlsExplainRFAndBoundedSVTSpeed() throws {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/AV1 Source.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 60_000_000_000),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: "av1",
                    dimensions: MediaDimensions(width: 1_920, height: 1_080),
                    colorInfo: MediaColorInfo(
                        range: "tv",
                        primaries: "bt709",
                        transfer: "bt709",
                        matrix: "bt709"
                    )
                )
            ]
        )
        var reviewedRequest: TrimReviewRequest?
        let controller = TrimWindowController(
            source: source,
            thumbnails: [],
            capabilities: FFmpegEncodingCapabilities(
                softwareAV1: .verified,
                softwareAV1Encoder: "libsvtav1",
                hevc10VideoToolbox: .unavailable,
                h264VideoToolbox: .unavailable,
                proRes: .unavailable,
                proResEncoder: nil,
                aac: .unavailable,
                aacEncoder: nil,
                availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters
            ),
            reviewProvider: { request in
                reviewedRequest = request
                throw NSError(domain: "AV1AdvancedReview", code: 1)
            }
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        let mode = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSSegmentedControl }.first
        )
        mode.selectedSegment = 1
        mode.sendAction(mode.action, to: mode.target)
        let advanced = try XCTUnwrap(
            buttons(in: content).first { $0.title == "Show exact encoding controls" }
        )
        advanced.performClick(nil)
        content.layoutSubtreeIfNeeded()

        let labels = descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains("AV1 quality RF (0–63; lower is higher quality)"))
        XCTAssertTrue(labels.contains("AV1 speed (0–13)"))
        let fields = descendants(in: content).compactMap { $0 as? NSTextField }.filter {
            $0.isEditable && !$0.isHiddenOrHasHiddenAncestor
        }
        XCTAssertEqual(
            Set(fields.map(\.stringValue)),
            ["00:00:00.000", "00:01:00.000", "30", "8"]
        )

        let inField = try XCTUnwrap(fields.first { $0.stringValue == "00:00:00.000" })
        let rfField = try XCTUnwrap(fields.first { $0.stringValue == "30" })
        let speedField = try XCTUnwrap(fields.first { $0.stringValue == "8" })
        inField.stringValue = "00:00:01.000"
        rfField.stringValue = "24"
        speedField.stringValue = "5"
        for field in [inField, rfField, speedField] {
            field.delegate?.controlTextDidChange?(
                Notification(name: NSControl.textDidChangeNotification, object: field)
            )
        }
        let review = try XCTUnwrap(buttons(in: content).first { $0.title == "Review Trim" })
        XCTAssertTrue(review.isEnabled)
        review.performClick(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(reviewedRequest?.exactChoice?.videoRateControl, .constantQuality(24))
        XCTAssertEqual(reviewedRequest?.exactChoice?.encoderTuning, .svtAV1Preset(5))
    }

    @MainActor
    func testTrimOffersOnlyLayoutSafeProbedAudioFormatsAndBindsSelection() throws {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/Media/Audio Source.mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 60_000_000_000),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: "h264",
                    dimensions: MediaDimensions(width: 1_920, height: 1_080),
                    colorInfo: MediaColorInfo(
                        range: "tv", primaries: "bt709", transfer: "bt709", matrix: "bt709"
                    )
                ),
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    codec: "aac",
                    channels: 8,
                    channelLayout: "7.1",
                    sampleRate: 48_000
                ),
            ]
        )
        var reviewedRequest: TrimReviewRequest?
        let controller = TrimWindowController(
            source: source,
            thumbnails: [],
            capabilities: FFmpegEncodingCapabilities(
                softwareAV1: .unavailable,
                softwareAV1Encoder: nil,
                hevc10VideoToolbox: .verified,
                h264VideoToolbox: .verified,
                proRes: .unavailable,
                proResEncoder: nil,
                aac: .verified,
                aacEncoder: "aac_at",
                availableFilters: FFmpegEncodingCapabilities.requiredJoinFilters,
                audioCapabilities: [
                    .aacCompatibility: .init(status: .verified, encoder: "aac_at"),
                    .opusQuality: .init(status: .verified, encoder: "libopus"),
                    .ac3Compatibility: .init(status: .verified, encoder: "ac3"),
                    .eac3Compatibility: .init(status: .verified, encoder: "eac3"),
                    .flacLossless: .init(status: .verified, encoder: "flac"),
                ]
            ),
            reviewProvider: { request in
                reviewedRequest = request
                throw NSError(domain: "AudioFormatReview", code: 1)
            }
        )
        let content = try XCTUnwrap(controller.window?.contentView)
        let mode = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSSegmentedControl }.first
        )
        mode.selectedSegment = TrimMode.exact.rawValue
        mode.sendAction(mode.action, to: mode.target)
        let popups = descendants(in: content).compactMap { $0 as? NSPopUpButton }
        let audio = try XCTUnwrap(
            popups.first { popup in
                popup.itemTitles.contains { $0.contains("Opus") }
            })
        XCTAssertEqual(
            audio.itemTitles,
            [
                "Preserve Audio Exactly (Packet Copy)",
                "Convert Once to Opus (Keep Layout, 48 kHz)",
                "Convert Once to FLAC (Lossless) (Keep Layout)",
            ]
        )
        XCTAssertFalse(audio.itemTitles.contains { $0.contains("AAC") })
        XCTAssertFalse(audio.itemTitles.contains { $0.contains("AC-3") })
        audio.selectItem(withTitle: "Convert Once to Opus (Keep Layout, 48 kHz)")
        audio.sendAction(audio.action, to: audio.target)
        if let capturePath = ProcessInfo.processInfo.environment[
            "MKV_MAGIC_TRIM_AUDIO_CAPTURE"
        ], capturePath.hasPrefix("/") {
            try captureTrimWindow(
                window: try XCTUnwrap(controller.window),
                content: content,
                at: capturePath
            )
        }
        let inField = try XCTUnwrap(
            descendants(in: content).compactMap { $0 as? NSTextField }.first {
                $0.isEditable && $0.stringValue == "00:00:00.000"
            }
        )
        inField.stringValue = "00:00:01.000"
        inField.delegate?.controlTextDidChange?(
            Notification(name: NSControl.textDidChangeNotification, object: inField)
        )
        let review = try XCTUnwrap(buttons(in: content).first { $0.title == "Review Trim" })
        XCTAssertTrue(review.isEnabled)
        review.performClick(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(reviewedRequest?.exactChoice?.audioPolicy, .opusPreserveLayout)
    }

    @MainActor
    func testChapterStudioExposesNestedEditingAndExplicitFlatteningActions() throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/Movie.mkv")
        let source = MediaAsset(
            sourceURL: sourceURL,
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 60_000_000_000),
            tracks: [MediaTrack(id: 0, kind: .video, codec: "av1")]
        )
        let original = MatroskaChapterDocument(
            editions: [
                MatroskaChapterEdition(
                    uid: 1,
                    chapters: [
                        MatroskaChapterAtom(
                            uid: 2,
                            start: .zero,
                            displays: [ChapterDisplay(title: "Opening")]
                        )
                    ]
                )
            ]
        )
        let controller = ChapterStudioWindowController(
            preview: ChapterEditPreview(
                source: source,
                original: original,
                sourceRevision: ChapterSourceRevision(
                    fileSize: 1,
                    modificationDate: Date(timeIntervalSince1970: 0)
                ),
                canonicalSHA256: Data(repeating: 0, count: 32)
            ),
            suggestionProvider: { _, _ in [] },
            thumbnailProvider: { _ in [] }
        )
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(NSSize(width: 820, height: 580))
        content.layoutSubtreeIfNeeded()
        let titles = buttonTitles(in: content)

        XCTAssertEqual(
            window.initialFirstResponder?.accessibilityLabel(),
            "Nested chapter hierarchy"
        )
        XCTAssertTrue(
            window.initialFirstResponder?.accessibilityHelp()?.contains("change nesting") == true
        )

        for expected in [
            "Add Edition", "Add Chapter", "Add Child", "Duplicate", "Remove", "Nest",
            "Unnest", "Every…", "Suggest…", "Thumbnails…", "Flatten for Jellyfin", "Import…",
            "Export…", "Use Changes",
        ] {
            XCTAssertTrue(titles.contains(expected), "Missing Chapter Studio action \(expected)")
        }
        let chapterButtons = buttons(in: content)
        XCTAssertTrue(try XCTUnwrap(chapterButtons.first { $0.title == "Suggest…" }).isEnabled)
        XCTAssertTrue(try XCTUnwrap(chapterButtons.first { $0.title == "Thumbnails…" }).isEnabled)
        for button in chapterButtons where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }

        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_CHAPTER_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            controller.showWindow(nil)
            controller.window?.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            content.layoutSubtreeIfNeeded()
            let bounds = content.bounds
            let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
            content.cacheDisplay(in: bounds, to: representation)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
        }
    }

    @MainActor
    func testChapterThumbnailChooserShowsLocalFramesAndExactTimesAtMinimumSize() throws {
        let jpeg = try makeThumbnailJPEG()
        let controller = try XCTUnwrap(
            ChapterThumbnailWindowController(
                thumbnails: [
                    ChapterThumbnail(
                        time: MediaTime(nanoseconds: 5_000_000_000), imageData: jpeg),
                    ChapterThumbnail(
                        time: MediaTime(nanoseconds: 10_000_000_000), imageData: jpeg),
                    ChapterThumbnail(
                        time: MediaTime(nanoseconds: 15_000_000_000), imageData: jpeg),
                ],
                currentTime: MediaTime(nanoseconds: 10_000_000_000)
            )
        )
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(NSSize(width: 560, height: 300))
        content.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.title, "Chapter Start Preview")
        XCTAssertEqual(window.minSize, NSSize(width: 560, height: 300))
        let controls = buttons(in: content)
        XCTAssertEqual(controls.filter { $0.title == "Use This Time" }.count, 3)
        XCTAssertTrue(controls.contains { $0.title == "Cancel" })
        let firstChoice = try XCTUnwrap(controls.first { $0.title == "Use This Time" })
        XCTAssertTrue(window.initialFirstResponder === firstChoice)
        XCTAssertTrue(firstChoice.accessibilityHelp()?.contains("exact numeric time") == true)
        let labels = descendants(in: content).compactMap { ($0 as? NSTextField)?.stringValue }
        for expected in [
            "Before", "Current", "After", "00:00:05.000", "00:00:10.000",
            "00:00:15.000",
        ] {
            XCTAssertTrue(labels.contains(expected), "Missing thumbnail label \(expected)")
        }
        XCTAssertEqual(descendants(in: content).compactMap { $0 as? NSImageView }.count, 3)
        for button in controls where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }

        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_THUMBNAIL_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            controller.showWindow(nil)
            window.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            content.layoutSubtreeIfNeeded()
            let bounds = content.bounds
            let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
            content.cacheDisplay(in: bounds, to: representation)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
        }
    }

    @MainActor
    func testChapterSuggestionReviewStartsSelectedAndExposesBulkControls() throws {
        let controller = ChapterSuggestionReviewWindowController(
            suggestions: [
                ChapterSuggestion(
                    time: MediaTime(nanoseconds: 10_000_000_000),
                    signals: [.sceneChange, .blackFrame]
                ),
                ChapterSuggestion(
                    time: MediaTime(nanoseconds: 30_000_000_000),
                    signals: [.silence]
                ),
            ]
        )
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(NSSize(width: 560, height: 400))
        content.layoutSubtreeIfNeeded()
        let controls = buttons(in: content)
        XCTAssertTrue(controls.contains { $0.title == "Select All" })
        XCTAssertTrue(controls.contains { $0.title == "Select None" })
        XCTAssertTrue(controls.contains { $0.title == "Cancel" })
        XCTAssertTrue(try XCTUnwrap(controls.first { $0.title == "Add Selected" }).isEnabled)
        let table = try XCTUnwrap(descendants(in: content).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertTrue(window.initialFirstResponder === table)
        XCTAssertTrue(table.accessibilityHelp()?.contains("false positives") == true)
        XCTAssertTrue(
            descendants(in: content).contains {
                $0.accessibilityLabel() == "Selected chapter suggestion count"
            }
        )
        XCTAssertGreaterThan(table.enclosingScrollView?.frame.height ?? 0, 150)
        for button in controls where !button.isHidden {
            let frame = button.convert(button.bounds, to: content)
            XCTAssertGreaterThanOrEqual(frame.minX, content.bounds.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.bounds.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.bounds.maxY + 1)
        }

        if let capturePath = ProcessInfo.processInfo.environment["MKV_MAGIC_SUGGESTION_CAPTURE"],
            capturePath.hasPrefix("/")
        {
            controller.showWindow(nil)
            controller.window?.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            content.layoutSubtreeIfNeeded()
            let bounds = content.bounds
            let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
            content.cacheDisplay(in: bounds, to: representation)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
        }
    }

    private func makeHistoryRecord(id: UUID, createdAt: Date) throws -> MediaJobRecord {
        var record = MediaJobRecord(
            id: id,
            createdAt: createdAt,
            workflowID: UUID(uuidString: "6A2D7635-AB6D-4C7A-AE02-1561631121F0")!,
            workflowName: "Edit segment title",
            inputs: [MediaJobInput(displayName: "Movie.mkv")],
            outputDisplayName: "Movie — Edited.mkv"
        )
        for state in [
            MediaJobState.inspecting, .planned, .ready, .running, .verifying, .committing,
            .succeeded,
        ] {
            try record.transition(
                to: state,
                at: createdAt,
                message: state == .succeeded ? "Verified output committed and reopened." : nil
            )
        }
        return record
    }

    private func losslessJoinOption(
        part: Int,
        duration seconds: Int64,
        sampleRate: Int = 48_000,
        channels: Int = 2,
        channelLayout: String? = nil,
        chapters: [MatroskaChapterEdition] = []
    ) -> LosslessJoinSourceOption {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Part \(part).mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: seconds * 1_000_000_000),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .audio,
                    codec: "aac",
                    codecID: "A_AAC",
                    profile: "LC",
                    uid: UInt64(part),
                    isDefault: true,
                    channels: channels,
                    channelLayout: channelLayout ?? (channels == 2 ? "stereo" : "5.1(side)"),
                    sampleRate: sampleRate
                )
            ],
            globalTagCount: 0,
            trackTagCount: 0
        )
        return LosslessJoinSourceOption(
            chapterPreview: ChapterEditPreview(
                source: source,
                original: MatroskaChapterDocument(editions: chapters),
                sourceRevision: ChapterSourceRevision(
                    fileSize: 1,
                    modificationDate: Date(timeIntervalSince1970: 1)
                ),
                canonicalSHA256: Data(repeating: 0, count: 32)
            )
        )
    }

    private func losslessJoinVideoOption(
        part: Int,
        codec: String,
        width: Int,
        height: Int
    ) -> LosslessJoinSourceOption {
        let isH264 = codec == "h264"
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Part \(part).mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: codec,
                    codecID: isH264 ? "V_MPEG4/ISO/AVC" : "V_MPEGH/ISO/HEVC",
                    profile: isH264 ? "High" : "Main 10",
                    level: isH264 ? 40 : 153,
                    uid: UInt64(part),
                    isDefault: true,
                    dimensions: MediaDimensions(width: width, height: height),
                    displayDimensions: MediaDimensions(width: width, height: height),
                    pixelFormat: isH264 ? "yuv420p" : "yuv420p10le",
                    bitDepth: isH264 ? 8 : 10,
                    frameRate: "24000/1001",
                    colorInfo: MediaColorInfo(
                        range: "tv",
                        primaries: "bt709",
                        transfer: "bt709",
                        matrix: "bt709"
                    )
                )
            ],
            globalTagCount: 0,
            trackTagCount: 0
        )
        return LosslessJoinSourceOption(
            chapterPreview: ChapterEditPreview(
                source: source,
                original: MatroskaChapterDocument(editions: []),
                sourceRevision: ChapterSourceRevision(
                    fileSize: 1,
                    modificationDate: Date(timeIntervalSince1970: 1)
                ),
                canonicalSHA256: Data(repeating: 0, count: 32)
            )
        )
    }

    private func losslessJoinHDR10VideoOption(
        part: Int,
        width: Int,
        height: Int
    ) -> LosslessJoinSourceOption {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/HDR Part \(part).mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            tracks: [
                MediaTrack(
                    id: 0,
                    kind: .video,
                    codec: "hevc",
                    codecID: "V_MPEGH/ISO/HEVC",
                    profile: "Main 10",
                    level: 153,
                    uid: UInt64(part),
                    isDefault: true,
                    dimensions: MediaDimensions(width: width, height: height),
                    displayDimensions: MediaDimensions(width: width, height: height),
                    pixelFormat: "yuv420p10le",
                    bitDepth: 10,
                    frameRate: "24000/1001",
                    colorInfo: MediaColorInfo(
                        range: "tv",
                        primaries: "bt2020",
                        transfer: "smpte2084",
                        matrix: "bt2020nc"
                    ),
                    masteringDisplayMetadata: MediaMasteringDisplayMetadata(
                        redX: 34_000,
                        redY: 16_000,
                        greenX: 13_250,
                        greenY: 34_500,
                        blueX: 7_500,
                        blueY: 3_000,
                        whitePointX: 15_635,
                        whitePointY: 16_450,
                        maxLuminance: 10_000_000,
                        minLuminance: 50
                    ),
                    contentLightLevelMetadata: MediaContentLightLevelMetadata(
                        maxContentLightLevel: 1_000,
                        maxFrameAverageLightLevel: 400
                    ),
                    hdrFormats: ["HDR10 metadata"]
                )
            ],
            globalTagCount: 0,
            trackTagCount: 0
        )
        return LosslessJoinSourceOption(
            chapterPreview: ChapterEditPreview(
                source: source,
                original: MatroskaChapterDocument(editions: []),
                sourceRevision: ChapterSourceRevision(
                    fileSize: 1,
                    modificationDate: Date(timeIntervalSince1970: 1)
                ),
                canonicalSHA256: Data(repeating: 0, count: 32)
            )
        )
    }

    private func ambiguousSubtitleJoinOption(
        part: Int,
        trackIDs: [Int]
    ) -> LosslessJoinSourceOption {
        let source = MediaAsset(
            sourceURL: URL(fileURLWithPath: "/media/Part \(part).mkv"),
            container: "matroska,webm",
            duration: MediaTime(nanoseconds: 10_000_000_000),
            tracks: trackIDs.map { trackID in
                MediaTrack(
                    id: trackID,
                    kind: .subtitle,
                    codec: "subrip",
                    codecID: "S_TEXT/UTF8",
                    uid: UInt64(part * 100 + trackID),
                    language: "en"
                )
            },
            globalTagCount: 0,
            trackTagCount: 0
        )
        return LosslessJoinSourceOption(
            chapterPreview: ChapterEditPreview(
                source: source,
                original: MatroskaChapterDocument(editions: []),
                sourceRevision: ChapterSourceRevision(
                    fileSize: 1,
                    modificationDate: Date(timeIntervalSince1970: 1)
                ),
                canonicalSHA256: Data(repeating: 0, count: 32)
            )
        )
    }

    private func advancedSubtitlePreview(
        sourceURL: URL,
        text: String
    ) throws -> AdvancedSubtitleCleanupFilePreview {
        let data = Data(text.utf8)
        let parsed = try AdvancedSubStationAlphaCodec().parse(
            DecodedSubtitleText(text: text, encoding: .utf8)
        )
        return AdvancedSubtitleCleanupFilePreview(
            sourceURL: sourceURL,
            sourceSHA256: Data(SHA256.hash(data: data)),
            encoding: .utf8,
            diagnostics: parsed.diagnostics,
            cleanup: AdvancedSubStationAlphaCleanupPolicy().preview(parsed.document),
            normalizationNeeded: false
        )
    }

    private func makeEncodingBenchmarkReport() -> EncodingBenchmarkReport {
        EncodingBenchmarkReport(
            environment: EncodingBenchmarkEnvironment(
                ffmpegSHA256: String(repeating: "a", count: 64),
                architecture: "arm64",
                activeProcessorCount: 8
            ),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceWidth: 640,
            sourceHeight: 360,
            sourceFrameRate: 24,
            sourceFrameCount: 72,
            attempts: [
                EncodingBenchmarkAttempt(
                    preset: .av1Quality,
                    encoder: "libsvtav1",
                    outcome: .completed,
                    metrics: EncodingBenchmarkMetrics(
                        elapsedSeconds: 1,
                        framesPerSecond: 72,
                        sourceRealtimeFactor: 3,
                        estimated1080pRealtimeFactor: 0.75,
                        outputBytes: 250_000,
                        outputBitrate: 666_667,
                        averagePSNR: 41.5
                    )
                )
            ],
            recommendedPreset: .av1Quality
        )
    }

    @MainActor
    private func buttonTitles(in view: NSView) -> [String] {
        buttons(in: view).map(\.title)
    }

    @MainActor
    private func buttons(in view: NSView) -> [NSButton] {
        descendants(in: view).compactMap { $0 as? NSButton }
    }

    @MainActor
    private func descendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor
    private func makeThumbnailJPEG() throws -> Data {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 160,
                pixelsHigh: 90,
                bitsPerSample: 8,
                samplesPerPixel: 3,
                hasAlpha: false,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let offset = y * bitmap.bytesPerRow + x * 3
                pixels[offset] = UInt8((x * 255) / bitmap.pixelsWide)
                pixels[offset + 1] = UInt8((y * 255) / bitmap.pixelsHigh)
                pixels[offset + 2] = 132
            }
        }
        return try XCTUnwrap(
            bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]))
    }

    @MainActor
    private func captureTrimWindow(window: NSWindow, content: NSView, at path: String) throws {
        window.appearance = NSAppearance(named: .aqua)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        window.displayIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        content.layoutSubtreeIfNeeded()
        let bounds = content.bounds
        let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
        content.cacheDisplay(in: bounds, to: representation)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    @MainActor
    private func captureWindow(window: NSWindow, content: NSView, at path: String) throws {
        window.appearance = NSAppearance(named: .aqua)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        window.displayIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        content.layoutSubtreeIfNeeded()
        let bounds = content.bounds
        let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: bounds))
        content.cacheDisplay(in: bounds, to: representation)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: min(deadline, Date(timeIntervalSinceNow: 0.01)))
        } while Date() < deadline
        return condition()
    }

    private func makeQueueJob(
        createdAt: Date,
        videoEncodes: Int = 0,
        audioEncodes: Int = 0,
        sourceDisposition: MediaQueueSourceDisposition = .keepOriginal
    ) -> MediaQueueJob {
        let workflow = SavedWorkflow(name: "Prepare for Jellyfin", steps: [])
        let impact = PlanImpact(
            videoEncodeCount: videoEncodes,
            audioEncodeCount: audioEncodes,
            copiesVideo: videoEncodes == 0
        )
        return MediaQueueJob(
            createdAt: createdAt,
            workflow: .saved(workflow),
            inputs: [
                MediaQueueFileReference(
                    displayName: "Movie.mkv",
                    securityScopedBookmark: Data([1, 2, 3])
                )
            ],
            destinationDirectory: MediaQueueFileReference(
                displayName: "Exports",
                securityScopedBookmark: Data([4, 5, 6])
            ),
            outputDisplayName: "Movie — Prepared.mkv",
            sourceDisposition: sourceDisposition,
            reviewedPlan: ExecutionPlan(
                stages: [
                    PlanStage(
                        mechanism: videoEncodes > 0 ? .ffmpegEncode : .mkvMerge,
                        summary: "Create one verified output"
                    )
                ],
                impact: impact
            )
        )
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? first : nil }
}
