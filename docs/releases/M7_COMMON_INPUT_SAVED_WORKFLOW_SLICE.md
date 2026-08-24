# M7 common-input saved-workflow slice

Date: 2026-08-24

## Delivered contract

Portable saved workflows now apply the existing verified complete-file
conversion path to bounded MP4, M4V, MOV, and chapter-free WebM sources. The
portable JSON remains unchanged: it stores only schema-v9 action intent and no
source path, track identity, capability result, bitrate, or media metadata.
Review resolves the recipe against the inspected file and the encoders that
passed the current Mac's local probe.

For common-container input, exactly one enabled video-conversion card must actually
apply. The recipe may also contain one audio-conversion card and filename
cleanup. Video and every mismatched audio track are encoded together in one
FFmpeg process; matching audio remains a packet copy. Filename cleanup affects
only the reviewed Save-panel suggestion, whose extension is forced to `.mkv`.
There is no private MKV preparation pass for this composition.

## Fail-closed composition

Common input cannot combine conversion with track removal, segment-title edits,
external subtitle muxing or cleanup, or other MKV-only structural work. Those
cards require a later workflow against the verified MKV. A conditional
conversion that finds common-container video already encoded as AV1 or HEVC also
stops for review: it cannot quietly turn into an unchanged `.mp4` copy while the
user expects an MKV conversion. Unsupported structures, metadata, chapters,
color/HDR facts, or packet-copy audio surface the exact complete-conversion
planner error.

The lightweight capability preflight mirrors this boundary. An invalid common
composition is rejected before MKV Magic spends time probing encoders. Container
recognition remains separate from structural validation so review can report the
specific unsafe media fact rather than a misleading generic-container error.

## Automatic queue and verification

The existing automatic saved-workflow queue admits the reviewed recipe as
video-heavy work. Admission restores the security-scoped input, proves its
filesystem revision unchanged, re-inspects it, repeats the encoder capability
probe, recompiles the portable intent, and requires the same semantic plan. The
direct saved-workflow video executor then performs exactly one complete-file
encode into Matroska. Its existing transaction verifies stream order, selected
codecs, language and title metadata, translated MP4/MOV chapters, copied-audio
packet fingerprints, source revision, temporary output, committed output, and
the final reopen audit. Trash remains off by default and can occur only after
durable verified success.

## Regression evidence

- Compiler tests cover one fused video/audio process, `.mkv` output intent,
  filename cleanup, no deterministic intermediate, invalid MKV-edit composition,
  standalone-audio refusal, conditional-conversion refusal, preflight behavior,
  and exact common-metadata failure propagation.
- Exact-conversion tests distinguish container recognition from full structural
  eligibility and retain the existing MP4/MOV/WebM preservation boundaries.
- A pinned bundled-tool application integration creates a real BT.709 H.264/AAC
  MP4, queues a portable H.264-plus-FLAC workflow, re-inspects and recompiles it,
  produces a verified MKV, preserves the segment and audio titles, proves the
  source digest unchanged, and records one video generation and one audio
  conversion through **Waiting -> Running -> Succeeded**.
- The complete local gate passed with the pinned full Universal runtime: 603
  tests and zero skips or failures in each of the normal, coverage,
  AddressSanitizer, and ThreadSanitizer runs. Coverage measured 75.20% lines,
  78.54% functions, 68.03% regions, and 88.86% non-UI lines. Universal release
  packaging, nested-code signature checks, Sparkle replacement, SBOM and
  manifest checks, archive hashes, and DMG verification also passed.

## Explicit limits

- MP4 timed text, other common-container subtitles, attachments, arbitrary data,
  multiple video tracks, chaptered WebM, unknown metadata, and unsupported HDR
  remain outside the accepted complete-conversion boundary.
- A common input must become a verified MKV before MKV-only cleanup cards can be
  applied. Crossfades, transitions, alternate output containers, and chained
  transcode generations are not introduced.
- Physical Intel throughput and representative Jellyfin/Plex playback remain
  personal-beta acceptance gates.
