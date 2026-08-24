# M8 standard Application menu

This slice completes MKV Magic's native Application-menu integration. It keeps
the menu lightweight and uses AppKit's responder and service systems instead
of custom command handling.

## Menu contract

The MKV Magic menu now contains:

- **About MKV Magic**;
- the user-initiated **Check for Updates…** action;
- a native **Services** submenu registered as `NSApp.servicesMenu`;
- **Command-H — Hide MKV Magic**;
- **Command-Option-H — Hide Others**;
- **Show All**; and
- **Command-Q — Quit MKV Magic**.

The Services registration lets installed macOS services participate through
the system-managed menu. Hide Others and Show All use AppKit's standard
application selectors. No service is invoked automatically, and no network,
media, workflow, or update behavior changes.

## Regression contract

The live app-delegate launch regression verifies that the visible Services item
owns the exact menu registered with `NSApp`, and that Hide Others and Show All
use the expected selectors. It also checks the Command-Option-H modifier mask,
alongside the existing File and Window menu assertions.

The focused `AppPolicyTests` suite passes 85 tests with zero failures on the
development Mac. The full source validation gate passes 510 tests with 33
intentional source-only fixture skips, zero failures, and a Universal
arm64/x86_64 release build. The isolated package gate passes nested app/Sparkle
signature verification, the noninteractive baseline probe, Universal ZIP and
DMG verification, checksums, SBOM, notices, appcast, build metadata, and the
supported-systems manifest.

Manual Services population, localization, VoiceOver menu traversal, physical
M1/Intel hardware, and private-media workflows remain M8 acceptance work.
