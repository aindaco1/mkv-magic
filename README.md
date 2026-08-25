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
save, import, and export portable recipe cards. On first use it includes an
editable **Clean MKV** workflow modeled on the legacy `clean_mkv.py` utility.
It preserves every video and audio stream, removes explicitly non-English and
redundant English SDH subtitles, removes the segment title, Matroska tags, and
image attachments, normalizes recognized commentary names and role flags,
marks recognized forced and SDH subtitles, and offers a conservative
Jellyfin/Plex-friendly filename. It never requests an audio or video encode.
Creating another workflow starts from the same useful cards with fresh portable
identifiers; users can disable, reorder, remove, or add cards before saving.
Deleting every saved workflow is respected and does not recreate the preset.
Add Step disables cards already present and does not expose the legacy combined
compatibility action. The tag card reports reviewed
global/track counts and clears every Matroska tag without encoding. The image
card removes only attachments whose reviewed MIME type is `image/*`; subtitle
fonts and unknown attachments remain. Both preserve unrelated structure and
metadata. Applicable subtitle
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
Saved workflows can now add exactly one **Convert video** card: use the locally
recommended verified encoder, request AV1, HEVC, H.264, or ProRes explicitly, or
choose the lossless-first condition that packet-copies video already encoded as
AV1/HEVC and converts only older codecs.
The reviewed plan binds the actual local preset and its one-generation impact.
If cleanup, track removal, title removal, or subtitle muxing is also applicable,
MKV Magic commits those packet-copy changes only to a private verified
intermediate, then performs one complete-file video encode into the final
destination. Audio and subtitles remain exact packet copies by default. One
optional audio card can explicitly make every retained audio track AAC, Opus,
AC-3, E-AC-3, or FLAC while preserving each known channel layout. Tracks already
in the requested codec remain exact packet copies; only mismatched tracks are
encoded, each at most once. The card can run alone while packet-copying video,
subtitles, and matching audio, or fuse into the video card's same single FFmpeg
process. If every audio track already matches, the card is a no-op and does not
require that encoder. Unsafe layout/rate choices fail before execution. Nested
chapters, attachments, HDR10, and reviewed metadata are
verified, and the source revision is bound from plan acceptance through queueing
or immediate execution. A conversion-only recipe skips the intermediate.
That direct portable recipe also accepts the bounded MP4, M4V, MOV, and
chapter-free WebM inputs supported by **Convert Video…**. Common input must
actually run one video-conversion card and may combine it only with one optional
audio conversion and filename cleanup; MKV-only track, subtitle, title, and
chapter edits fail before the capability probe. The Save panel always changes a
common-input conversion suggestion to `.mkv`. Immediate and automatic queue
execution re-use the same one-process encoder and verified Matroska output
transaction.
Automatic queue reinspection must resolve the same codec-bearing semantic plan
or move the job to Needs Review. Audio-only execution independently fingerprints
every copied video, audio, and subtitle packet before commit.
Workflow schema v16 still stores only portable action intent—never paths, local
capability results, bitrate controls, subtitle text, or per-file review IDs.
Original v1-v15 workflow files migrate
without changing recipe IDs, card IDs, order, enablement, or action semantics.
Older schema numbers cannot claim actions introduced by a newer schema.
Tag removal can share one mkvpropedit invocation with segment-title removal,
run after an existing zero-encode remux, or prepare a tagged MKV for one final
video/audio conversion. The conversion itself still occurs at most once.
Image-attachment removal shares one mkvmerge pass with track cleanup or external
subtitle muxing, or creates the one verified private preparation remux before a
single final conversion. Its portable review reports only the number of images,
never attachment names, MIME values, UIDs, or paths.
The opt-in **If useful: Mark commentary tracks** card recognizes only audio and
subtitle names containing the distinct word `commentary`, then sets Matroska's
commentary flag without renaming the track or changing its language, other
flags, or packets. Already marked files are skipped. The portable recipe stores
only the policy action; current UIDs and the count shown in review are ephemeral.
Commentary flags share the existing single property pass and can prepare one
final video/audio conversion without introducing another encode.
The separate opt-in **If useful: Normalize commentary names** card renames
recognized audio and subtitle tracks independently as `Commentary`,
`Commentary #2`, and so on. It preserves languages, flags, packet payloads, and
all other track facts. When both commentary cards apply, MKV Magic merges their
intent by stable UID and still performs one property pass with one edit per
track; the portable recipe stores neither UIDs nor resolved names.
The opt-in **If useful: Mark forced subtitles** card recognizes only unforced
subtitle names containing the distinct word `forced`. It sets the native
Matroska forced flag while preserving the name, language, default and enabled
states, accessibility roles, and packets. Overlapping commentary/name/forced
intent is merged by stable UID into one reviewed edit and one property pass.
The opt-in **If useful: Mark SDH subtitles** card recognizes only unmarked
subtitle names containing the distinct token `SDH`, `CC`, or `hearing impaired`.
It sets Matroska's native hearing-impaired flag while preserving the name,
language, playback state, every other role, and packets. Overlapping
commentary/name/forced/SDH intent is merged into that same single property pass.
The opt-in **If useful: Mark audio-description tracks** card recognizes only
unmarked audio names containing a clear phrase such as `Audio Description`,
`Descriptive Audio`, or `Visually Impaired`. It deliberately ignores the
ambiguous abbreviation `AD`. It sets Matroska's native visual-impaired flag
without renaming the track, changing another flag, or encoding media, and its
intent joins the same single reviewed property pass.
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
For inspected Matroska files, **Extract Subtitle…** writes one selected embedded
SRT, ASS, or SSA track to a separate sidecar in its original format and exact
extracted bytes. A single eligible track proceeds directly; multiple tracks use
the readable shared chooser. Review and Save each re-inspect the complete media
snapshot, bind the source revision and stable track UID, independently extract
and parse the bounded text payload, and require the bytes plus timing/style
document to agree. The final sidecar is audited before commit and after reopen,
History records zero video/audio encodes, and the MKV is never changed.
For inspected Matroska files, **Attachments…** copies one selected embedded
font, image, or other regular attachment into a separate exact file. One
eligible attachment proceeds directly; multiple attachments use a readable
filename, type, and size chooser. Review and Save each re-inspect the complete
media snapshot, bind the source revision plus stable attachment UID, and run
bundled `mkvextract` in private storage. The repeated extraction must match the
reviewed byte count and streaming SHA-256 digest; the final file is checked
before commit and after reopen. Attachments must be non-empty and no larger
than 512 MiB. History records zero video/audio encodes and the MKV is never
changed.
For inspected Matroska files, **Remove Attachments…** provides an explicit
multi-selection list and creates a new MKV containing only the retained
attachments. It re-inspects the complete source snapshot, resolves choices by
stable unique attachment UID and ID, and uses bundled `mkvmerge` to copy every
media track without encoding. Verification permits the attachment IDs that
Matroska remuxing normally renumbers, but requires each retained UID, filename,
MIME type, description, size, and order plus all tracks, tags, nested chapters,
duration, and metadata to match before commit and after reopen. Removing every
attachment is supported when media remains; the original MKV is never changed.
For inspected Matroska files, **Tags…** reports the global and track tag-entry
counts and offers two explicit zero-encode actions. **Export XML…** repeats the
reviewed bundled-`mkvextract` operation and saves the complete exact Matroska
tag XML as a separately verified sidecar without changing the MKV. **Review
Removal…** clears every global and track tag with bundled `mkvpropedit` on a
temporary clone, then requires zero tag entries while preserving the segment
title, tracks, nested chapters, attachments, duration, and segment identity
before commit and after reopen. Both paths bind the source revision throughout,
record separate privacy-safe History jobs, and never overwrite the original.
For inspected MP4, M4V, and MOV files, **Convert MP4 Subtitle…** exposes each
TX3G/`mov_text` track in a readable chooser and converts one selected track into
a separate editable UTF-8 ASS sidecar. Review runs bundled FFmpeg privately and
binds the exact source revision plus parsed text, styles, and timing. Save repeats
the conversion, requires the same document, writes one normalized temporary
ASS, reopens it before and after atomic commit, and records zero video/audio
encodes in History. The source video is never modified or replaced.
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

