# M4 Chapter Studio core slice

This records engineering acceptance of the nested chapter model, native outline
editor, and verified Matroska chapter-replacement path. It is a usable M4
vertical slice, not completion of the full thumbnail/analysis milestone, join
recomposition, physical Intel testing, real-library beta testing, or a public
signed/notarized release.

## User-facing scope

- Selecting an inspected Matroska file enables **Chapters…** and privately
  extracts its complete nested chapter document.
- Chapter Studio presents editions and nested atoms in one expandable outline.
  It can add editions, add chapters or children, duplicate, remove, nest, and
  unnest without editing the source.
- A chapter exposes exact start and optional end time with up to nine fractional
  digits, hidden/enabled flags, and one or more localized display names with
  editable language and country. An edition exposes default, hidden, and
  ordered flags.
- **Every…** creates reviewed English fixed-interval chapters. **Flatten for
  Jellyfin** is explicit and retains only unique chronological leaves with new
  UIDs; nesting remains the default.
- Import and export support bounded Matroska chapter XML and simple
  `CHAPTER01` text. Nested documents must be flattened before simple-text
  export.
- Continue creates one final file through `mkvpropedit` on a temporary clone.
  It performs zero video and audio encodes and never modifies or automatically
  trashes the source.

## Safety and verification contract

1. Preview requires an inspected regular Matroska source, captures its file
   revision, extracts chapters into a private directory, parses a bounded
   document, and stores the canonical chapter digest. MKVToolNix's successful
   absent/zero-byte extraction is recognized as an empty document.
2. XML parsing rejects NULs, oversized inputs, entities, arbitrary document
   types, unknown elements, repeated singletons, invalid integers/flags/times,
   malformed nesting, duplicate/zero UIDs, empty editions, invalid language or
   country values, and chapters outside media or parent bounds. Only the exact
   local `matroskachapters.dtd` declaration emitted by `mkvextract` is accepted,
   stripped, and parsed with external entity loading disabled.
3. Execution validates the reviewed document against media duration, refuses an
   unchanged document, rechecks the source revision, re-extracts the current
   tree, and refuses a stale preview before creating an output.
4. The app creates a private APFS clone, rechecks the source revision after the
   clone, and replaces or removes chapters only on that working copy.
5. Before commit, the output inspector must show the original container,
   duration, tracks, metadata, tag counts, attachments, and segment UID. A fresh
   chapter extraction must canonicalize to the exact reviewed editions, nested
   atoms, UIDs, flags, languages, countries, names, and nanosecond timestamps.
6. Exclusive commit occurs only after both audits pass. The committed file is
   reopened and both the structural and exact chapter audits repeat. A final
   audit failure reports the recoverable output location and is never recorded
   as success.
7. Durable history stores display filenames, the Chapter Studio workflow
   identity, chapter count, and bounded lifecycle messages. Chapter names,
   document bytes, digests, and full paths are excluded.

## Observed evidence

- The complete local gate passed 204 tests with 10 intentional tool-dependent
  skips in source-only mode, coverage, AddressSanitizer, ThreadSanitizer,
  preflight/security checks, a fresh Universal build, inside-out ad-hoc signing,
  SBOM and checksums, ZIP/appcast generation, and verified DMG packaging. The
  same 204-test suite then passed against the assembled Universal tool runtime
  with zero skips and zero failures.
- Core regressions cover nested and multilingual XML round trips, exact
  nanosecond parsing, hostile XML, duplicate metadata and UIDs, empty editions,
  media/parent bounds, fixed intervals, simple text, and Jellyfin flattening.
- Executor regressions prove source-revision refusal before editing, no-change
  refusal, failed exact extraction audit cleanup, original-byte preservation,
  and the complete verifying/committing stage sequence.
- A bundled-tool integration creates a real chapterless MKV, writes one nested
  edition with multilingual names and a one-nanosecond child boundary,
  re-extracts the exact three-atom tree, then removes all chapters into another
  verified copy.
- The real app-history integration runs Chapter Studio after the subtitle
  pipeline and records the complete sanitized queued-through-succeeded
  lifecycle while the original source digest remains unchanged.
- A rendered native-window acceptance artifact at 980 by 680 points confirms
  the hierarchy, selected-chapter inspector, numeric fields, compact action
  rows, and final action remain visible without a browser or third-party UI
  runtime. macOS Accessibility permission was unavailable for automated clicks,
  so this is observed layout evidence, not a claimed full keyboard/VoiceOver
  walkthrough.

## Still pending in M4

- Lazy thumbnail timeline and frame/keyframe snapping.
- Reviewed scene-change, black-frame, and silence-boundary suggestions.
- Synchronized timeline dragging and explicit chronological reorder controls.
- Saved-workflow and batch chapter actions.
- Full keyboard-only and VoiceOver acceptance.
- Physical Intel smoke testing, private real-library beta acceptance, and the
  eventual Developer ID-signed, Apple-notarized public release.
