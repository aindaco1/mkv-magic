# M8 accessible failure recovery

This slice connects MKV Magic's bounded error-language contract to native
AppKit accessibility behavior. It is automated runtime and source evidence,
not a claimed observed VoiceOver walkthrough.

## Runtime contract

`AccessibleStatusPresentation` is the one path for a dynamic actionable
failure. It:

- writes the complete plain-language failure, safe state, recovery, and bounded
  detail to the visible status field;
- posts AppKit's native accessibility value-change notification for that same
  field;
- optionally returns keyboard focus to the relevant field, table, or retry
  button, but only when the recovery view is visible and an `NSControl` is
  enabled; and
- leaves empty routine status clears silent.

The verified-output progress sheet now uses the same presenter instead of its
own notification path. Main-window model failures remember their last announced
value so ordinary table or inspector refreshes do not repeat identical speech.
Routine progress and success text remains visible without being promoted into
urgent failure announcements.

The migration covers the main window, Queue, History export, workflow library,
Chapter Studio, trim review, common-format choices, encoding test, track edit
and removal, join track mapping, external subtitle metadata, and verified-output
progress. Recovery focus is assigned only where the next useful control is
unambiguous; asynchronous informational failures that should not steal the
user's current position announce their status without moving focus.

## Workflow regression found during the pass

The live workflow-name delegate reloaded its workflow table after each edit.
AppKit cleared the selected row during that reload, so a later Save could behave
as though no workflow were selected. The editor now restores the same row after
the reload. A native AppKit regression changes a workflow name to whitespace,
sends the real text-change delegate event, invokes Save, and verifies that:

- the edited workflow remains selected;
- persistence is not called;
- the actionable validation text remains visible; and
- keyboard focus returns to the invalid name field.

The existing asynchronous Queue failure regression now also verifies that the
last confirmed queue remains visible and focus returns to its job table.

## Guardrails and evidence

- A focused presenter test injects the notification sink and proves the status
  field, native `.valueChanged` notification, and recovery focus as one action.
- The AppKit source gate rejects direct assignments from
  `UserFacingErrorPresentation` to text fields.
- The same gate rejects direct `NSAccessibility.post` calls outside the shared
  presenter, keeping notification behavior DRY and reviewable.
- The focused `AppPolicyTests` suite passes 83 tests with zero failures on the
  development Mac.
- The full source validation gate passes 508 tests with 33 intentional
  source-only fixture skips, zero failures, and a Universal arm64/x86_64 release
  build.
- The isolated package gate passes nested app/Sparkle signature verification,
  the noninteractive baseline probe, Universal ZIP and DMG verification,
  checksums, SBOM, notices, appcast, build metadata, and the supported-systems
  manifest.

Observed VoiceOver announcement order, focus behavior after native Open/Save
panels, Full Keyboard Access settings, localization, visual accessibility
settings, representative private-media failures, and physical M1/Intel hardware
remain M8 acceptance work.
