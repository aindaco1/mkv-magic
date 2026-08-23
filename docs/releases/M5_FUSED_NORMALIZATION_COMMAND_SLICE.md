# M5 fused common-format command slice

This records engineering acceptance of the exact-choice resolver and pure
FFmpeg command compiler for common-format joins. It does not claim a native
choice screen, a complete joined MKV, transactional execution, HDR conversion,
subtitle conversion, public release, or physical Intel acceptance.

## Revision-bound choices

- A proposal snapshot now contains every deterministic inspected source fact,
  not only the compatibility issue categories. A changed dimension, stream fact,
  chapter, attachment, tag, duration, or source path invalidates the review.
- Video decisions name an exact preset, even-sized canvas, source-timing policy,
  SDR/HDR target, and rate control. HEVC/H.264 require an explicit bounded
  average bitrate; AV1 requires an explicit bounded constant-quality value;
  ProRes uses its reviewed codec default.
- Audio decisions name exact AAC channels, layout, sample rate, bitrate, and
  whether missing parts may receive synthetic silence. AAC must have passed the
  active local probe.
- Attachment retention, lane metadata source, empty subtitle sections, and
  variable source timing are represented explicitly when the proposal requires
  them. Missing decisions, unexpected extra decisions, and choices that no
  longer match the proposal fail closed.

These choices are file-specific and are not serialized into portable saved
workflows. Portable workflows continue to store intent without media paths or
track identifiers.

## One-pass compiler

- All affected video and audio lanes share one `-filter_complex` and one FFmpeg
  invocation. Each source is opened once, each affected output lane has one
  concat, and each output lane is mapped to exactly one encoder.
- SDR video is source-timed, fit inside the chosen even canvas, letter/pillar
  boxed when necessary, assigned square pixels, and tagged BT.709. The compiler
  emits the probed AV1, HEVC VideoToolbox, H.264 VideoToolbox, or ProRes encoder
  and only its reviewed rate-control mode.
- Audio is resampled and rematrixed to the reviewed layout without automatic
  downmix selection. A missing lane is created only after explicit approval and
  is trimmed to that part's exact positive inspected duration.
- The intermediate Matroska stream bundle deliberately excludes source
  metadata and chapters. Compatible packet-copy lanes, subtitles, attachments,
  chosen metadata, exact nested chapters, final `mkvmerge`, verification, and
  commit remain separate stages so they do not trigger another video encode.
- Input filenames are process arguments, never filter-graph text. Track IDs,
  dimensions, layouts, rates, and codec options are bounded or allowlisted.
  Existing destinations, source/output aliasing, missing filters, capability
  regressions, changed reports, oversized commands, and unsafe paths are refused.

## Current executable boundary

The compiler executes uniform BT.709 SDR video, standard mono/stereo/5.1/7.1
audio layouts, resampling/rematrixing, and explicitly approved missing-audio
silence. HDR10 preservation or tone mapping remains blocked until its pixel,
color, and metadata verification contract is complete. Dolby Vision and
image-subtitle conversion retain their existing fail-closed behavior.

## Regression evidence

Pure regressions cover exact-choice completion, active encoder/AAC availability,
stale facts, attachment and metadata selection, unexpected choices, safe odd
canvas rounding, every video rate-control mode, one-process graph shape,
audio-layout conversion, exact-duration silence, missing filters, capability
regression, existing output, and HDR refusal.

Two bundled-tool tests create real Matroska inputs and execute the compiled
commands. One joins different canvases into a single 10-bit HEVC generation; the
other converts stereo plus 5.1 input into one 5.1 AAC lane. Both results inspect
as expected, decode completely, and leave every source byte-identical. The full
bundled-tool suite passes all 285 tests with zero skips and zero failures.

The standard source gate passes all 285 tests with 17 intentional bundled-tool
skips and builds the Universal `arm64`/`x86_64` app. The isolated complete local
gate also passes coverage collection, AddressSanitizer, ThreadSanitizer,
inside-out signatures and entitlement checks, SBOM/checksums, ZIP/appcast
assembly, and verified sandboxed DMG packaging.

## Still pending

- Compact native controls for exact file-specific choices.
- A private transactional executor with progress and cancellation.
- Final assembly of normalized streams with compatible packet-copy lanes,
  subtitles, selected attachments/metadata, and exact nested chapters.
- Strict pre-commit and post-reopen output verification, including decode checks
  around every source boundary.
- HDR10 execution, pinned software AV1, private-library beta acceptance, and
  physical Intel performance acceptance.
