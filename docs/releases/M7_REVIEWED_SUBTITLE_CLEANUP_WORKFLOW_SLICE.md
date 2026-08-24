# M7 reviewed external-subtitle cleanup workflow slice

This follow-on slice makes deterministic subtitle text cleanup composable with
the existing external-subtitle workflow input. It does not add a second output,
remux, transcode, online service, or language model.

## User contract

- Add Step offers **Clean the added subtitle text** only after **Add one external
  text subtitle** is present.
- Enabling the cleanup card enables its input card. Disabling the input card
  disables cleanup; removing it removes the dependent cleanup card.
- Save & Preview chooses the SRT, ASS, or SSA, opens the existing cue-by-cue
  review when suggestions exist, then confirms track metadata and shows every
  outcome in the normal workflow review.
- No suggestion is applied without that review. Restored suggestions remain
  byte-semantically equivalent to the reviewed original event or cue.
- Accepted ad removal, edge-whitespace cleanup, and English OCR changes are fed
  into the same external-subtitle remux. The selected subtitle is never replaced
  and no cleaned sidecar is created.
- Cancelling selection, cleanup review, metadata confirmation, or plan review
  leaves no runnable plan.

## Portable and revision-safe boundary

1. Workflow schema v3 adds only `cleanExternalSubtitleText`. JSON stores no
   input path, bookmark, track metadata, subtitle text, cue/event identifier,
   restoration set, or applied-change count.
2. v1 and v2 recipes migrate to v3 while preserving recipe and step identities,
   order, enablement, name, and action semantics. Older claimed schemas cannot
   contain newer actions.
3. The external file path, format, metadata, review selection, and applied count
   exist only in the active preview and compiled plan. The compiler rejects an
   enabled cleanup card without its enabled external-subtitle input or without a
   completed per-run cleanup review.
4. The subtitle preview's byte hash, reparsed document, cleanup proposal, and
   restoration identifiers are validated again before any tool runs. Unknown
   identifiers, a changed sidecar, or a review that removes every event fails
   closed.

## One-output verification contract

- Stable-UID track removal, the reviewed cleaned subtitle, and track ordering
  share one `mkvmerge`. Optional segment-title removal remains one
  `mkvpropedit` pass on the same temporary output. Video and audio have zero
  encoded generations.
- Only a normalized private subtitle payload is handed to `mkvmerge`; it is
  removed immediately after the tool returns.
- Reviewed SRT is extracted with `mkvextract` and compared cue-by-cue for exact
  text plus millisecond timing tolerance. Reviewed ASS/SSA retains its stricter
  header, style, structural-field, text, and timing comparison.
- The payload audit runs on the temporary output before commit and again after
  reopening the committed destination. Track, metadata, title, chapters, tags,
  attachments, duration, segment identity, and source-preservation verification
  remain unchanged.
- App history records one sanitized workflow lifecycle with the MKV and sidecar
  display names. Privacy-safe export receives neither paths nor subtitle text.

## Regression evidence required by this slice

- Compiler and store tests cover dependencies, applied/skipped outcomes, fused
  passes, v1/v2 migration, schema backport refusal, and path/text/review-free
  portable JSON.
- AppKit tests cover dependent card authoring, enable/disable/removal behavior,
  reviewed-cleanup confirmation copy, and the minimum-size plan review.
- Executor tests prove invalid reviews fail before tools, reviewed SRT is the
  only payload supplied to one remux, and both temporary and committed outputs
  are extracted.
- The pinned real-tool application test removes an existing French subtitle,
  applies reviewed cleanup to an English SRT, adds it, removes the segment title,
  re-extracts the final text, preserves both input hashes, and records one
  complete eight-state history lifecycle.

## Verified local gate — 2026-08-23

- The normal source gate passed 441 tests with 31 intentional runtime-dependent
  skips, strict Swift formatting and source checks, and the Universal arm64 plus
  x86_64 build.
- With the repository's exact pinned tool root required, all 441 tests passed
  with zero skips and zero failures. The real-tool application workflow covered
  one reviewed cleaned-subtitle transaction from selection through committed
  output and history.
- Code-coverage collection completed, then AddressSanitizer and ThreadSanitizer
  each passed all 441 tests with zero failures.
- The package gate built the Universal app and verified the complete nested code
  signature, tool manifests, ZIP, appcast, notices, build metadata, supported
  systems document, SBOM, dependency resolution, SHA-256 manifest, and DMG
  checksum. The complete local gate exited successfully.

## Evidence boundary

Passing local source, sanitizer, package, and pinned-tool gates is engineering
evidence. It is not public Developer ID notarization, publication,
downloaded-artifact verification, physical Intel acceptance, or private-library
playback acceptance.
