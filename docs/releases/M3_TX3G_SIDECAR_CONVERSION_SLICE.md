# M3 TX3G sidecar-conversion slice

Date: 2026-08-24

## Delivered user path

An inspected MP4, M4V, or MOV containing TX3G/`mov_text` now enables
**Convert MP4 Subtitle…**. A single timed-text track proceeds directly to
review; multiple tracks open the shared readable subtitle chooser with track
number, language, name, and playback/accessibility flags. The review reports
the exact parsed event count and makes clear that the output is a separate ASS
subtitle and the video remains unchanged.

The Save panel suggests `Title — TX3G.ass`, adding the one-based track number
when the source has multiple timed-text tracks. The extension is fixed to
`.ass`, but the destination remains user-selected.

## Verified conversion contract

- Only an inspected MP4-family container/extension pair and unique non-negative
  timed-text stream indexes are offered.
- Bundled FFmpeg runs through an absolute executable and argument array; no
  shell, inherited Homebrew path, custom arguments, or network access is used.
- Review converts the selected stream inside a private `0700` temporary
  directory and parses the bounded ASS result. No extracted subtitle persists.
- Execution requires the exact reviewed source filesystem revision, repeats the
  conversion, and requires the complete parsed ASS document to match review.
- The shared verified subtitle-output writer checks cancellation and the source
  revision before verification, before commit, and after the committed reopen;
  existing SRT/ASS cleanup paths reuse the same transaction implementation.
- MKV Magic serializes normalized UTF-8 ASS into a same-volume temporary output,
  verifies its exact bytes plus parsed text, styles, fields, and timing, checks
  the source again, commits without overwrite, reopens the result, and repeats
  the audit.
- The source video is neither modified nor replaced. History records the normal
  eight-state lifecycle with zero video generations and zero encoded audio
  tracks; support export identifies only the coarse built-in workflow kind.

## Regression evidence

- Core tests cover MP4-family recognition, TX3G codec aliases, stable stream
  ordering, extension/container mismatch, duplicate indexes, and negative
  indexes.
- Executor tests cover exact FFmpeg mapping arguments, two-pass conversion
  agreement, UTF-8 ASS verification and reopen, unchanged source bytes, stale
  source refusal, conversion drift, wrong output format, and absence of a
  destination after failure, including source mutation during output
  verification.
- AppKit tests cover explicit single/multiple-track output names, timed-text
  chooser labels, the separate-sidecar explanation, and the main action's
  disabled initial state.
- A pinned bundled-tool integration creates a real BT.709 H.264 MP4 with two
  TX3G cues and reviewed language/name/forced metadata, inspects and converts it
  through AppModel, reparses the saved ASS, proves the MP4 SHA-256 unchanged,
  and records **Queued -> Inspecting -> Planned -> Ready -> Running -> Verifying
  -> Committing -> Succeeded** with zero video/audio encodes.
- The complete local gate passed with the pinned full Universal runtime: 613
  tests and zero skips or failures in each normal, coverage, AddressSanitizer,
  and ThreadSanitizer run. Coverage measured 75.04% lines, 78.59% functions,
  67.98% regions, and 88.75% non-UI lines. Universal arm64/x86_64 source and app
  builds, bundled-tool layout, nested Sparkle signatures and replacement,
  package metadata, SBOM, notices, archive hashes, ZIP, and independent DMG
  verification all passed.

## Deliberate limits

- The current action creates one external ASS sidecar at a time. It does not
  clean the converted text in the same review, convert image subtitles, add the
  sidecar back to an MKV automatically, join multiple subtitle tracks, or enter
  the automatic saved-workflow queue.
- Remux to MKV and complete video conversion continue to refuse a source that
  still contains TX3G rather than silently dropping or rewriting it.
