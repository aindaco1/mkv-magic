# M7 portable Matroska tag-removal workflow slice

## Outcome

Saved workflows can add **If present: Remove all Matroska tags**. The card is
portable, conditional, zero-encode by itself, and available to immediate or
automatic queue execution.

## Contract

- Workflow schema v10 stores only the clearAllTags action. It never stores a
  media path, tag XML, tag name/value, inspected count, track UID, tool path, or
  command.
- Valid v1-v9 recipes migrate without changing workflow or step identity,
  order, enablement, or prior action semantics. An older schema cannot claim
  the v10 action.
- Compilation requires inspected nonnegative global and track counts. A
  tag-free MKV marks the card already satisfied and creates no tag-removal work.
- The review reports the exact global and track counts to remove and declares
  zero video/audio generations unless another explicit conversion card applies.
- Segment-title and tag removal share one fail-closed mkvpropedit invocation.
  Existing track cleanup or subtitle muxing still uses at most one preceding
  packet-copy remux.
- Explicit tag removal can prepare a tagged MKV for the existing complete-file
  conversion executors. Preparation produces one verified private tag-free
  intermediate; the final video/audio conversion still runs exactly once.
- Verification requires zero global and track tag counts while preserving
  unrelated metadata, retained track technical facts, nested chapters,
  attachments, and the source file. Queue admission re-inspects and recompiles
  the same semantic plan before starting.

## Verification

- Compiler regressions cover apply, skip, unavailable counts, zero-encode
  planning, and a tagged MKV that becomes eligible for one video conversion.
- Property-editor and executor regressions prove shell-free exact arguments,
  truncated-output refusal, one fused title/tag command, verified commit, and
  unchanged source bytes.
- Output-verifier regressions cover pure metadata cleanup and tag-aware track
  removal without weakening the default tag-preservation contracts.
- Store and queue-policy regressions cover path-free schema-v10 round trips,
  v9 migration/backport refusal, and lightweight automatic admission.
- The bundled-tool app regression creates real global and track tags, persists
  the recipe in the production queue, re-inspects and recompiles it, executes
  one zero-encode property pass, reopens a tag-free/title-free output, preserves
  the source digest, and records privacy-safe successful History.
