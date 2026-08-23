# M4 chapter thumbnail preview slice

This records engineering acceptance of lazy local frame previews for numeric
chapter starts. It extends Chapter Studio without claiming synchronized timeline
dragging, decoded-frame or keyframe snapping, physical Intel testing,
real-library beta acceptance, or a public signed/notarized release.

## User-facing scope

- **Thumbnails…** is available only for a selected chapter in an inspected video
  with a known positive duration.
- The chooser shows the exact current start and, where the duration permits,
  bounded previews five seconds before and after it. Each card pairs a local
  frame with its explicit `HH:MM:SS.mmm` value.
- The user must choose **Use This Time** before the in-memory chapter start is
  changed. Cancel does nothing, and normal nested-chapter validation can still
  refuse a time that conflicts with sibling or parent ranges.
- Extraction is lazy. Inspecting a file, opening Chapter Studio, and editing
  metadata do not start thumbnail work.

## Extraction and safety contract

1. The generator accepts one to five unique, sorted times inside the known
   duration and requires an inspected video stream.
2. Each thumbnail is requested directly from the bundled FFmpeg executable with
   a fixed argument array, no shell or network input, one selected video frame,
   no audio/subtitle/data mapping, a 120-second timeout, and bounded process
   output.
3. Images are downscaled without upscaling to at most 480 pixels wide and
   encoded as JPEG because the bundled Universal FFmpeg build does not include a
   PNG encoder. Every file must be a regular non-symlink JPEG between 4 bytes and
   4 MiB with valid start and end markers.
4. Files live only in a private mode-0700 temporary directory, are read after
   FFmpeg exits, and are removed before the operation returns.
5. The source revision must still match the exact revision that opened Chapter
   Studio and is checked again before, between, and after extractions. A file
   changed before or during preview fails closed; the source itself is never
   opened for output or mutated.
6. Extraction and the native chooser are cancellable when Chapter Studio
   closes. Late results are discarded if the selected chapter or its start
   changed while FFmpeg was running.
7. These are previews at requested numeric timestamps. The UI does not claim
   decoded-frame accuracy or keyframe snapping; those remain explicit M4 work.

## Regression and real-tool evidence

- The complete local gate passes 223 tests with 12 intentional tool-dependent
  skips in source-only mode, coverage, AddressSanitizer, ThreadSanitizer,
  local-only/security checks, a fresh Universal build, inside-out ad-hoc
  signing, SBOM and checksums, ZIP/appcast generation, and verified DMG
  packaging. The same 223-test suite passes separately against the assembled
  bundled runtime with zero skips.
- Execution tests cover exact timestamps and direct argument arrays, sorted
  output, duplicate/out-of-range requests, missing video, stale chapter-preview
  revisions, cancellation mapping, malformed JPEGs, bounded FFmpeg errors, and
  output-size policy.
- A bundled-tool integration creates a two-second FFV1 Matroska video, extracts
  JPEG previews at zero and one second with the shipped FFmpeg, checks the byte
  bounds and JPEG markers, and confirms the source remains byte-identical.
- Native AppKit tests exercise the new Chapter Studio action and a three-card
  chooser at its declared 560 by 300 minimum size. The inspected render keeps
  the explanation, Before/Current/After labels, exact timestamps, all actions,
  and all frames inside the compact window. This is rendered layout evidence,
  not a claimed keyboard-only or VoiceOver walkthrough.

## Still pending in M4

- Synchronized timeline dragging and explicit chronological reorder controls.
- Decoded-frame and keyframe snapping.
- Saved-workflow and batch chapter actions.
- Full keyboard-only and VoiceOver acceptance.
- Physical Intel smoke testing, private real-library beta acceptance, and the
  eventual Developer ID-signed, Apple-notarized public release.
