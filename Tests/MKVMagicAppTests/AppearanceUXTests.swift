import AppKit
import MKVMagicCore
import MKVMagicPlanning
import XCTest

@testable import MKVMagic

final class AppearanceUXTests: XCTestCase {
    @MainActor
    func testAppearanceDefaultsToSystemAndPersistsExplicitOverrides() throws {
        let suite = "MKVMagic.Appearance.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppearancePreferences(defaults: defaults)
        XCTAssertEqual(preferences.mode, .system)
        defaults.set("unknown", forKey: AppearancePreferences.defaultsKey)
        XCTAssertEqual(preferences.mode, .system)
        for mode in AppAppearanceMode.allCases {
            preferences.mode = mode
            XCTAssertEqual(AppearancePreferences(defaults: defaults).mode, mode)
        }
    }

    @MainActor
    func testAppearanceChangesExistingAndNewWindowsAndSystemClearsTheOverride() async throws {
        let suite = "MKVMagic.Appearance.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let preferences = AppearancePreferences(defaults: defaults)
        let app = NSApplication.shared
        let previous = app.appearance
        let existing = NSWindow(contentViewController: NSViewController())
        defer {
            app.appearance = previous
            existing.close()
            defaults.removePersistentDomain(forName: suite)
        }
        for mode in [AppAppearanceMode.dark, .light] {
            preferences.mode = mode
            preferences.apply(to: app)
            XCTAssertEqual(app.appearance?.name, mode.appearanceName)
            let next = NSWindow(contentViewController: NSViewController())
            for window in [existing, next] {
                XCTAssertNil(window.appearance, "Windows must inherit the shared override")
                // AppKit can propagate a changed appearance on a later main-loop
                // turn. Still require the exact result, with a bounded deadline.
                for _ in 0..<100 {
                    if window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                        == mode.appearanceName
                    {
                        break
                    }
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertEqual(
                    window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                    mode.appearanceName)
            }
            next.close()
        }
        preferences.mode = .system
        preferences.apply(to: app)
        XCTAssertNil(app.appearance, "System must keep following future macOS appearance changes")
    }

    @MainActor
    func testSettingsAppearancePopupAppliesImmediatelyAndFitsBothModes() throws {
        let suite = "MKVMagic.Appearance.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let preferences = AppearancePreferences(defaults: defaults)
        let controller = SettingsWindowController(
            preferences: OutputDestinationPreferences(defaults: defaults),
            appearancePreferences: preferences)
        let window = try XCTUnwrap(controller.window)
        let root = try XCTUnwrap(window.contentView)
        let app = NSApplication.shared
        let previous = app.appearance
        defer {
            app.appearance = previous
            window.close()
            defaults.removePersistentDomain(forName: suite)
        }
        let popup = try XCTUnwrap(
            descendants(root).compactMap { $0 as? NSPopUpButton }
                .first { $0.accessibilityLabel() == "Appearance" })
        XCTAssertEqual(popup.itemTitles, ["System", "Light", "Dark"])
        XCTAssertEqual(popup.indexOfSelectedItem, 0)
        XCTAssertEqual(window.initialFirstResponder, popup)
        for (index, mode) in AppAppearanceMode.allCases.enumerated() {
            popup.selectItem(at: index)
            popup.sendAction(popup.action, to: popup.target)
            XCTAssertEqual(preferences.mode, mode)
            XCTAssertEqual(app.appearance?.name, mode.appearanceName)
            window.setContentSize(window.minSize)
            root.layoutSubtreeIfNeeded()
            for control in descendants(root).filter({
                $0 is NSControl && !$0.isHiddenOrHasHiddenAncestor
            }) {
                let frame = control.convert(control.bounds, to: root)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertGreaterThanOrEqual(frame.minY, 0)
                XCTAssertLessThanOrEqual(frame.maxX, root.bounds.width + 1)
                XCTAssertLessThanOrEqual(frame.maxY, root.bounds.height + 1)
            }
        }
    }

    @MainActor
    func testSharedTextPaletteMeetsContrastInLightDarkAndIncreasedContrast() throws {
        for name: NSAppearance.Name in [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                for foreground in [
                    AppPalette.secondaryText, AppPalette.warningText, AppPalette.errorText,
                ] {
                    for background in [
                        NSColor.windowBackgroundColor, .textBackgroundColor,
                        .controlBackgroundColor,
                    ] {
                        let first = luminance(foreground)
                        let second = luminance(background)
                        let contrast = (max(first, second) + 0.05) / (min(first, second) + 0.05)
                        XCTAssertGreaterThanOrEqual(
                            contrast, 4.5, "\(name): \(foreground), \(background)")
                    }
                }
            }
        }
    }

    func testWorkflowReviewUsesNeutralStatusesAndDoesNotImplyWorkAlreadyRan() {
        for disposition: SavedWorkflowStepDisposition in [.applied, .skipped, .disabled] {
            let outcome = SavedWorkflowStepOutcome(
                stepID: UUID(), action: .removeSegmentTitle, disposition: disposition,
                detail: "Fixture")
            let color = WorkflowPlanReviewPresentation.color(for: outcome)
            XCTAssertNotEqual(color, NSColor.systemOrange)
            XCTAssertNotEqual(color, NSColor.systemGreen)
            if disposition == .applied {
                XCTAssertEqual(
                    WorkflowPlanReviewPresentation.statusLabel(for: outcome), "Will apply")
                XCTAssertEqual(
                    WorkflowPlanReviewPresentation.symbolName(for: outcome), "arrow.right.circle")
            } else if disposition == .skipped {
                XCTAssertEqual(
                    WorkflowPlanReviewPresentation.statusLabel(for: outcome), "Already satisfied")
            }
        }
    }

    private func luminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            XCTFail("Could not resolve \(color) into sRGB")
            return 0
        }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
