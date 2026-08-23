# M5 joined chapter policy slice

This records engineering acceptance of the pure nested-chapter recomposition
policy needed by future hard joins. It does not claim a join UI, track mapping,
compatibility analysis, mux execution, real-file join acceptance, physical
Intel testing, or a public signed/notarized release.

## Policy scope

- Every input names its known source duration, positive retained range, optional
  source title, parent display language/country, and the chapter atoms from an
  explicitly selected edition. The caller—not this policy—must choose among
  multiple source editions so data is never silently discarded.
- Sources are consumed only in the supplied final timeline order. Their retained
  durations accumulate with checked integer arithmetic at nanosecond precision.
- Source chapters outside a half-open retained range are removed. Chapters that
  cross either retained edge are clamped, then every surviving start/end is
  shifted by the negative retained-start offset and the cumulative duration of
  preceding sources. A missing Matroska chapter end is materialized from the
  next sibling start, or from its parent/source boundary for the last sibling,
  before clipping so the joined result has unambiguous ranges.
- Existing nested structure, display names, languages, countries, hidden flags,
  and enabled flags are preserved. Every surviving atom receives a new ID and
  Matroska UID to prevent cross-file collisions.
- Each source becomes a top-level `Part N — Source Title` parent spanning its
  complete retained output section. A chapterless or fully trimmed source gets
  one globally numbered English boundary child instead of disappearing.
- The result is exactly one default Matroska edition. It is validated against
  the calculated final duration and the shared 20,000-atom, depth, UID,
  metadata, parent-bound, and chronological-order rules before it can be used.

## Safety and boundedness

1. Empty source lists, unknown/nonpositive durations, empty/backward/out-of-file
   retained ranges, invalid source chapter trees, invalid display metadata, and
   integer overflow fail closed.
2. Source trees are validated before transformation. Aggregate output count is
   checked as each source is added, and source count itself is capped before any
   output tree is allocated.
3. The composer is deterministic policy over in-memory values except for the
   intentionally regenerated UUID/UID identities. It performs no I/O, launches
   no tool, uses no network or LLM, and cannot modify a source.
4. Exact join-boundary duplication is avoided by half-open retained ranges: a
   marker at the prior source's retained end is excluded while a marker at the
   next source's retained start is retained inside that source's parent.

## Regression evidence

- Golden structural tests cover a two-source join with a trimmed nested tree,
  global offsets, clamped edges, an excluded retained-end marker, a chapterless
  second source, globally numbered fallback naming, and byte-independent fresh
  identities.
- Additional tests cover display/flag preservation, canonical parent language,
  implicit-end materialization, invalid source trees, every invalid range class,
  empty input, cumulative nanosecond overflow, aggregate output bounds, and
  final shared validation.
- The complete isolated local gate passed all 228 tests with 12 intentional
  bundled-tool skips in source-only and sanitizer runs, both architectures of
  the Universal build, address/thread sanitizers, inside-out package signature
  validation, SBOM/checksums, ZIP/appcast, and verified DMG assembly.
- A separate clean run against the pinned bundled FFmpeg and MKVToolNix runtime
  passed all 228 tests with zero skips and zero failures.

## Still pending in M5

- Native joined-group ordering, trim-range, chapter-edition choice, and track
  mapping UI.
- Lossless append compatibility checks and explicit unmatched-track handling.
- MKVToolNix hard-join execution through the verified-output transaction.
- Re-extraction and exact comparison of the composed nested chapter result.
- Common-format/layout proposals and one-encode enforcement for incompatible
  sources.
- Real bundled-tool fixtures, private-library beta acceptance, and physical
  Intel smoke testing.
