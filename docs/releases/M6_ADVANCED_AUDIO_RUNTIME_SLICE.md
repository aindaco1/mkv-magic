# M6 advanced audio runtime slice

This slice establishes the reproducible Universal runtime and active capability
boundary for advanced audio. It does not yet claim user-facing conversion:
packet copy remains the default, and existing explicit audio execution remains
AAC-only until the typed planner, command, interface, and output-audit slice is
complete.

## Runtime contract

- libopus 1.6.1 is downloaded from the official Xiph archive at a pinned SHA-256,
  built as separate static `arm64` and `x86_64` libraries for macOS 13, and
  linked into the matching network-disabled FFmpeg slices.
- FFmpeg must declare `libopus`, AC-3, E-AC-3, FLAC, and AAC encoders. The build
  performs real output smokes for both architectures and fails if any is absent.
- The native experimental `opus` encoder is never an eligible fallback. Only
  stable `libopus` may satisfy the Opus capability.
- The source manifest, corresponding-source bundle, license inventory, notices,
  and CycloneDX SBOM describe the exact Opus source and static linkage.
- Tool-tree verification rejects missing or altered Opus provenance, a missing
  `--enable-libopus` configuration, unexpected dynamic linkage, or absent audio
  encoders.

## Application capability contract

The native capability probe represents AAC, Opus, AC-3, E-AC-3, and FLAC as
typed presets. Each declared encoder runs a bounded local stereo smoke encode in
a private temporary directory. A preset becomes available only after that
encode succeeds without truncated output. Cancellation propagates; other
failures remain declared but unavailable. No user media or network request is
involved.

Conservative channel boundaries are explicit: AC-3/E-AC-3 top out at 5.1;
AAC, Opus, and FLAC can retain reviewed layouts through 7.1. These boundaries
do not authorize rematrixing. The next execution slice must validate the exact
layout and must never silently downmix.

## Acceptance evidence — 2026-08-23

- A fresh pinned Universal runtime completed its internal architecture, source,
  encoder, decoder, filter, license, no-network, and audio smoke checks.
- Both FFmpeg slices declare static libopus support plus AAC, AC-3, E-AC-3, and
  FLAC, and have no dynamic libopus dependency.
- The application integration probe passed against that exact runtime and made
  all five typed audio presets available only after successful local smokes.
- Mock regressions prove a failed libopus smoke is unavailable and the
  experimental native Opus encoder is ignored.
- The normal source gate passed all 403 tests with 28 intentional no-runtime
  skips, source validation, and the Universal app build. The exact runtime ran
  all 403 with zero skips.
- Coverage passed. AddressSanitizer and ThreadSanitizer each passed all 403 tests
  without a finding.
- The package gate passed for the Universal app, both media-tool architectures,
  nested signatures, Sparkle components, update feed, SBOM, third-party notices,
  checksums, ZIP, and mounted/verified DMG.
- From the clean signed commit, the corresponding-source rehearsal verified the
  exact app source archive, manifest, documentation, and checksum-matching Opus
  1.6.1 source archive in the distributable ZIP.

This evidence does not claim Developer ID signing, Apple notarization,
publication, downloaded-app verification, private-library playback, or physical
Intel acceptance.

## Still pending

- User-facing Exact Trim and common-format Join audio choices.
- Exact layout-preserving single-generation execution and semantic output audit.
- Mixed SDR/HDR tone mapping and SDR-to-HDR conversion.
- Representative Jellyfin/Plex corpus tuning and physical Intel performance.
- Public Developer ID signing, notarization, publication, and downloaded-artifact
  verification.
