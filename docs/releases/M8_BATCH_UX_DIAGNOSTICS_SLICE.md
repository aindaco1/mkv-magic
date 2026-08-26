# M8 batch UX and diagnostics slice

This continuation addresses the supplied minimum-size screenshots and the
privacy-safe v0.1.5 support report. It covers native layout, multi-file review,
bounded failure diagnostics, and one remux-verification defect. It does not
claim physical Intel/Apple Silicon or private-library acceptance.

## Delivered contract

- AppKit workflow surfaces share one small set of window insets, section gaps,
  control gaps, and stack-content constraints. Progress status, indicators, and
  Cancel actions stay inset; dense Inspector actions use equal-width rows with a
  wider bounded panel.
- The media table supports native Command-click and Shift-click selection.
  Delete and the row remove control change only the inspected list and never
  delete a source file.
- A selected SRT/ASS/SSA batch is previewed file by file. One native review
  lists the proposed output and a ready, no-change, or blocked state before any
  work starts. Ready items run as independent verified outputs, stay beside
  their source by default, may share another chosen folder, never overwrite an
  existing destination, and do not roll back successful siblings when another
  file fails.
- A portable saved workflow compiles independently against every selected
  asset. Applicable items become separate queue jobs; already-satisfied and
  blocked items are disclosed first. External-subtitle workflows remain
  single-file because the external pairing requires individual review.
- Batch queue admission retains each exact reviewed source revision and honors
  the explicit per-batch keep/Trash-after-verified-success choice. Eligible
  automatic work is reconsidered after the complete batch is admitted.
- History gives the selected lifecycle a visible semantic background and text
  color in Light and Dark appearances. Support-report schema v2 adds only a
  fixed failure category; it still excludes filenames, paths, titles, subtitle
  text, custom workflow names, raw tool output, and exact timestamps.

## Failure investigation

The attached v0.1.5 report cannot identify the exact assertion because its
schema intentionally exported only the terminal stage. It does show that both
failed MP4-to-MKV jobs reached verification and both inputs had ten chapters,
while the chapterless MP4 remux succeeded. The remux verifier required chapter
starts to be bit-identical even though duration and chapter ends already allowed
100 ms for container time-base representation.

Chapter starts now use that same bounded 100 ms comparison. A value at the
boundary passes and one nanosecond beyond it fails. Track count/order, technical
facts, metadata, packet payloads, title, attachments, and segment identity remain
strictly verified.

## Regression and visual evidence

- The focused AppKit suite covers minimum-size progress insets, visible History
  details, batch review columns, multi-selection, keyboard removal, source-byte
  preservation, initial disabled controls, and the non-duplicated Activity
  navigation label.
- Privacy-safe report tests prove the fixed failure category is exported without
  a failure message or media name and that the previous report shape remains
  decodable through optional fields.
- Remux tests prove bounded chapter-start rounding, overflow-safe comparison,
  and strict rejection beyond the tolerance. A real chaptered MP4 remux passes
  against the bundled MKVToolNix 101 runtime.
- Generated captures for the main window, progress, History, batch review,
  Queue, workflows, join, trim, chapter, attachment, encoding, tag, and Help
  surfaces were inspected after the shared layout change.
- The full suite passes 718 tests with 51 intentional source-only real-tool
  skips and zero failures. The repository validation gate also passes its
  accessibility, coverage, security, release-control, and Universal arm64 plus
  x86_64 Release-build checks.

## Remaining acceptance

- Repeat the original failing chaptered MP4 files on the candidate build and
  confirm committed output playback in Jellyfin/Plex.
- Exercise a mixed SRT/ASS/SSA batch with ready, no-change, malformed, and
  destination-collision cases on real files.
- Complete clean-account Apple Silicon and Intel installation checks and the
  prior-version updater replacement gate against the exact candidate DMG digest
  before public publication.
