# M8 offline Help window

This slice makes MKV Magic's essential operating guidance available inside the
app. It uses a retained native AppKit window and bundled text, with no browser,
account, network, telemetry, or LLM dependency.

## Help contract

The registered native Help menu contains **Command-? — MKV Magic Help**. It
opens or raises one lightweight window covering:

- opening files and folders, selecting a task, reviewing impact, and choosing
  an output;
- verified-output safety and the explicit, opt-in Trash-after-success policy;
- metadata editing, remuxing, stream copy, one-pass encoding, AV1 preference,
  and compatibility alternatives;
- portable saved workflows, Queue, and History;
- the main keyboard shortcuts; and
- the local-only privacy contract and user-initiated update boundary.

The help text is read-only but selectable and scrollable. It is the window's
initial keyboard target, exposes explicit accessibility name and help, and the
Close button supports Escape. The window is retained and reused instead of
creating duplicates.

## Regression contract

The live app-delegate launch regression verifies that:

- `NSApp.helpMenu` is the visible Help menu;
- the Help item has Command-?, the expected selector, and the live delegate
  target;
- invoking that exact item opens a visible window at the declared minimum size;
- the help text is the intentional initial responder; and
- the rendered content includes the no-encode metadata path, explicit Trash
  boundary, and local-only privacy promise.

The auto-discovered accessibility source gate also includes this nineteenth
auxiliary window and requires the shared keyboard-navigation and assistive
semantics contracts.

An optional test capture rendered the window at its 520-by-420-point minimum in
deterministic Aqua appearance. The observed artifact keeps the heading,
introduction, scrollable topic region, and Close action readable and within the
window. This is bounded layout evidence, not a Dark Mode, display-scaling, or
visual-accessibility-settings claim.

The focused `AppPolicyTests` suite passes 85 tests with zero failures on the
development Mac. The full source validation gate passes 510 tests with 33
intentional source-only fixture skips, zero failures, and a Universal
arm64/x86_64 release build. The isolated package gate passes nested app/Sparkle
signature verification, the noninteractive baseline probe, Universal ZIP and
DMG verification, checksums, SBOM, notices, appcast, build metadata, and the
supported-systems manifest.

Manual keyboard/VoiceOver traversal, localization, Dark Mode and accessibility
display settings, physical M1/Intel hardware, and private-media workflows remain
M8 acceptance work.
