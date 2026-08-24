# M3 exact embedded text-subtitle extraction slice

This records engineering acceptance of direct, same-format extraction for one
embedded SRT, ASS, or SSA track in an inspected Matroska file. It fulfills the
bounded `mkvextract tracks` quick action recorded in `other.txt`. It is not
acceptance of PGS/VobSub artifact extraction, image-to-text OCR, directory-wide
batching, saved-workflow extraction, general attachment/track extraction, or a
public release.

## User-facing scope

- An inspected Matroska file enables **Extract Subtitle…** only when it has at
  least one SRT, ASS, or SSA track with a stable unique UID and unambiguous
  nonnegative track ID.
- A single eligible track proceeds directly. Multiple tracks open the shared
  readable chooser with track number, format, language, name, and playback or
  accessibility roles.
- Review states `0 video/audio encodes`, the exact same-format sidecar, parsed
  item count, and byte count. The Save panel fixes the extension to `.srt`,
  `.ass`, or `.ssa` and suggests a title plus selected-track suffix.
- The output is one separate subtitle file. The source MKV is never modified,
  replaced, remuxed, or moved to Trash.

## Safety and verification contract

1. Review re-inspects the source and compares its URL, container, duration,
   size, tracks, nested chapters, attachments, metadata/tag counts, and segment
   UID with the on-screen inspection before trusting a track ID.
2. The selected track is addressed by stable Matroska UID. Duplicate or missing
   UIDs, duplicate track IDs, non-Matroska input, and image/unknown subtitle
   formats fail closed before extraction.
3. Bundled `mkvextract` receives an exact absolute executable and argument array,
   never a shell command. It writes to a private owner-only temporary directory,
   has bounded time and log output, and must return a safe regular text file no
   larger than 16 MiB. Truncated tool output is a failure.
4. Review binds the source revision, exact extracted bytes, original subtitle
   format, and parsed SRT or ASS/SSA timing/style document. Save re-inspects and
   re-extracts, requires every bound value to agree, and refuses source or tool
   drift.
5. The exact extracted bytes are written through the shared verified subtitle
   transaction. Source revision is checked before verification, before atomic
   commit, and after final reopen. The temporary and committed files must match
   the reviewed bytes and parse to the reviewed document.
6. An existing destination is never silently overwritten. Cancellation and any
   pre-commit failure remove private output. A rare post-commit audit failure
   reports the committed filename explicitly instead of claiming rollback.
7. History uses the built-in **Extract embedded text subtitle** identity, stores
   the source and output display filenames plus bounded lifecycle states, and
   records zero video/audio encodes. It stores no subtitle text, full path,
   digest, raw tool output, security bookmark, or track identifier.

## Observed evidence

- Core policy tests cover deterministic track ordering plus refusal of
  non-Matroska input, duplicate IDs, and duplicate UIDs.
- Executor tests cover exact direct arguments and bytes, source preservation,
  inspection drift before extraction, source-revision changes after review and
  during verification, repeated extraction drift, wrong extensions, tool
  failure, and truncated tool output.
- AppKit tests cover the compact chooser wording, accessibility labels, review
  action, suggested output names, and the disabled initial-state action.
- A real bundled-tool app integration creates a two-cue SRT, muxes it with track
  metadata into Matroska, inspects and extracts it through `AppModel`, reparses
  the exact sidecar, proves the source digest is unchanged, and verifies the
  zero-encode eight-state History record.
- The default app window was launched and visually inspected at its normal size;
  the extraction and TX3G conversion actions fit together without clipping.
- The complete pinned-runtime local gate passed 624 tests with zero failures or
  skips in normal, coverage, AddressSanitizer, and ThreadSanitizer runs. Coverage
  measured 74.88% lines, 78.68% functions, 67.95% regions, and 88.69% non-UI
  lines. Universal compilation, source/security checks, nested Sparkle signing,
  SBOM/checksums, update replacement, ZIP packaging, and DMG verification also
  passed.

## Still pending

- PGS and VobSub extraction, which require format-specific multi-file artifact
  handling rather than this one-file text contract.
- Saved-workflow or queued extraction, multiple-output batch confirmation, and
  physical Intel/Apple Silicon user-flow acceptance.
- Real-library beta acceptance and a public signed/notarized release.
