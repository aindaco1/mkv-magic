# M7 filename-cleanup workflow slice

This slice closes the first portable workflow filename-cleanup deliverable. It
turns the naming behavior from the legacy `clean_mkv.py` script into a bounded,
reviewed output policy instead of an implicit source rename.

## User contract

- **Add Step…** includes **If useful: Clean up the output filename**. The card
  is optional, independently enabled, duplicate-safe, and portable.
- Common dot/underscore-separated movie release names produce a conservative
  `Title (Year)` suggestion. A trailing legacy `.clean` marker is discarded,
  the original extension spelling is retained, and already-simple names do not
  manufacture work.
- Plan review shows the exact proposed filename before the user can choose
  **Use This Plan**. The Save panel starts with that value and remains editable.
  A workflow that also adds a subtitle still enforces the required MKV output
  extension.
- The recipe stores only `normalizeFilename` intent. It never stores a source
  path, reviewed filename, server-library title, or per-file identifier.

## Lossless execution boundary

Filename policy does not add an MKVToolNix or FFmpeg pass to a workflow that
already changes media. When it is the only applicable card, compilation creates
an explicit **No transcoding • byte-identical file copy** plan with only verify
and commit stages.

Execution uses the existing same-volume clone transaction. No media command is
invoked. The temporary clone is reopened and compared with the reviewed source
for exact file size and stable inspection facts: container, duration and
bitrate, tracks, metadata and tag counts, canonical chapter structure,
attachments, muxing/writing applications, and Matroska segment identity. The
same audit repeats after exclusive commit. Exact source-revision checks continue
through the commit boundary for automatic queue execution.

The source is never renamed in place. With the default **Keep original**, the
result is a verified second file. If the user separately selects
Trash-after-verified-success, the already established durable follow-up moves
the original only after the output commits, reopens, audits, and records queue
success. This provides recoverable rename-shaped behavior without weakening the
original-preservation rule.

## Schema and automation

- Portable workflows advance from schema v3 to v4. v1, v2, and v3 recipes
  migrate without changing workflow/card IDs, order, enablement, or existing
  actions.
- A v1-v3 document that claims the new action fails closed as an invalid
  backport. Unknown actions and unexpected fields retain their prior stable
  errors.
- The automatic queue accepts the card under the same one-input saved-workflow
  policy. Reinspection and recompilation must still reproduce the reviewed
  semantic plan before execution.

## Regression evidence

- Core tests cover the legacy movie examples, already-simple names, extension
  preservation, fallback separator cleanup, hidden names, and invalid years.
- Compiler tests cover filename-only verify/commit planning, an unchanged-copy
  impact, already-satisfied behavior, and composition with a metadata card
  without another pass.
- Store tests cover schema-v4 portable round trip without a concrete filename,
  v3 migration, and v3 backport refusal.
- Execution tests prove filename-only work invokes no media tool, commits the
  cloned bytes, preserves the source, and still rejects unreviewed no-operation
  calls. Verifier coverage rejects structural drift and ignores only ephemeral
  in-memory chapter UUIDs.
- AppKit tests cover the card catalog, editable container-safe output naming,
  and the explicit byte-identical-copy review language.
- A pinned bundled-tool integration creates a real release-style MKV, executes
  the filename-only app workflow, preserves its Matroska title, records
  sanitized History, and confirms the source and output SHA-256 are identical.

- The repository-defined complete local gate passed. Normal, coverage,
  AddressSanitizer, and ThreadSanitizer each executed all 497 tests with zero
  failures. The source-only modes intentionally skipped 33 pinned-runtime cases;
  the new real-MKV filename acceptance also passed separately against the exact
  bundled runtime.
- Source validation built the release executable for both `arm64` and `x86_64`.
  The isolated package gate passed nested Sparkle and app signature validation,
  disposable update ZIP/appcast generation, third-party notices, supported-
  systems metadata, CycloneDX SBOM, recorded checksums, build metadata, and
  independent DMG verification.

## Explicit limits

- This is deterministic filename cleanup, not an online metadata lookup. It
  does not contact TMDB, TVDB, Plex, Jellyfin, or any other service.
- The first policy targets common movie release names. Series/episode parsing,
  user-configurable token dictionaries, and optional online naming assistance
  remain future work.
- The user may replace the proposed name in the Save panel. MKV Magic does not
  silently move or overwrite an existing destination.
