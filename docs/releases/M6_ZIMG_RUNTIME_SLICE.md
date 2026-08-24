# M6 zimg runtime slice

This slice adds the PQ-aware conversion primitive required before MKV Magic can
truthfully implement HDR10-to-SDR tone mapping. It does not expose mixed-range
conversion by itself.

## Runtime contract

- zimg 3.0.6 is downloaded from the official project archive at a pinned
  SHA-256 and built separately for ARM64 and x86_64.
- Both libraries are static, target macOS 13, and are linked into the matching
  static FFmpeg slice through a constrained `pkg-config` search path.
- FFmpeg must report `--enable-libzimg`, `zscale`, and `tonemap` in both slices.
- The runtime remains network-disabled and may not load an unpackaged zimg
  dynamic library.

The zimg license, manifest facts, SBOM component, third-party notice, and source
archive are included in the normal release and corresponding-source checks.

## Acceptance evidence

- Both ARM64 and x86_64 FFmpeg slices report `--enable-libzimg`, `zscale`, and
  `tonemap`; `otool` reports no unpackaged zimg dynamic dependency.
- The complete local gate passed with 415 tests, the exact zero-skip bundled-tool
  suite, address and thread sanitizers, coverage, package validation, SBOM, and
  corresponding-source verification.

## Still pending

- Representative Jellyfin/Plex corpus tuning and physical Intel performance.
- Public Developer ID signing, notarization, publication, and downloaded-artifact
  verification.
