# M8 Window-menu keyboard access

This slice makes MKV Magic's recurring workspaces reachable through native,
discoverable menu commands. It is automated AppKit evidence, not a claimed
complete Full Keyboard Access walkthrough.

## Commands

The app now registers a standard Window menu containing:

- **Command-0 — Main Window**: restores and activates MKV Magic's main window;
- **Command-1 — Workflows**: opens the portable workflow builder;
- **Command-2 — Queue**: opens or raises the durable production queue;
- **Command-3 — History**: opens the verified local job history;
- **Command-4 — Encoding Test**: opens the explicit-consent synthetic encoder
  benchmark without starting it; and
- native **Minimize**, **Zoom**, and **Bring All to Front** actions.

The numbered items all target the one retained main view controller. They reuse
the same actions as the visible buttons, so loading, local-only behavior,
window reuse, error handling, and explicit encoding-test consent do not fork
into a second implementation.

## Regression evidence

The live app-delegate regression now verifies:

- the menu is registered as `NSApp.windowsMenu`;
- all five workspace items have the expected Command-number shortcut, selector,
  and live main-controller target;
- the standard File → Open Command-O behavior remains unchanged; and
- after the main window is ordered out, invoking the Main Window menu action
  makes it visible again.

The focused regression passes on the development Mac. The full source gate
passes 508 tests with 33 intentional source-only fixture skips, zero failures,
and a Universal arm64/x86_64 release build. The isolated package gate passes
nested app/Sparkle signature verification, the noninteractive baseline probe,
Universal ZIP and DMG verification, checksums, SBOM, notices, appcast, build
metadata, and the supported-systems manifest.

Explicit Tab/Shift-Tab traversal of every control with Full Keyboard Access on
and off, observed menu behavior under VoiceOver, localization, physical
M1/Intel hardware, and private-media use remain M8 acceptance work.
