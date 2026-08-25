# M7 portable SDH-subtitle workflow slice

## Outcome

Saved workflows can add **If useful: Mark SDH subtitles**. The card is portable,
conditional, zero-encode by itself, and supported by immediate and automatic
queue execution. It turns clear subtitle-name signals into Matroska's native
hearing-impaired role without renaming tracks or changing playback defaults.

## Contract

- Workflow schema v15 stores only the `markSDHSubtitles` action. It never stores
  a path, track UID, name, flags, inspected count, tool path, or command.
- Valid v1-v14 recipes migrate without changing workflow or step identity,
  order, enablement, or prior action semantics. An older schema cannot claim
  the v15 action.
- Recognition is limited to subtitle tracks whose hearing-impaired flag is
  unset and whose name contains the distinct token `SDH`, `CC`,
  `hearingimpaired`, or adjacent words `hearing impaired`, case-insensitively.
  Audio/video tracks, already marked subtitles, and substring lookalikes skip.
- Every match requires one UID unique across the complete track table. The
  ephemeral edit sets only `flag-hearing-impaired=1`, preserving name,
  canonical language meaning, every other role/default/enabled flag, and all
  technical facts.
- Commentary role marking, commentary name normalization, forced role marking,
  and SDH role marking merge by stable UID into one edit per track. Multiple
  edits, segment-title removal, and tag clearing still share one fail-closed
  `mkvpropedit` process after any existing remux.
- The role work can prepare one private verified MKV for audio or video
  conversion; the final conversion still encodes each affected stream at most
  once.
- Verification requires exact reviewed flags and names plus unchanged unrelated
  tracks, packets, chapters, attachments, tag policy, timing, and source bytes.
  Queue admission re-inspects and recompiles before execution.

## Verification

- Policy regressions cover SDH, CC, and hearing-impaired spellings;
  subtitle-only scope; false-positive and already-marked no-ops; field
  preservation; and whole-track-table UID refusal.
- Compiler and store regressions cover role/name composition, count-only review,
  one property stage, path/name/UID-free schema-v15 JSON, v14 migration, and v14
  backport refusal.
- Exact-command and output-verifier regressions prove the hearing-impaired flag
  composes with commentary/name/forced edits plus title/tag cleanup in one
  property process and fails verification if any reviewed field is absent or
  any unrelated fact drifts.
- The bundled-tool automatic-queue regression creates a real `English Forced
  SDH` subtitle and commentary audio track, re-inspects and recompiles the
  portable recipe, sets all requested native roles, preserves subtitle name,
  playback state, font and source digest, and keeps sanitized History free of
  private names and paths.
