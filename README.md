# MKV Magic

MKV Magic is a local-first, lossless-first macOS application for inspecting,
cleaning, editing, muxing, joining, trimming, transcoding, and automating MKV
and other common media files.

The product is named **MKV Magic**. The repository and workspace directory are
named `mkv-magic`; the internal Swift package and executable are `MKVMagic`.

## Status

The release foundation and first local inspection vertical slice are in place.
The app can recursively discover media, inspect files with its bundled FFprobe
and MKVToolNix runtime, and present normalized file, track, chapter, attachment,
and tag facts without modifying the source. Executable metadata actions edit a
Matroska segment title or one track's name, language, playback flags, and roles
on a temporary clone. They verify every unrelated track and structure fact,
then commit a new output without replacing the original. Track removal remuxes
retained streams without encoding, preserves their order, chapters, tags, and
attachments, and uses the same verify-before-commit rule. A deterministic Clean
MKV preview can suggest English-library subtitle removals for individual review.
The native Workflows builder can name, duplicate, reorder, enable, save, import,
and export portable recipes. Its first reusable actions are English Library
Cleanup and segment-title removal. Workflows store intent rather than media
paths or track identifiers, compile against the selected inspection, show a
zero-encode impact preview, and share one verified output pipeline.
Selected SRT, ASS, and SSA files can also be decoded, structurally normalized,
and reviewed cue by cue for deterministic YTS/YIFY advertisement removal and
accidental edge whitespace. A bounded local English OCR policy automatically
selects only unambiguous digit/letter corrections and presents curated possible
spelling corrections unchecked. Explicit non-English filename suffixes disable
the English rules. Markup, URLs, email addresses, and ASS/SSA override tags are
protected. Cleanup preserves every timestamp and, for ASS/SSA, the script
sections, style definitions, override tags, layout fields, comments, and unknown
sections. It refuses to remove every event, detects a source changed since
preview, writes a new UTF-8 subtitle, and reopens the exact planned result before
commit while leaving the source intact.
For inspected Matroska video, **Add Subtitle…** accepts a reviewed external SRT,
ASS, or SSA file, ranks the filename and timing match, infers editable
language/forced/SDH metadata, and adds it as the last track in a new MKV without
encoding. Existing tracks, chapters, tags, and attachments are verified before
and after commit. Styled subtitles receive an additional `mkvextract` audit of
their header, styles, layout, timing, and text; both selected inputs remain
unchanged.
An inspected Matroska file with embedded SRT, ASS, or SSA tracks can use the
same **Clean Subtitle…** review without first exporting a sidecar. A chooser
appears when more than one editable text track is present. MKV Magic privately
extracts the selected track, applies only the reviewed changes, and replaces it
at the same track position in one zero-encode remux. Track UID, name, language,
playback/accessibility flags, every other track, chapters, tags, attachments,
and the original file are preserved. The replacement is re-extracted before
commit and after reopen; compatible contiguous packet timelines receive an
additional exact nanosecond timing audit, while gapped timelines avoid an unsafe
timestamp override and retain the subtitle format's own timing semantics.
For inspected Matroska files, **Chapters…** now opens a native nested Chapter
Studio. It can add, remove, duplicate, nest, and unnest editions and atoms; edit
nanosecond start/end values, flags, and localized display names; generate fixed
interval chapters; analyze scene changes, black frames, and silence locally;
review each suggested boundary; lazily preview bounded local frames before, at,
and after a selected start and adopt an exact displayed timestamp; explicitly
flatten leaf chapters for Jellyfin; and import or export Matroska XML and simple
chapter text. The reviewed tree is written only to a temporary clone with
`mkvpropedit`, then re-extracted for exact hierarchy, UID, timestamp, language,
and flag comparison before commit and after reopen. Synchronized timeline
dragging and frame/keyframe snapping remain M4 work.
The first M5 slice can compose explicitly selected source chapter trees for a
hard join: it intersects retained ranges, rebases nested timestamps, creates
source-part parents and missing boundary children, regenerates identities, and
validates one final default edition. M5 also has a bounded joined-track mapping
foundation. It proposes only unique
codec/parameter or language/role matches, leaves indistinguishable tracks in
separate visible lanes, requires every appendable track exactly once, and
classifies gaps or stream differences before work begins. A static
`losslessCandidate` is not an execution guarantee: bundled `mkvmerge` and final
output verification remain mandatory.

