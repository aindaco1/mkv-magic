# M7 standalone audio workflow slice

Date: 2026-08-24

## Delivered contract

Portable saved workflows can add one **Convert all audio** card without adding
a video conversion. AAC, Opus, AC-3, E-AC-3, and lossless FLAC are offered only
when the bundled encoder passes the active local probe and every retained audio
track has a layout and sample rate the selected format can preserve. The plan
reports zero video generations, the exact number of audio-track encodes, and an
audio-heavy queue resource class.

Audio-only execution uses one bounded FFmpeg process. Every audio track is
encoded exactly once; video and subtitles retain their reviewed order and
are packet-copied. The verifier compares media structure, duration, track
metadata and roles, output codecs, channel layouts, sample rates, attachments,
metadata, tag policy, segment identity, and the canonical nested chapter tree.
It also independently fingerprints every copied video and subtitle packet.
Source file and chapter revisions remain bound from review through the final
reopen audit, and the destination is committed only after verification.

When a video card is also selected, the compiler folds the audio policy into the
existing complete-file video command. Video and all retained audio are encoded
in the same FFmpeg invocation, never as serial generations. Deterministic track,
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

- Planner and compiler regressions cover audio-only impact, video/audio fusion,
  unavailable encoders, tag refusal, missing audio, and layout/rematrix refusal.
- Command tests prove ordered maps, attachment copying, one audio encoder per
  output audio lane, bounded arguments, overwrite refusal, and capability
  revalidation.
- Output-verifier regressions reject changes to copied tracks.
- A bundled-runtime integration converts audio to FLAC in exactly one FFmpeg
  invocation, preserves nested chapters and attachment facts, fingerprints the
  copied video and subtitle packets, and confirms the source digest is unchanged.
- `./scripts/ci/local-gate.sh` passed on 2026-08-24: source and security
  validation; 553 tests with 37 expected environment-dependent skips and zero
  failures; repository line coverage of 68.41% and non-UI line coverage of
  84.89%; AddressSanitizer and ThreadSanitizer suites; and the Universal
  arm64/x86_64 release build.
- The same complete gate validated the package signatures, Sparkle update
  replacement, CycloneDX SBOM, appcast and release metadata, ZIP checksum, and
  DMG checksum and filesystem image.

## Explicit limits

- The standalone path currently accepts inspected, tag-free Matroska MKVs with
  a known positive duration and video, audio, and text-subtitle media tracks.
- One selected format applies to every retained audio track. Per-track formats
  and conditional source-codec predicates are not implemented.
- Image subtitles may be preserved as packet copies only when inspection and
  FFmpeg mapping satisfy the current media-track contract; image-to-text OCR
  remains roadmap work.
- Physical Intel throughput and representative Jellyfin/Plex playback remain
  personal-beta acceptance work.
