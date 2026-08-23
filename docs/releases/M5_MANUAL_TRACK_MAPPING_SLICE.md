# M5 manual track-mapping slice

This records engineering acceptance of the native manual resolver for track
layouts the deterministic matcher cannot identify safely. It completes the M5
implementation surface; it does not claim private-library beta, physical Intel
acceptance, M6 HDR/transcoding completeness, or public release.

## User contract

- The main Join review continues to propose only unambiguous matches. When
  indistinguishable tracks remain, Save stays disabled and **Resolve Track
  Mapping…** is available.
- The resolver is one horizontally scrollable, lane-by-Part table. Every row is
  one final output track; every source cell shows the current track or an
  explicit gap. Compact labels expose track ID, codec, language, title, layout
  or dimensions, and important role flags.
- Selecting a same-type track already used elsewhere moves or swaps the two
  cells. The editor cannot duplicate or discard a source track. Fully empty
  temporary lanes collapse automatically.
- **Use This Mapping** is the explicit confirmation. The compatibility and
  common-format reviews are rebuilt from that exact mapping; gaps and format
  differences remain visible and retain their existing fail-closed policies.
- A confirmed mapping is bound to the selected assets in their exact order.
  Including, excluding, or reordering any Part clears it and returns to a fresh
  automatic proposal.

## Safety and architecture

`JoinTrackMappingEditor` is a pure Core operation. It validates the incoming
exhaustive mapping, same-source track identity, and lane kind before a swap,
removes only a lane proven empty, then runs the strict compatibility validator
again. Missing tracks, bad indices, wrong kinds, duplicate assignments, and
unmapped tracks fail before a candidate can reach an executor.

The AppKit sheet holds only inspected metadata and mapping identifiers. It does
not read media, invoke tools, mutate source files, use a network, or retain a
security-scoped URL beyond the existing Join flow. The confirmed mapping feeds
the same immutable preview, source-revision validation, verified-output
transaction, boundary decode, copied-payload fingerprint, atomic commit, reopen,
and sanitized History path as an automatic lossless or common-format map.

## Regression and real-tool evidence

- Core tests cover moving ambiguous tracks into existing lanes, automatic empty
  lane compaction, occupied-cell swaps, wrong-kind refusal, and strict
  post-edit exactly-once validation.
- App tests cover ambiguity blocking, explicit source-order binding, a fully
  resolved lossless candidate, the compact native table at minimum size, and
  popup-driven edits that collapse four provisional lanes into two reviewed
  lanes.
- A bundled-tool app integration creates two MKVs with two indistinguishable
  AAC tracks apiece, confirms the manual map, executes the full lossless Join,
  verifies both copied lanes and every boundary before and after commit, records
  one successful History job, and proves both source files remain byte-identical.

The standard source validation completes all 348 tests with zero failures and
24 intentional bundled-tool skips, then builds the Universal `arm64`/`x86_64`
executable. The exact bundled runtime completes all 348 tests with zero skips
and zero failures.

The complete local gate also passes coverage, AddressSanitizer,
ThreadSanitizer, Universal compilation, inside-out app signature and entitlement
validation, SBOM and checksum verification, ZIP/appcast assembly, and verified
DMG packaging.

## Still pending

- Private-library beta across representative malformed, variable-rate, delayed,
  subtitle-heavy, HDR, and large-track-count files.
- Physical Intel responsiveness, memory, throughput, and thermal acceptance.
- M6 format coverage and public signed/notarized release acceptance.