With at least two inspected MKVs, **Join Files…** now opens a native strict
review. Users can include, exclude, and reorder sources; explicitly choose among
multiple chapter editions; inspect every proposed track lane and compatibility
issue; and continue only when the group is a zero-encode candidate with stable
track identities. The app revalidates every exact source chapter document,
prompts for one MKV destination, shows cancellable progress, records every input
in History, and hard-joins through the verified-output transaction. It reopens
the temporary and committed results, compares the exact nested chapter XML,
decodes a bounded window spanning every join, and fingerprints the ordered
encoded packet payloads of every lane promised as a direct copy. When automatic
matching finds indistinguishable tracks, **Resolve Track Mapping…** opens an
explicit lane-by-Part table. Selecting a same-type track moves or swaps its
assignment, never duplicates or discards it, and the confirmed map is invalidated
if source inclusion or order changes. When a reviewed group
needs normalization, the same window previews the proposed common video,
audio, and text-subtitle targets. Compatible lanes remain packet copies;
affected video is bounded to one generation using an encoder that passed a
local one-frame capability probe; affected audio lanes are converted once to
verified AAC without automatic downmix; uniform static HDR10 lanes retain one
identical reviewed BT.2020/PQ and mastering/light-level signal; and mixed
SDR/HDR, Dolby Vision, incomplete facts, and image-subtitle limitations fail
closed or require explicit choices. Behind that read-only preview, file-specific choices are now
bound to every inspected source fact and compiled into one bounded FFmpeg graph:
each affected video or audio lane is encoded exactly once, ordinary audio layouts
can be normalized without an automatic downmix, and explicitly approved missing
audio becomes exact-duration silence. Real bundled-tool fixtures decode the HEVC
and AAC results and prove that source bytes do not change. The internal
normalization executor now binds every source to a filesystem revision, invokes
that graph once, verifies the intermediate stream bundle's exact encoded lanes,
duration, Matroska structure, dimensions, bit depth, reviewed SDR or static HDR10
color signal, audio layout, and sample rate, and atomically commits only after a
second reopen audit. Each
encoded segment is padded and trimmed to its reviewed source-container duration,
so an encoded video lane remains aligned with a directly copied audio lane even
when the source contains encoder padding. A final pure compiler now emits one
`mkvmerge` invocation that combines those verified normalized lanes with direct
packet-copy lanes, selected attachments and track metadata, one title, and the
exact nested joined chapters. It refuses overwrite, changed chapters/bundles,
unsafe paths or text, unpreserved tags, subtitle conversion, and subtitle gaps.
The revision-bound final executor compiles that command again inside a
verified-output transaction, semantically audits the temporary MKV, re-extracts
and canonically compares its full nested chapter XML, decodes every join
boundary, fingerprints direct packet-copy lanes without retaining film-length
packet listings in memory, commits atomically, then repeats the complete audit
after reopening the saved path. Exact packet lanes of the same stream family
share one FFprobe scan per source/output while their hashes remain isolated by
track; H.264/HEVC retain their codec-aware canonical scan. A real mixed-lane
fixture passes this transaction without changing either original. The native
review now enables **Review Common Format…** only when those exact contracts are
executable. A compact second sheet lists the resolved targets, nested chapter
output, packet-copy behavior, and one-generation impact, then requires explicit
approval before Save. For each video lane that actually needs conversion, this
sheet now offers every locally verified codec compatible with the reviewed color
range, the same Smaller File/Balanced/Higher Quality tiers as Exact Trim, and an
optional exact RF/SVT-speed or bitrate disclosure. Changing any target clears
approval and recompiles the immutable plan; it never adds another video
generation. The app binds the approval to unchanged source and chapter
revisions, creates the verified normalized bundle only in private temporary
storage, assembles the final MKV, adds only the reopened final result to the
library, and records exactly one sanitized History job. Source tags, executable
subtitle conversion/gaps, mixed SDR/HDR conversion, HDR10+, HLG, and Dolby Vision
transcodes continue to fail closed before encoding.

For an eligible inspected MKV, **Trim…** now opens one compact native review
window. Five bounded local thumbnails provide quick **Set In** and **Set Out**
actions while exact `HH:MM:SS.mmm` fields remain directly editable. Fast Trim is
the default and truthfully previews any forward keyframe adjustment before Save
is enabled. Exact Trim retains the numeric range and exposes only video presets
that passed the active local encoder probe, with packet-copy audio as the safe
default and explicit one-generation AAC as an option. Both modes require an
immutable review, use the same cancellable verified-output progress surface,
disable cancellation during commit, save to a new deterministic MKV name, and
record a sanitized eight-state History lifecycle.

Exact Trim keeps **Balanced** as the default but also offers plain-language
**Smaller File** and **Higher Quality** choices. An optional disclosure reveals
the exact bounded control: AV1 RF 0–63 plus SVT speed preset 0–13, or HEVC/H.264
bitrate in kbps. The reviewed numeric values are stored in the immutable plan,
shown in the execution summary, and compiled through the same one-generation
encoder policy used by common-format Join. Free-form FFmpeg arguments are never
accepted.