For an eligible inspected MKV, MP4, M4V, MOV, or chapter-free WebM,
**Convert Video…** reuses that same reviewed one-generation engine for the
complete file. It starts with the locally
recommended verified video format—AV1 for quality/size unless a completed
Encoding Test recommends the faster HEVC path—while keeping every verified
AV1, HEVC, H.264, or ProRes alternative selectable. Audio is packet-copied by
default when its codec is valid in Matroska; only layout-safe, locally verified
audio conversions appear. Embedded subtitle tracks are packet-copied for MKV
input. The review binds the complete duration, one video generation, audio and
subtitle decisions, track metadata, attachments, and chapters.
Execution creates `— Converted.mkv` through the same private temporary-output,
semantic verification, atomic commit, and reopen audit used by Exact Trim.
Complete conversion omits trim seeking and duration truncation, then compares
streaming ordered packet hashes for copied audio and subtitles before commit and
after reopen. MKV input retains its exact canonical nested chapter document.
MP4/M4V/MOV chapter entries are promoted into one default nested Matroska
edition, and one known QuickTime chapter carrier is excluded from the media map.
Common-container input requires one video, no subtitles or attachments,
unambiguous chapter facts, only known container-internal metadata, and complete
color facts. Chaptered WebM, ambiguous data, multiple video tracks, source tags
on MKV, unsupported HDR, incomplete facts, and non-MKV output fail closed.

