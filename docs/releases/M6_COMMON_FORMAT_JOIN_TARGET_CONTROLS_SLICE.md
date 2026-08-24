# M6 common-format Join target controls slice

This records engineering acceptance of user-editable, bounded video targets in
the common-format Join review. It does not add a timeline editor or another
transcode stage: every affected video transform still compiles into one filter
graph and one encoded generation.

## User contract

For each video lane that requires normalization, the native review sheet shows:

- every encoder that passed the active local capability probe and is compatible
  with the reviewed dynamic range;
- Smaller File, Balanced, and Higher Quality tiers, with Balanced selected by
  default;
- an optional exact disclosure for AV1 RF 0–63 and SVT speed 0–13, or HEVC/H.264
  bitrate from 100–200,000 kbps; and
- the resulting codec, canvas, color target, rate control, and AV1 speed in the
  approval summary.

ProRes truthfully shows its codec-managed rate instead of a no-op quality field.
Static HDR10 lanes offer AV1 and HEVC only. The reviewed largest even canvas,
source timing, nested chapters, packet-copy lanes, metadata, and attachments stay
unchanged by a codec or quality selection.

## Safety and execution contract

The initially recommended codec is a default, not an artificial execution lock.
A replacement must still be present in the actively verified capability set and
pass the existing typed resolver. The resolver continues to reject unavailable
encoders, invalid codec/rate/tuning combinations, unsupported HDR targets,
changed sources, a changed canvas or timing policy, and unexpected choices.

Every edit clears the approval checkbox and resolves a fresh immutable plan.
The command compiler accepts the reviewed codec instead of assuming the initial
recommendation, but still emits one bounded argument array directly to FFmpeg,
one fused graph, and one encoded output per affected video lane. Free-form
arguments and shell execution remain unavailable. The intermediate and final
semantic auditors compare their outputs against the replacement reviewed target.

## Verification contract

Regression coverage binds the visible format, tier, exact bitrate, AV1 RF, and
SVT speed controls to the resolved plan; proves invalid input disables approval;
accepts a verified replacement codec at the resolver; and asserts the emitted
FFmpeg encoder and rate-control arguments. The real bundled-tool Join fixture
starts with AV1 as the proposal recommendation, intentionally selects HEVC, then
decodes, audits, commits, assembles, and reopens the result without changing its
sources.

The normal source gate, exact Universal runtime, sanitizers, coverage, and
packaging gate are required before this slice is landed.

## Acceptance evidence — 2026-08-23

- The normal source gate passed all 400 tests with 28 intentional no-runtime
  skips, source validation, and the Universal arm64/x86_64 application build.
- The pinned Universal runtime passed all 400 tests with zero skips. The real
  replacement-codec fixture began with an AV1 recommendation, selected HEVC,
  decoded and semantically audited the normalized output, committed it through
  the verified-output transaction, assembled the final MKV, reopened it, and
  left both source digests unchanged.
- Coverage passed. AddressSanitizer and ThreadSanitizer each passed all 400 tests
  without a finding.
- The package gate passed for the Universal app, both media-tool architectures,
  nested signatures, Sparkle components, update feed, SBOM, third-party notices,
  checksums, ZIP, and mounted/verified DMG.
- The AppKit regression and inspected rendering cover AV1 and HEVC selection,
  quality tiers, exact values, invalid-input approval reset, and the expanded
  controls at the supported minimum window size.
- These are local engineering and ad-hoc-signing results. They do not claim
  public Developer ID signing, Apple notarization, publication, download, or
  private-library playback acceptance.

## Still pending

- Opus, AC-3, E-AC-3, and lossless advanced audio presets.
- Mixed SDR/HDR tone mapping and SDR-to-HDR conversion.
- Representative Jellyfin/Plex corpus tuning and physical Intel performance.
- Public Developer ID signing, notarization, publication, and downloaded-artifact
  verification.
