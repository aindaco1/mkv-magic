# M7 portable image-attachment workflow slice

## Outcome

Saved workflows can add **If present: Remove image attachments**. The card is
portable, conditional, zero-encode by itself, and available to immediate or
automatic queue execution. It removes cover art without removing subtitle
fonts or attachments whose type is unknown.

## Contract

- Workflow schema v11 stores only the removeImageAttachments action. It never
  stores a media path, attachment filename, MIME value, ID, UID, size, inspected
  count, tool path, or command.
- Valid v1-v10 recipes migrate without changing workflow or step identity,
  order, enablement, or prior action semantics. An older schema cannot claim
  the v11 action.
- Compilation requires every attachment to have a stable unique UID and an
  unambiguous nonnegative ID. It selects only trimmed, case-insensitive
  `image/*` MIME types and never infers image status from a filename extension.
- A source with no MIME-confirmed images marks the card already satisfied. The
  review reports only the number of images to remove.
- Track cleanup, image cleanup, and external subtitle muxing share at most one
  fail-closed mkvmerge invocation. The retained attachment selector is explicit.
- Explicit image cleanup can prepare an MKV for the complete-file conversion
  executors. Preparation produces one verified private attachment-clean
  intermediate; the final video/audio conversion still runs exactly once.
- Verification permits normal attachment-ID renumbering but requires the exact
  retained UID, filename, MIME type, description, size, and order while
  preserving unrelated tracks, tags, nested chapters, metadata, and source
  bytes. Queue admission re-inspects and recompiles before starting.
- FFprobe streams marked `attached_pic` are cover-art projections rather than
  playable tracks and are excluded during normalized inspection. MKVToolNix
  remains authoritative for the Matroska attachment table.

## Verification

- Policy regressions cover MIME-confirmed images, trimmed/case-insensitive MIME
  values, preserved fonts, and unknown extension-only attachments.
- Compiler regressions cover apply, skip, unstable-identity refusal, count-only
  path-free review, one fused remux/property plan, and exactly one final
  conversion after cleanup.
- Executor and command regressions prove exact shell-free selectors, one fused
  track/image/subtitle remux, retained font attachments, verified commit, and
  unchanged source bytes.
- Inspector and output-verifier regressions prevent FFprobe attached pictures
  from becoming synthetic video tracks and require exact retained attachments.
- Store and queue-policy regressions cover path-free schema-v11 round trips,
  v10 migration/backport refusal, and lightweight automatic admission.
- The bundled-tool app regression creates real tags plus JPEG and font
  attachments, persists the recipe in the production queue, re-inspects and
  recompiles it, produces one title/tag/image-clean output, preserves the font
  and source digest, and records privacy-safe successful History.
