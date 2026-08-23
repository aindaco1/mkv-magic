# M4 offline chapter suggestions slice

This records engineering acceptance of deterministic, local chapter-boundary
analysis and review. It extends the Chapter Studio core without claiming the
remaining thumbnail timeline, frame/keyframe snapping, physical Intel testing,
real-library beta acceptance, or a public signed/notarized release.

## User-facing scope

- **Suggest…** offers three plain-language detectors: scene changes, black
  frames, and silence. Controls unavailable for the inspected track layout are
  disabled.
- Analysis uses only the bundled FFmpeg executable and the selected local file.
  It does not use a network service, LLM, temporary transcode, or source write.
- The default keeps results at least 60 seconds apart. The user can change that
  spacing before analysis; edge noise and boundaries near existing chapters are
  excluded automatically.
- A separate native checklist displays exact timestamps and every contributing
  signal. All results begin selected, with Select All, Select None, Cancel, and
  Add Selected controls. Nothing enters the in-memory chapter plan until this
  review is confirmed.
- Added boundaries become editable English top-level chapters in the selected
  edition. Existing nested chapters remain intact. Exact duplicate starts and
  boundaries inside explicitly closed chapter ranges are skipped and reported.

## Analysis and safety contract

1. Options require at least one detector and bounded finite thresholds,
   durations, spacing, tolerances, edge guard, and result count.
2. The analyzer requires a regular non-symlink local file with a known positive
   duration and at least one matching inspected audio or video stream.
3. Selected video detectors share one decoded video pass through an FFmpeg
   `split` graph. Filter work is capped at 10 fps and 640 pixels wide for old-Mac
   efficiency without upscaling smaller sources; selected audio analysis shares
   the same process. Commands are direct argument arrays with a fixed locale,
   no shell, no network input, a duration-aware timeout, and a 16 MiB output
   ceiling.
4. Only bounded `showinfo`, `blackdetect`, and `silencedetect` records are parsed.
   Non-finite or malformed timestamps are ignored; truncated output and nonzero
   FFmpeg exits fail closed.
5. The source revision is captured before analysis and rechecked afterward.
   Results from a file that changed during analysis are refused.
6. Duplicate detections are collapsed. Nearby signals are merged with scene
   time preferred, then black-frame end, then silence end. Results are sorted,
   spaced, edge-guarded, existing-chapter-aware, and hard capped.
7. Analysis is cancellable when Chapter Studio closes. If the user edits
   chapters while analysis runs, consolidation repeats against the current
   in-memory starts before review.
8. Applying reviewed suggestions is reusable core policy. It validates after
   each addition, preserves the selected edition and nesting, and skips unsafe
   overlaps rather than weakening the Matroska chapter validator.

## Regression and real-tool evidence

- The complete local gate passed 217 tests with 11 intentional tool-dependent
  skips in source-only mode, coverage, AddressSanitizer, ThreadSanitizer,
  preflight/security checks, a fresh Universal build, inside-out ad-hoc signing,
  SBOM and checksums, ZIP/appcast generation, and verified DMG packaging. The
  same 217-test suite passed separately against the assembled bundled tool
  runtime with zero skips and zero failures.
- Core tests cover invalid options/duration, stable IDs, duplicate collapse,
  multi-signal merging, source-edge/existing-marker exclusion, spacing, caps,
  empty-document creation, selected-edition application, exact duplicates, and
  explicitly closed-range exclusion.
- Execution tests cover the one-process filter graph, stream-aware detector
  selection, bounded output, malformed records, unavailable streams, truncation,
  and FFmpeg failure.
- A bundled-tool integration generates a two-second FFV1/PCM Matroska fixture,
  detects its one-second boundary independently as both a scene change and the
  end of black frames in the same FFmpeg process, and consolidates it exactly.
- Native AppKit policy tests verify the Chapter Studio action and the review
  sheet's two-row checklist, enabled Add Selected default, and bulk controls.
  Bounds regressions and inspected native renders at the declared 820 by 580
  Chapter Studio and 560 by 400 review sizes confirm that all actions remain
  inside each compact window. This is rendered layout evidence, not a claimed
  keyboard-only or VoiceOver walkthrough.

## Still pending in M4

- Lazy thumbnail timeline and frame/keyframe snapping.
- Synchronized timeline dragging and explicit chronological reorder controls.
- Saved-workflow and batch chapter actions.
- Full keyboard-only and VoiceOver acceptance.
- Physical Intel smoke testing, private real-library beta acceptance, and the
  eventual Developer ID-signed, Apple-notarized public release.
