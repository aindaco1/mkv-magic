# M5 join compatibility policy slice

This records engineering acceptance of the pure joined-track mapping and
lossless-append preflight policy. The later executor slice is documented in
`M5_LOSSLESS_JOIN_EXECUTOR_SLICE.md`; this document does not claim a joined-group
UI, trim execution, common-format proposal screen, physical Intel testing, or a
public signed/notarized release.

## Mapping contract

- A mapping is an ordered list of output lanes. Every lane is video, audio, or
  subtitle and has exactly one explicit track ID or an explicit gap for each
  source in final timeline order.
- Every appendable source track must appear exactly once. Missing IDs, wrong
  kinds, duplicate assignments, unmapped tracks, duplicate source IDs, empty
  lanes, and malformed lane widths fail before analysis.
- The deterministic proposer starts with the first source's track order. For
  each following source it pairs mutually unique full-parameter identities,
  then mutually unique language/role identities, then an obvious single
  same-kind track and lane.
- If multiple tracks remain indistinguishable, the proposer does not guess.
  They receive separate lanes and one grouped ambiguity record names the source,
  kind, unresolved IDs, and candidate lanes for the future native review table.
- New tracks never disappear merely because an earlier source lacks them. Their
  leading gaps remain visible for explicit handling.

## Compatibility classifications

The analyzer returns one highest-impact disposition while retaining every
specific issue:

1. `losslessCandidate`: all inspected, required parameters agree.
2. `confirmationRequired`: no known encode requirement, but metadata, frame
   rate, missing audio/subtitle, non-Matroska input, attachments, or incomplete
   inspector facts require review.
3. `normalizationRequired`: codec/profile/level, video geometry/display geometry,
   pixel format, bit depth, color/HDR, audio sample rate/channels/layout, or a
   missing video segment cannot use the simple lossless lane unchanged.
4. `unsupported`: a data, attachment-like, or unknown stream appears in the
   normalized track list and no supported append policy exists yet.

Language comparison canonicalizes legacy Matroska codes such as `eng` and
`fre`. Roles include forced, commentary, hearing/visual impairment, original,
and text-description flags. Default/enabled flags and titles are separate
metadata confirmations instead of codec decisions.

## MKVToolNix authority

Static inspection cannot reproduce MKVToolNix's packetizer-specific connection
rules. Review of the current upstream source snapshot
`8e35fba45346c40c77a269fe1b3f533b7e1286c1` confirmed that the checks vary by
codec: generic video checks encoded dimensions, codec ID, and codec-private
data; AAC checks sample rate, channels, and profile; Opus also checks private
headers; text subtitle formats may depend on codec-private data; and other
packetizers implement different rules. The app runtime remains pinned to
MKVToolNix 100.0.

Therefore every report sets
`requiresAuthoritativeMKVToolNixValidation = true`. A future executor must run
the bundled exact-path tool inside the verified-output transaction and verify
the finished output; `losslessCandidate` alone is never permission to commit or
Trash a source.

Primary references:

- [mkvmerge append and explicit `--append-to` documentation](https://mkvtoolnix.download/doc/mkvmerge.html#mkvmerge.description.append_to)
- [MKVToolNix generic video connection checks](https://codeberg.org/mbunkus/mkvtoolnix/src/commit/8e35fba45346c40c77a269fe1b3f533b7e1286c1/src/output/p_generic_video.cpp)
- [MKVToolNix AAC connection checks](https://codeberg.org/mbunkus/mkvtoolnix/src/commit/8e35fba45346c40c77a269fe1b3f533b7e1286c1/src/output/p_aac.cpp)
- [MKVToolNix Opus connection checks](https://codeberg.org/mbunkus/mkvtoolnix/src/commit/8e35fba45346c40c77a269fe1b3f533b7e1286c1/src/output/p_opus.cpp)

## Boundedness and regression evidence

- Source count is capped at 1,000 and aggregate inspected tracks at 1,000 before
  lane or ambiguity allocation. Ambiguities are grouped by source and kind to
  prevent per-track candidate matrices from growing quadratically.
- The policy is deterministic in-memory work with no I/O, tools, network, LLM,
  source mutation, or random identity generation.
- Ten focused tests cover a fully known lossless candidate; video/audio
  normalization fields; metadata, frame-rate, and gap confirmations; unknown
  facts; unsupported streams/attachments/containers; reordered tracks;
  cross-codec language pairing; ambiguous duplicates; one-to-one fallback;
  every silent-loss mapping error; deterministic output; and allocation bounds.
- A clean run against the pinned bundled FFmpeg 9.0.1 and MKVToolNix 100.0
  runtime passed all 238 tests with zero skips and zero failures.
- The complete isolated local gate passed all 238 tests with 12 intentional
  bundled-tool skips in source-only and sanitizer runs, both architectures of
  the Universal build, address/thread sanitizers, inside-out package signature
  validation, SBOM/checksums, ZIP/appcast, and verified DMG assembly.

## Still pending in M5

- Native joined-group ordering, trim controls, track mapping, ambiguity review,
  and output metadata/attachment selection UI.
- A common video/audio format proposal, mixed HDR/SDR decision surface, and
  user-confirmed gap behavior.
- Native invocation of the full-file lossless executor, progress presentation,
  and cancellation/retry controls.
- Decode checks around every join, stream-copy fingerprints, and strict
  verification mode.
- Additional malformed/variable-rate/delayed-track fixtures, private-library
  beta acceptance, and physical Intel smoke testing.
