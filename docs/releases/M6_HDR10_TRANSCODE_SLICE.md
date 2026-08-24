# M6 static HDR10 transcode preservation slice

This records engineering acceptance of one bounded HDR10 preservation contract
for Exact Trim and uniform-HDR common-format Join. It does not claim tone
mapping, SDR-to-HDR conversion, HDR10+, HLG, Dolby Vision transcoding, private
library acceptance, physical Intel performance acceptance, or a public
signed/notarized release.

## Accepted signal

An executable static HDR10 source must be a video track with:

- at least 10-bit samples;
- limited (`tv`) range;
- BT.2020 primaries;
- SMPTE ST 2084/PQ transfer;
- BT.2020 non-constant-luminance matrix coefficients; and
- no HDR10+, HLG, Dolby Vision, or unknown HDR marker.

When FFprobe reports SMPTE ST 2086 mastering-display or CTA-861.3 content-light
side data, MKV Magic normalizes the exact bounded rational values into a stable
integer model. A declared static metadata block that cannot be parsed completely
is not treated as safely preservable.

## One-generation execution

- Exact Trim accepts the reviewed static HDR10 signal only with verified AV1 or
  HEVC 10-bit output and preserves the numeric range in one video generation.
- Common-format Join accepts uniform static HDR10 only when every source in the
  lane has the same mastering-display and content-light values. Scaling, padding,
  pixel-format conversion, signal annotation, and concatenation remain fused in
  one FFmpeg filter graph and one encoded generation.
- FFmpeg receives the exact MDCV/CLL values before each affected input, explicit
  limited-range BT.2020/PQ frame properties, explicit output color properties,
  and a 10-bit pixel format. SVT-AV1 also receives explicit color parameters.
- Audio, compatible media lanes, metadata edits, and packet-copy paths retain
  their existing no-extra-generation behavior.

## Codec boundary

The pinned FFmpeg 9.0.1 and SVT-AV1 4.1.0 sources and the exact bundled runtime
were checked together. AV1 carries BT.2020/PQ plus MDCV/CLL in the encoded AV1
stream and in Matroska. HEVC VideoToolbox carries the reviewed signal in Matroska
container metadata, but the extracted raw HEVC elementary stream did not retain
MDCV/CLL in this runtime. MKV Magic therefore guarantees HEVC HDR10 preservation
only for its default MKV output and makes no raw-bitstream preservation claim.

## Verification and failure behavior

Temporary output and the committed saved path are both reopened. Verification
requires the reviewed codec, dimensions, 10-bit depth, limited BT.2020/PQ matrix
signal, and exact optional mastering/content-light values. A one-unit metadata
drift fails verification. Changed sources, incomplete static metadata, differing
joined metadata, non-AV1/HEVC HDR targets, unsupported HDR formats, or an output
that loses the signal fail before commit.

Pure regressions cover exact rational parsing, malformed metadata, HDR10+/Dolby
Vision refusal, preset restrictions, exact FFmpeg arguments, mixed SDR/HDR
refusal, planner metadata mismatch, and post-encode signal drift. Real
bundled-tool fixtures prove both Exact Trim and common-format Join preserve the
static signal while leaving the input hashes unchanged. The complete normal,
exact-runtime, sanitizer, Universal packaging, signing, update, SBOM, checksum,
and mounted-DMG gates are rerun for this high-risk media slice.

## Acceptance evidence — 2026-08-23

- The normal source gate passed 389 tests with 28 intentional bundled-runtime
  skips, source validation, and a Universal application build.
- The fresh pinned Universal runtime passed all 389 tests with zero skips. The
  runtime-backed AV1 fixtures exercised both Exact Trim and common-format Join
  and verified exact BT.2020/PQ, MDCV, and CLL output metadata.
- The complete local gate passed coverage plus all 389 tests under AddressSanitizer
  and all 389 tests under ThreadSanitizer.
- The package gate passed for the Universal app, both architecture-specific tool
  trees, nested code signatures, update feed, SBOM, third-party notices,
  checksums, ZIP, and mounted/verified DMG.
- This is engineering evidence from an ad-hoc-signed package gate. It is not
  evidence of Developer ID signing, Apple notarization, publication, download,
  or real-library playback acceptance.

## Still pending

- Mixed SDR/HDR tone mapping and explicit SDR-to-HDR conversion.
- HDR10+, HLG, and Dolby Vision transcode contracts.
- Representative private-library Jellyfin/Plex playback acceptance.
- Long-duration thermal and performance tuning on Apple Silicon and a physical
  Intel Mac.
- Public Developer ID signing, Apple notarization, update testing, and
  downloaded-artifact verification.
