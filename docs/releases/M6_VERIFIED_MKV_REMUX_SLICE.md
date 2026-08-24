# M6 verified common-media MKV remux slice

This slice adds the first native non-MKV input execution path. It is a bounded
zero-encode container conversion, not a claim of arbitrary input/output support
or a shortcut around the standalone transcoding contract.

## User contract

For a compatible inspected MP4, M4V, MOV, or chapter-free WebM, the Inspector
enables **Remux to MKV…**. Review states the exact copied-track count, zero video
and audio encodes, and whether an MP4/MOV chapter carrier will become ordinary
Matroska chapters. **Verify & Run** then offers one deterministic
`— Remuxed.mkv` destination. The original remains unchanged.

The planner requires one video track, a known positive duration, unique
non-negative stream indexes, no attachments, and no unknown or arbitrary data
tracks. The copy allowlist is intentionally typed:

- video: AV1, H.264, HEVC, ProRes, VP8, VP9, and MPEG video;
- audio: AAC, AC-3, E-AC-3, Opus, Vorbis, FLAC, ALAC, PCM, MP3, DTS, and
  TrueHD; and
- subtitles: SRT, ASS, SSA, WebVTT, PGS, and VobSub.

MP4 timed text (TX3G / `mov_text`) is refused with a specific explanation
because Matroska needs an explicit text conversion. Chaptered WebM is also
deferred: its source hierarchy must be extracted and canonically compared
before MKV Magic can make the same exact nested-chapter promise as its native
Matroska editing paths.

## Execution and verification contract

The reviewed source is bound to a filesystem revision. A pure command builder
emits one absolute bundled `mkvmerge` executable plus an argument array—never a
shell or free-form command. It refuses an existing or non-MKV output and pins
the reviewed track order. Production runs only in a private empty temporary
output transaction.

Before atomic commit and again after reopening the saved output, MKV Magic
checks:

- non-empty Matroska output with a new segment identity;
- duration within the bounded 100 ms container-timestamp tolerance;
- exact track count, order, codec, technical facts, HDR/color facts, language,
  user-visible name, and playback/accessibility roles;
- the reviewed segment title;
- MP4/MOV chapter count, titles, starts, nesting representation, and bounded end
  timestamps; and
- no unexpected attachment.

The shared streaming packet auditor additionally hashes every ordered encoded
packet body for every copied media track. H.264 and HEVC use the existing
codec-aware canonical path; the remaining codecs use exact packet payloads.
Missing, reordered, altered, or extra copied packets fail the transaction. The
source revision is checked before mux, after mux, after both audit phases, and
immediately before commit. No failed or stale run creates the requested output.

## Application and support integration

The AppKit button is disabled when inspection cannot satisfy the contract and
its tooltip exposes the planner's exact reason. A successful run registers only
the reopened result. History records the standard eight-state verified
lifecycle under a stable built-in workflow ID and reports zero video and audio
encodes through the privacy-safe support schema. No path, filename, title,
chapter text, packet data, or raw tool output enters that report.

## Verification evidence

- Unit coverage exercises accepted and rejected containers, every supported
  codec family, TX3G refusal, the WebM chapter boundary, stable indexes,
  shell-hostile paths, deterministic `mkvmerge` arguments, output drift,
  duration tolerance, stale sources, tool failure, temporary cleanup, commit,
  and reopen behavior.
- A real bundled-tool fixture creates a chaptered H.264/AAC MP4, observes its
  QuickTime `bin_data` chapter carrier, remuxes only the video and audio streams,
  verifies both packet copies and translated chapters, decodes the saved MKV,
  and proves the source SHA-256 remains unchanged.
- A separate real AppModel fixture proves native preview/execution integration,
  reopened-library registration, and the complete zero-encode History
  lifecycle.

- The complete local gate passed with the exact bundled runtime: the normal,
  AddressSanitizer, and ThreadSanitizer suites each executed 583 tests with zero
  failures or skips. The coverage run also executed all 583 tests and measured
  74.76% source line coverage, 78.06% function coverage, 67.45% region
  coverage, and 88.49% non-UI line coverage.
- The gate built the release executable for both arm64 and x86_64, validated
  the source and exact tool layout, assembled the Universal app, and verified
  the app and nested Sparkle component signatures on disk. Its package gate
  validated build metadata, the CycloneDX SBOM, third-party notices, supported
  systems, troubleshooting material, resolved dependencies, appcast, ZIP, and
  DMG; exercised a signed Sparkle replacement; and independently verified the
  DMG checksum.

This slice does not claim Developer ID signing, Apple notarization,
publication, downloaded-artifact verification, private-library playback, or
physical Intel acceptance.

## Deliberate limits

Alternate output containers, preserve-container copy, embedded TX3G conversion,
chaptered WebM, attachments, arbitrary data tracks, multiple video tracks, and
unknown codecs remain separate preservation contracts. Container-specific
technical metadata may be regenerated by the new container; the verified
promise covers the user-visible title and track metadata listed above, not a
byte-identical container header.