For a compatible inspected MP4, M4V, MOV, or chapter-free WebM,
**Remux to MKV…** remains the preferred lossless container-change path when the
video does not need conversion. It copies the reviewed video, audio,
and supported subtitle streams in their original order with zero encodes. MP4
and MOV chapter carriers become ordinary Matroska chapters; the segment title,
track names, languages, technical facts, HDR facts, and playback/accessibility
roles are checked on the result. MKV Magic fingerprints every ordered encoded
packet promised as copied, validates the source revision throughout one private
temporary-output transaction, commits atomically, and repeats the semantic and
packet audits after reopening `— Remuxed.mkv`. MP4 timed text (TX3G) can be
explicitly converted to a verified ASS sidecar, but it is still not silently
rewritten inside this zero-encode remux. Attachments,
arbitrary data tracks, multiple video tracks, unknown codecs, and chaptered
WebM fail closed until their exact preservation contracts are available.
The same operation is available as the portable **If needed: Remux compatible
media to MKV** workflow card. It can be paired with filename cleanup, compiles
to a zero-encode lightweight plan for compatible non-MKV input, and is skipped
as already satisfied for MKV input. A saved remux recipe is eligible for the
automatic queue; reinspection must reproduce the exact reviewed track/chapter
plan and source revision before execution. Other media-changing cards cannot be
combined with an active common-media remux until their stream-to-Matroska-track
mapping has an equally exact contract.

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
facts, unavailable encoders, and non-MKV inputs for trimming. Complete-file
conversion has the separately bounded common-input support described above.
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
job. After reviewing a supported saved workflow, **Add to Queue** stores fresh,
narrow security-scoped bookmarks and the exact reviewed plan as waiting work.
That can be one primary media file or the primary plus one reviewed external
SRT, ASS, or SSA subtitle. MKV Magic takes a live macOS power and thermal
snapshot on launch, after resume, and after queue authoring, then invokes the
production admission coordinator. The coordinator combines the scheduler policy
with an explicit workflow-capability check, unchanged input revisions, a
writable destination, and an unused safe output before marking work **Running**.

Automatic execution re-inspects the current media file with the bundled tools and
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

External-subtitle queue records remain private and path-free. They store only
opaque bookmark authority, file revisions, the reviewed sidecar SHA-256, SRT or
ASS/SSA format, track metadata, and sorted cleanup-restoration IDs—not subtitle
text or a source path, and never inside an exported workflow. Admission parses a
fresh sidecar preview, requires the original digest, reapplies the exact review,
and recompiles the same plan before the existing verified mux executor runs.
A changed sidecar moves to **Needs Review** and creates no output.

