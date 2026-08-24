# M6 verified standalone transcode slice

This records engineering acceptance of the first native **Convert Video…**
path. It is a bounded Matroska-to-Matroska capability, not a claim of arbitrary
container conversion or full timeline editing.

## User contract

For an eligible inspected MKV, the Inspector exposes **Convert Video…**. Its
compact native sheet:

- uses the complete source duration without trim controls or thumbnail work;
- defaults to the locally recommended compatible encoder, normally AV1 for
  quality/size with benchmark-recommended HEVC available for slower Macs;
- keeps every locally verified compatible AV1, HEVC, H.264, and ProRes choice;
- packet-copies every audio track by default and offers only probed conversions
  that preserve each reviewed layout and supported sample-rate contract;
- shows Smaller File, Balanced, Higher Quality, and optional bounded exact
  encoder controls; and
- requires a successful immutable review before choosing a new deterministic
  `— Converted.mkv` destination.

## One-generation and preservation contract

An explicit `transcode` operation distinguishes a valid whole-file conversion
from a no-op trim. The command builder re-resolves that operation before it can
emit FFmpeg arguments. One invocation maps the reviewed media tracks and
attachments, encodes the video once, copies or explicitly encodes each audio
track once, and creates one temporary Matroska output.

The shared executor binds the source revision and canonical extracted chapter
digest to review. Full-file conversion reinstalls the original nested chapter
document unchanged; Exact Trim continues to clip, rebase, and regenerate the
retained chapter tree. The verifier checks duration, track order and metadata,
the selected video codec and color/HDR facts, audio copy/encode facts,
attachments, zero-tag policy, chapter count, canonical chapter XML, and new
segment identity before atomic commit and again after reopening the saved path.
The original remains byte-identical.

## Verified evidence

- Planner regression proves a zero-to-duration range remains rejected as a
  no-op Trim and resolves as exactly one video generation for `transcode`.
- Command regression proves full duration, one video encode, and packet-copy
  audio are compiled without a second generation.
- Executor regression proves unchanged canonical chapters, stale-source
  rejection, temporary-output cleanup, verification, commit, and reopen audit.
- Native UI regression proves the compact sheet, visible format/audio/quality
  controls, AV1 recommendation, complete-range binding, packet-copy default,
  keyboard focus, and deterministic output name.
- The bundled-tool fixture completed both Exact Trim and complete conversion,
  decoded the output, preserved audio, attachment facts, and canonical nested
  chapters, and left the source SHA-256 unchanged.

## Deliberate limits

This slice fails closed for subtitle/data tracks, multiple video tracks, source
tags, non-MKV input/output, incomplete video/audio facts, ordered or unsupported
HDR structures, HDR10+, HLG, Dolby Vision, and SDR-to-HDR conversion. Image
subtitle OCR, subtitle-bearing transcode preservation, scaling/cropping, burn-in,
and arbitrary container export remain separate roadmap work.
