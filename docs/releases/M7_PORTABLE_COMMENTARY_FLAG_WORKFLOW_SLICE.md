# M7 portable commentary-flag workflow slice

## Outcome

Saved workflows can add **If useful: Mark commentary tracks**. The card is
portable, conditional, zero-encode by itself, and available to immediate or
automatic queue execution. It turns a clear track-name signal into Matroska's
native commentary role without renaming or otherwise normalizing the track.

## Contract

- Workflow schema v12 stores only the `markCommentaryTracks` action. It never
  stores a media path, track UID, track name, language, flags, inspected count,
  tool path, or command.
- Valid v1-v11 recipes migrate without changing workflow or step identity,
  order, enablement, or prior action semantics. An older schema cannot claim
  the v12 action.
- Compilation considers audio and subtitle tracks only. The distinct
  case-insensitive word `commentary` must appear in the inspected track name;
  substring lookalikes such as `commentaryless` do not qualify.
- Already marked tracks are unchanged. Every remaining match must have one
  unique stable Matroska UID or compilation fails before execution. Review
  reports only the number of affected tracks.
- Each ephemeral edit preserves the inspected name, canonical language meaning,
  default, forced, enabled, accessibility, original-language, text-description,
  and technical media facts while setting only `flag-commentary=1`.
- Multiple track edits, segment-title removal, and tag clearing share one
  fail-closed `mkvpropedit` process after any existing track, attachment, or
  subtitle remux.
- Explicit commentary cleanup can prepare an MKV for complete-file conversion.
  Preparation produces one verified private intermediate; final video/audio
  conversion still runs exactly once.
- Verification requires every reviewed metadata value and unchanged unrelated
  tracks, chapters, attachments, tag policy, container timing, segment identity
  according to the property/remux mechanism, and source bytes. Queue admission
  re-inspects and recompiles before starting.

## Verification

- Policy regressions cover audio/subtitle matching, case and punctuation,
  excluded video and substring lookalikes, already-set flags, field
  preservation, and missing/duplicate-UID refusal.
- Compiler and store regressions cover apply, skip, count-only review, one
  property stage, path/name/UID-free schema-v12 JSON, v11 migration, and v11
  backport refusal.
- Command and executor regressions prove exact argument-array execution without
  a shell, multiple flags plus title/tag cleanup in one property process,
  verified commit, and unchanged source bytes.
- Output-verifier regressions cover multiple simultaneous edits, combined tag
  and title removal, external subtitle mux composition, and refusal when even
  one reviewed flag or unrelated technical fact drifts.
- The bundled-tool automatic-queue regression creates a real named commentary
  audio track plus private global/track tags and image/font attachments,
  persists the portable recipe, re-inspects and recompiles it, produces one
  title/tag/image-clean output with the native commentary flag, preserves the
  font and source digest, and records privacy-safe successful History.
