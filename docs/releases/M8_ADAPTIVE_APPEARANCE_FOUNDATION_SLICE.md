# M8 adaptive appearance foundation

This slice fixes the one production path that froze a semantic AppKit color
into a layer color. It is deterministic runtime and source evidence, not a
claimed manual visual-accessibility acceptance pass.

## Defect and fix

Common-format join's video and audio lane cards converted
`NSColor.separatorColor` directly to `CGColor` during construction. AppKit
semantic colors are appearance-dependent, but a layer retains the resolved
Core Graphics color. A card created in one appearance could therefore keep
that border after the app or system changed between Light and Dark.

Both card types now reuse `AppearanceAwareBorderStackView`. It keeps the same
native stack layout, corner radius, one-point border, and system separator
semantics, but resolves the border against the view's current effective
appearance whenever AppKit reports an appearance change. No custom theme,
background, text color, animation, or transparency effect is introduced.

## Regression contract

- A live AppKit test applies Aqua and Dark Aqua to the shared view and verifies
  that its layer matches the separator color resolved for each appearance.
- The test also proves the two observed resolved border values differ, so it
  would catch a border frozen in the first appearance.
- The automatically discovered accessibility source gate rejects direct
  conversion from an AppKit semantic color to a one-shot `CGColor` outside the
  shared appearance-aware view.

The focused `AppPolicyTests` suite passes 85 tests with zero failures on the
development Mac. The full source validation gate passes 510 tests with 33
intentional source-only fixture skips, zero failures, and a Universal
arm64/x86_64 release build. The isolated package gate passes nested app/Sparkle
signature verification, the noninteractive baseline probe, Universal ZIP and
DMG verification, checksums, SBOM, notices, appcast, build metadata, and the
supported-systems manifest.

Increase Contrast, Reduce Transparency, appearance changes while a real sheet
is onscreen, visual contrast judgment, physical M1/Intel hardware, and
private-media workflows remain M8 acceptance work.
