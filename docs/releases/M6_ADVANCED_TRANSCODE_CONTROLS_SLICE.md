# M6 advanced transcode controls slice

This records engineering acceptance of the first user-facing advanced video
control surface. It is intentionally bounded: MKV Magic still does not accept
free-form FFmpeg options, and this slice does not claim advanced audio formats,
mixed SDR/HDR conversion, private-library tuning, physical Intel acceptance, or
a public signed/notarized release.

## User contract

Exact Trim keeps the lightweight default experience:

- **Balanced** is selected initially.
- **Smaller File** and **Higher Quality** offer understandable alternatives.
- **Show exact encoding controls** is optional and collapsed initially.
- AV1 exposes RF 0–63 and SVT speed 0–13. The labels explain that lower values
  mean higher quality or better compression at the cost of time.
- HEVC and H.264 expose a bounded 100–200,000 kbps bitrate.
- ProRes retains its reviewed codec-managed profile and does not show a control
  that would have no effect.

Static HDR10 sources show only AV1 and HEVC choices. Packet-copy audio remains
the default, and AAC remains an explicit one-generation option.

## Planning and execution contract

The reviewed rate control and encoder tuning are typed, Codable plan values.
Exact Trim and common-format Join pass them through one shared encoder compiler.
The compiler accepts only the matching combination and emits argument arrays
directly to `Process`; no shell or free-form argument string is involved.

SVT preset 8 remains the deterministic default. A reviewed preset from 0 through
13 replaces only that value. An out-of-range preset, an SVT preset attached to a
non-AV1 codec, an invalid RF/bitrate, a stale source, or an unavailable encoder
fails before output commit. Legacy serialized choices that lack the new tuning
field decode to the codec default instead of becoming unreadable.

## Verification

Regression tests bind the visible AppKit controls to the reviewed plan, exercise
plain-language and exact values, validate legacy decoding, reject invalid codec
combinations, and assert the final FFmpeg argument array for Exact Trim and Join.
The full normal and exact-runtime gates are required before this slice is landed.

## Acceptance evidence — 2026-08-23

- The normal source gate passed all 397 tests with 28 intentional no-runtime
  skips, source validation, and the Universal arm64/x86_64 application build.
- The fresh pinned Universal runtime passed all 397 tests with zero skips. Real
  AV1 Exact Trim and uniform-HDR Join fixtures both completed with a reviewed
  non-default SVT preset and preserved their existing semantic contracts.
- Coverage passed. AddressSanitizer and ThreadSanitizer each passed all 397
  tests without a finding.
- The package gate passed for the Universal app, both architecture-specific
  media tool trees, nested signatures, Sparkle components, update feed, SBOM,
  third-party notices, checksums, ZIP, and mounted/verified DMG.
- The visual regression and manual image inspection cover the collapsed simple
  path and expanded exact HEVC control at the supported minimum window size.
- These are local engineering and ad-hoc-signing results. They do not claim
  public Developer ID signing, Apple notarization, publication, download, or
  private-library playback acceptance.

## Still pending

- SDR-to-HDR conversion.
- Representative Jellyfin/Plex corpus tuning and physical Intel performance.
- Public Developer ID signing, notarization, publication, and downloaded-artifact
  verification.
