# M8 every-window accessibility foundation

This slice extends MKV Magic's automated AppKit accessibility contract from the
main, Queue, History, workflow, plan-review, and verified-output surfaces to all
18 implemented window-controller files. It is source and UI regression
evidence, not a claimed manual VoiceOver or Full Keyboard Access walkthrough.

## Window contract

Every implemented window now declares an intentional first responder rather
than relying on incidental view order. The starting control is the useful entry
point for that task: a media or job table, chapter outline, track or format
selector, trim-in field, first thumbnail choice, encoding-test action, or safe
review action.

The continuation adds explicit names or help for controls whose visible layout
does not fully communicate their purpose to assistive technology, including:

- track metadata fields, removable-track choices, and their review status;
- subtitle cleanup suggestions, embedded/external subtitle fields, match
  warnings, and validation state;
- join source order, otherwise untitled include checkboxes, nested chapter
  edition selectors, compatibility output, and per-Part track mapping popups;
- Chapter Studio, offline suggestion review, thumbnail time choices, common-
  format targets and approval, the encoding benchmark, and trim review state.

Cancel buttons on modal workflow surfaces use Escape where cancellation is
safe. Return remains bound to the explicit review, acceptance, or continuation
action. Help continues to state source safety and the next reviewed step rather
than implying that a button mutates original media directly.

## Reduced motion and non-color meaning

The native AppKit interface contains no custom `NSAnimationContext`, animator,
Core Animation basic/keyframe, or `NSViewAnimation` path. The indeterminate
verified-output progress indicator remains a native control. A source gate now
rejects newly introduced custom motion until it has an explicit Reduce Motion
policy and regression test.

Colored validation, warning, readiness, and outcome states retain text or
symbol meaning; color is not the only conveyed difference. This is source and
automated-tree evidence only. Increase Contrast, Differentiate Without Color,
Reduce Transparency, Reduce Motion, light/dark appearance, and larger display
scaling still require observed packaged-app walkthroughs.

## Regression evidence

- Existing AppKit tests now assert initial responders and accessibility names,
  help, Return/Escape bindings, status fields, untitled include choices, and
  dynamic per-Part mapping controls across every implemented workflow family.
- The focused 81-test `AppPolicyTests` suite passes with zero failures on the
  development Mac.
- `scripts/ci/check-appkit-accessibility.sh` automatically discovers every
  `*WindowController.swift` file and requires both intentional focus and
  explicit accessibility semantics. It also fails closed on custom motion APIs.
- Strict Swift formatting and macOS 13 compilation pass; the implementation
  avoids the newer macOS-14-only `loadViewIfNeeded()` API.
- The complete local gate passes in normal, coverage, Address Sanitizer, and
  Thread Sanitizer modes: 506 tests per mode, 33 intentional source-only
  fixture skips, and zero failures.
- The isolated package gate also passes: the ad hoc signed Universal app and
  nested Sparkle components satisfy their designated requirements, the
  noninteractive launch baseline completes, and the ZIP, DMG, checksums, SBOM,
  notices, appcast, build metadata, and supported-systems manifest verify.

Observed VoiceOver announcements, focus return after real cancellation and
failure, native Open/Save panels, Full Keyboard Access modes, visual
accessibility settings, physical M1/Intel hardware, and private media remain M8
acceptance work.
