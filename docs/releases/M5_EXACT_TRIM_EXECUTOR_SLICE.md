# M5 verified one-generation Exact Trim executor slice

This records engineering acceptance of the non-UI Exact Trim path for inspected,
tag-free Matroska MKVs containing exactly one BT.709 SDR video track plus zero or
more audio tracks. It does not claim a native trim window, multiple-video or
subtitle/data-track timing, HDR/Dolby Vision handling, source-tag preservation,
ordered-edition support, generic splitting, private-library acceptance, physical
Intel acceptance, or a public release.

## Immutable exact review

- The requested positive in/out range is retained without keyframe adjustment.
- The planner requires a known duration, complete even video dimensions, exact
  BT.709 primaries/transfer/matrix facts, no HDR or Dolby Vision signal, stable
  media-track IDs, and zero inspected Matroska tag entries.
- Only video presets that passed the bounded active local FFmpeg probe are
  selectable. The recommendation preserves capability order: software AV1,
  HEVC VideoToolbox, H.264 VideoToolbox, then ProRes.
- Exactly one video track is encoded exactly once. Audio is packet-copied by
  default. Optional AAC retains each track's reviewed sample rate, channel count,
  and channel layout and encodes each such track once.
- The preview binds the complete inspected source, filesystem revision, canonical
  source-chapter SHA-256, exact range, codec/rate-control choice, and the exact
  encoded/copied track IDs. Those facts are recompiled and compared before work.

## One-generation command

The command builder emits one direct-argument FFmpeg invocation without a shell,
filter graph, overwrite flag, or intermediate video encode. It explicitly maps
the reviewed media tracks in source order plus all attachments, defaults streams
to packet copy, overrides only the single video encoder and any explicitly
selected AAC tracks, preserves global and stream metadata, omits source chapters,
and writes Matroska.

The seek is deliberately output-side. Input-side accurate seeking cannot discard
pre-in packets from a copied audio stream; the bundled integration exposed that
as a longer-than-reviewed container. Output-side seeking decodes forward and
discards every stream before the exact in-point, retaining packet-copy audio and
one video generation at the cost of more decode work on long sources.

AV1 uses 10-bit constant-quality output. HEVC uses 10-bit VideoToolbox bitrate
control, H.264 uses 8-bit VideoToolbox bitrate control, and ProRes uses its 10-bit
codec default. All routes declare reviewed BT.709 limited-range output through
one encoder-argument policy shared with join normalization, avoiding duplicated
codec behavior.

## Verified output transaction

1. Reserve a non-existent private output on the destination volume.
2. Revalidate the source revision and canonical source chapters.
3. Run the reviewed FFmpeg command once.
4. Revalidate the source again, then use one `mkvpropedit` call to install the
   already reviewed clipped/rebased nested chapters and remove FFmpeg-synthesized
   Matroska statistics tags. This is safe only because nonzero source tags fail
   planning.
5. Require non-empty Matroska, exact duration within 100 ms, the exact media-track
   kind order and metadata, selected video codec/dimensions/bit depth/BT.709 SDR,
   packet-copy audio identity or reviewed AAC layout, exact attachments, preserved
   non-provenance global metadata, zero tags, reviewed top-level chapter count,
   and a new segment UID.
6. Re-extract bounded chapter XML and require canonical equality with the complete
   reviewed nested tree.
7. Commit atomically without overwrite, reopen the final path, and repeat every
   semantic and canonical chapter audit.

A changed source never commits. Tool, duration, codec, track, metadata,
attachment, tag, chapter, capability-regression, or pre-commit cancellation
failures remove the temporary output. A post-commit failure truthfully reports
the actual saved URL.

## Regression and bundled-tool evidence

Twelve new tests cover recommendation order, copied-versus-AAC encode counts,
unsupported tracks/tags/HDR and incomplete facts, invalid/no-op ranges,
capability regression, exact output-side command rendering, one-generation
execution, synthesized-tag deletion, source changes before and during encode,
tool/semantic/chapter failures, commit-stage truth, and real bundled tools.

The bundled integration creates a ten-second H.264/AAC MKV with two-second GOPs,
track metadata, one attachment, and nested chapters. It requests 3.25–7.75
seconds, keeps those exact reviewed boundaries, executes the production
transaction with the first verified output preset, packet-copies AAC, preserves
the attachment, decodes both output streams, re-extracts exact 0–4.5-second nested
chapters, and proves the source SHA-256 did not change.

The current suite contains 328 tests. The standard source run has 20 intentional
bundled-tool skips; the assembled Universal runtime runs all 328 with zero skips
and zero failures. The complete gate additionally covers coverage, AddressSanitizer,
ThreadSanitizer, Universal build, signatures/entitlements, SBOM/checksums,
ZIP/appcast assembly, and verified DMG packaging.

## Still pending

- Native thumbnails plus numeric in/out fields, explicit Fast/Exact selection,
  codec/audio choices, progress, and History wiring.
- Source-tag preservation, subtitle/data-track timing, multiple-video policy,
  ordered-edition handling, HDR10 preservation, and Dolby Vision policy.
- Split by chapters/ranges/duration/size, Chapter Studio keyframe snapping,
  private-library beta, physical Intel performance acceptance, and public release.

The native-window item above was subsequently completed in
`M5_NATIVE_TRIM_SLICE.md`; the remaining limitations still apply.
