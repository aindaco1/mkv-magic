# M6 common-input standalone transcode slice

Date: 2026-08-24

## Delivered contract

The native **Convert Video…** action now accepts bounded MP4, M4V, MOV, and
chapter-free WebM input in addition to its existing Matroska path. It still
requires the exact complete duration, creates one new MKV, and performs exactly
one video generation through a locally verified AV1, HEVC, H.264, or ProRes
encoder. The original is never replaced.

Lossless work stays lossless. The shared Matroska packet-copy policy is now used
by both **Remux to MKV…** and standalone conversion. Compatible audio remains a
packet copy by default. When a common-container audio codec cannot be stored in
Matroska safely, review stops with an actionable error and the user may select a
locally verified AAC, Opus, AC-3, E-AC-3, or FLAC conversion whose channel
layout and sample-rate boundary is known. No workflow can encode the video more
than once.

## Chapter and metadata translation

MKV input retains the existing exact canonical nested-chapter contract.
Inspected MP4/M4V/MOV chapters are promoted into one default Matroska edition;
their stable inspected identifiers produce stable edition and chapter UIDs. A
single recognized QuickTime `bin_data` chapter carrier is omitted from the
media map. A mismatched reported chapter count or more than one possible carrier
fails closed. Chaptered WebM remains unsupported because its exact nested source
hierarchy is not yet available to inspection.

The common-input boundary accepts only one video, unique stream indexes, no
subtitle or attachment tracks, no arbitrary data, and only the reviewed segment
title, track language/name, and known container provenance fields. FFmpeg is
given explicit stream language and title metadata so container-specific MP4
`name` representation becomes the intended Matroska track title. Common inputs
also require complete supported SDR or static-HDR10 facts; incomplete or
unsupported color metadata is rejected rather than inferred.

## Verified-output transaction

The planner, command builder, executor, and verifier share the existing
complete-file transaction. Review binds the source filesystem revision, exact
stream map, complete duration, encoder choice, audio policy, and translated
chapter document. FFmpeg emits no trim seek or duration cap. The candidate must
pass semantic inspection, copied-audio streaming packet fingerprints, canonical
chapter extraction, atomic commit, and the same audits after reopening the final
path. Cross-container verification deliberately normalizes codec IDs and
container-only bit-depth reporting while still requiring codec family, profile,
level, channel count, layout, sample rate, track metadata, and the exact copied
packet payload. The source SHA-256 remains unchanged.

## Regression evidence

- Planner regressions cover MP4/M4V/MOV and WebM classification, transcode-only
  eligibility, one-generation impact, chapter-carrier exclusion, incompatible
  packet-copy audio with explicit AAC recovery, metadata refusal, subtitle and
  attachment refusal, inconsistent chapter facts, and chaptered-WebM refusal.
- Core regression proves deterministic import of a nested inspected hierarchy
  into one validated Matroska edition with canonical language handling.
- Command regression proves only reviewed media streams are mapped and explicit
  language/title metadata is emitted without a shell.
- A real bundled-tool regression creates a chaptered H.264/AAC MP4, converts the
  video once, packet-copies and fingerprints AAC, translates both chapters,
  decodes the result, and proves the source digest unchanged.
- A second real bundled-tool regression creates an explicitly BT.709 AV1/Opus
  WebM, converts the video once, packet-copies and fingerprints Opus, verifies
  the chapter-free MKV, and proves the source digest unchanged.

- The runtime-pinned 2026-08-24 complete local gate ran all 599 tests with zero
  failures and zero skips under normal, AddressSanitizer, and ThreadSanitizer
  configurations. Source coverage was 75.14% line, 78.47% function, 67.95%
  region, and 88.79% non-UI line. The Universal ARM64/x86_64 build, source and
  exact bundled-tool layout validation, nested app/Sparkle signature checks,
  signed Sparkle replacement rehearsal, build metadata, SBOM, notices,
  checksums, package contents, and independent DMG verification all passed.

## Explicit limits

- Common-container conversion is currently a direct reviewed action, not a
  portable saved-workflow input contract.
- MP4 TX3G and other common-container subtitles require an explicit future text
  conversion path; they are not silently dropped or rewritten.
- Alternate output containers, chaptered WebM, attachments, arbitrary data,
  multiple video tracks, incomplete color facts, and unknown metadata remain
  fail-closed boundaries.
- Physical Intel throughput, representative Jellyfin/Plex playback, notarized
  distribution, and private-library acceptance remain separate release gates.
