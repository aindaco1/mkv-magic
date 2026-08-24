# M6 mixed HDR10 and SDR tone-mapping slice

This slice adds one bounded conversion contract for common-format Join: a lane
containing validated static HDR10 and BT.709 SDR defaults to a final BT.709 SDR
signal. It does not add SDR-to-HDR conversion, HDR10+, HLG, Dolby Vision
transcoding, crossfades, or another encoded generation.

## Planning and review contract

- Every SDR source must have an explicit limited-range BT.709 signal.
- Every HDR source must satisfy the existing static 10-bit BT.2020/PQ contract;
  incomplete or unsupported HDR facts still fail before execution.
- The native common-format review says that only HDR10 Parts will be tone-mapped,
  shows the final SDR target, and requires the same explicit approval as every
  other resolved Join choice.
- AV1, HEVC, H.264, and ProRes remain eligible only when their local encoder probe
  passes. The user can still change the codec and bounded quality controls
  without adding an encode stage.

## One-generation execution contract

Each SDR Part follows the existing scale, pad, pixel-format, and BT.709 path.
Each HDR10 Part is explicitly treated as limited BT.2020/PQ, converted to linear
floating-point light with zimg, tone-mapped with the Mobius operator and bounded
desaturation, converted to limited BT.709, and then fed into the same concat
graph. Peak luminance comes from reviewed content-light metadata, then mastering
metadata, with a bounded 1,000-nit fallback when neither optional block exists.

All Part transforms, concat, and codec output remain in one FFmpeg invocation and
one encoded video generation. `tonemap` and `zscale` are required only for this
mixed-range path; their absence cannot disable unrelated Join work. No shell or
free-form filter input is accepted.

## Verification and failure behavior

The intermediate and committed outputs must reopen as the reviewed codec,
dimensions, bit depth, duration, and limited BT.709 SDR signal, with no mastering,
content-light, or HDR-format residue. Source revisions and SHA-256 fixture digests
must remain unchanged. Missing filters, changed sources, incomplete signals,
unexpected HDR output, or any normal verified-output audit failure prevents a
destination from being committed.

## Acceptance evidence

- Planner, resolver, command-graph, capability-regression, native review, and
  verification regressions cover the mixed-range contract.
- A real bundled-tool transaction joins one generated BT.709 H.264 Part and one
  static HDR10 HEVC Part, tone-maps only the HDR Part, reopens a verified BT.709
  H.264 MKV, and confirms both source digests are unchanged.

### 2026-08-23 gate results

- The normal source gate passed all 418 tests with 30 intentional no-runtime
  skips, source validation, and the Universal application build.
- The exact pinned Universal runtime passed all 418 tests with zero skips.
- AddressSanitizer and ThreadSanitizer each passed all 418 tests. Coverage also
  passed.
- The package gate passed the Universal app, both architecture-specific media
  tool trees, nested signatures, Sparkle components, update feed, SBOM,
  corresponding source, third-party notices, checksums, ZIP, and mounted and
  verified DMG.
- The native review was rendered and inspected at its supported minimum size;
  its tone-mapping disclosure, target controls, review text, approval, and save
  actions fit without clipping.
- GitHub-hosted CI and CodeQL could not start because the account reported a
  payment or spending-limit block. This is local engineering and ad-hoc signing
  evidence, not public Developer ID, notarization, publication, download, or
  private-library playback acceptance.

## Still pending

- Representative Jellyfin and Plex playback tuning with private-library media.
- Visual tuning against reference displays and a broader range of HDR peak
  luminance values.
- Physical Intel performance and thermal acceptance.
- Public Developer ID signing, notarization, publication, and downloaded-artifact
  verification.