Standalone audio recipes use this same path as audio-heavy work. If packet-copy
or metadata preparation precedes a final video or audio conversion, the exact
original-file revision remains guarded through that final generation and the
committed reopen audit rather than being replaced by the private intermediate's
revision.

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

This is a narrowly supported automatic production path, not a background daemon:
built-in quick actions, multiple or image-based subtitle inputs, and automatic
sidecar discovery are not queued; there is no watched folder, scheduled wake,
helper process, or continuous power-state monitor. A blocked queue is
reconsidered at the next launch, resume, or **Add to Queue** action. Long queue
soak and physical Intel acceptance remain open. See
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
extended to reviewed external subtitle inputs in
[docs/releases/M7_AUTOMATIC_EXTERNAL_SUBTITLE_QUEUE_SLICE.md](docs/releases/M7_AUTOMATIC_EXTERNAL_SUBTITLE_QUEUE_SLICE.md),
followed by portable filename cleanup in
[docs/releases/M7_FILENAME_CLEANUP_WORKFLOW_SLICE.md](docs/releases/M7_FILENAME_CLEANUP_WORKFLOW_SLICE.md),
portable tag cleanup in
[docs/releases/M7_PORTABLE_TAG_REMOVAL_WORKFLOW_SLICE.md](docs/releases/M7_PORTABLE_TAG_REMOVAL_WORKFLOW_SLICE.md),
and MIME-strict image-attachment cleanup in
[docs/releases/M7_PORTABLE_IMAGE_ATTACHMENT_WORKFLOW_SLICE.md](docs/releases/M7_PORTABLE_IMAGE_ATTACHMENT_WORKFLOW_SLICE.md),
followed by conservative commentary-flag cleanup in
[docs/releases/M7_PORTABLE_COMMENTARY_FLAG_WORKFLOW_SLICE.md](docs/releases/M7_PORTABLE_COMMENTARY_FLAG_WORKFLOW_SLICE.md),
and opt-in commentary-name normalization in
[docs/releases/M7_PORTABLE_COMMENTARY_NAME_WORKFLOW_SLICE.md](docs/releases/M7_PORTABLE_COMMENTARY_NAME_WORKFLOW_SLICE.md),
followed by conservative forced-subtitle role marking in
[docs/releases/M7_PORTABLE_FORCED_SUBTITLE_WORKFLOW_SLICE.md](docs/releases/M7_PORTABLE_FORCED_SUBTITLE_WORKFLOW_SLICE.md),
and conservative SDH/hearing-impaired role marking in
[docs/releases/M7_PORTABLE_SDH_SUBTITLE_WORKFLOW_SLICE.md](docs/releases/M7_PORTABLE_SDH_SUBTITLE_WORKFLOW_SLICE.md),
followed by conservative audio-description role marking in
[docs/releases/M7_PORTABLE_AUDIO_DESCRIPTION_WORKFLOW_SLICE.md](docs/releases/M7_PORTABLE_AUDIO_DESCRIPTION_WORKFLOW_SLICE.md).

The first M8 performance harness is also checked in. Its release-mode,
synthetic-only responsiveness probe measures workflow compilation against a
200-track MKV model, scheduling from a 5,000-job production queue, and typed
cancellation-to-exit latency for a fixed five-second `/bin/sleep` child through
the real command runner. The JSON report contains architecture, macOS version,
processor count, workload sizes, latency statistics, and a workload checksum—
never a media path, title, host name, timestamp, or user file. Workflow and queue
budgets are 15 ms p95; the deliberately loose cancellation budget is 500 ms p95.
These are early regression tripwires, not claims about bundled media-tool
cleanup or physical Intel acceptance. See
[docs/releases/M8_RESPONSIVENESS_BASELINE_SLICE.md](docs/releases/M8_RESPONSIVENESS_BASELINE_SLICE.md).

A separate hidden app-baseline mode now builds and signs the real Universal app,
prohibits activation, creates zero windows, lays out the actual main AppKit view,
and reports bounded process round-trip, main-view readiness, and current
resident memory. The seven-round arm64 development observation remains a
provisional engineering baseline, not physical Intel/M1 or Finder-launch
acceptance. See
[docs/releases/M8_APP_BASELINE_PROBE_SLICE.md](docs/releases/M8_APP_BASELINE_PROBE_SLICE.md).

