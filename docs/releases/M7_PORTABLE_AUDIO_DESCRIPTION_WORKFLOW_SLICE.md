# M7 portable audio-description workflow slice

## Outcome

Saved workflows can add **If useful: Mark audio-description tracks**. The card
is portable, conditional, zero-encode by itself, and supported by immediate and
automatic queue execution. It turns clear audio-track name signals into
Matroska's native visual-impaired role without renaming tracks or changing
playback defaults.

## Contract

- Workflow schema v16 stores only the `markAudioDescriptionTracks` action. It
  never stores a path, track UID, name, flags, inspected count, tool path, or
  command.
- Valid v1-v15 recipes migrate without changing workflow or step identity,
  order, enablement, or prior action semantics. An older schema cannot claim
  the v16 action.
- Recognition is limited to audio tracks whose visual-impaired flag is unset
  and whose name contains `audio description`, `audio described`, `descriptive
  audio`, `visual impaired`, or `visually impaired`, case-insensitively. Compact
  spellings are also accepted; ambiguous `AD`, non-audio tracks, already marked
  tracks, and substring lookalikes skip.
- Every match requires one UID unique across the complete track table. The
  ephemeral edit sets only `flag-visual-impaired=1`, preserving name, canonical
  language meaning, every other role/default/enabled flag, channel layout, and
  all technical facts.
- Commentary role marking, commentary name normalization, forced and SDH role
  marking, and audio-description role marking merge by stable UID into one edit
  per track. Multiple edits, segment-title removal, and tag clearing still
  share one fail-closed `mkvpropedit` process after any existing remux.
- The role work can prepare one private verified MKV for audio or video
  conversion; the final conversion still encodes each affected stream at most
  once.
- Verification requires exact reviewed flags and names plus unchanged unrelated
  tracks, packets, chapters, attachments, tag policy, timing, and source bytes.
  Queue admission re-inspects and recompiles before execution.

## Verification

- Policy regressions cover each accepted phrase and compact spelling,
  audio-only scope, false-positive and already-marked no-ops, field
  preservation, and whole-track-table UID refusal.
- Compiler and store regressions cover role/name composition, count-only review,
  one property stage, path/name/UID-free schema-v16 JSON, v15 migration, and v15
  backport refusal.
- Exact-command and output-verifier regressions prove the visual-impaired flag
  composes with commentary/name/forced/SDH edits plus title/tag cleanup in one
  property process and fails verification if only the reviewed role is absent.
- The bundled-tool automatic-queue regression creates a real audio-description
  commentary track plus a forced SDH subtitle, re-inspects and recompiles the
  portable recipe, sets every requested native role, preserves media structure,
  font and source digest, and keeps sanitized History free of private names and
  paths.
