# M7 lossless-first conditional conversion slice

This slice implements the workflow condition from the product example:
**convert video only when it is not already AV1 or HEVC**.

## User contract

- **Add Step…** offers **If needed: Convert video unless it is already AV1 or
  HEVC** alongside the unconditional recommended and fixed-codec cards.
- For inspected AV1, HEVC, H.265, or H.265-labeled video, the card reports that
  the modern video is already satisfied and adds no encode stage.
- A dependent audio card also skips in that case, preserving every audio track
  byte-for-byte. Other applicable title, subtitle, track, or naming work still
  compiles through its normal zero-video-generation path.
- For an older codec, the card resolves the first source-compatible encoder from
  the current Mac's verified recommendation order. Optional audio conversion is
  fused exactly as in the schema-v6 audio-policy slice.

## Planning and queue contract

The condition reads only the inspected primary video codec. It does not infer
quality from a filename or probe the network. When AV1/HEVC satisfies the card,
plan review does not run the local encoder smoke probe at all. When conversion
is needed, the reviewed plan binds the resolved codec, audio policy, one-video-
generation impact, and exact inspected source revision.

Automatic queue execution reopens the unchanged input and evaluates the same
portable condition again. Any source-revision or semantic-plan difference moves
the job to **Needs Review**; it cannot silently switch between copy and encode.

## Portable schema

Schema v7 stores only the condition's action identifier. It retains no observed
codec, encoder result, path, media identity, or per-run choice. Valid v1-v6
recipes migrate without identity or meaning changes, while a v6 file claiming
the v7 condition fails closed.

## Verification evidence

- Compiler regressions prove HEVC takes the zero-encode branch without probing
  capabilities, dependent audio remains packet copy, and simultaneous title
  removal still uses only `mkvpropedit` plus verification and commit.
- A second compiler regression proves H.264 takes the encode branch, resolves
  the current HEVC recommendation, and fuses one Opus audio generation.
- Store coverage proves a path-free schema-v7 round trip, v6 migration, and v6
  conditional-action backport refusal.
- AppKit catalog coverage keeps the conditional beside the other mutually
  exclusive video choices.
- `./scripts/ci/local-gate.sh` passed on 2026-08-24: source validation, 540 tests
  with 36 expected runtime-dependent skips and zero failures, coverage policy,
  AddressSanitizer, ThreadSanitizer, Universal arm64/x86_64 packaging, packaged
  signature and DMG verification, dependency/notices manifests and SBOM,
  launch-baseline enforcement, and a prior-version Sparkle replacement rehearsal.

## Explicit limits

- The condition currently recognizes codec identity only. Resolution, bitrate,
  bit depth, profile, and quality thresholds are not guessed.
- AV1/HEVC sources are preserved even if a different encode might be smaller.
  An unconditional fixed or recommended card remains available for that intent.
- Physical Intel and representative Jellyfin/Plex playback remain personal-beta
  acceptance work.
