# M7 automatic external-subtitle queue slice

Date: 2026-08-24

## Delivered contract

A saved workflow containing **Add an external subtitle** can be added to the
production queue after the user has selected and reviewed one SRT, ASS, or SSA
sidecar. **Clean the added subtitle text** remains optional and uses the exact
per-cue or per-event restoration choices accepted in that review. Both forms are
classified from their compiled plan and use the existing queue scheduler,
admission coordinator, cancellable process supervision, verified output
transaction, sanitized History, and opt-in Trash-after-verified-success policy.

The main workflow preview now enables **Add to Queue** for this reviewed two-input
case. Queue authoring stores a fresh read/write or read-only bookmark for the
primary media according to its Trash policy, a read-only sidecar bookmark, each
file's reviewed revision, the output directory authority, and the same reviewed
semantic plan. **Review Again** remains the only retry path: it re-resolves and
re-inspects the media, asks the user to choose and review the sidecar again, and
atomically replaces all review-bound queue state.

## Portable, private, and integrity boundaries

The exported schema-v9 `.mkvmagic-workflow` remains unchanged. It stores only the
external-subtitle and optional cleanup actions. It contains no path, bookmark,
track metadata, subtitle text, cleanup identifier, digest, or inspected-media
identity.

The app-private, mode-0600 queue document uses an additive workflow-intent case
under its existing v1 document schema. That case stores only:

- external text format;
- reviewed language, name, default, forced, and hearing-impaired flags;
- nil for original text, or a sorted unique list of restored cleanup IDs; and
- the 32-byte SHA-256 of the reviewed sidecar.

The sidecar path remains only inside its opaque security-scoped bookmark. No
subtitle text or parsed media identity is persisted. Existing one-input queue
documents retain their prior encoding and decode behavior.

Admission resolves both unchanged file bookmarks, parses a fresh deterministic
subtitle preview, requires the original SHA-256, and reapplies the exact cleanup
restorations. It recompiles the portable recipe with the reconstructed track
metadata and requires the same ordered mechanisms, summaries, and encode impact.
Both file revisions are checked again before execution. The existing mux
executor then rechecks the sidecar digest, writes one temporary MKV, extracts and
semantically compares the added subtitle, verifies all preserved media facts,
commits atomically, reopens, and audits again. A missing, changed, malformed, or
unsupported review returns **Needs Review** without creating an output.

## Regression evidence

- Core policy tests accept only the exact one-primary-plus-one-sidecar shape,
  require the add card, require cleanup-selection presence to match the cleanup
  card, and reject invalid language, digest length, ordering, duplication, or
  negative cleanup IDs.
- Private-store tests round-trip the additive intent under
  `mkv-magic-job-queue-v1`, preserve mode 0600, and prove the JSON contains no
  path or subtitle text. Malformed review/card combinations fail closed.
- A real bundled-tool regression creates a source MKV and advertised SRT,
  reviews cleanup, runs the immediate transaction, then queues and automatically
  reconstructs the same work. Both outputs contain the reviewed English track,
  omit the advertisement, remove the segment title, preserve both input digests,
  and record **Waiting -> Running -> Succeeded**.
- A table-driven real bundled-tool regression separately queues modern ASS and
  legacy SSA. It proves the automatic run restores the user's retained OCR
  event, applies the accepted advertisement and whitespace cleanup, preserves
  each format's header, style, and override tags, emits the distinct
  `S_TEXT/ASS` or `S_TEXT/SSA` codec, applies all reviewed track flags, removes
  the segment title, records one zero-encode History job, and leaves both input
  files byte-identical.
- The same regression replaces the sidecar with different same-size content and
  restores its reviewed millisecond modification time. Although the path-free
  revision still matches, the SHA-256 boundary moves the automatic job to
  **Needs Review**, creates no output, and records no false History success.

- The runtime-pinned 2026-08-24 complete local gate ran all 593 tests with zero
  failures and zero skips under normal, AddressSanitizer, and ThreadSanitizer
  configurations. Source coverage was 75.01% line, 78.32% function, 67.80%
  region, and 88.72% non-UI line. The Universal arm64/x86_64 build, nested
  signature/layout verification, bundled-tool manifest checks, Sparkle update
  replacement, SBOM and checksum validation, and independent DMG verification
  all passed.

## Explicit limits

- One text sidecar is supported per workflow run. Multiple sidecars, embedded
  image-subtitle OCR, and automatic sidecar discovery remain out of scope.
- Queue authoring still requires an interactive initial file, metadata, and
  cleanup review. There is no watched folder or rule that guesses a sidecar.
- Physical Intel throughput, representative Jellyfin/Plex playback, long queue
  soak, notarized distribution, and private-library acceptance remain separate
  release gates.