The main File menu now routes **Command-O** to the same local file/folder
chooser as the visible button. The main window, Queue, History, and saved-
workflow plan review set an intentional first keyboard target; plan review uses
Return to accept and Escape to cancel. Their primary lists, read-only details,
impact/source-safety text, dynamic queue actions, and status fields now expose
explicit VoiceOver names and concise help. The saved-workflow editor also begins
in its workflow list, names its builder controls, uses Command-S to save, and
explains why preview is disabled when no inspected media is selected.
Verified-output progress sheets focus Cancel, use Escape for safe cancellation,
name their status/progress, and explain why cancellation closes at atomic
commit. These native AppKit regressions are a baseline, not a claimed manual
keyboard-only or VoiceOver walkthrough. See
[docs/releases/M8_KEYBOARD_VOICEOVER_BASELINE_SLICE.md](docs/releases/M8_KEYBOARD_VOICEOVER_BASELINE_SLICE.md).

The follow-on every-window foundation now gives all 20 implemented AppKit
window-controller surfaces intentional first focus and explicit assistive
semantics. Modal workflow cancellation uses Escape where safe, and a source
gate prevents new windows without these contracts or custom motion without an
explicit Reduce Motion policy. This remains automated evidence, not an observed
VoiceOver or visual-accessibility-settings pass. See
[docs/releases/M8_EVERY_WINDOW_ACCESSIBILITY_FOUNDATION_SLICE.md](docs/releases/M8_EVERY_WINDOW_ACCESSIBILITY_FOUNDATION_SLICE.md).

Central workflow, Queue, and History failures now use one bounded message
contract: what failed, what remains safe or last-confirmed, how to retry, and a
single-line technical detail capped at 240 characters. This is the first M8
error-language slice, not a claimed every-window wording pass. See
[docs/releases/M8_ERROR_LANGUAGE_FOUNDATION_SLICE.md](docs/releases/M8_ERROR_LANGUAGE_FOUNDATION_SLICE.md).

All remaining AppKit catches that previously exposed a raw localized technical
error now use the same action, safe-state, recovery, and bounded-detail
contract. The source validation gate prevents that direct pattern from being
reintroduced. This is a source-level and automated-UI pass, not observed
VoiceOver, localization, or real-failure acceptance. See
[docs/releases/M8_ACTIONABLE_ERROR_LANGUAGE_PASS.md](docs/releases/M8_ACTIONABLE_ERROR_LANGUAGE_PASS.md).

The accessible-failure continuation routes dynamic AppKit failures through one
presenter that updates visible text, posts a native value-change notification,
and returns focus to an enabled recovery control when the failure has one.
Model failures are deduplicated so routine refreshes do not repeat the same
announcement. The pass also fixes live workflow renaming so its selected row
and subsequent Save validation remain intact. See
[docs/releases/M8_ACCESSIBLE_FAILURE_RECOVERY_SLICE.md](docs/releases/M8_ACCESSIBLE_FAILURE_RECOVERY_SLICE.md).

The native Window menu now makes the app's recurring workspaces reachable
without returning to the main window or hunting for a button: Command-0 shows
the main window, and Command-1 through Command-4 open Workflows, Queue, History,
and Encoding Test. Standard Minimize, Zoom, and Bring All to Front commands are
present too. See
[docs/releases/M8_WINDOW_MENU_KEYBOARD_SLICE.md](docs/releases/M8_WINDOW_MENU_KEYBOARD_SLICE.md).

The main window and all 20 implemented auxiliary windows now share one native
keyboard-navigation policy: each keeps an intentional starting control and asks
AppKit to own automatic key-view-loop recalculation as each window's contents
evolve. A source gate keeps future windows on that policy. This is automated
AppKit coverage, not a claimed manual Full Keyboard Access traversal. See
[docs/releases/M8_DYNAMIC_KEY_VIEW_LOOP_SLICE.md](docs/releases/M8_DYNAMIC_KEY_VIEW_LOOP_SLICE.md).

