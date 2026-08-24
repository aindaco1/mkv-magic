# M7 external-subtitle workflow slice

This slice adds the first interactive runtime input to portable workflows. A
recipe can request one external SRT, ASS, or SSA without storing a media path or
turning the workflow into an opaque command script.

## User contract

- Add Step offers **Add one external text subtitle** as an optional card.
- Save & Preview asks for one SRT, ASS, or SSA only when the enabled recipe needs
  it. Cancelling creates no runnable plan.
- The existing local filename/timing matcher and editable language, name,
  default, forced, and hearing-impaired confirmation are reused.
- The normal plan review names the reviewed subtitle addition and shows the
  exact fused passes before **Use This Plan** can enable execution.
- The subtitle is added as the last playable track. Existing retained tracks
  keep their order and identity.
- Deterministic cleanup suggestions remain visible in the confirmation warning,
  but this mux card does not silently apply them. It uses the parsed,
  structurally normalized original subtitle content.
- MKV Magic writes one new verified MKV and leaves the source MKV and selected
  subtitle unchanged.

## Portable schema and runtime boundary

1. `SavedWorkflow` schema v2 adds only the `addExternalSubtitle` action. The
   saved JSON contains no file path, bookmark, metadata choice, track identity,
   subtitle text, or other media-specific value.
2. v1 recipes migrate to v2 on library load, portable import, and direct
   compilation while retaining workflow ID, step IDs, order, enablement, name,
   and actions. A file claiming v1 cannot use the v2-only runtime-input action;
   unknown or internally inconsistent schema versions fail closed.
3. `SavedWorkflowResolvedInputs` exists only for the current preview. The
   compiler rejects a missing input, the source MKV itself, or an extension that
   disagrees with the reviewed format.
4. Execution requires the preview object to match the compiled path and format.
   Its source-revision validation then detects a sidecar changed after review.
5. No network service, LLM, free-form shell command, or persisted external path
   is introduced.

## One-output execution contract

- Granular track cleanup and the external subtitle are compiled into one
  `mkvmerge` invocation. Segment-title removal, when applicable, is one
  `mkvpropedit` pass on that same temporary MKV.
- The shared retained-track selector prevents the cleanup and mux paths from
  drifting and emits the exact retained track order followed by the new track.
- The verified-output transaction checks the expected retained tracks, the one
  added text-subtitle codec and reviewed metadata, duration tolerance, chapters,
  tags, attachments, segment title, structure counts, and regenerated segment
  identity before commit and after reopening the destination.
- ASS/SSA also retains the existing `mkvextract` payload audit for header,
  styles, layout fields, event timing, and text.
- A single sanitized History job records the MKV and external subtitle as inputs
  without including their paths or subtitle content in privacy-safe exports.

## Regression evidence

- Compiler tests cover missing/mismatched runtime input, portable intent, recipe
  ordering, and the fused remux/metadata plan.
- Store tests cover v2 path-free round trips and lossless v1 migration.
- Command and verifier tests cover the shared track selectors, one remux, one
  metadata pass, retained/new track ordering, subtitle metadata, title removal,
  and rejection of an incorrectly retained or removed track.
- AppKit tests drive the new Add Step card and render the external-subtitle plan
  review at minimum size.
- A pinned real-tool app integration removes a French subtitle, adds a reviewed
  English SRT, removes the segment title, verifies both input hashes are
  unchanged, and records one complete eight-state History lifecycle.

### 2026-08-23 gate results

- The normal source gate passed all 434 tests with 31 intentional no-runtime
  skips, strict source validation, and the Universal application build.
- The exact pinned Universal runtime passed all 434 tests with zero skips.
- AddressSanitizer and ThreadSanitizer each passed all 434 tests. Coverage also
  passed.
- The package gate passed the Universal app, both architecture-specific media
  tool trees, nested signatures, Sparkle components, update feed, SBOM,
  corresponding source, third-party notices, checksums, ZIP, and mounted and
  verified DMG.
- The external-subtitle workflow review was rendered and visually inspected at
  its supported minimum size without clipped content or actions.
- This is local engineering and ad-hoc signing evidence, not public Developer ID
  notarization, publication, downloaded-artifact verification, or private-library
  playback acceptance.

## Still pending

- A dedicated subtitle text-cleanup workflow card with per-run change review.
- Broader conditions, filename cleanup, and durable queue controls.
- VoiceOver, keyboard-only, physical Intel, and private-library beta acceptance.
- Public Developer ID signing/notarization, publication, and downloaded-artifact
  verification.
