# M0 release rehearsal

This document records a private release-pipeline rehearsal. It is evidence for
the release machinery, not a public MKV Magic release or user acceptance.

## Rehearsed build

- Date: 2026-08-22
- Product version: `0.0.0` (non-release fixture)
- Source commit: `373d359ef20c6b4cd742ec33c8ca6391072d6d26`
- Minimum system: macOS 13
- Application architectures: `arm64` and `x86_64`
- Bundled FFmpeg: 9.0.1
- Bundled MKVToolNix: 100.0
- Bundled Qt Core: 6.11.1

## Observed results

- The Universal application and its nested code passed strict Developer ID
  signature and reviewed-entitlement checks.
- Apple notarization returned `Accepted` independently for the application and
  DMG. Both tickets stapled successfully.
- Gatekeeper accepted the stapled application and DMG as Notarized Developer
  ID software.
- The mounted DMG passed its checksum and layout checks.
- The application executed bundled `ffmpeg`, `ffprobe`, `mkvmerge`,
  `mkvpropedit`, and `mkvextract` successfully as native Apple Silicon code and
  as Intel code under Rosetta.
- The runtime source build, tool manifests, packaged licenses, dynamic-library
  closure, and minimum deployment targets passed the automated checks.
- Hosted CI independently passed coverage, sanitizer, and full Universal media
  runtime jobs for the rehearsed commit. A missing hosted-runner `rg`
  dependency was identified in the source job and added to the workflow.

## Deliberately not claimed

- No public GitHub release or updater feed was published.
- No installation or end-to-end media workflow was accepted on a physical
  Intel Mac.
- No update from an older installed MKV Magic release was exercised.
- The `0.0.0` fixture is not suitable for users.

Those three acceptance paths remain mandatory before the first public release.