Common-format video and audio cards now resolve their native separator border
against the view's effective appearance and refresh it when that appearance
changes. This fixes stale Light/Dark borders without adding custom themes or
motion, and the source gate rejects future one-shot semantic-color conversion.
See
[docs/releases/M8_ADAPTIVE_APPEARANCE_FOUNDATION_SLICE.md](docs/releases/M8_ADAPTIVE_APPEARANCE_FOUNDATION_SLICE.md).

The Application menu now follows the standard macOS integration contract with
a registered Services submenu, Command-Option-H Hide Others, and Show All,
alongside the existing About, update, Hide, and Quit commands. See
[docs/releases/M8_STANDARD_APPLICATION_MENU_SLICE.md](docs/releases/M8_STANDARD_APPLICATION_MENU_SLICE.md).

A native Command-? Help window now keeps the essential getting-started,
output-safety, no-transcode, workflow, queue, keyboard, and privacy guidance
available offline inside the app. See
[docs/releases/M8_OFFLINE_HELP_WINDOW_SLICE.md](docs/releases/M8_OFFLINE_HELP_WINDOW_SLICE.md).

Help → Third-Party Software now opens a bounded, offline viewer for the notices
and complete license texts inside the installed app, including bundled-tool
licenses when that runtime is present. See
[docs/releases/M9_THIRD_PARTY_SOFTWARE_VIEWER_SLICE.md](docs/releases/M9_THIRD_PARTY_SOFTWARE_VIEWER_SLICE.md).

The coverage workflow now measures repository production sources only and
fails below conservative line, function, or region floors; tests, generated
runners, Sparkle, and other dependencies cannot inflate the gate. See
[docs/releases/M8_SOURCE_COVERAGE_GATE_SLICE.md](docs/releases/M8_SOURCE_COVERAGE_GATE_SLICE.md).
It also enforces the public-beta requirement of at least 80% collective non-UI
line coverage; the current bundled-runtime result is 88.64%. See
[docs/releases/M8_NON_UI_COVERAGE_GATE_SLICE.md](docs/releases/M8_NON_UI_COVERAGE_GATE_SLICE.md).

For safe recovery steps, unavailable-action prerequisites, queue/encoding
guidance, and privacy-safe support evidence, see the canonical
[troubleshooting guide](docs/TROUBLESHOOTING.md). The same guide is embedded in
the app and published beside every release.

The protected release path now applies the same exact-asset, checksum,
notarization-evidence, size-evidence, provenance, Gatekeeper, and bundled-tool
verifier to both the downloaded draft candidate and a fresh download of the
published release. See
[docs/releases/M9_PUBLISHED_RELEASE_READBACK_SLICE.md](docs/releases/M9_PUBLISHED_RELEASE_READBACK_SLICE.md).

Corresponding source is now read back semantically instead of trusted as an
opaque checksummed filename. Verification binds the source tar's Git commit to
the binary build metadata and proves the exact eight dependency archives,
hashes, build pins, safe layout, license, package locks, and build entry points.
See
[docs/releases/M9_CORRESPONDING_SOURCE_READBACK_SLICE.md](docs/releases/M9_CORRESPONDING_SOURCE_READBACK_SLICE.md).

The bundled media runtime now has an exact fail-closed layout contract before
copying and after signing/resealing; unrelated build caches or extra payloads
cannot ride inside the app. A real pinned-runtime DMG rehearsal passed both
ARM64 and Rosetta x86_64 tool launch checks. See
[docs/releases/M9_EXACT_RUNTIME_LAYOUT_SLICE.md](docs/releases/M9_EXACT_RUNTIME_LAYOUT_SLICE.md).

Release verification now goes beyond tool version output: the mounted signed
app creates, inspects, safely edits, verifies, preserves, and extracts a fixed
Matroska fixture under both ARM64 and x86_64 sandbox inheritance. See
[docs/releases/M9_SIGNED_FIXTURE_SMOKE_SLICE.md](docs/releases/M9_SIGNED_FIXTURE_SMOKE_SLICE.md).
A private `0.0.0` production rehearsal from exact source commit `113526c`
subsequently passed Developer ID signing, independent app and DMG notarization,
stapling, Gatekeeper, and both architecture fixture paths. It was not published
and does not replace final-tag, clean-account, physical-Intel, or updater
acceptance.

