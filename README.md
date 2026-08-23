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
the temporary and committed results and compares the exact nested chapter XML.
Manual ambiguity mapping, native trim controls, decode spot checks, attachment
selection, and native common-format execution remain pending. When a reviewed group
needs normalization, the same window now previews the proposed common video,
audio, and text-subtitle targets. Compatible lanes remain packet copies;
affected video is bounded to one generation using an encoder that passed a
local one-frame capability probe; affected audio lanes are converted once to
verified AAC without automatic downmix; and mixed SDR/HDR, Dolby
Vision, incomplete facts, and image-subtitle limitations fail closed or require
explicit choices. Behind that read-only preview, file-specific choices are now
bound to every inspected source fact and compiled into one bounded FFmpeg graph:
each affected video or audio lane is encoded exactly once, ordinary audio layouts
can be normalized without an automatic downmix, and explicitly approved missing
audio becomes exact-duration silence. Real bundled-tool fixtures decode the HEVC
and AAC results and prove that source bytes do not change. The internal
normalization executor now binds every source to a filesystem revision, invokes
that graph once, verifies the intermediate stream bundle's exact encoded lanes,
duration, Matroska structure, dimensions, bit depth, SDR color, audio layout,
and sample rate, and atomically commits only after a second reopen audit. Each
encoded segment is padded and trimmed to its reviewed source-container duration,
so an encoded video lane remains aligned with a directly copied audio lane even
when the source contains encoder padding. A final pure compiler now emits one
`mkvmerge` invocation that combines those verified normalized lanes with direct
packet-copy lanes, selected attachments and track metadata, one title, and the
exact nested joined chapters. It refuses overwrite, changed chapters/bundles,
unsafe paths or text, unpreserved tags, subtitle conversion, and subtitle gaps.
The revision-bound final executor now compiles that command again inside a
verified-output transaction, semantically audits the temporary MKV, re-extracts
and canonically compares its full nested chapter XML, commits atomically, then
repeats the complete audit after reopening the saved path. A real mixed-lane
fixture passes this transaction without changing either original. The native
preview still does not enable saving because exact choice controls and app-level
execution wiring are not implemented yet.

The internal Fast Trim path now scans the primary video track with bounded local
`ffprobe`, shows the first-keyframe-at-or-after adjustment for both requested
boundaries, and refuses to call the result frame-exact. For one-video Matroska
MKVs it uses `mkvmerge --split parts:` with no video or audio encode, clips and
rebases the complete nested chapter tree, writes that reviewed tree to the
temporary output, and verifies streams, metadata, attachments, duration,
segment identity, and canonical re-extracted chapters before commit and after
reopen. It rejects ordered editions and changed sources rather than guessing.
The native thumbnail/numeric Trim window and frame-exact encoding path remain
pending.
The currently bundled FFmpeg proves HEVC and H.264 VideoToolbox, ProRes, AAC,
and the required join filters on the running Mac. It has AV1 decoding but no AV1
encoder, so AV1 is not presented as available: HEVC 10-bit is the current
verified fallback. A pinned software AV1 sidecar remains planned before AV1
encoding can be selected.
Every action's sanitized queue lifecycle is persisted atomically in the app's
private Application Support container and is available from the lightweight
History report. No public release is available yet. The canonical product and
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

## License

MKV Magic is licensed under GPL-3.0-or-later. Bundled components retain their
own licenses and notices; see `THIRD_PARTY_NOTICES.md` in release artifacts.
