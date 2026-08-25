# M7 portable forced-subtitle workflow slice

## Outcome

Saved workflows can add **If useful: Mark forced subtitles**. The card is
portable, conditional, zero-encode by itself, and supported by immediate and
automatic queue execution. It turns a clear subtitle-name signal into
Matroska's native forced role without renaming or changing playback defaults.

## Contract

- Workflow schema v14 stores only the `markForcedSubtitles` action. It never
  stores a path, track UID, name, flags, inspected count, tool path, or command.
- Valid v1-v13 recipes migrate without changing workflow or step identity,
  order, enablement, or prior action semantics. An older schema cannot claim
  the v14 action.
- Recognition is limited to subtitle tracks whose forced flag is unset and
  whose name contains `forced` as a distinct case-insensitive word. Audio/video
  tracks, already forced subtitles, and substring lookalikes are skipped.
- Every match requires one UID unique across the complete track table. The
  ephemeral edit sets only `flag-forced=1`, preserving name, canonical language
  meaning, default, enabled and accessibility roles, and all technical facts.
- Commentary role marking, commentary name normalization, and forced role
  marking merge by stable UID into one edit per track. Multiple edits,
  segment-title removal, and tag clearing still share one fail-closed
  `mkvpropedit` process after any existing remux.
- The role work can prepare one private verified MKV for audio or video
  conversion; the final conversion still encodes each affected stream at most
  once.
- Verification requires exact reviewed flags and names plus unchanged unrelated
  tracks, packets, chapters, attachments, tag policy, timing, and source bytes.
  Queue admission re-inspects and recompiles before execution.

## Verification

- Policy regressions cover case/punctuation matching, subtitle-only scope,
  substring and already-forced no-ops, field preservation, and whole-track-table
  UID refusal.
- Compiler and store regressions cover role/name composition, count-only review,
  one property stage, path/name/UID-free schema-v14 JSON, v13 migration, and v13
  backport refusal.
- Exact-command and output-verifier regressions prove the forced flag composes
  with two commentary edits plus title/tag cleanup in one property process and
  fails verification if any reviewed field is absent or any unrelated fact
  drifts.
- The bundled-tool automatic-queue regression creates a real `English Forced`
  subtitle and `Director Commentary` audio track, re-inspects and recompiles the
  portable recipe, sets both native roles, normalizes only commentary, preserves
  subtitle name/default/enabled state, font and source digest, and keeps
  sanitized History free of private names and paths.
