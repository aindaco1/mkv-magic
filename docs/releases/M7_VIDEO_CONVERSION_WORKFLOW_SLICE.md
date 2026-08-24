# M7 portable video-conversion workflow slice

This slice makes complete-file video conversion a portable saved-workflow step
without weakening MKV Magic's lossless-first or one-generation contracts.

> The original MKV workflow boundary recorded here was extended on 2026-08-24
> to bounded MP4, M4V, MOV, and chapter-free WebM input. See
> [M7_COMMON_INPUT_SAVED_WORKFLOW_SLICE.md](M7_COMMON_INPUT_SAVED_WORKFLOW_SLICE.md).

## User contract

- **Add Step…** offers one locally recommended conversion and explicit AV1,
  HEVC, H.264, and ProRes choices.
- A recipe can contain at most one conversion card. Adding one hides the other
  conversion choices until it is removed.
- **Recommended for this Mac** follows the active verified capability order and
  the optional local Encoding Test. A fixed choice fails before execution when
  that encoder is unavailable or incompatible with the inspected HDR signal.
- Plan review names the exact resolved preset, reports one video generation and
  zero audio generations, and keeps packet-copy audio as the default.

## Portable schema and queue contract

Schema v5 persists only conversion intent. It never stores a media path, tool
path, probe result, benchmark measurement, rate control, encoder tuning, or
per-file identity. Existing v1-v4 workflows migrate without changing their
identifiers, card order, enablement, or action meaning; an older schema claiming
a v5 conversion action fails closed.

The reviewed plan summary contains the resolved codec. Automatic queue execution
re-probes the current Mac, re-inspects the unchanged input, and recompiles the
portable recipe. A changed recommendation, missing fixed encoder, incompatible
source, or other semantic-plan difference moves the job to **Needs Review**.
Both **Verify & Run** and **Add to Queue** retain the full source revision captured
when the user accepted the plan.

## One-generation composition

A conversion-only workflow calls the complete-file encoder directly. When the
same recipe also removes tracks, removes a segment title, or adds and cleans an
external subtitle, MKV Magic:

1. performs those deterministic operations in one private verified remux/clone;
2. reopens that intermediate and resolves the already reviewed conversion;
3. encodes its video exactly once into the user destination while packet-copying
   every retained audio and subtitle track;
4. reinstalls and canonically verifies the nested chapters; and
5. verifies and commits the final output, then reopens and audits it again.

The intermediate is never user-visible and is deleted with its private 0700
workspace. Its internal verify/commit events are not reported as the final job
commit. The original remains unchanged. Filename cleanup only changes the Save
panel suggestion and does not manufacture an intermediate media pass.

## Verification evidence

- Compiler regressions cover local recommendation order, fixed-encoder refusal,
  HDR-incompatible preference fallback, multiple-conversion refusal, packet-copy
  audio, codec-bearing semantic plans, and deterministic-step-before-encode
  ordering.
- Store regressions cover path-free schema-v5 round trip, v4 migration, and v4
  conversion backport refusal.
- AppKit policy regressions prove the builder exposes only one conversion intent
  at a time; queue policy explicitly admits non-interactive conversion recipes.
- A bundled-tool integration creates a real MKV with video, audio, a forced text
  subtitle, an attachment, nested chapters, and a segment title. It removes the
  title in the private preparation pass, invokes FFmpeg for video exactly once,
  verifies the retained structures, and confirms the source SHA-256 and title
  are unchanged.
- `./scripts/ci/local-gate.sh` passed on 2026-08-24: source validation, 532 tests
  with 36 expected runtime-dependent skips and zero failures, coverage policy,
  AddressSanitizer, ThreadSanitizer, Universal arm64/x86_64 packaging, packaged
  signature and DMG verification, dependency/notices manifests, launch-baseline
  enforcement, and a prior-version Sparkle replacement rehearsal.

## Explicit limits

- Saved-workflow audio was packet copy at this slice's boundary. Later
  [fused audio-policy](M7_FUSED_AUDIO_POLICY_WORKFLOW_SLICE.md) and
  [standalone audio](M7_STANDALONE_AUDIO_WORKFLOW_SLICE.md) slices added the
  explicit portable conversion policies.
- Image-subtitle OCR, data tracks, multiple video tracks, unsupported dynamic
  range, and source tags continue to fail closed under the complete-conversion
  planner.
- Physical Intel throughput and representative Jellyfin/Plex playback remain
  personal-beta acceptance work.
