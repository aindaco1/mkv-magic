# M5 final common-format assembly command slice

This records engineering acceptance of the pure final `mkvmerge` compiler for
common-format hard joins. The transactional executor was completed in the later
`M5_FINAL_JOIN_EXECUTOR_SLICE.md`; this command slice does not claim the native
choice UI, subtitle conversion, tag preservation, HDR conversion, public
release, or physical Intel acceptance.

## One final mux

- Verified normalized video/audio lanes enter as input file 0. Compatible
  packet-copy video, audio, and complete subtitle lanes are selected from the
  originals and appended directly; there is no second copy-stream intermediate.
- One explicit `--append-to` chain joins every retained copy lane across adjacent
  parts. One deterministic `--track-order` interleaves normalized and copy lanes
  in the reviewed mapping order.
- Exact nested chapters enter once from canonical Matroska XML. The source title,
  reviewed per-lane language/name/disposition flags, and explicitly retained
  attachments are rendered without invoking an encoder.
- Every source is passed as a direct process argument. The command is bounded,
  contains one output, never requests overwrite, and enables abort-on-warning,
  flush-on-close, canonical language handling, and disabled generated statistics
  tags.

## Timeline alignment defect closed

The real mixed-lane fixture exposed AAC encoder padding: a source container can
end slightly after its video stream. Concatenating only the decoded video made
the normalized video bundle shorter than the directly copied audio timeline.
The fused FFmpeg graph now clones the final video frame and trims every encoded
video segment to the exact reviewed source-container duration. Encoded audio is
likewise padded and trimmed to that duration. This keeps encoded and copy lanes
aligned while retaining the one-generation invariant.

`tpad`, `trim`, and `apad` are now mandatory active capability facts. A bundled
runtime that lacks any of them cannot offer this normalization path.

## Fail-closed preservation boundary

- The reviewed report, chapter XML, and normalized bundle must still match their
  exact in-memory facts at command compilation.
- Existing output, symlinked inputs, unsafe absolute paths, embedded NULs,
  unbounded user text, malformed track IDs, duplicate lanes, and oversized
  commands are rejected.
- Source global/track tags and unsupported container metadata currently block
  final assembly rather than being silently discarded.
- Text subtitle conversion and explicitly approved missing-subtitle timeline
  sections remain blocked until their intermediate payloads can be verified and
  placed in the final timeline.

## Regression evidence

Five pure command tests cover mixed normalized/copy track ordering, the exact
append chain, reviewed track metadata, attachment selection, exact chapter
binding, normalized-bundle drift, tag refusal, no overwrite, symlink refusal,
and unsafe user text.

Bundled FFmpeg and MKVToolNix tests execute two final assembly shapes. One writes
the verified HEVC-only bundle with exact nested chapters. The other normalizes
only mismatched video, appends AAC directly from both original sources in the
same final `mkvmerge` process, reopens a two-track output, verifies the retained
audio track identity and chapters, and proves both originals remain byte-exact.

At this command-only boundary the suite contained 298 tests. With the assembled
bundled runtime all 298 executed with zero skips; the standard source-only run
intentionally skipped the 18 bundled-tool integrations.

## Still pending

- Join-boundary decode checks beyond the later transactional semantic/chapter
  audits.
- Verified source-tag preservation and text-subtitle conversion/gap payloads.
- Native exact-choice controls, private-library beta acceptance, and physical
  Intel performance acceptance.
