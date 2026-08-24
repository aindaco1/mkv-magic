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
The native Workflows builder can name, duplicate, add, remove, reorder, enable,
save, import, and export portable recipe cards. Add Step disables cards already
present and does not expose the legacy combined compatibility action. New
workflows begin with separate plain-language conditions for removing explicitly
non-English subtitles and removing redundant English SDH subtitles, plus
optional segment-title removal. Applicable subtitle
removals are fused into one remux. Workflows store intent rather than media paths
or track identifiers, compile against the selected inspection, show a zero-encode
impact preview, and share one verified output pipeline. Imported workflows using
the original combined English Library Cleanup action remain supported. Save &
Preview opens a native review that marks each recipe card as applied, already
satisfied, or disabled; no plan becomes runnable until the user chooses **Use
This Plan**. An already-satisfied recipe creates no output and offers only Done.
The optional **Add one external text subtitle** card stores only portable input
intent. At preview time it asks for one SRT, ASS, or SSA file, reuses the native
match and track-metadata confirmation, and binds that reviewed file only to the
current plan. Its path and metadata are never saved in the workflow JSON. Track
cleanup, subtitle addition, and segment-title removal share one MKV remux plus at
most one metadata pass before the existing verify-and-commit transaction. Any
subtitle cleanup suggestions are disclosed during confirmation but are not
silently applied by the mux card. The dependent **Clean the added subtitle
text** card opens the existing cue-by-cue deterministic cleanup review, applies
only accepted changes to the private subtitle payload, and feeds it into that
same remux. The source sidecar remains unchanged; reviewed SRT and ASS/SSA
payloads are extracted and audited before commit and after reopening the saved
MKV. The optional **If useful: Clean up the output filename** card now derives
a conservative Jellyfin/Plex-friendly `Title (Year)` suggestion from common
release-style names. The exact suggestion appears in plan review and remains
editable in the Save panel. If naming is the only applicable card, MKV Magic
creates a clone-based byte-identical verified copy—no remux and no encode. The
existing opt-in Trash-after-verified-success choice can make that path behave
like a recoverable rename; otherwise the original remains beside the copy.
Workflow schema v4 still stores only portable action intent—never paths,
subtitle text, or per-file review IDs. Original v1-v3 workflow files migrate
without changing recipe IDs, card IDs, order, enablement, or action semantics.
Older schema numbers cannot claim the newer filename action.
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
local one-frame capability probe; affected audio lanes default to compatible
AAC and can instead use locally verified Opus, AC-3, E-AC-3, or lossless FLAC
when that format can represent the reviewed common layout, without automatic
downmix; uniform static HDR10 lanes retain one
identical reviewed BT.2020/PQ and mastering/light-level signal; mixed BT.709 SDR
and static HDR10 lanes default to reviewed BT.709 output that tone-maps only the
HDR10 Parts; and Dolby Vision, incomplete facts, and image-subtitle limitations
fail closed. Behind that read-only preview, file-specific choices are now
bound to every inspected source fact and compiled into one bounded FFmpeg graph:
each affected video or audio lane is encoded exactly once, ordinary audio layouts
can be normalized without an automatic downmix, and explicitly approved missing
audio becomes exact-duration silence. Real bundled-tool fixtures decode the HEVC
and all five audio-format results and prove that source bytes do not change. The internal
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
subtitle conversion/gaps, SDR-to-HDR conversion, HDR10+, HLG, and Dolby Vision
transcodes continue to fail closed before encoding.

For an eligible inspected MKV, **Trim…** now opens one compact native review
window. Five bounded local thumbnails provide quick **Set In** and **Set Out**
actions while exact `HH:MM:SS.mmm` fields remain directly editable. Fast Trim is
the default and truthfully previews any forward keyframe adjustment before Save
is enabled. Exact Trim retains the numeric range and exposes only video presets
that passed the active local encoder probe, with packet-copy audio as the safe
default. Explicit AAC, Opus, AC-3, E-AC-3, and FLAC choices appear only when the
encoder smoke and every source track's exact layout/rate boundary are safe. Both modes require an
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
facts. Every audio track is packet-copied by default. Explicit AAC, Opus, AC-3,
E-AC-3, and FLAC conversion preserves each reviewed channel layout while encoding
each selected audio track once. AAC, AC-3, E-AC-3, and FLAC retain accepted sample
rates; Opus explicitly targets its 48 kHz Matroska clock. Incompatible choices are
hidden instead of silently downmixing or rematrixing. Output-side seeking makes the reviewed boundary
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
H.264 VideoToolbox, ProRes, AAC, stable statically linked libopus, AC-3, E-AC-3,
FLAC, and every required join filter are independently probed as well. Packet
copy remains the application default; an audio encoder is eligible for later
explicit conversion choices only after its bounded local encode succeeds.
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

