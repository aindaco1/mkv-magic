# M6 Universal AV1 runtime slice

This records engineering acceptance of MKV Magic's pinned software AV1 encode
and decode runtime on the Apple Silicon reference Mac and under Rosetta. At this
checkpoint it did not claim physical Intel performance acceptance, HDR10
transcoding, or a public signed/notarized release. The subsequent timed
recommendation work is recorded in `M6_ENCODING_BENCHMARK_SLICE.md`.

## Runtime contract

- FFmpeg 9.0.1 is built separately for `arm64` and `x86_64` with network
  protocols and ambient dependency discovery disabled and a macOS 13 deployment
  target.
- SVT-AV1 4.1.0 is built as a checksum-pinned static library for each slice with
  native-build specialization disabled and runtime CPU dispatch retained.
- dav1d 1.5.4 is built as a checksum-pinned static library for each slice. It
  gives Macs without AV1 decode hardware a software path for AV1 inputs and for
  outputs MKV Magic creates itself.
- The only non-system dynamic library in the media-tool runtime remains the
  packaged, replaceable Qt Core dependency used by MKVToolNix. Neither AV1
  library creates a separate dynamic dependency or an ambient Homebrew
  requirement.
- Runtime assembly refuses a missing tool, architecture mismatch, wrong minimum
  OS, source-manifest drift, missing license, hash mismatch, unsafe symlink,
  unbundled dynamic dependency, missing required encoder/filter/decoder, or
  enabled network protocol.

Each architecture must complete a real 64x64 10-bit AV1 encode with
`libsvtav1` preset 8 and then force-decode that bitstream with `libdav1d` before
the runtime is accepted. This is a behavioral gate, not a capability-listing
check.

## Application behavior

- The existing bounded local encoder probe now actively verifies
  `libsvtav1`; only a successful one-frame encode exposes AV1 to the user.
- Verified AV1 remains the preferred quality/size preset. Verified 10-bit HEVC
  VideoToolbox remains the faster fallback for slow or unsupported Intel Macs,
  with H.264 and ProRes available lower in the existing priority order.
- The shared SDR video argument compiler explicitly pins the reviewed balanced
  SVT preset 8 instead of inheriting a version-dependent upstream default.
- Join normalization and Exact Trim continue to compile all requested video
  work into one encoded generation. Metadata-only, remux, packet-copy, and
  property-edit paths remain unchanged and still avoid transcoding.
- A native AppKit regression verifies that usable AV1 is presented as the
  preferred choice while the existing unavailable-AV1 UI still presents the
  verified HEVC fallback truthfully.

## Supply-chain and licensing boundary

- `SOURCES.json` records the exact upstream URLs, SHA-256 hashes, licenses,
  static-linkage declarations, FFmpeg configure boundary, and per-library build
  settings.
- Tool bundles contain the SVT-AV1 software and patent licenses plus the dav1d
  BSD-2-Clause license. Third-party notices describe their purpose and linkage.
- CycloneDX generation includes separate static-library components for SVT-AV1
  and dav1d. Corresponding-source generation verifies and packages both pinned
  archives alongside FFmpeg, MKVToolNix, Qt, NASM, and the exact app source.
- CI and release workflows install only the declared build-time CMake, Meson,
  Ninja, and pkg-config dependencies; released media processing stays local and
  self-contained.

## Regression evidence

The normal source gate passes all 359 tests with 24 intentional real-tool skips
and builds the Universal `arm64`/`x86_64` app. Shell scripts pass ShellCheck and
the source tree passes formatting, package resolution, dependency-policy,
forbidden-API, license, and static security checks.

A fresh runtime was built from the pinned archives outside iCloud Drive. Both
slices passed architecture, signature, deployment-target, manifest, license,
dynamic-linkage, network-protocol, required-feature, real 10-bit SVT encode, and
forced dav1d decode checks. The x86_64 slice executed under Rosetta; this is not
a substitute for a physical Intel performance run.

The exact-runtime suite then passed all 359 tests with zero skips and zero
failures. That includes the complete AV1 Exact Trim transaction, real Join
normalization and assembly, chapter editing/suggestions/thumbnails, subtitle
cleanup and muxing, track/segment edits, attachment preservation, source-byte
preservation, and post-commit reopen audits.

The isolated complete local gate also passed coverage collection,
AddressSanitizer, ThreadSanitizer, Universal app assembly with the exact runtime,
inside-out nested signing, entitlement checks, Sparkle update ZIP and appcast,
CycloneDX SBOM and artifact checksums, personal-path leak checks, and a mounted,
checksum-verified sandboxed DMG.

The full test exposed and prevented one important integration defect: FFmpeg's
built-in AV1 decoder attempted hardware decoding on the M1 reference Mac and
could not decode the app's new AV1 output. Adding the static dav1d path changed
that failure into a passing end-to-end application transaction and a permanent
two-architecture runtime-build regression.

## Still pending after the companion benchmark slice

- Performance/thermal tuning with representative beta files on the M1 reference
  Mac and at least one physical Intel Mac.
- User-facing advanced AV1 quality and speed controls backed by measured beta
  defaults; preset 8 is the explicit balanced engineering default for now.
- HDR10 transcode preservation and verification, mixed HDR/SDR decisions, and
  Dolby Vision fail-safe UX.
- A public Developer ID-signed, Apple-notarized release and downloaded-artifact
  verification.
