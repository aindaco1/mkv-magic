# M7 portable commentary-name workflow slice

## Outcome

Saved workflows can add **If useful: Normalize commentary names**. The card is
portable, conditional, zero-encode by itself, and supported by immediate and
automatic queue execution. It turns inconsistent commentary labels into a
small predictable convention without changing media payloads or other metadata.

## Contract

- Workflow schema v13 stores only the `normalizeCommentaryNames` action. It
  never stores a path, track UID, original or resolved name, inspected count,
  flag, tool path, or command.
- Valid v1-v12 recipes migrate without changing workflow or step identity,
  order, enablement, or prior action semantics. An older schema cannot claim
  the v13 action.
- Recognition is limited to audio and subtitle tracks whose native commentary
  role is set or whose name contains the distinct case-insensitive word
  `commentary`. Substring lookalikes do not qualify.
- Audio and subtitle tracks are numbered independently in inspected order as
  `Commentary`, `Commentary #2`, and so on. Already correct names are skipped.
- A track whose name must change requires one UID unique across the complete
  inspected track table. The ephemeral edit changes only its name and preserves
  language, every playback/accessibility role, and all technical facts.
- If flag marking and name normalization target the same track, compilation
  merges them by UID into one edit. Multiple tracks, segment-title removal, and
  tag clearing still share one fail-closed `mkvpropedit` process after any
  existing remux.
- The combined property work can prepare one private verified MKV for audio or
  video conversion; the final conversion still encodes each affected stream at
  most once.
- Verification requires exact reviewed names and flags plus unchanged unrelated
  tracks, packets, chapters, attachments, tag policy, timing, and source bytes.
  Queue admission re-inspects and recompiles before execution.

## Verification

- Policy regressions cover independent audio/subtitle numbering, native-role
  recognition, distinct-word matching, already-normalized no-ops, field
  preservation, and whole-track-table UID refusal.
- Compiler and store regressions cover count-only outcomes, name/flag merging,
  one property stage, path/name/UID-free schema-v13 JSON, v12 migration, and v12
  backport refusal.
- Executor and output-verifier regressions prove a combined name/flag edit uses
  one exact-argument property process, commits only after reinspection, and
  preserves source bytes and unrelated facts.
- The bundled-tool automatic-queue regression recompiles a portable recipe
  against a real `Director Commentary` audio track, produces the native role and
  simple `Commentary` name while also clearing tags/title and removing only an
  image attachment, preserves the font and source digest, and keeps sanitized
  History free of the private original name and paths.
