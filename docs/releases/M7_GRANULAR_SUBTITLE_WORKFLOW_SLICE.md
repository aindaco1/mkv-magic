# M7 granular subtitle-workflow slice

This slice turns the original combined English Library Cleanup recipe action
into two independently controlled, plain-language conditions for newly created
workflows. It does not add subtitle text cleanup, external subtitle muxing,
arbitrary expressions, folder watching, or batch queue execution.

## User contract

- New workflows enable **If present: Remove non-English subtitles** and **If
  redundant: Remove English SDH subtitles** by default. Segment-title removal is
  visible but disabled by default.
- The first condition removes only subtitle tracks with an explicit non-English
  language. English, unknown-language, commentary, and signs/songs tracks remain.
- The second condition removes an English SDH track only when the deterministic
  cleanup policy identifies another preferred English subtitle to retain.
- A condition with no applicable change is skipped. If every enabled condition
  is already satisfied, preview reports no applicable changes and creates no
  output.

## Compilation and portability contract

1. A saved or exported recipe contains only the versioned action names and user
   ordering. It contains no media path, Matroska track ID, track UID, security
   bookmark, or generated command.
2. Each condition filters the established English Library Cleanup suggestions by
   reason only after compiling against the selected inspection.
3. Applicable stable UIDs from every cleanup condition are unioned into exactly
   one removal operation at the first cleanup step's position. Interleaved
   metadata cards therefore still produce one `mkvmerge` remux followed by one
   `mkvpropedit` pass when needed, never one remux per condition.
4. The compiler reuses the existing fail-closed stable-identity and
   would-remove-all-playable-tracks checks after aggregation.
5. The original `englishLibraryCleanup` action remains decodable, compilable, and
   executable so existing `.mkvmagic-workflow` files do not require migration.

## Verification and failure behavior

The compiled plan has zero video encodes. Execution uses the existing verified
output transaction: it must remove exactly the reviewed stable UIDs, preserve
all unrelated track and structure facts, reopen the temporary and committed
results, and leave every source digest unchanged. An unsupported container,
unstable identity, changed source, failed remux, verification mismatch, or no
applicable change cannot commit a destination.

## Acceptance evidence

- Compiler regressions cover independent reason filtering, aggregation across an
  interleaved metadata step, one stable-UID removal operation, one remux, one
  property pass, zero video encodes, and already-satisfied conditions.
- Portable-store regressions round-trip both new action names without media
  identity. Existing tests continue to decode and compile the legacy combined
  action.
- A real pinned bundled-tool integration compiles the two granular conditions,
  removes a generated French subtitle, removes a segment title, verifies and
  reopens the output, records the workflow lifecycle, and confirms the source
  SHA-256 digest is unchanged.
- The native builder was captured and visually inspected at its supported minimum
  size. All three default cards, explanations, workflow controls, and save/preview
  actions fit without clipping.

### 2026-08-23 gate results

- The normal source gate passed all 420 tests with 30 intentional no-runtime
  skips, source validation, and the Universal application build.
- The exact pinned Universal runtime passed all 420 tests with zero skips,
  including the real granular-workflow transaction.
- AddressSanitizer and ThreadSanitizer each passed all 420 tests. Coverage also
  passed.
- The package gate passed the Universal app, both architecture-specific media
  tool trees, nested signatures, Sparkle components, update feed, SBOM,
  corresponding source, third-party notices, checksums, ZIP, and mounted and
  verified DMG.
- The minimum-size native builder capture was visually inspected on macOS; its
  two enabled conditional cards, disabled title card, explanations, and controls
  are fully visible without clipping.
- This is local engineering and ad-hoc signing evidence, not public Developer ID
  notarization, publication, downloaded-artifact verification, or private-library
  playback acceptance.

## Still pending

- Subtitle text-cleanup and subtitle-mux workflow cards.
- Track-role, chapter, trim, join, and encoding conditions.
- Durable queue pause, resume, retry, cancel, reorder, and concurrency behavior.
- VoiceOver, keyboard-only, physical Intel, and private-library beta acceptance.
- Public Developer ID signing, notarization, publication, and downloaded-artifact
  verification.
