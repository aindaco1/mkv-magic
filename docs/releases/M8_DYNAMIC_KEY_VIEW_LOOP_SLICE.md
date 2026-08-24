# M8 dynamic key-view loops

This slice gives every implemented MKV Magic window one native, dynamic
keyboard-navigation policy. It is automated AppKit evidence, not a claimed
manual Full Keyboard Access walkthrough.

## Runtime contract

The main window and all 18 auxiliary window-controller surfaces now call the
same `NSWindow` helper. The helper:

- enables AppKit's automatic key-view-loop recalculation;
- retains each window's intentional initial responder; and
- leaves the window's current native control ordering to AppKit instead of
  freezing a hand-linked responder chain.

This is especially important for Queue actions, encoding-test Cancel/Close,
workflow prerequisites, trim choices, join compatibility and mapping controls,
and track, subtitle, and chapter editors whose available actions change with
selection or execution state. The policy avoids a duplicated, hand-linked
`nextKeyView` chain that would become stale as those controls change.

## Regression contract

A live AppKit test starts with automatic recalculation disabled, applies the
shared policy, and verifies both that automatic recalculation is enabled and
that the requested initial responder is retained.

The automatically discovered accessibility source gate now requires the shared
policy in every `*WindowController.swift` file and in the main-window setup.
Adding a future window without the policy fails the supported validation gate.

## Evidence and limits

The focused `AppPolicyTests` suite passes 84 tests with zero failures on the
development Mac. The full source validation gate passes 509 tests with 33
intentional source-only fixture skips, zero failures, and a Universal
arm64/x86_64 release build. The isolated package gate passes nested app/Sparkle
signature verification, the noninteractive baseline probe, Universal ZIP and
DMG verification, checksums, SBOM, notices, appcast, build metadata, and the
supported-systems manifest.

These source and runtime checks do not prove the perceptual order of every
control, Tab/Shift-Tab traversal with Full Keyboard Access on and off,
VoiceOver focus order, native Open/Save panels, physical M1/Intel hardware, or
private-media workflows. Those remain M8 acceptance work.
