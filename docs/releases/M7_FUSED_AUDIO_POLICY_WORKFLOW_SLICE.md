# M7 fused audio-policy workflow slice

This slice adds explicit audio conversion to portable saved workflows without
changing packet copy as the default or adding another FFmpeg process.

## User contract

- After one video-conversion card exists, **Add Step…** offers AAC, Opus, AC-3,
  E-AC-3, and FLAC audio cards.
- A recipe can contain at most one video card and one dependent audio card.
  Removing or disabling the video card removes or disables its audio card;
  enabling the audio card re-enables the existing video card.
- The audio card applies one target to every retained audio track. Tracks already
  in that codec remain packet copies; plan review reports one video generation
  plus the exact number of mismatched audio tracks encoded once.
- Packet-copy audio remains the safe default when no audio card is present. A
  file with no audio marks the dependent card skipped.

## Capability and preservation contract

When at least one track differs, the active bundled-runtime probe must verify the
explicit audio encoder. Every mismatched source audio track must expose a known
channel count, channel layout, and sample rate that the chosen preset can
represent without implicit downmix or rematrix.
AAC, AC-3, E-AC-3, and FLAC retain accepted sample rates; Opus explicitly uses
its reviewed 48 kHz Matroska clock. Any unavailable encoder or incompatible
track fails during plan review, before a destination is created.

Video and audio choices resolve through the existing complete-file exact
planner. The executor emits one FFmpeg invocation: video is encoded once, every
mismatched retained audio track is encoded once, and matching audio plus
subtitles are packet-copied and fingerprinted. Attachments, nested chapters, track metadata, HDR10, source
revision, and the existing pre-commit/post-reopen audits retain their prior
contracts. Deterministic track, subtitle, and title work still occurs in one
private verified preparation pass before that single encoding process.

## Portable schema and DRY migration

Schema v6 persists only the explicit audio-format intent. It stores no encoder
name, capability result, media path, track identity, layout, sample rate,
bitrate, or other inspected fact. Queue reinspection re-resolves both current
capability lists and requires the same audio-policy-bearing semantic plan.

The workflow migrator now uses each action's minimum schema version instead of
duplicating an expanding action blacklist for every historical version. Valid
v1-v5 recipes migrate without changing identifiers, card order, enablement, or
meaning; an older schema claiming a newer action fails closed.

## Verification evidence

- Compiler regressions cover the video dependency, one-audio-card limit, local
  encoder refusal, layout/rematrix refusal, codec-bearing plan summary, and
  exact audio-generation impact.
- Store regressions prove path-free schema-v6 round trip, v5 migration, and v5
  audio-action backport refusal.
- AppKit policy regressions cover authoring visibility plus removal and
  enablement dependencies.
- A pinned-runtime integration performs title cleanup, one H.264 video encode,
  and one FLAC audio encode in exactly one FFmpeg invocation while retaining a
  forced subtitle, attachment, nested chapter, metadata, and the unchanged
  source digest.
- A second pinned-runtime integration executes the same portable recipe through
  automatic queue reinspection and records one video generation and one encoded
  audio track in privacy-safe History.
- `./scripts/ci/local-gate.sh` passed on 2026-08-24: source validation, 537 tests
  with 36 expected runtime-dependent skips and zero failures, coverage policy,
  AddressSanitizer, ThreadSanitizer, Universal arm64/x86_64 packaging, packaged
  signature and DMG verification, dependency/notices manifests and SBOM,
  launch-baseline enforcement, and a prior-version Sparkle replacement rehearsal.

## Explicit limits

- This card depends on full-file video conversion. It does not claim standalone
  audio-only workflow conversion.
- It applies one target format to every retained audio track and automatically
  copies matching codecs. User-authored per-track policies and arbitrary codec
  predicates remain unimplemented.
- Physical Intel throughput and representative Jellyfin/Plex playback remain
  personal-beta acceptance work.
