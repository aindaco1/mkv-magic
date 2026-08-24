# M7 standalone audio workflow slice

Date: 2026-08-24

## Delivered contract

Portable saved workflows can add one **Convert all audio** card without adding
a video conversion. AAC, Opus, AC-3, E-AC-3, and lossless FLAC are offered only
when the bundled encoder passes the active local probe and every mismatched audio
track has a layout and sample rate the selected format can preserve. Tracks
already in the requested codec remain packet copies. A matching-only card is a
no-op and does not require the encoder. The plan reports zero video generations,
the exact number of mismatched audio-track encodes, and an audio-heavy queue
resource class whenever conversion work remains.

Audio-only execution uses one bounded FFmpeg process. Every mismatched audio
track is encoded exactly once; video, matching audio, and subtitles retain their
reviewed order and are packet-copied. The verifier compares media structure, duration, track
metadata and roles, output codecs, channel layouts, sample rates, attachments,
metadata, tag policy, segment identity, and the canonical nested chapter tree.
It also independently fingerprints every copied video, audio, and subtitle packet.
Source file and chapter revisions remain bound from review through the final
reopen audit, and the destination is committed only after verification.

The same recipe is eligible for automatic queue execution. Reinspection and
recompilation must reproduce the reviewed semantic plan, and the scheduler
classifies it as audio-heavy rather than video-heavy. Composed workflows now
share one exact original-file revision guard across private preparation and the
final conversion transaction; changing the original after preparation prevents
commit, while a change observed during the committed reopen becomes a truthful
final-audit failure.

When a video card is also selected, the compiler folds the audio policy into the
existing complete-file video command. Video and mismatched retained audio are
encoded in the same FFmpeg invocation, while matching audio remains a packet copy
and conversions never become serial generations. Deterministic track,
subtitle, title, and filename work still composes through the existing private
verified preparation path.

## Portable compatibility

Workflow schema v8 introduces five standalone audio actions. The JSON stores
only format intent—not paths, encoder names, probe results, track IDs, layouts,
sample rates, or other file-specific facts. Valid v1-v7 recipes migrate without
changing identifiers, card order, enablement, or semantics. Older schema-v6
**With video conversion** actions remain decodable and retain their original
dependency; the editor creates only the clearer schema-v8 standalone actions.

## Verification evidence

- Planner and compiler regressions cover audio-only impact, mixed matching and
  mismatched codecs, matching-only no-ops, video/audio fusion, unavailable
  encoders, tag refusal, missing audio, and layout/rematrix refusal.
- Command tests prove ordered maps, attachment copying, one audio encoder per
  output audio lane, bounded arguments, overwrite refusal, and capability
  revalidation.
- Output-verifier regressions reject changes to copied tracks.
- A bundled-runtime integration converts AAC to FLAC while packet-copying an
  existing FLAC track in exactly one FFmpeg invocation, preserves nested chapters
  and attachment facts, fingerprints the copied video, audio, and subtitle
  packets, and confirms the source digest is unchanged.
- A second bundled-runtime integration admits the audio-only recipe through the
  production queue as audio-heavy work, re-inspects and recompiles it, records
  **Waiting -> Running -> Succeeded**, and preserves the source digest and copied
  video while reporting zero video generations and one encoded audio track.
- Mutation integrations cover both composed video and composed audio workflows:
  changing the original during their final FFmpeg generation is detected before
  commit. Shared transaction regressions also exercise the final-reopen guard.
- `./scripts/ci/local-gate.sh` passed on 2026-08-24: source and security
  validation; 566 tests with 39 expected environment-dependent skips and zero
  failures; repository line coverage of 68.51% and non-UI line coverage of
  84.97%; AddressSanitizer and ThreadSanitizer suites; and the Universal
  arm64/x86_64 release build.
- The same complete gate validated the package signatures, Sparkle update
  replacement, CycloneDX SBOM, appcast and release metadata, ZIP checksum, and
  DMG checksum and filesystem image.

## Explicit limits

- The standalone path currently accepts inspected, tag-free Matroska MKVs with
  a known positive duration and video, audio, and text-subtitle media tracks.
- One selected target applies to every retained audio track; built-in codec
  matching automatically copies tracks already at that target. User-authored
  per-track formats and arbitrary source-codec predicates are not implemented.
- Image subtitles may be preserved as packet copies only when inspection and
  FFmpeg mapping satisfy the current media-track contract; image-to-text OCR
  remains roadmap work.
- Physical Intel throughput and representative Jellyfin/Plex playback remain
  personal-beta acceptance work.
