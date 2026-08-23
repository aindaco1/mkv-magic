# M3 ASS/SSA subtitle slice

This records engineering acceptance of style-preserving ASS and SSA cleanup and
external Matroska muxing. Embedded cleanup is accepted separately in
`M3_EMBEDDED_SUBTITLE_SLICE.md`. This document is not acceptance of
image-subtitle conversion, batch execution, or a public release. Deterministic
English OCR cleanup is accepted separately in `M3_ENGLISH_OCR_SLICE.md`.

## User-facing scope

- Selecting an inspected `.ass` or `.ssa` file enables the shared **Clean
  Subtitle…** review flow.
- The compact native review lists deterministic whole-event advertisement
  removals, edge-whitespace changes, and local English OCR suggestions. Possible
  spelling corrections start unselected; every suggestion can be changed.
- Script information, V4/V4+ styles, comments, unknown sections, arbitrary valid
  event formats, override tags, timing, layer/marked value, speaker/name,
  margins, and effect values are retained.
- Cleanup writes a separate UTF-8 ASS or SSA file. The source is never edited.
- **Add Subtitle…** accepts SRT, ASS, and SSA through one confirmation flow.
  Match confidence, timing warnings, inferred metadata, and unapplied cleanup
  suggestions remain explicit before a zero-encode plan is created.

## Safety and verification contract

1. Input must be a regular, non-symbolic-link text subtitle no larger than 16
   MiB. UTF-8, BOM-marked UTF-8/UTF-16, Windows-1252, and Latin-1 are decoded;
   empty, null-containing, malformed, overflowed, or backwards events fail
   closed.
2. Cleanup changes only the raw Dialogue Text field or removes a whole reviewed
   Dialogue event. It does not rewrite headers, style definitions, comments,
   unknown sections, timings, or structural event fields.
3. Execution re-reads the source and requires both its SHA-256 digest and parsed
   semantics to match the preview. Output cannot replace the source or an
   existing item and is committed only through the verified-output transaction.
4. Cleanup output is compared byte-for-byte with the planned UTF-8 serialization
   and parsed again before commit and after reopen. Parser-local event IDs are
   deliberately excluded from semantic equality.
5. External muxing serializes the reviewed original—not pending cleanup—to a
   private temporary sidecar, invokes the bundled `mkvmerge` directly, and
   removes the sidecar afterward. Video and audio are copied, not encoded.
6. Before commit and again after the committed file is reopened, the newly added
   ASS/SSA track is re-extracted with the bundled `mkvextract`. Its header and
   style lines, event count, every non-timing/text structural field, and
   dialogue text must match. Matroska's observed 10 ms timestamp representation
   difference is tolerated; larger changes fail the transaction or final audit.
7. The ordinary remux verifier still requires a nonempty Matroska output, a
   fresh segment UID, preserved existing track order and technical facts,
   chapters, attachments, tags, duration, plus exactly one final S_TEXT/ASS or
   S_TEXT/SSA track with the reviewed metadata.
8. History stores display filenames and bounded lifecycle messages only. It
   excludes full paths, subtitle text, digests, and security scopes.

## Observed evidence

- Parser and rule tests cover exact normalized round trips, modern ASS, legacy
  SSA `Marked` events, Dialogue text containing commas, style and override-tag
  preservation, unknown sections, ad removal, edge trimming, restoration,
  malformed events, timestamp overflow, and backwards timing.
- Executor regressions cover Windows-1252 normalization, exact style retention,
  source preservation, restoration, wrong destinations, all-events-removed
  refusal, stale previews, injected progress failure, symbolic links, and the
  16 MiB bound.
- Mux regressions prove cleanup is not silently applied, a changed pre-commit
  margin/layout field refuses the output transaction, and a changed committed
  payload is reported as a final reopen-audit failure while retaining the
  already committed output for recovery.
- AppKit tests exercise the shared compact cleanup and mux sheets, explicit
  unapplied-cleanup warning, output naming, and a sanitized ASS cleanup history
  lifecycle.
- Real bundled-tool tests create Matroska sources, add and re-extract both a
  modern V4+ ASS track and a legacy V4 SSA track, verify their distinct codec
  IDs, styles, override tags, and original-file digests. The real app-history
  integration also completes an ASS mux through the queued-to-succeeded
  lifecycle.

## Still pending

- Embedded-cleanup saved-workflow and batch actions.
- Image-subtitle pass-through/mux operations; image-to-text OCR remains roadmap.
- Packaged VoiceOver, full keyboard-only, physical Intel, and real-library beta
  acceptance, plus the eventual signed/notarized public release.
