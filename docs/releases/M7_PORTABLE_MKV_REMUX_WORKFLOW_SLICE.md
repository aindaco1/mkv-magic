# M7 portable MKV remux workflow slice

Date: 2026-08-24

## Delivered contract

Portable saved workflows can add **If needed: Remux compatible media to MKV**.
For a compatible inspected MP4, M4V, MOV, or chapter-free WebM, the compiler
resolves a zero-encode plan that packet-copies every supported media track in
reviewed order. An MP4/MOV chapter carrier is translated into ordinary nested
Matroska chapters. The plan reports `mkvMerge -> verify -> commit`, zero video
generations, zero audio generations, copied video, and lightweight queue work.

For an MKV source, the remux card is shown as already satisfied. Other existing
Matroska cards in an imported recipe may still compile and run. For active
non-MKV remuxing, only output filename cleanup may accompany the card. Track,
metadata, subtitle, and transcode actions are rejected before execution because
their Matroska identity semantics cannot yet be mapped from generic stream IDs
without guessing. The native editor prevents enabling those combinations while
preserving disabled cards for later reuse.

Filename cleanup remains a separate portable intent. The reviewed suggestion is
converted to an `.mkv` name in the Save panel and adds no media pass. If no name
cleanup applies, the normal `— Remuxed.mkv` suggestion is used.

## Portable and automatic boundary

Workflow schema v9 stores only the `remuxToMKV` action. It stores no media path,
bookmark, stream or chapter-carrier ID, resolved plan, tool path, probe result,
or command. Valid v1-v8 files migrate without changing workflow IDs, step IDs,
order, enablement, or action meaning. A document claiming schema v8 cannot use
the schema-v9 action.

Immediate execution remains bound to the source revision accepted during plan
review. Automatic queue admission resolves the stored bookmark, requires that
same reviewed revision, re-inspects the input, recompiles the portable recipe,
and compares the ordered semantic plan before marking work Running. It then
invokes the existing verified MKV remux executor directly. That executor audits
track order and metadata, title, duration, translated chapters, and the exact
ordered encoded packet bodies of every copied track before commit and after
reopening the saved result.

## Verification evidence

- Store regressions prove path-free schema-v9 round trip, v8 migration, and
  rejection of a remux action forged into an older document.
- Compiler regressions cover compatible non-MKV resolution, zero encode impact,
  filename composition, MKV no-op behavior, imported MKV composition, unsafe
  media-card combinations, and exact TX3G refusal propagation.
- Native editor regressions cover the stable catalog and bidirectional
  enablement conflicts while allowing filename cleanup.
- A real bundled-tool integration creates a chaptered H.264/AAC MP4, saves the
  schema-v9 recipe in the production queue, re-inspects and recompiles it, and
  reaches Waiting -> Running -> Succeeded as lightweight work. The output keeps
  both chapter titles and media tracks, preserves the segment title, records
  zero encode generations in the normal eight-state History lifecycle, and
  leaves the source SHA-256 unchanged. The executor's packet verifier proves the
  media payloads were copied rather than encoded.
- The 2026-08-24 complete local gate passed with the exact bundled runtime: 591
  tests, zero failures, and zero skips; AddressSanitizer and ThreadSanitizer
  reported no findings; source coverage was 74.83% line, 78.08% function,
  67.55% region, and 88.51% non-UI line; and the Universal arm64/x86_64 build,
  nested-signature checks, tool-manifest checks, update replacement, artifact
  checksums, and DMG verification all passed.

## Explicit limits

- This workflow inherits the standalone remux allowlist and its refusal of
  TX3G, chaptered WebM, attachments, arbitrary data tracks, multiple video
  tracks, unknown codecs, invalid duration, and unstable stream identity.
- Combining common-media remux with Matroska track cleanup, metadata edits,
  subtitle muxing, or transcoding remains a future compiler contract. The app
  refuses such active combinations instead of silently running multiple or
  lossy passes.
- Physical Intel throughput, representative Jellyfin/Plex playback, notarized
  distribution, and private-library acceptance remain separate release gates.
