# M5 encoder capability slice

This records engineering acceptance of the local encoder/filter capability
boundary used by common-format Join planning. It does not claim normalization
execution, a bundled AV1 encoder, a public release, or physical Intel acceptance.

## Capability contract

- MKV Magic resolves only the signed bundled FFmpeg selected by its runtime
  catalog; it does not search `PATH`, Homebrew, or another ambient installation.
- The probe reads bounded, non-truncated encoder and filter listings. A declared
  encoder is not considered available until it completes a bounded one-frame
  encode on the running Mac.
- Smoke inputs are tiny generated raw frames and PCM samples inside a shared
  private `0700` temporary workspace. No user media, filename, upload, network
  access, benchmark corpus, or retained probe output is involved.
- Cancellation propagates. A declared encoder that fails its smoke encode stays
  visible to diagnostics as `declared` but is excluded from user choices.
- Join additionally requires `concat`, `scale`, `pad`, `format`, `setpts`,
  `setsar`, `aformat`, `aresample`, `asetpts`, `atrim`, `channelmap`, and
  `anullsrc`; a missing required filter blocks the common-format preview from
  advancing.

## Current bundled-runtime result

The pinned FFmpeg runtime actively verifies HEVC 10-bit VideoToolbox, H.264
VideoToolbox, ProRes, and AAC on the Apple Silicon reference Mac. It contains an
AV1 decoder but no `libsvtav1`, libaom, rav1e, or other AV1 encoder. Consequently:

- AV1 remains the product's preferred quality/size target for a future pinned
  software sidecar, but it is not currently selectable or described as usable.
- HEVC 10-bit VideoToolbox is the current verified common-format video fallback.
- H.264 and ProRes remain lower-priority verified choices for later explicit
  controls.
- AAC is verified independently before any audio-normalization recommendation.

The runtime build script now requires the expected AAC, VideoToolbox, ProRes,
and join-filter declarations in both architecture trees. App launch still
performs the active machine-specific smoke test because a compiled encoder can
fail on hardware where it is declared.

## Native review and fail-closed behavior

The Join setup probes once and caches a successful result for that app session.
Its common-format proposal uses the highest-priority actively verified preset.
When AV1 is absent and HEVC succeeds, the review names one HEVC 10-bit
VideoToolbox generation and explicitly explains the AV1-to-HEVC fallback. If no
video encoder, AAC encoder, or required filter verifies, the review displays a
specific blocker. Common-format saving remains disabled because concrete choice,
execution, and output-verification work is still pending.

## Regression evidence

Unit regressions cover verified priority ordering, declared-but-failing encoder
fallback, truncated-listing refusal, private temporary-directory permissions,
cleanup after both success and failure, and unsafe prefix rejection. A bundled-
tool integration test proves the current encoder/filter result. A native AppKit
regression proves that HEVC—not AV1—is shown as the verified fallback and that
the save action remains disabled.

The standard source gate passes all 270 tests with 15 intentional bundled-tool
skips and builds the Universal `arm64`/`x86_64` app. The full bundled-tool suite
passes all 270 tests with zero skips and zero failures. The isolated complete
local gate also passes coverage collection, AddressSanitizer, ThreadSanitizer,
inside-out signatures and entitlement checks, SBOM/checksums, ZIP/appcast
assembly, and verified sandboxed DMG packaging. Public notarization and
real-library beta acceptance remain separate delivery gates.

## Still pending

- Pinned, Universal-compatible SVT-AV1 sidecar build and licensing evidence.
- User-facing common-format choice controls and a complete execution preview.
- Progress, cancellation, and transactional execution of the fused FFmpeg
  command described in `M5_FUSED_NORMALIZATION_COMMAND_SLICE.md`.
- Strict HDR10, audio layout, final MKV, chapter, and decode-boundary output
  verification.
- Physical Intel capability and performance acceptance.