Public release is now a deliberate second phase. The signed-tag workflow can
only leave a fully verified draft; a separate manual workflow binds clean-account
Apple Silicon, clean-account Intel, and prior-version updater acceptance to the
exact candidate DMG digest before publication, then redownloads and reverifies
the public assets. See
[docs/releases/M9_TWO_PHASE_PUBLICATION_SLICE.md](docs/releases/M9_TWO_PHASE_PUBLICATION_SLICE.md).

The packaged app also exposes a path-free native release-verification command
for clean-account testing. It constructs the real main view, records bounded
startup memory facts, launches all five bundled tools, and completes the
verified-output fixture from the currently selected architecture without
reading user media. See
[docs/releases/M9_NATIVE_RELEASE_VERIFICATION_SLICE.md](docs/releases/M9_NATIVE_RELEASE_VERIFICATION_SLICE.md).

Prior-version updater acceptance now has a reproducible, fail-closed operator
path. It uses Sparkle's pinned external updater against a disposable prior-app
copy and a loopback-only signed feed, compares the archive signature to the
downloaded draft appcast, then prints the exact candidate DMG digest required by
the publication gate. The production app receives no alternate-feed capability.
See
[docs/releases/M9_SPARKLE_UPDATE_REPLACEMENT_SLICE.md](docs/releases/M9_SPARKLE_UPDATE_REPLACEMENT_SLICE.md).

A later private rehearsal from exact source commit `7a1fd82` signed and
notarized build `20260825`, verified both packaged architecture paths, and used
the production-key appcast to replace a disposable copy of notarized build
`20260824`. It was not published and does not replace final-version,
corresponding-source, downloaded-draft, clean-account, or physical-Intel gates.
See
[docs/releases/M9_PRIVATE_SPARKLE_REPLACEMENT_REHEARSAL.md](docs/releases/M9_PRIVATE_SPARKLE_REPLACEMENT_REHEARSAL.md).

Release build numbers are derived from the signed annotated tag's Unix tagger
timestamp, remain stable across workflow reruns, and must be newer than the
accepted private build `20260825`. The disposable package gate exercises that
10-digit build shape through app assembly, appcast generation, and real Sparkle
replacement. See
[docs/releases/M9_RELEASE_BUILD_NUMBER_SLICE.md](docs/releases/M9_RELEASE_BUILD_NUMBER_SLICE.md).

The release workflow also verifies live repository controls before any signing
or Apple submission. It requires a public repository, immutable releases, and
an active no-bypass `v*` tag ruleset that blocks deletion and force updates. On
August 25, 2026, the public repository enabled immutable releases and activated
that exact tag ruleset; the repository's live preflight passes. The hosted
workflow still uses a repository-scoped, Administration-read-only environment
token rather than a broad personal credential, and that narrow token is not
provisioned yet. See
[docs/releases/M9_REPOSITORY_RELEASE_CONTROLS_SLICE.md](docs/releases/M9_REPOSITORY_RELEASE_CONTROLS_SLICE.md).

Candidate notes for a possible 0.1.0 beta now describe only currently executable
capabilities and disclose the important roadmap gaps. The release workflow
rejects fixture, placeholder, unbounded, linked, missing, or version-mismatched
notes before runtime building or credential use. This preparation does not
create or commit to a release tag. See
[docs/releases/M9_RELEASE_NOTES_GATE_SLICE.md](docs/releases/M9_RELEASE_NOTES_GATE_SLICE.md).

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
- `actionlint`, `rg`, `shellcheck`, and standard Apple command-line developer
  tools
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

Measure synthetic large-track workflow compilation and production-queue
scheduling without reading any media:

```sh
./scripts/performance/benchmark-responsiveness.sh --enforce
```

Use `--quick` while developing. Run the standard enforced probe on both the M1
reference and a physical Intel Mac before treating its budgets as hardware
acceptance evidence.

## License

MKV Magic is licensed under GPL-3.0-or-later. Bundled components retain their
own licenses and notices; see `THIRD_PARTY_NOTICES.md` in release artifacts.