The separate M7 production-queue foundation now has a versioned, atomic private
store for bookmark-backed source and destination authority, reviewed workflow
intent and plan impact, retry attempts, and ordered state events. Interrupted
running or cancelling work becomes **Needs Review** after relaunch and is never
silently restarted. Its pure scheduler starts at most one video-heavy job,
bounds audio-heavy and zero-encode lightweight work separately, stops new starts
under serious thermal pressure, and reduces battery operation to one lightweight
job. After reviewing a saved workflow without an external subtitle, **Add to
Queue** stores fresh, narrow security-scoped bookmarks and the exact reviewed
plan as waiting work. MKV Magic takes a live macOS power and thermal snapshot on
launch, after resume, and after queue authoring, then invokes the production
admission coordinator. The coordinator combines the scheduler policy with an
explicit workflow-capability check, unchanged input revisions, a writable
destination, and an unused safe output before marking work **Running**.

Automatic execution re-inspects the current MKV with the bundled tools and
recompiles the portable recipe. The semantic plan must retain the same impact,
ordered mechanisms, and summaries as the reviewed plan; ephemeral stage IDs do
not create false mismatches. The exact source revision is checked again after
inspection and throughout the verified output transaction, including
immediately before commit. A verified result is reopened and audited before the
queue records **Succeeded**. Changes, legacy entries without a revision,
unsupported workflows, and unsafe destinations move to **Needs Review** without
silently refreshing authority. Per-job cancellation reaches the supervised tool
task. Saved-workflow **Verify & Run** remains a distinct immediate path even
while automatic starts are paused.

The native **Queue** window shows resource cost, status, and attempts; it offers
hold/resume, pending reorder, cancel, review-again retry, and persistent pause.
Opening the window refreshes current work without treating it as a relaunch
interruption.

Saved workflows also offer an opt-in **Move original video file to Trash after
verified success** checkbox in the Save panel. It is off by default. Only the
primary media bookmark receives write authority when selected; supplemental
subtitle bookmarks remain read-only. MKV Magic first commits and reopens the
new output, records durable queue success, and only then asks macOS to move the
original to Trash. A Trash error never turns a verified output into a failed
encode or deletes it; the verified output remains, and the app checks whether
the original still exists before reporting a precise warning. The queue then
atomically records **Trashed**, **Trash failed**, or **Check Trash** as a
post-success outcome. If the app stops after queue success but before that
outcome is stored, relaunch uses the original read/write bookmark to finish the
pending follow-up. A source that has already disappeared is recorded as
uncertain and is never falsely reported as successfully trashed; once any
outcome is durable, later queue refreshes do not repeat the request.

This is the first narrowly supported automatic production path, not a background
daemon: built-in quick actions and workflows requiring ephemeral external-
subtitle review are not automatically queued; there is no watched folder,
scheduled wake, helper process, or continuous power-state monitor. A blocked
queue is reconsidered at the next launch, resume, or **Add to Queue** action.
Long queue soak and physical Intel acceptance remain open. See
[docs/releases/M7_QUEUE_UI_EXECUTION_BRIDGE_SLICE.md](docs/releases/M7_QUEUE_UI_EXECUTION_BRIDGE_SLICE.md)
and
[docs/releases/M7_TRASH_AFTER_VERIFIED_SUCCESS_SLICE.md](docs/releases/M7_TRASH_AFTER_VERIFIED_SUCCESS_SLICE.md),
with its relaunch outcome contract in
[docs/releases/M7_DURABLE_SOURCE_DISPOSITION_OUTCOME_SLICE.md](docs/releases/M7_DURABLE_SOURCE_DISPOSITION_OUTCOME_SLICE.md),
and the automatic-admission input boundary in
[docs/releases/M7_REVIEWED_INPUT_REVISION_SLICE.md](docs/releases/M7_REVIEWED_INPUT_REVISION_SLICE.md),
followed by the coordinator foundation in
[docs/releases/M7_QUEUE_ADMISSION_COORDINATOR_FOUNDATION_SLICE.md](docs/releases/M7_QUEUE_ADMISSION_COORDINATOR_FOUNDATION_SLICE.md),
and its app connection in
[docs/releases/M7_AUTOMATIC_SAVED_WORKFLOW_QUEUE_SLICE.md](docs/releases/M7_AUTOMATIC_SAVED_WORKFLOW_QUEUE_SLICE.md),
followed by portable filename cleanup in
[docs/releases/M7_FILENAME_CLEANUP_WORKFLOW_SLICE.md](docs/releases/M7_FILENAME_CLEANUP_WORKFLOW_SLICE.md).

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