The internal Fast Trim path now scans the primary video track with bounded local
`ffprobe`, shows the first-keyframe-at-or-after adjustment for both requested
boundaries, and refuses to call the result frame-exact. For one-video Matroska
MKVs it uses `mkvmerge --split parts:` with no video or audio encode, clips and
rebases the complete nested chapter tree, writes that reviewed tree to the
temporary output, and verifies streams, metadata, attachments, duration,
segment identity, and canonical re-extracted chapters before commit and after
reopen. It rejects ordered editions and changed sources rather than guessing.
The internal Exact Trim path retains the user's numeric boundaries and encodes
the video exactly once with the selected encoder that passed the active local
probe. It accepts strict BT.709 SDR, or validated 10-bit static HDR10 through AV1
or HEVC while preserving BT.2020/PQ, matrix, mastering-display, and content-light
facts. Every audio track is packet-copied by default. Explicit AAC
conversion preserves each reviewed channel layout and sample rate while encoding
each selected audio track once. Output-side seeking makes the reviewed boundary
apply to copied audio as well as encoded video. The same transaction preserves
track metadata and attachments, clips and rebases the exact nested chapter tree,
removes only FFmpeg-synthesized statistics tags from a reviewed tag-free source,
and repeats semantic and chapter audits after reopen. It currently fails closed
for source tags, subtitle/data tracks, multiple video tracks, ordered editions,
mixed or unsupported HDR, HDR10+, HLG, Dolby Vision, incomplete color/layout
facts, unavailable encoders, and non-MKV inputs.
The bundled FFmpeg includes checksum-pinned, statically linked SVT-AV1 4.1.0
for native 10-bit software AV1 encoding and dav1d 1.5.4 for software AV1
decoding on both Apple Silicon and Intel. This allows Macs without hardware AV1
decoding to reopen the app's preferred outputs. MKV Magic still offers an
encoder only after its one-frame local smoke probe succeeds on the running Mac:
verified AV1 is the preferred quality/size choice, while verified HEVC 10-bit
VideoToolbox remains the faster fallback for slow or unsupported Intel hardware.
H.264 VideoToolbox, ProRes, AAC, and every required join filter are independently
probed as well.
The sidebar's explicit **Encoding Test…** action can refine that initial choice
without touching user media. It encodes one private three-second synthetic
10-bit clip with the verified AV1 and HEVC paths, measures speed, bitrate, and
PSNR, estimates 1080p real-time performance, and saves a private recommendation
only for the exact bundled FFmpeg hash, architecture, and processor count. A slow
or timed-out AV1 result can recommend HEVC on that Mac; all verified choices
remain visible, and the test never runs without a click or uses the network.
Every action's sanitized queue lifecycle is persisted atomically in the app's
private Application Support container and is available from the lightweight
History report. History also offers an explicit privacy-safe JSON export for
private beta and support work. New jobs contribute only allowlisted coarse media
facts, planned video/audio encode counts, lifecycle states and elapsed-time
buckets. The export excludes filenames, paths, media and track titles, subtitle
text, custom workflow names, raw tool output, identifiers and exact timestamps;
it remains local until the user chooses a destination. See
[docs/beta/PRIVATE_LIBRARY_ACCEPTANCE.md](docs/beta/PRIVATE_LIBRARY_ACCEPTANCE.md)
for the beta loop. No public release is available yet. The canonical product and
delivery plan is [PRODUCT_SPEC.md](PRODUCT_SPEC.md).

## Design promises

- Avoid transcoding whenever metadata editing, remuxing, appending, or stream
  copying can satisfy the request.
- Encode video no more than once for each final output.
- Preserve originals until a result passes its declared verification contract.
- Preserve embedded subtitle identity, ordering, metadata, text/style payload,
  and timing without encoding; refuse a result that fails its declared audit.
- Process locally without telemetry, accounts, uploads, LLMs, or an ambient
  Homebrew/runtime dependency.
- Ship as a Universal Developer ID-signed and Apple-notarized macOS app.

## Development

Requirements:

- macOS 13 or newer
- Xcode 16 or newer with Swift 6
- `rg`, `shellcheck`, and standard Apple command-line developer tools
- `cmake`, `meson`, `ninja`, and `pkg-config` when rebuilding the bundled media
  runtime from source

Run the supported source gate:

```sh
./scripts/ci/validate.sh
```

Build and launch the Swift executable during development:

```sh
swift run MKVMagic
```

Media tools are resolved only from an explicit development tool root or from
the packaged app. The runtime never silently uses `/opt/homebrew`,
`/usr/local`, or the process `PATH`.

Compare the old per-lane copied-packet scan pattern with the current bounded
stream-family demultiplexer on a local, unchanged media file:

```sh
./scripts/performance/benchmark-join-packet-audit.sh "/absolute/input.mkv" a 1 2
```

The script withholds the media path from its report. It uses only the pinned
FFprobe for the running architecture, never writes to the input, and rejects
measurements if the source revision changes while it runs.

## License

MKV Magic is licensed under GPL-3.0-or-later. Bundled components retain their
own licenses and notices; see `THIRD_PARTY_NOTICES.md` in release artifacts.
