# M5 common-format join planner slice

This records engineering and native-review acceptance of the first deterministic
common-format proposal for joined sources. It is intentionally a planning slice:
normalization cannot be saved or executed yet, and this document does not claim
an AV1/AAC encoder, HDR output verification, attachment decisions, public
release, or physical Intel acceptance.

## Planning contract

The planner consumes the same exhaustive track mapping and current compatibility
report used by strict joins. It recomputes the report and rejects a reviewed
report whose facts changed. Its proposal is independent of AppKit.

- Compatible video and audio lanes remain packet-copy append lanes.
- An incompatible video lane encodes each present source segment once into one
  fused output generation. The default proposal is AV1 10-bit, a fit-and-pad
  canvas matching the largest source frame, source-timed cadence, and an
  explicitly reviewed SDR or HDR10 target.
- Multiple affected video segments or video operations do not create multiple
  generations. The plan impact remains `1 video generation` for the final
  output.
- An incompatible audio lane converts each present source segment once to AAC.
  It chooses the largest source channel layout, the highest inspected sample
  rate, and the documented 96/192/512/640 kbps mono/stereo/5.1/7.1 policy.
- A missing audio segment becomes silence only after an explicit choice. No
  available program content is upmixed, and no downmix occurs automatically.
- Compatible subtitle packets are rebased on the joined timeline. Mixed
  supported text formats may normalize once to ASS. Image or unsupported
  subtitle conversion is blocked; OCR is not proposed.
- Attachment, track-metadata, missing-lane, variable-frame-rate, video-target,
  audio-target, and mixed-dynamic-range decisions remain explicit proposal
  requirements.

## HDR and incomplete-fact safety

Uniform SDR recommends SDR. Uniform HDR10 recommends HDR10. Mixed SDR/HDR offers
SDR tone mapping or an HDR10 signal without silently selecting either. Dolby
Vision, HDR10+, HLG/other unsupported HDR facts, unknown dynamic range, missing
video, and incomplete copy parameters block advancement. This is deliberately
stricter than assuming an FFmpeg command will preserve metadata it cannot prove.

## Native review

The existing **Join Files…** review gains a **COMMON-FORMAT OPTION** section. It
shows each affected lane, the recommended common target, the bounded video/audio
encode count, silence disclosure, the first blocker, and the fact that every
target still needs explicit approval. `Continue to Save…` remains disabled for
every non-lossless proposal, so the UI cannot imply that the encoder exists.

## Regression evidence

Nine planner regressions cover zero-encode compatible lanes; one AV1 generation
for incompatible video; largest-layout AAC conversion; confirmed silence for a
missing audio segment; explicit mixed SDR/HDR choice; Dolby Vision refusal;
image-subtitle refusal; incomplete-copy refusal; and stale reviewed reports. A
native AppKit regression proves that an AAC normalization preview is rendered
while the save action remains disabled.

The standard source-validation gate passes all 262 tests with 14 intentional
real-tool skips and builds the Universal `arm64`/`x86_64` app. The full bundled-
tool suite passes all 262 tests with zero skips and zero failures. The isolated
complete local gate also passes coverage, AddressSanitizer, ThreadSanitizer,
inside-out signatures and entitlements, SBOM/checksums, ZIP/appcast assembly,
and verified sandboxed DMG packaging.

## Still pending

- Concrete choice controls and a revision-bound normalization preview.
- Fused FFmpeg filter-graph and command rendering.
- Bundled SVT-AV1 and AAC encoder execution plus cancellation.
- HDR10 metadata transfer and strict output verification.
- Final MKV mux, exact nested chapter verification, and verified commit.
- Private-library and physical Intel performance acceptance.
