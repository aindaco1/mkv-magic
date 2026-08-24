# MKV Magic — Product Specification and Build Plan

**Status:** Scope locked for initial implementation

**Last updated:** 2026-08-24

**Purpose:** Canonical product, architecture, and delivery specification

This document supersedes informal planning notes. Decisions should be changed here before implementation diverges from them.

## 1. Project identity

| Item | Decision |
|---|---|
| Product name | MKV Magic |
| Repository slug | `mkv-magic` |
| Workspace directory | `mkv-magic` |
| Xcode project and app target | `MKV Magic` |
| Internal executable/module name | `MKVMagic` |
| Bundle identifier | `com.dustwave.mkvmagic` |
| App license | GPL-3.0-or-later |
| Distribution | Free, open source, direct download |
| Release trust | Developer ID signed and Apple notarized |
| Platform | macOS 13 Ventura or newer |
| Architectures | Universal Intel and Apple Silicon |
| Default output | Matroska (`.mkv`) |
| Privacy | Local-only processing, no telemetry, no LLM |

The app will be distributed outside the Mac App Store. Bundled tools retain their upstream licenses, source obligations, notices, versions, build options, and checksums.

## 2. Product definition

MKV Magic is a lightweight native macOS application for inspecting, cleaning, editing, joining, muxing, trimming, transcoding, and automating Matroska and other common media files.

Its differentiator is not merely exposing FFmpeg and MKVToolNix controls. Its core is an understandable workflow planner that chooses the least destructive execution path, combines compatible operations, and proves what happened before it replaces any source.

The primary personal playback targets are Jellyfin and Plex. The reference server is an M1 Mac mini, with successful AV1 playback already observed across the user's clients.

### Product promise

1. Do not transcode when a metadata edit, stream copy, remux, append, or selective encode will work.
2. When video encoding is unavoidable, encode the video only once per final output.
3. Explain quality loss, compatibility, duration, track, HDR, and source-file consequences before running.
4. Preserve source files until the result passes verification.
5. Make powerful workflows feel like plain-language recipes rather than shell scripts.

## 3. Product principles

### 3.1 Inspect, plan, preview, run, verify

Every operation follows the same lifecycle:

1. Inspect inputs.
2. Compile user intent into an execution plan.
3. Show a before/after preview and transcode impact.
4. Run against temporary outputs.
5. Verify expected results.
6. Move originals to Trash only when explicitly enabled and verification succeeds.

### 3.2 Lossless-first planning

The planner selects the lowest-cost valid mechanism in this order:

1. `mkvpropedit` for Matroska properties and chapters that can be changed in place.
2. `mkvmerge` for remuxing, structural track changes, append operations, and Matroska output.
3. `mkvextract` for track, attachment, tag, cue, timestamp, and chapter extraction.
4. FFmpeg stream copy for compatible non-Matroska operations.
5. FFmpeg selective audio or subtitle processing.
6. FFmpeg video decoding, filtering, and a single final video encode.

### 3.3 Local and deterministic

- No local or remote LLM is required.
- No online metadata lookup is included in v1.
- English subtitle correction uses deterministic rules and offline dictionaries.
- Commands are generated as executable plus argument arrays, never passed through a shell.
- Network access is unnecessary for media processing. The only permitted in-app network path is a user-initiated, signed software-update check delegated to Sparkle's sandboxed services.

### 3.4 Lightweight and native

- Native Swift and AppKit, not Electron or a browser-hosted interface.
- System frameworks are preferred over large third-party UI dependencies.
- Expensive inspection and processing never runs on the main thread.
- The UI remains responsive during probing, thumbnail generation, analysis, muxing, and encoding.

### 3.5 Reference-repository engineering standard

MKV Magic adopts the durable practices proven in the Record and Podcast Visualizer repositories while keeping its media-editing domain independent:

- Source media and completed outputs are immutable inputs. Destructive-looking actions are explicit, transactional commits after verification.
- State machines and job transitions are typed, deterministic, persisted where recovery requires it, and independently testable from AppKit.
- System APIs, Sparkle, filesystem access, SQLite, and every bundled executable sit behind narrow adapters. Domain and planning targets do not import UI or process-launch code.
- Reusable media-time, track, chapter, subtitle, workflow, planning, and verification policy lives in focused Swift modules rather than view controllers or command-specific features.
- Hosted CI calls the same repository scripts used locally; release logic is not duplicated inline across workflows.
- A cross-repository shared package is introduced only after the same stable abstraction has two real consumers. MKV Magic does not depend directly on either reference app, and it does not pull their JavaScript runtime into this native app merely to reuse small algorithms.
- Every defect receives a regression test at the lowest useful layer. Privacy, entitlement, path-containment, signature, original-preservation, and one-generation guards may not be weakened to make a test pass.
- Failures are actionable and privacy-safe: explain the failed stage, preserve recoverable data, identify a next step, and make diagnostic export optional.
- Performance changes begin with a repeatable baseline and end with recorded wall-time, memory, artifact-size, and responsiveness evidence.

## 4. Success criteria

The initial public release is successful when all of the following are true:

- A new user can add a file, understand its tracks, choose a quick action, preview the outcome, and run it without reading documentation.
- The same media intent produces the same execution plan and commands on repeated runs.
- Planner tests prove that metadata-only and stream-copy workflows do not invoke a video encoder.
- A workflow with multiple video-affecting steps produces at most one final video encoding stage.
- Cancellation, a tool crash, corrupt input, insufficient space, permission denial, or verification failure never causes the original to be deleted or replaced.
- Nested chapters survive MKV round-trip extraction and validation.
- The optional Jellyfin-compatible chapter flattening produces the expected leaf timeline.
- Signed and notarized builds run on tested Intel and Apple Silicon Macs without separately installed tools.
- Real beta files covering H.264, HEVC, AV1, HDR10, stereo, 5.1, 7.1, text subtitles, image subtitles, attachments, tags, and chapters pass the acceptance matrix.

Performance targets are goals to validate on reference hardware, not reasons to weaken correctness:

- Cold launch target: under 2 seconds on the M1 reference Mac and under 4 seconds on the Intel reference Mac.
- Idle resident-memory target: under 100 MB after the main window settles.
- Lightweight metadata edits should begin promptly without waiting for unrelated thumbnail or deep-analysis work.

## 5. Initial-release scope

### 5.1 Media inspection

For every input, show:

- Container, duration, size, overall bitrate, and creation metadata.
- Video codec, profile, level, resolution, frame rate, pixel format, bit depth, color primaries, transfer, matrix, HDR10 metadata, and Dolby Vision presence when detectable.
- Audio codec, language, name, sample rate, channel count, channel layout, bitrate, and default/forced/commentary/descriptive role.
- Subtitle codec, language, name, text/image type, default/forced/SDH/commentary role, and external-file match.
- Chapters, editions, nested hierarchy, languages, names, start/end times, and flags.
- Attachments, MIME types, filenames, sizes, and likely roles such as font or cover art.
- Global tags, segment title, track tags, and track flags.

The inspector uses `mkvmerge -J` for Matroska-specific structure and `ffprobe` JSON for cross-format stream and codec information. The app normalizes both into a single internal media model.

### 5.2 Quick actions

The main window exposes these first-class actions:

1. Clean MKV
2. Clean Subtitles
3. Add Subtitles or Audio
4. Edit Tracks
5. Create or Edit Chapters
6. Join Files
7. Trim or Split
8. Convert
9. Extract
10. Build Workflow

Each action opens a focused inspector with a concise default path and an Advanced disclosure area.

### 5.3 Clean MKV

The safe default preserves all video, audio, subtitle, chapter, and font data. It may propose, but does not silently perform, destructive cleanup.

Default behavior:

- Preserve every video and audio track bit-for-bit unless the workflow explicitly converts one.
- Preserve every subtitle track.
- Preserve chapters and chapter hierarchy.
- Preserve subtitle font attachments.
- Identify empty tracks, malformed metadata, redundant tags, promotional attachments, and suspicious flags.
- Normalize language codes, commentary labels, forced/default/enabled flags, and empty or release-noise track names only after preview.
- Keep every track enabled even when it is not default.
- Preserve the existing default audio unless the workflow explicitly changes it.
- Mark recognized forced subtitles as forced.
- With English audio, leave normal English subtitles optional.
- Without English audio, propose the best English subtitle as default.

The built-in **English Library Cleanup** preset may:

- Keep English and unknown-language subtitles.
- Remove other subtitle languages after showing the removal list.
- Prefer non-SDH English when both SDH and non-SDH versions exist.
- Preserve the only available English/unknown subtitle even when it is SDH.
- Preserve commentary, alternate audio, signs-and-songs subtitles, and chapters unless explicitly deselected.

### 5.4 Subtitle cleanup

V1 text cleanup supports SRT first and ASS/SSA with style-preserving text edits. Text-based tracks embedded in containers can be extracted, cleaned, reviewed, and remuxed.

Capabilities:

- Detect and normalize common text encodings to UTF-8.
- Normalize line endings, BOM usage, blank lines, sequence numbering, and accidental whitespace.
- Remove known advertisement blocks, including the YTS/YIFY patterns in the existing scripts.
- Apply high-confidence English OCR-error rules automatically.
- Use an offline English dictionary to suggest uncertain spelling corrections.
- Present uncertain changes in a before/after review.
- Never silently change probable names, uncommon dialogue, timings, or styling.
- Preserve subtitle timing unless the user invokes a timing action.
- Show removed or changed subtitle blocks and allow individual restoration.

Image-subtitle OCR is not in v1. PGS and VobSub tracks can be inspected, extracted, copied, removed, and muxed unchanged. Image-to-text OCR is a roadmap item.

### 5.5 Subtitle and audio muxing

The external-track matcher ranks candidates by:

1. Exact basename.
2. Normalized title and year.
3. Season/episode token such as `S01E02` or date-based episode identifier.
4. Language token.
5. `forced`, `sdh`, `commentary`, or descriptive-audio token.
6. Duration compatibility when the external file provides usable timing information.

Supported initial external inputs include SRT, ASS/SSA, VobSub IDX/SUB, common audio files, and chapter files. Ambiguous matches always require confirmation.

The mux preview shows the resulting track order, names, languages, flags, and whether any track will be converted.

### 5.6 Track editor

The track editor supports single-file and bulk changes:

- Include/exclude tracks.
- Reorder tracks.
- Edit names and BCP 47/ISO language metadata.
- Edit default, forced, enabled, commentary, and descriptive roles.
- Normalize commentary naming as `Commentary`, `Commentary #2`, and so forth.
- Copy settings across selected files by matched track role rather than brittle numeric IDs.
- Preview unsupported or contradictory flag combinations.

Bulk matching uses type, language, role, channel layout, codec compatibility, and user-confirmed overrides.

### 5.7 Chapter creation and editing

Chapter creation and editing are core v1 features.

The chapter editor provides:

- A table and thumbnail timeline representing the same model.
- Add, remove, duplicate, move, reorder, rename, nest, and unnest.
- Numeric start and end entry with frame-aware validation.
- Dragging and snapping to exact frames, keyframes, detected scenes, black frames, silence boundaries, and joined-file boundaries.
- Import/export for Matroska XML and simple chapter text.
- Extract/replace chapters in an MKV without a full remux when supported.
- English chapter language by default, with editable language and country.
- Edition flags, nested atoms, end times, and stable regenerated UIDs.

Automatic suggestions are offline analysis, never semantic invention:

- At each joined-file boundary.
- At a configurable fixed interval.
- At scene changes.
- At black-frame boundaries.
- At silence boundaries.

Suggestions require review. Automatic names use embedded source title, cleaned source filename, then `Part 1`, `Part 2`, etc. Generic child names use `Chapter 01`, `Chapter 02`, etc.

#### Default hierarchy for joined files

```text
Default Edition
├── Part 1 — Source Title
│   ├── Chapter 01
│   ├── Chapter 02
│   └── Chapter 03
├── Part 2 — Source Title
│   ├── Chapter 04
│   └── Chapter 05
└── Part 3 — Source Title
    ├── Chapter 06
    └── Chapter 07
```

Parent atoms span the full retained duration of their source section. Child atoms preserve source names and receive output-global timestamps.

The default output is nested Matroska chapters. **Flatten for Jellyfin compatibility** is an explicit option because Jellyfin's current chapter ingestion model does not retain parent/child relationships.

#### Joined chapter algorithm

For each source in final timeline order:

1. Extract its complete chapter XML.
2. Preserve edition and display metadata for editing.
3. Intersect chapter ranges with retained trim ranges.
4. Remove chapters outside retained content.
5. Clamp chapters crossing a retained boundary.
6. Subtract the source's retained start offset.
7. Add the cumulative duration of preceding retained sources.
8. Regenerate UIDs to avoid collisions.
9. Remove only verified duplicates at exact joins.
10. Create a parent atom spanning the retained source section.
11. Add a boundary child when the source has no chapters.
12. Write one final default edition and validate by re-extraction.

### 5.8 Joining files

Users drag files into final order and may preview the join timeline before processing.

Rules:

- Use lossless MKV append/remux when stream parameters and mappings are compatible.
- Use hard joins only. Crossfades and editorial transitions are outside the product scope and roadmap.
- Produce one final media file per joined group.
- Recalculate nested chapters and source boundaries.
- Present an explicit track-mapping table.
- Never silently discard an unmatched track.
- When normalization is required, propose one common output plan and encode each affected output stream once.

Tracks are paired by type, language, role, channel layout, and codec compatibility. The user confirms uncertain mappings.

For differing audio layouts, the default proposal preserves the largest layout without fabricating surround information:

- Same layout/different codecs: recommend AAC, then offer each locally verified
  AAC, Opus, AC-3, E-AC-3, or FLAC target that can represent the reviewed lane.
- Stereo plus 5.1: continuous 5.1 in the chosen format; stereo material occupies
  front left/right and other channels remain silent.
- 5.1 plus 7.1: continuous 7.1 only in a format whose exact target layout is
  verified; unavailable channels remain silent during 5.1 material.
- Never downmix automatically.
- A format change resets approval and remains part of the same single fused
  normalization pass as any required video conversion.

For differing video properties, propose but do not silently choose resolution, frame-rate behavior, pixel format, color space, HDR policy, and codec.

Mixing HDR and SDR requires an explicit choice:

- Tone-map all content to SDR.
- Convert all content into an HDR10 signal, with a warning that SDR gains no real dynamic range.
- Cancel and keep sources separate.

### 5.9 Trimming and splitting

The trim UI uses thumbnails plus numeric in/out fields.

- **Fast and lossless:** keyframe-aligned stream-copy cut; the preview shows any timestamp adjustment.
- **Frame-exact:** exact requested boundary with a video transcode.
- Split by timestamp, chapter, duration, size, or selected ranges where the underlying tools support it safely.
- Preserve and recalculate chapters, subtitles, audio timing, and tags across retained ranges.
- Never describe a keyframe-aligned cut as frame-exact.

### 5.10 Transcoding

Full transcoding is included in v1 but remains the last planning resort.

Current implementation: **Convert Video…** provides a reviewed, full-file
transcode to MKV for eligible inspected MKV, MP4, M4V, MOV, and chapter-free
WebM inputs. It reuses the Exact Trim encoder compiler and verified-output
transaction, so the selected video is encoded exactly once. Compatible audio
is packet-copied by default; an incompatible common-container audio codec must
use one explicitly selected, locally verified layout-preserving conversion.
For MKV input, subtitle tracks are copied, attachments and track metadata are
preserved, and the original nested chapter document is reinstalled and
canonically verified without retiming. For MP4/M4V/MOV input, inspected chapter
entries become one default nested Matroska edition and the single recognized
QuickTime `bin_data` chapter carrier is not mapped as media. Common-container
input must have one video, no subtitle or attachment tracks, a stable unique
stream map, unambiguous chapter facts, only reviewed title/track metadata plus
known container provenance, and complete supported color/HDR facts. Chaptered
WebM and unknown or ambiguous data fail closed. Complete conversion emits no
seek or duration cap and compares streaming ordered packet hashes for copied
audio and MKV subtitles before commit and after reopen. The compact native sheet
defaults to the locally recommended verified AV1/HEVC/H.264/ProRes choice, keeps
every compatible verified alternative, and uses a deterministic
`— Converted.mkv` destination. Multiple video tracks, source tags on MKV,
unsupported or incomplete HDR/color facts, and non-MKV outputs fail closed.

Saved workflows now expose the same complete-file conversion as portable intent:
**Recommended for this Mac**, AV1, HEVC, H.264, or ProRes. Plan review resolves
and names the exact locally verified preset; the portable JSON retains only the
intent. The separate lossless-first conditional converts with the same local
recommendation only when the inspected video is not already AV1 or HEVC; a
modern source skips that card, its dependent audio card, and the capability
probe. At most one conversion card may be present. A conversion-only workflow
encodes directly to the final verified output. When deterministic track,
subtitle, or title steps also apply, MKV Magic first creates a private
verified packet-copy/metadata intermediate and then performs exactly one final
video encode. It never chains conversion generations. Audio and text subtitles
remain packet-copied by default. One audio card may instead choose AAC, Opus,
AC-3, E-AC-3, or FLAC as the target for every retained audio track. Tracks already
in that codec remain packet copies; only mismatched tracks require the active
encoder probe and exact layout/rate policy. With video conversion, those
mismatched tracks are encoded once inside the same FFmpeg process as the one
video generation. Without video conversion, one audio-only FFmpeg process
packet-copies video, subtitles, and matching audio, and independent packet
fingerprints prove those copied payloads. When every audio track already matches,
the audio card is skipped without requiring an encoder.
Queue reinspection must reproduce the codec-bearing, audio-policy-bearing
semantic plan before automatic execution. The reviewed source revision is
retained through both immediate and queued starts.

#### Video presets

| User-facing choice | Preferred implementation | Intent |
|---|---|---|
| Best Compression | SVT-AV1 10-bit software | Preferred when time permits |
| Fast | HEVC 10-bit VideoToolbox | Recommended for slow Intel Macs and time-sensitive work |
| Most Compatible | H.264 8-bit VideoToolbox or software fallback | Broad playback support |
| Editing/Master | ProRes | Post-production interoperability |

AV1 uses constant-quality controls with simple quality labels and advanced RF/preset controls. Actual defaults are selected from benchmark results on the beta corpus rather than copied blindly from another application.

#### First-run capability benchmark

With user consent, MKV Magic runs short local AV1 and HEVC test encodes and records:

- Available encoders/decoders and hardware paths.
- Frames per second and estimated real-time factor.
- A representative output bitrate and quality result.
- A recommended encoder for that Mac.

The result drives recommendations, never removes user choice. Old Intel systems may default to HEVC VideoToolbox when SVT-AV1 is impractically slow.

Current implementation: **Encoding Test…** is an explicit native action; it
does not run at launch or before metadata/remux work. It generates a private,
three-second 640×360 P010 fixture, measures the verified AV1 and HEVC paths with
their real app arguments, records encode FPS, output bitrate, and PSNR, and
scales measured throughput into a conservative 1080p real-time estimate. AV1
remains the quality-first recommendation at an estimated `0.5×` real time or
better; otherwise a completed HEVC VideoToolbox result becomes the initial
choice. A timeout is recorded as performance evidence instead of discarding a
successful alternative. The bounded, versioned report is stored with `0600`
permissions and is applied only when the FFmpeg SHA-256, process architecture,
and active processor count still match. It contains no user-media identity,
and every verified encoder remains selectable.

#### Audio presets

Audio is copied by default. Exact Trim can explicitly encode once to AAC through
AudioToolbox, stable libopus, AC-3, E-AC-3, or lossless FLAC. A format appears
only after its local encoder smoke succeeds and every selected track has a known
layout/sample rate that the target can represent without implicit downmix or
rematrixing. Opus explicitly targets its standardized 48 kHz Matroska clock;
other accepted Exact Trim inputs retain their sample rate.

| Preset | Mono | Stereo | 3–6 channels | 7–8 channels |
|---|---:|---:|---:|---:|
| AAC | 96 kbps | 192 kbps | 384 kbps | 512 kbps when the exact layout is representable |
| Opus | 96 kbps | 160 kbps | 384 kbps | 512 kbps |
| AC-3 | 192 kbps | 256 kbps | 640 kbps | Not offered |
| E-AC-3 | 192 kbps | 256 kbps | 768 kbps | Not offered |
| FLAC | Lossless | Lossless | Lossless | Lossless |

Common-format Join uses the same bounded audio preset policy per lane. AAC is the
compatibility-first default when it is verified and representable. Otherwise the
first verified compatible choice is selected; for example, a reviewed 7.1 lane
can offer Opus and FLAC while hiding AC-3/E-AC-3 and an unrepresentable AAC
layout. Join may explicitly normalize 5.1 versus 5.1(side) channel order without
changing the six-channel count, and discloses the final reviewed layout.

#### Input and output containers

- Accept common FFmpeg-readable media as input, with Matroska-specific editing enabled only when the container supports it.
- Default every compatible conversion, join, and remux to MKV.
- Offer MP4/MOV and WebM output when the selected video, audio, subtitle, chapter, and attachment combination is valid for that container.
- Filter or explain invalid combinations instead of producing a file that nominally muxes but will not play reliably.
- Preserve a source container during a copy-only operation when the workflow requests it and all planned changes are supported.
- Treat less-common FFmpeg output containers as Advanced choices added only after fixture and playback validation; “any container” does not mean bypassing compatibility rules.

Current implementation: **Remux to MKV…** accepts an inspected MP4, M4V, MOV,
or chapter-free WebM with one video track and a known positive duration when
every media codec is approved for Matroska packet copy. The current allowlist
covers AV1, H.264, HEVC, ProRes, VP8, VP9, MPEG video; AAC, AC-3, E-AC-3, Opus,
Vorbis, FLAC, ALAC, PCM, MP3, DTS, and TrueHD audio; and SRT, ASS, SSA, WebVTT,
PGS, and VobSub subtitles. One shell-free `mkvmerge` invocation preserves media
order and promotes an inspected MP4/MOV chapter carrier into Matroska chapters.
The immutable review records zero video and audio encodes. Before commit and
after reopening, verification compares duration, codec and technical facts,
track language/name/roles, title, chapter count/titles/timing, attachment
absence, and a new segment identity, then performs a streaming ordered-packet
fingerprint for every copied track. The source revision is checked throughout,
and the original is never replaced. MP4 TX3G timed text requires the separate
explicit text-conversion action specified in section 5.13. Chaptered WebM,
attachments, arbitrary data, multiple video tracks, and unknown codecs fail
closed rather than receiving a partial preservation claim. Alternate output
containers and preserve-container copy remain roadmap work.

### 5.11 HDR and Dolby Vision safety

- Stream copy preserves the encoded stream and its metadata.
- HDR10 transcodes preserve 10-bit processing, BT.2020 primaries, PQ transfer, matrix information, mastering-display metadata, and content-light metadata when available.
- Verification compares expected color/HDR metadata with the output.
- A preservation workflow fails or warns instead of silently emitting incorrect colors.
- Exact Trim and uniform-HDR common-format Join accept only a validated static HDR10 signal. Joined sources must have identical mastering-display and content-light values because one output lane cannot truthfully carry multiple static signals.
- AV1 carries the validated static signal in both its encoded stream and Matroska output. HEVC VideoToolbox preservation is guaranteed at the Matroska container layer; raw elementary-stream MDCV/CLL preservation is not claimed.
- Common-format Join accepts mixed validated static HDR10 and BT.709 SDR. It defaults to BT.709 SDR, applies one bounded local Mobius tone map only to each HDR10 Part, leaves SDR Parts in BT.709, and fuses the result into the lane's one encoded generation. The review discloses and requires approval of that conversion.
- SDR-to-HDR signaling, HDR10+, and HLG remain blocked until their pixel transforms and verification contracts are implemented.
- Dolby Vision is preserved during compatible stream-copy operations.
- Any transcode whose Dolby Vision result cannot be guaranteed requires an explicit warning and choice.
- No operation silently strips Dolby Vision metadata.

### 5.12 Filename cleanup

Filename cleanup is a separate workflow action, never an implicit part of media cleaning.

- Movie: `Movie Title (Year).mkv`
- Episode: `Show Name (Year) - S01E02 - Episode Title.mkv`
- Preserve provider IDs and version suffixes when already present.
- Never guess or rename an ambiguous file without confirmation.
- Do not perform online title or episode lookup in v1.

### 5.13 Attachments, tags, and extraction

- Inspect, add, replace, extract, and remove attachments.
- Recognize and preserve common subtitle font types by default.
- Identify likely cover art and unknown attachments.
- Inspect, export, replace, and clear global or track tags.
- Extract tracks, subtitles, chapters, attachments, cues, and timestamps.
- Convert MP4 TX3G text subtitles to a supported editable text format through an explicit action.

### 5.14 Saved workflows

V1 workflows are ordered, plain-language recipes rather than node graphs.

Example:

```text
For every MKV
→ Clean subtitle text
→ If present, remove non-English subtitles
→ If redundant, remove English SDH subtitles
→ Prefer English track flags
→ Convert video only when not already AV1 or HEVC
→ Verify
→ Replace original after success
```

Workflow cards may include simple conditions such as codec, container, language, resolution, HDR presence, track role, or file type.

Every card and compiled plan displays one of:

- No transcoding
- Audio-only transcode
- Video transcode required

Workflows can be named, duplicated, added to, reduced, reordered,
enabled/disabled step-by-step, and exported/imported as versioned human-readable
`.mkvmagic-workflow` JSON. Add Step exposes the safe portable card catalog in a
stable order, disables actions already present, and excludes the legacy combined
cleanup action from new authoring. Removing the final card is allowed while
editing, but Save & Preview still requires at least one enabled card.

The first conditional implementation separates explicitly non-English subtitle
removal from redundant English SDH removal. Each condition is evaluated against
the selected inspection; all applicable stable UIDs are unioned into one removal
operation and one verified remux even when metadata work appears between the
cards. The saved recipe never contains media paths or track identity. The legacy
combined English Library Cleanup action remains decodable and executable for
portable workflow compatibility.

Save & Preview evaluates every recipe card in its original order and opens a
native review before installing a runnable plan. Applied, already-satisfied, and
disabled cards are visually distinct; the review also states the fused tool
passes, video-encode count, one-output transaction, and unchanged-source
contract. The user must explicitly choose **Use This Plan** before **Verify &
Run** is enabled. A recipe with no applicable changes shows its skipped cards,
offers only Done, and creates no destination.

The first interactive input card adds one external SRT, ASS, or SSA subtitle.
The portable recipe stores only that input-slot intent: it contains no path,
bookmark, track metadata, subtitle text, or inspected-media identity. Save &
Preview asks for the file, runs the existing local match and editable metadata
confirmation, and binds that ephemeral review to the compiled plan. Compilation
fails closed if the input is absent or its reviewed path/format changes. Track
cleanup and subtitle addition fuse into one `mkvmerge`; optional segment-title
removal runs once on that temporary output before the normal pre-commit and
post-commit audits. The subtitle card alone preserves the reviewed normalized
source content and only discloses cleanup suggestions.

The dependent **Clean the added subtitle text** card makes those suggestions an
explicit per-run review. It is authorable only after the external-subtitle card;
disabling or removing its input card also disables or removes the dependent
cleanup card. Accepted deterministic ad, whitespace, and English OCR changes
exist only in the active plan and feed the external subtitle's private temporary
payload. They do not create a cleaned sidecar or another remux. SRT and ASS/SSA
payloads selected by this card are re-extracted and semantically compared before
commit and after reopening the final MKV. Source and sidecar content hashes must
still match the reviewed revisions. Schema v3 introduced only the cleanup
action—not a path, subtitle text, metadata, cue/event selection, or review
identifier—and current schema v9 preserves that boundary. v1-v8 workflows
migrate without changing recipe or step identity, order, enablement, or action
semantics; a file cannot claim an older schema while using a newer action.
When the user explicitly adds this reviewed run to the production queue, its
private queue record separately stores two narrow bookmarks and revisions plus
the sidecar format, reviewed track metadata, 32-byte source digest, and restored
cleanup-change identifiers. It never adds those file-specific facts to the
portable workflow or stores subtitle text or a path.

Schema v8 adds five standalone **Convert all audio** actions. The editor permits
one without a video card and keeps it when a video card is removed or disabled.
Compilation applies one target format to every retained audio track, packet-copies
tracks already in that codec, fails closed when a mismatched track cannot use the
local encoder or preserve its exact layout and sample rate, and reports the exact
number of audio generations. A matching-only card is skipped without capability
probing. Audio-only execution packet-copies video, subtitles, and matching audio
and independently fingerprints their encoded packets.
If a video conversion is also applicable, both policies compile into the same
single FFmpeg process. Imported schema-v6 **With video conversion** actions keep
their historical dependency and are not emitted by the current editor.

Schema v9 adds **If needed: Remux compatible media to MKV** as portable
container intent. For compatible inspected MP4, M4V, MOV, or chapter-free WebM,
the compiler resolves current stream indexes and any MP4 chapter carrier into a
zero-encode `mkvmerge -> verify -> commit` plan; none of those file-specific
facts enter the recipe JSON. For MKV input, the card is already satisfied and
other existing Matroska cards may still apply. While remux is active on non-MKV
input, only filename cleanup may accompany it: track, metadata, subtitle, and
transcode cards fail closed until the compiler can map their semantics across
container identities without guessing. The editor prevents those active
combinations but retains disabled cards. The automatic queue re-inspects and
recompiles schema-v9 intent, requires the same reviewed semantic plan and exact
source revision, classifies it as lightweight work, and executes through the
same packet and chapter verifier as the standalone action.

V1 exposes the generated FFmpeg/MKVToolNix commands with Copy buttons but does not execute arbitrary shell commands.

### 5.15 Queue and history

- Add individual files, joined groups, or recursively scanned folders.
- Inspect multiple files concurrently within bounded limits.
- Run one heavy software video transcode by default.
- Permit several lightweight metadata/remux operations when safe.
- Reduce default activity on battery power.
- Pause, resume, reorder, retry, and cancel.
- Continue past an independent file failure.
- Never Trash a failed job's source.
- Persist job state so interrupted safe jobs can be re-planned or retried.
- Store plan, tool versions, commands, progress, result, verification report, and sanitized diagnostic log.

## 6. Workflow compiler and optimizer

The workflow compiler is a testable domain service independent of AppKit.

### 6.1 Core models

- `MediaAsset`: input path/bookmark, fingerprint, container, streams, metadata, chapters, attachments.
- `MediaTrack`: type, codec parameters, language, role, flags, timing, and source identity.
- `ChapterTree`: editions and nested atoms with nanosecond-based rational time.
- `WorkflowDefinition`: portable user intent and conditions.
- `WorkflowStep`: one declarative transformation.
- `ExecutionPlan`: ordered analysis, copy, remux, encode, metadata, validation, and commit stages.
- `PlanImpact`: quality loss, video/audio encode counts, copied data, compatibility warnings, and estimated resources.
- `Job`: persisted execution state and progress.
- `VerificationReport`: expected-versus-observed output contract.

### 6.2 Compilation passes

1. **Inspect:** normalize MKVToolNix and FFprobe data.
2. **Resolve conditions:** apply workflow steps to each file or joined group.
3. **Build timeline:** calculate retained ranges, joins, stream mapping, and chapter offsets.
4. **Resolve capabilities:** probe bundled tools and current Mac hardware.
5. **Choose mechanisms:** property edit, remux, copy, selective encode, or full encode.
6. **Fuse transformations:** combine compatible video and audio filters into one graph per final stream.
7. **Order structural work:** analysis before encoding; muxing and metadata after media production.
8. **Validate safety:** space, destination, permissions, collisions, unsupported combinations, HDR/DV rules.
9. **Render commands:** executable and arguments plus machine-readable progress configuration.
10. **Emit preview:** exact impact, warnings, commands, output path, and verification contract.

### 6.3 One-generation rule

A plan may read or analyze media several times, but it must not encode an intermediate lossy file and then encode that result again.

For one final output:

- Trimming, concatenation, scaling, cropping, deinterlacing, frame-rate work, color conversion, and subtitle burn-in are fused into one video filter graph where compatible.
- The graph feeds one final video encoder.
- Each audio track is copied or encoded once.
- Chapter and subtitle text analysis does not trigger video encoding.
- Two-pass rate control is permitted because its first pass is analysis; the final encoded generation remains one.
- A plan that cannot honor this rule fails compilation with an explanation instead of silently cascading encodes.

## 7. Safety and verification

### 7.1 Output transaction

1. Resolve an explicit destination and collision policy.
2. Confirm sufficient working and final disk space with a safety margin.
3. Create a uniquely named temporary output on the destination volume where possible.
4. Run the compiled plan without modifying the source.
5. Flush and close the output.
6. Verify the output contract.
7. Atomically move the verified result into its final name where the filesystem permits.
8. If replacement is enabled, move the source to macOS Trash using a recoverable API.
9. Never permanently delete a source as part of normal operation.

Because `mkvpropedit` edits a file in place, safe metadata-only jobs operate on an APFS clone when available, then verify and commit the clone. On filesystems without clone support, MKV Magic creates a normal temporary copy or asks the user to choose an explicitly less-safe direct-edit mode. The default never edits the only source copy before verification.

Default non-replacement naming is `Original Name — MKV Magic.mkv`. Replacement gives the verified result the source's final filename only after the source is safely in Trash.

### 7.2 Verification levels

**Standard verification:**

- Output exists, is non-empty, and is readable by both relevant inspectors.
- Container and requested codec/profile are correct.
- Duration matches the planned timeline within operation-specific tolerance.
- Expected track count, order, types, languages, layouts, names, and flags match.
- Chapters round-trip with expected hierarchy and timestamps.
- Expected attachments and tags are present or absent.
- Color and HDR metadata match the contract.
- Decode spot checks succeed near the start, middle, end, and joins.
- Subtitle text parses and expected cleaned blocks are present/removed.

**Strict verification:**

- Adds a full decode scan where practical.
- Adds more join and seek-point checks.
- Compares stream fingerprints or packet-level invariants for streams promised as copied.

Trash-after-success requires at least Standard verification. Any failed required check blocks replacement and preserves the temporary output for diagnosis when useful.

## 8. Application architecture

### 8.1 Stack

- Swift with AppKit-first UI.
- AVFoundation for lightweight playback, thumbnail extraction, and time presentation when compatible.
- Swift Package Manager for modular source organization and tests.
- Foundation `Process` with explicit arguments and pipes for bundled tools.
- System SQLite for durable queue/history state; versioned JSON for portable workflows.
- Structured concurrency with bounded task groups and cancellable subprocess supervision.

AppKit is chosen over a web wrapper to minimize baseline resource use and retain predictable behavior on Intel systems. SwiftUI may be used only for isolated components if measurement shows no regression; it is not the architectural center.

### 8.2 Modules

```text
MKVMagic
├── App                 lifecycle, menus, settings, update surface
├── Domain              media, tracks, chapters, workflows, plans
├── Inspection          ffprobe and MKVToolNix normalization
├── Planning            condition resolver and workflow compiler
├── Execution           subprocesses, progress, cancellation, temp files
├── Verification        output contracts and reports
├── Persistence         workflows, bookmarks, queue, history
├── Features
│   ├── Clean
│   ├── Subtitles
│   ├── Tracks
│   ├── Chapters
│   ├── Join
│   ├── Trim
│   ├── Transcode
│   └── Extract
├── UI                  AppKit views, controllers, inspectors
└── Support             logging, diagnostics, licensing, utilities
```

### 8.3 Main-window structure

- Sidebar: Quick Actions, Workflows, Queue, History.
- Center: dropped files, joined groups, workflow cards, or jobs depending on selection.
- Inspector: media tracks, properties, warnings, and advanced settings.
- Persistent bottom summary: output, `0/1 video encodes`, estimated time/size, Verify & Run.

The main File menu's **Command-O** opens the same bounded local chooser as the
visible file button. Main, Queue, History, and saved-workflow review windows set
an intentional initial keyboard target. Their core lists, details, impact and
safety summaries, dynamic actions, and status fields expose explicit VoiceOver
names and help; plan review uses Return to accept and Escape to cancel. These
contracts have AppKit regressions. The saved-workflow editor begins in its
workflow list, exposes explicit builder semantics, uses Command-S to save, and
explains its unavailable preview prerequisite. Verified-output progress begins
on Cancel, maps Escape to safe cancellation, names status/progress, and explains
why cancellation closes at atomic commit. A packaged manual keyboard/VoiceOver
walkthrough and the rest of the app surface remain M8 acceptance work.

The chapter editor is a dedicated window or workspace with a synchronized outline/table, timeline, thumbnails, analysis suggestions, and inspector.

### 8.4 Bundled tools

Bundle architecture-specific signed executables under app resources and select by runtime architecture:

```text
Resources/Tools/
├── arm64/
│   ├── ffmpeg
│   ├── ffprobe
│   ├── mkvmerge
│   ├── mkvpropedit
│   └── mkvextract
└── x86_64/
    ├── ffmpeg
    ├── ffprobe
    ├── mkvmerge
    ├── mkvpropedit
    └── mkvextract
```

The build system pins versions, sources, patches, configure flags, SDK deployment target, architectures, checksums, and licenses. It verifies every binary's architecture and dynamic-library closure before signing. Runtime discovery never falls back to Homebrew, `/usr/local`, `/opt/homebrew`, or the ambient `PATH`.

The tool bundle has two integrity layers:

1. A source/build manifest records upstream URLs, source digests, build inputs, licenses, expected files, minimum macOS version, architectures, linked libraries, and pre-signing hashes.
2. After Developer ID signing changes Mach-O bytes, the release pipeline inventories every executable and dynamic library again and seals the signed tree in a release manifest. The finished app must match that exact inventory.

Absolute or escaping symbolic links, dangling links, unexpected executables, unsupported architectures, unapproved dynamic-library paths, and manifest/hash mismatches fail the build. Every bundled Mach-O file is signed explicitly from the inside out; `codesign --deep` is verification only, never the signing strategy.

HandBrake is a UX, preset, and benchmark reference. HandBrakeCLI/libhb is not bundled in v1 because it duplicates the FFmpeg pipeline and adds another build, update, and licensing boundary.

## 9. Privacy, security, and diagnostics

- No telemetry or media-content reporting.
- No background folder watching in v1.
- No arbitrary shell execution.
- No implicit network upload.
- File access begins with explicit drag/drop or open-panel selection.
- The app is sandboxed with user-selected read/write access and app-scoped security bookmarks. Persist only access needed for user-saved workflows and queued jobs.
- The main app has no client or server network entitlement. Manual updates use only the reviewed, bundle-scoped Sparkle Mach-service exceptions; bundled media tools inherit the app sandbox under their own reviewed entitlements.
- All process launches use an absolute bundled executable, an argument array, a sanitized environment, bounded concurrently drained stdout/stderr pipes, a timeout policy, cancellation escalation, and no shell.
- Canonicalize and contain temporary, destination, workflow-import, attachment, and runtime paths. Reject traversal, unsafe identifiers, escaping/dangling symlinks, special files, and unexpected manifest fields.
- Create private temporary directories with restrictive permissions. Refuse broad destructive targets, unresolved globs, root paths, and silent overwrite of existing release or user output.
- Logs record commands and tool output locally.
- The first support export is built only from allowlisted coarse facts; it never receives media filenames, personal paths, media/track/chapter titles, subtitle text, custom workflow names, raw tool output, persistent job/input identifiers, or exact timestamps.
- The app displays tool versions, license texts, source links, configure flags, and checksums.
- Secret scanning, dependency review, CodeQL, locked-dependency checks, entitlement-policy tests, and a local-only source guard run in CI.
- The hardened runtime and an exact reviewed entitlement set are used for public releases. CI compares entitlements extracted from the signed app and signed helpers against the reviewed plist files.

### 9.1 Signed manual updates

- Use an exact, reviewed Sparkle 2 version; begin with the same proven 2.9.5 baseline as the reference apps unless compatibility testing requires a newer audited pin.
- `Check for Updates…` is visible and user initiated. Automatic checks, background checks, and automatic installation are disabled in `Info.plist` and asserted by tests.
- Sparkle's sandboxed Downloader and Installer XPC services own update networking. The appcast and update archive require a dedicated MKV Magic Ed25519 key pair; never reuse another app's private update key.
- Sign Sparkle's nested helpers inside out while preserving only the upstream Downloader entitlements, then sign the framework and app.
- Generate the signed appcast only from the final notarized and stapled ZIP. Exercise update replacement and relaunch from the prior public version before release.
- Exercise replacement through Sparkle's pinned external updater against a disposable copy of the prior app and a loopback-only signed acceptance feed. Require the acceptance feed's archive signature to equal the downloaded draft appcast's signature; do not add an alternate-feed control to the shipped app. For the first public version only, the separately notarized private rehearsal may serve as the prior build when its production identifier and update key match.

### 9.2 Diagnostics boundary

Diagnostics remain local unless the user explicitly exports them. The current privacy-safe beta report includes allowlisted app/tool versions, architecture, workflow class, coarse input facts, planned encode counts, lifecycle state, result, last active stage, and elapsed-time bucket. It is capped at the 500 newest jobs and one megabyte, writes with owner-only permissions, and excludes media payloads, all filenames and paths, media/track/chapter titles, subtitle text, custom workflow names, raw tool output, security bookmarks, credentials, persistent identifiers, exact timestamps, tool source URLs, license text, and update keys. A future detailed diagnostic bundle may add a bounded sanitized tail only after its redaction boundary has equivalent adversarial tests. Logs are size-bounded and old logs are purged by a documented retention policy.

## 10. Licensing and release

### 10.1 Licensing posture

- MKV Magic source: GPL-3.0-or-later.
- FFmpeg licensing depends on the exact build configuration and must be generated from the pinned build manifest.
- MKVToolNix executables retain upstream licensing.
- HandBrake remains a reference and is not distributed in v1.
- JMkvpropedit is a behavior reference; do not copy archived Java implementation code into the Swift app without explicit review.
- A Third-Party Software screen and packaged notices accompany every release.
- Release artifacts link to corresponding source and build scripts sufficient to reproduce distributed GPL components.

### 10.2 Release pipeline

1. Release only an immutable, signed, annotated `vMAJOR.MINOR.PATCH` tag that resolves to the reviewed `main` commit and validates against the repository's pinned allowed signers. Derive the positive signed-32-bit `CFBundleVersion` from that signed tag's Unix tagger timestamp, require it to increase beyond the accepted prior build, and keep the result stable across workflow reruns. Before any release build, live API evidence must prove the repository is public, immutable releases are enabled, and an active no-bypass `v*` tag ruleset blocks tag update and deletion. The current private-repository plan does not satisfy this gate.
2. Run the complete local gate on the exact commit, then rerun it in hosted CI with read-only default permissions, commit-pinned GitHub Actions, a pinned release Xcode, and locked Swift dependencies that must not change during resolution.
3. Run formatting/lint, unit, planner-golden, integration, UI, fault, security, sanitizer, architecture, package, secret, license, and dependency gates. Build-script fixtures must test their own rejection paths.
4. Build or fetch only provenance-verified, checksum-pinned FFmpeg and MKVToolNix inputs for both `arm64` and `x86_64`; verify source/build manifests before assembly.
5. Assemble the Universal app and architecture-specific tool trees outside the iCloud-backed checkout so File Provider metadata cannot invalidate signatures. Refuse to replace an existing candidate artifact.
6. Verify bundle layout, version/build metadata, deployment target, both app slices, every tool architecture, dynamic-library closure, licenses, and unsigned/pre-sign manifests.
7. Materialize the Developer ID certificate in an ephemeral keychain with `umask 077`. Materialize the App Store Connect API key and Sparkle private key only at exact temporary paths. Remove the certificate file immediately after import and delete every temporary key, keychain, and notarization archive even after failure.
8. Sign all nested Mach-O code explicitly from the inside out with hardened runtime and timestamps, reseal the signed-runtime manifest, then sign the app with reviewed entitlements.
9. Verify strict code signatures, the expected bundle identifier, Team ID, designated requirement, extracted signed entitlements, signed tool inventory, architecture slices, and runtime manifest on an attribute-free copy of the app.
10. Submit the app to Apple, require an `Accepted` JSON response, retain sanitized notarization evidence, staple the ticket, and pass `stapler` plus Gatekeeper assessment.
11. Create a ZIP and a DMG containing exactly `MKV Magic.app` plus an `/Applications` link. Sign, notarize, and staple the DMG separately.
12. Mount the finished DMG read-only in a private temporary directory and recheck layout, app and DMG signatures, signed entitlements, tool inventory, stapled tickets, and Gatekeeper. Run the packaged app's path-free native release verification from both architecture slices so each one constructs the main view, records bounded memory facts, launches all bundled tools, processes a fixture, and proves original preservation.
13. Generate the Ed25519-signed Sparkle appcast from the final notarized ZIP. For releases after v1, fetch the previous archive only by pinned digest and generate a bounded signed delta when worthwhile.
14. Create a draft containing the DMG, update ZIP, appcast, checksums, dependency locks, release notes, source/build metadata, third-party notices, CycloneDX SBOM, artifact-size report, notarization evidence, and build-provenance attestations. Download the complete draft into a fresh directory and repeat its full verifier, but do not publish it.
15. Install that exact candidate on clean physical Intel and Apple Silicon accounts, execute fixture media, and exercise the prior-version update path. Bind each acceptance statement to the candidate DMG digest.
16. In a separate manually dispatched publication workflow, re-download and fully verify the still-draft candidate, require all three acceptance digests and an exact tag confirmation, publish it, verify GitHub's immutable-release attestation, then download the public assets into another fresh directory, repeat the complete verifier, and verify each asset against the release attestation. Only this downloaded-artifact acceptance closes the release. Add required-reviewer approval when repository visibility or plan support makes it available.

An installed, processed, and verified downloaded artifact on both architectures is the release gate; a successful build, upload, visible release page, or notarization submission alone is insufficient.

### 10.3 Signing and notarization credentials

The local iCloud Drive `Apple Auth` directory is the offline credential source. It is never copied, symlinked, enumerated into logs, or referenced by a personal absolute path in the repository. The current local inventory includes candidate material for Developer ID signing, App Store Connect API-key notarization, and Sparkle update signing; actual usability is proved by an M0 release rehearsal without exposing values.

The installed Developer ID Application certificate currently expires on February 1, 2027. Add a release check that fails when fewer than 60 days remain, and plan renewal before that threshold.

Protected release-environment secrets use these interfaces, with values provisioned manually from the offline source:

- `CERTIFICATE_P12_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `RELEASE_KEYCHAIN_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `APPLE_API_KEY_P8_BASE64`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `SPARKLE_ED25519_PRIVATE_KEY`

The live repository-control preflight separately requires
`RELEASE_CONTROLS_READ_TOKEN`: a fine-grained token limited to this repository
with Administration read access and no write permissions. The standard Actions
token cannot read that setting, and a broad personal token is not acceptable.

The repository contains only the Sparkle public key, reviewed entitlement plists, allowed tag signers, and non-secret expected signing identity metadata. No release job runs on an untrusted pull request or exposes secrets to forked code; release secrets live in a ref-restricted environment. Add required reviewers when repository visibility or plan support makes that protection available.

## 11. Testing strategy

### 11.1 Unit tests

- Media-probe JSON normalization.
- Language and role inference.
- Track matching and mapping.
- Filename cleanup and collision handling.
- SRT/ASS parsing, ad removal, encoding normalization, whitespace, and OCR rules.
- Chapter tree editing, nesting, flattening, trimming, offsetting, UID regeneration, and XML round trips.
- Workflow JSON migrations.
- Planner mechanism selection and filter fusion.
- Output naming and Trash transaction state machine.

### 11.2 Planner golden tests

Fixtures map intent and media facts to exact expected plans:

- Metadata edit → `mkvpropedit`, zero remux, zero encode.
- Remove track → `mkvmerge`, zero encode.
- Add compatible subtitle → `mkvmerge`, zero encode.
- Convert one audio track → video copied, one audio encode.
- Trim losslessly → keyframe-aligned copy with disclosed adjustment.
- Exact trim plus resize plus subtitle burn → one video filter graph, one video encode.
- Join compatible MKVs → append/remux, zero encode.
- Join incompatible video → one unified video encode.
- HDR preservation plan → required metadata and validation contract.

### 11.3 Integration fixtures

Use small generated or redistributable files covering:

- H.264, HEVC 8/10-bit, AV1 8/10-bit, and ProRes.
- SDR and HDR10 metadata.
- Stereo, 5.1, 7.1, AAC, AC-3/E-AC-3, Opus, and lossless audio.
- SRT, ASS, TX3G, PGS, and VobSub.
- Multiple editions, nested chapters, malformed chapters, and UID collisions.
- Fonts, cover art, unknown attachments, global tags, and track tags.
- Variable frame rate, delayed audio, missing tracks, and mismatched joined sources.

Private beta media remains outside version control. Record anonymized input facts, intended plan, observed result, and regression fixture needed.

### 11.4 Fault and safety tests

- Insufficient disk space before and during processing.
- Destination removed or disconnected.
- Read-only source and destination.
- Tool crash and nonzero exit.
- App termination and relaunch.
- Cancellation during inspect, remux, encode, verify, and commit.
- Corrupt or truncated source.
- Existing destination collision.
- Verification mismatch.
- Trash collision and Trash failure.

### 11.5 Coverage and continuous security gates

- Collect Swift coverage in CI and publish a per-target report. Domain, Planning, Verification, chapter/subtitle rules, workflow migrations, and transaction state machines target at least 90% line coverage; non-UI Swift targets collectively target at least 80% before public beta.
- AppKit rendering and platform adapters are not excused by a low-value line metric: cover their policy through fakes and contract tests, then exercise real file panels, bookmarks, queue actions, cancellation, error recovery, and update controls with focused UI/integration tests.
- Once the M2 baseline is established, pull requests may not lower either enforced coverage floor without an explicit documented exception. Every fixed defect adds a regression test even when the percentage is already above target.
- Run AddressSanitizer and ThreadSanitizer suites separately. Run scheduled Swift CodeQL, dependency review, secret scanning, entitlement/local-only guards, and dependency/license audits.
- Test CI/release guards themselves with safe and deliberately invalid fixtures: unpinned Actions, changed lockfiles, extra entitlements, unexpected/unsigned tools, escaping symlinks, wrong architectures, mismatched hashes, malformed appcasts, unsafe DMG layouts, and existing-output collisions.
- A package gate builds an unsigned or ad-hoc-signed distributable with disposable update keys on ordinary CI. Real Apple credentials are reserved for the protected release job.

### 11.6 Performance, soak, and size gates

- Record reproducible baselines on the M1 reference Mac and an Intel reference for cold/warm launch, idle resident memory, probe latency, large-track-list rendering, thumbnail generation, planner compilation, queue responsiveness, cancellation latency, mux throughput, and representative AV1/HEVC encodes.
- The checked-in release-mode responsiveness probe supplies the first synthetic,
  path-free baseline for saved-workflow compilation against 200 tracks and
  scheduling from 5,000 queued jobs. It records median and p95 latency and can
  enforce a provisional 15 ms p95 budget for each path. This is a deterministic
  regression harness, not a substitute for app-window, private-library, soak,
  M1-reference, or physical-Intel measurements.
- Stream files, progress, hashes, and subprocess output instead of reading them wholesale. Drain stdout and stderr concurrently, bound log retention, use bounded task groups, and keep thumbnails in a size-limited cache.
- Default to one video encode at a time. Permit a measured, configurable number of lightweight probes/remuxes; cap FFmpeg/encoder threads so parallel jobs do not make an old Intel Mac unusable.
- Deep inspection and thumbnails are lazy and cancellable. Metadata edits must not wait for unrelated thumbnail, scene, silence, or benchmark work.
- Establish app, ZIP, DMG, and Sparkle-delta size budgets from the first representative M0/M1 release artifact; CI then rejects unexplained growth above the recorded budget.
- Before public v1, run at least one hour-long mixed-media queue and a multi-hour single-file transcode with memory sampling, thermal/battery observations, cancellation/recovery, output verification, and no unbounded growth. Store only anonymized measurements and synthetic/redistributable fixture references.

### 11.7 Hardware acceptance matrix

At minimum test:

- M1 Mac mini reference system.
- Current Apple Silicon development Mac.
- Intel Mac supporting macOS 13.
- An older/slower Intel reference when available.

Validate launch, inspection, quick actions, software AV1, VideoToolbox H.264/HEVC, queue responsiveness, pause/cancel, signed sidecars, and notarized distribution.

## 12. Phased implementation roadmap

Each milestone ends with a usable vertical slice and an acceptance gate.

### M0 — Repository and release foundation

Deliverables:

- Initialize the Git repository in the existing `mkv-magic` directory and create the `MKV Magic` Xcode project/app target.
- Add GPL-3.0-or-later license, contribution and security policies, code style, ADR template, canonical spec link, and ignore rules that exclude media, credentials, build products, diagnostics, security bookmarks, and private paths.
- Establish the AppKit shell, modular Swift targets, test targets, deterministic state skeleton, and narrow filesystem/process/update adapters.
- Add reviewed app/helper entitlements, sandbox/bookmark behavior, the no-network source guard, and an ADR for manual signed updates. Pin the reviewed Sparkle version exactly and test the disabled automatic-update policy.
- Create one local `scripts/ci/validate.sh` and a complete local gate used by commit-pinned hosted CI. Include lockfile immutability, formatting, tests with coverage, sanitizer jobs, dependency review, CodeQL, secret scan, Action pinning, entitlement checks, and package fixtures.
- Define sidecar source/build and signed-runtime manifests, reproducible build inputs, checksums, dynamic-library rules, notices, SBOM generation, size evidence, and version reporting.
- Produce a Universal skeleton app containing verified Intel/ARM tools, sign each nested binary, and test tool selection with `PATH` restricted to system directories.
- Scaffold the protected release workflow, signed-tag validation, ephemeral keychain, notarization evidence, DMG/ZIP verification, checksums, provenance, and dedicated Sparkle public-key wiring.
- Use Apple Auth only for a local credential-readiness check and one controlled signing/notarization rehearsal; never import its contents into Git.

Gate: a downloaded M0 rehearsal DMG contains a Universal sandboxed app, passes strict signature/entitlement/tool-inventory checks, is Apple-notarized and stapled, launches natively on Intel and Apple Silicon, and every bundled tool reports the pinned version without Homebrew or network access.

### M1 — Inspector, domain model, and planner skeleton

Deliverables:

- File/folder intake and recursive scan.
- MKVToolNix/FFprobe inspection adapters.
- Unified media, track, attachment, tag, and chapter models.
- Main window inspector.
- Execution-plan model and no-op preview.
- Persistent queue/history schema.

Gate: representative fixtures display normalized facts identically across repeated runs without blocking the UI.

### M2 — Safe metadata, track, and cleanup vertical slice

Deliverables:

- Track editor and bulk role matching.
- `mkvpropedit` and `mkvmerge` execution adapters.
- Clean MKV and English Library Cleanup previews.
- Temporary-output transaction, Standard verification, and optional Trash commit.
- Command/details log.

Gate: metadata edits and track removals pass planner tests with zero video encode; fault tests preserve originals.

### M3 — Subtitle pipeline

Deliverables:

- SRT and ASS/SSA parsers.
- Encoding/whitespace/sequence normalization.
- YTS/YIFY and extensible ad-rule engine.
- High-confidence English OCR corrections and review UI.
- External-track matcher and mux preview.
- Text subtitle extraction, cleanup, and remux.

Gate: subtitle fixtures round-trip without unintended timing/style changes; every uncertain spelling change requires review.

### M4 — Chapter studio

Deliverables:

- Nested chapter domain model and XML/simple-text import/export.
- Outline/table editor and thumbnail timeline.
- Manual, interval, scene, black-frame, and silence suggestions.
- `mkvpropedit` chapter replacement and re-extraction validation.
- Flatten for Jellyfin compatibility.

Gate: nested chapter round trips and flattened timelines match golden fixtures exactly.

### M5 — Join, trim, and chapter recomposition

Deliverables:

- Joined-group ordering and track-mapping table.
- Lossless append compatibility checker.
- Fast/keyframe and exact trim modes.
- Chapter offset/nesting algorithm.
- Audio/video normalization proposal UI.
- One-output enforcement.

Gate: compatible joins and fast trims use zero video encode; incompatible joins compile to a maximum of one video encoding stage.

Current implementation: complete full-file, gap-free `losslessCandidate` joins
have a native include/order/chapter-edition/track-lane review, deterministic MKV
output naming, cancellable pre-commit progress, multi-input History, and exact
post-reopen verification. A pure common-format planner now previews packet-copy
lanes, one-generation video normalization, per-lane AAC conversion,
largest-layout audio preservation, silent missing audio sections, text-subtitle
normalization, and explicit format decisions. A bounded active FFmpeg probe now
admits only encoders and required filters that work on the running Mac. The
current bundled runtime includes checksum-pinned, statically linked SVT-AV1
4.1.0 and dav1d 1.5.4 in both architecture slices, actively verifies AV1 10-bit
encoding, and requires software decode of the produced AV1 frame. This keeps AV1
usable on Macs without AV1 decode hardware. The native review prefers AV1 only
after its local encode succeeds and retains HEVC as the verified faster fallback.
The opt-in timed Encoding Test now persists a runtime-bound recommendation and
reorders the same verified choices when measured AV1 throughput is impractical;
it never reads user media or removes an encoder choice.
It fails closed for
incomplete copy facts, missing video, unavailable encoders/filters, Dolby Vision,
HDR10+, HLG, SDR-to-HDR conversion, and image subtitle conversion. Uniform
static HDR10 lanes with identical metadata can select AV1 or HEVC. Mixed validated
static HDR10 and BT.709 SDR lanes can select a verified SDR encoder and tone-map
only their HDR10 Parts. A revision-bound
choice resolver and pure FFmpeg compiler now turn exact SDR or static HDR10 video and AAC layout
decisions into one filter graph and one process, with no repeated encode stage;
explicit missing-audio approval produces exact-duration silence. Bundled-tool
fixtures execute and decode both HEVC video and stereo-to-surround AAC results.
The internal executor now binds every source filesystem revision, runs FFmpeg
once, semantically verifies the encoded-only Matroska stream bundle before
commit and after reopen, and refuses changed sources, missing timelines, wrong
duration/lane/codec/layout/color facts, or unexpected chapters and attachments.
Encoded segments are now padded/trimmed to each inspected source-container
duration so mixed normalized and packet-copy lanes remain aligned. A pure final
assembly compiler emits one bounded `mkvmerge` invocation: verified normalized
lanes are ordered with compatible source lanes appended directly, while reviewed
track metadata, attachment selections, the segment title, and exact external
nested chapters are rendered once. It fails closed on unpreserved Matroska tags,
text-subtitle conversion, subtitle gaps, changed chapter/bundle facts, unsafe
paths, or overwrite. The revision-bound executor now runs this command inside
the verified-output transaction, checks duration, stream identity/order,
reviewed metadata, attachments, title, zero-tag policy, chapter count, and new
segment identity, canonically compares re-extracted nested chapter XML, commits
atomically, and repeats every audit after reopening. The internal Fast Trim path
now probes the primary video's keyframes, resolves each requested boundary to
the first keyframe at or after it, explicitly exposes both adjustments, and
executes `mkvmerge --split parts:` without encoding. It clips and rebases the
full nested chapter tree, regenerates retained chapter identities, refuses
ordered editions, binds the source and original chapter digest to review, and
audits copied streams, metadata, attachments, duration, segment identity, and
canonical nested chapters before commit and after reopen. The internal Exact
Trim path now holds the requested range exactly, selects only an encoder that
passed the active local capability probe, and compiles one FFmpeg invocation
with one video generation. Strict BT.709 SDR and validated 10-bit static HDR10
are executable; HDR10 uses only AV1 or HEVC and binds output verification to the
exact inspected BT.2020/PQ, matrix, mastering-display, and content-light signal.
Audio is packet-copied by default. Explicit AAC, Opus, AC-3, E-AC-3, and FLAC
choices encode each mismatched selected track once, copy tracks already in the
requested codec, and retain the exact reviewed channel layout. Accepted
AAC/AC-3/E-AC-3/FLAC rates remain unchanged; Opus declares a
48 kHz output clock. Static layout/rate policy plus the active encoder probe hide
unsafe choices rather than accepting FFmpeg's implicit downmix/rematrix behavior.
Output-side seeking applies the in-point to copied audio,
avoiding the pre-in packets retained by input-side accurate seeking. The executor
preserves reviewed track metadata and attachments, replaces FFmpeg-generated
statistics tags only after requiring a tag-free source, installs the clipped and
rebased nested chapter tree, and verifies duration, streams, metadata,
attachments, tags, chapter count/XML, color/HDR signal, and segment identity
before commit and again after reopen. It currently fails closed for subtitle/data
tracks, multiple video tracks, source tags, ordered chapters, mixed or unsupported
HDR, HDR10+, HLG, Dolby Vision, incomplete facts, unavailable encoders, and
non-MKV inputs. The native Trim sheet now samples five
local thumbnails, supports exact numeric in/out entry, defaults to disclosed
zero-encode Fast Trim, and offers one-generation Exact Trim choices only from the
active local capability probe. Save remains disabled until an immutable review
has resolved the actual output range, encoder, audio policy, and clipped nested
chapters. Both routes use shared cancellable verified-output progress, add the
reopened result to inspection, and persist a sanitized History lifecycle. The
native **Convert Video…** route invokes the same exact planner for the complete
duration under an explicit transcode operation. Unlike Trim, a zero-to-duration
range is required. MKV input preserves the original canonical nested chapter
document rather than clipping or regenerating chapter identities; inspected
MP4/M4V/MOV chapters are promoted into one default nested Matroska edition.
Compatible audio and MKV subtitle tracks are packet-copied by default. The complete-file command omits
trim seeking and duration truncation, and the executor compares their streaming
ordered packet hashes before commit and after reopen. The review, one FFmpeg
video generation, optional per-track audio encodes, private temporary output,
semantic/chapter verification, atomic commit, reopen audit, and sanitized History
lifecycle remain shared rather than duplicated. Exact Trim continues to fail
closed for subtitle timing. Common-container conversion fails closed for
subtitle/attachment layouts, ambiguous data, chaptered WebM, and unpreserved
metadata.
native common-format Join route now enables only after the active capability
probe and the same fail-closed source-metadata policy used by final assembly.
It presents the exact resolved SDR or uniform static HDR10 video and AAC audio targets, packet-copy lanes,
attachments, metadata source, and nested chapter output; requires one explicit
approval; binds that approval to unchanged source and chapter revisions; creates
the verified normalized stream bundle only in private temporary storage; and
persists one final-output History lifecycle through final assembly, verification,
commit, and reopen. Both lossless and common-format final outputs now decode a
bounded window spanning every source boundary before commit and again after
reopen. Direct packet-copy lanes also receive streaming ordered payload
fingerprints: audio, subtitles, and other codecs use exact FFprobe packet hashes;
H.264/HEVC video removes only muxer-managed parameter-set units before hashing
the retained encoded packet bodies. Exact packet lanes in one stream family now
share one input scan and are demultiplexed into isolated bounded SHA-256 states,
instead of rescanning the container for every lane. This remains memory-bounded
for long media and fails on missing lanes, packet loss, reordering, or payload
changes. Ambiguous automatic
matches now open a native lane-by-source table. Each explicit edit moves or
swaps a same-type track while preserving the exhaustive exactly-once mapping;
the confirmed map is bound to the exact source identities and order. A real
two-lane ambiguous fixture passes the full app transaction without changing
either source. M5 implementation is complete; private-library beta and physical
Intel performance acceptance remain before the milestone is accepted.

### M6 — Transcoding and hardware adaptation

Deliverables:

- FFmpeg filter-graph compiler and progress parser.
- SVT-AV1 10-bit, HEVC/H.264 VideoToolbox, ProRes, AAC, and advanced audio presets.
- First-run capability benchmark and recommendation model.
- HDR10 preservation and mixed HDR/SDR decision surface.
- Dolby Vision warnings and fail-safe handling.
- Standard and Strict transcode verification.

Gate: multi-step video workflows use one encoded generation, and tested HDR outputs retain the required metadata or fail safely.

Current implementation: the pinned Universal runtime now builds separate
`arm64` and `x86_64` SVT-AV1 4.1.0, dav1d 1.5.4, libopus 1.6.1, and zimg 3.0.6 static
libraries, links them
into the network-disabled FFmpeg, bundles the required notices, publishes the
matching source archives and SBOM components, and proves real 10-bit AV1 encode
and software decode for both slices. Join and Exact Trim already route a
verified AV1 choice through their shared single-generation compiler with an
explicit balanced SVT preset.
The native, consent-based timed benchmark now measures the actual bundled AV1
and HEVC encoders against one synthetic fixture, persists only bounded local
metrics, and feeds the shared initial preset order without removing choices.
The media model now retains exact bounded ST 2086 mastering-display and CTA-861.3
content-light values from FFprobe. Exact Trim and uniform-HDR common-format Join
compile static HDR10 through the same one-generation encoder policy, require
10-bit BT.2020/PQ limited-range input, inject deterministic frame and output
signaling, and compare the reopened output to the exact reviewed signal. Uniform
joined sources must agree on static metadata. AV1 is verified at the stream and
Matroska layers; the HEVC VideoToolbox contract is Matroska-container preservation.
Exact Trim now exposes Smaller File, Balanced, and Higher Quality choices plus
an optional exact control for AV1 RF and SVT speed or HEVC/H.264 bitrate. Those
bounded, Codable choices pass planner validation and the shared one-generation
encoder compiler; old serialized choices decode to the stable codec default.
Common-format Join exposes the same bounded controls for each encoded video lane
and permits any actively verified codec compatible with the reviewed SDR or
static-HDR10 target. Each change invalidates approval, resolves a fresh immutable
plan against the exact inspected sources, and still compiles one fused video
generation rather than chaining conversions.
The complete-file route also accepts bounded MP4, M4V, MOV, and
chapter-free WebM inputs when their structure, metadata, and color facts can be
translated to MKV without guessing. It uses the shared Matroska packet-copy
codec policy for audio, explicitly restores reviewed language and track names,
fingerprints every copied audio packet, promotes inspected QuickTime chapters
into one default nested Matroska edition, and still performs only one video
generation. The same path is now a portable saved-workflow input contract when
one video-conversion card actually applies. A common-input recipe may add one
audio conversion and filename cleanup, but it cannot compose MKV-only track,
subtitle, title, or chapter edits. Filename review is forced to `.mkv`, and
automatic queue reinspection must reproduce the same codec-bearing plan before
the direct one-process executor can run.
Portable saved workflows now share the complete-file conversion path. Their
schema-v9 cards choose the local recommendation, one explicit video preset, or
the lossless-first AV1/HEVC condition, plus an optional AAC, Opus, AC-3, E-AC-3,
or FLAC audio policy that may also run without video conversion. Plan
review binds both locally verified choices and composes deterministic cleanup
into a private verified intermediate followed by one final FFmpeg process. A
pinned-runtime integration proves the edit precedes that only invocation, each
mismatched retained audio track is encoded at most once, matching audio remains
a proven packet copy, the final metadata/track/chapter/attachment contract
passes, and the source digest is unchanged.
Mixed BT.709 SDR and validated static HDR10 Join lanes now default to BT.709 SDR.
The compiler preserves each SDR Part's BT.709 path, converts each HDR10 Part from
PQ to linear light, applies bounded Mobius tone mapping with a peak derived from
the reviewed static signal, converts to BT.709, and concatenates all Parts before
the lane's single encode. The verified transaction requires reopened BT.709 SDR
without residual HDR metadata and unchanged source digests.
The runtime additionally requires FFmpeg's AC-3, E-AC-3, and FLAC encoders and
statically links checksum-pinned stable libopus. The app capability probe smoke
encodes AAC, Opus, AC-3, E-AC-3, and FLAC independently and fails each choice
closed; FFmpeg's experimental native Opus encoder is never eligible. Packet copy
remains the product default. Exact Trim now exposes those five formats only for
source layouts/rates that the selected codec can retain without implicit
downmix/rematrix, compiles every selected track into the same single-generation
FFmpeg invocation, and verifies codec, layout, declared sample rate, metadata,
timing, attachments, chapters, and source immutability before and after commit.
Common-format Join now exposes the same five verified per-lane audio formats.
SDR-to-HDR conversion, HDR10+, HLG, Dolby Vision transcoding, representative
beta-corpus tuning, and physical Intel performance acceptance remain open.

### M7 — Workflow builder and production queue

The builder now starts new recipes with two independently enabled subtitle
conditions: remove explicitly non-English subtitles when present, and remove an
English SDH track only when a preferred English track remains. Compilation
resolves stable track UIDs from the current inspection, fuses both conditions
into one zero-encode remux, and preserves the original combined cleanup action
for imported workflows. A separate native compilation review now shows every
card as applied, already satisfied, or disabled before the plan can be selected;
an entirely satisfied recipe cannot become runnable. The builder now supports
adding and removing the safe card catalog with duplicate prevention, in addition
to enable/disable and reordering. The external text-subtitle input card now asks
for and confirms one SRT, ASS, or SSA during preview, keeps that runtime input out
of the portable recipe, and fuses it with granular cleanup and title removal in
one verified output transaction. A dependent subtitle text-cleanup card now
reuses the deterministic cue review and feeds only accepted changes into that
same remux. The review is ephemeral and both the temporary and committed MKV
must pass extracted SRT or ASS/SSA payload comparison.

The portable filename card now recognizes common dot/underscore-separated movie
release names and presents a simple `Title (Year)` output suggestion in the
immutable plan review. The suggestion never renames a source and remains
editable in the Save panel. When it accompanies media cards, it adds no media
pass. When it is the only applicable card, the plan explicitly declares a
clone-based unchanged file copy, reopens the temporary and committed MKV, and
compares size, container, timing/bitrate, tracks, metadata/tags, canonical
chapters, attachments, and segment identity. Selecting the separate
Trash-after-verified-success option makes this a recoverable rename-shaped
workflow; leaving it off preserves both files. Workflow schema v4 introduced
only the naming intent, never a source or generated filename; current schema v9
retains that boundary and strictly migrates v1-v8 without allowing an older
schema to claim a newer action. Broader
conditions remain open.

The production-queue persistence and scheduling foundation is implemented as a
separate contract from sanitized History. A private versioned document stores
only reviewed workflow intent, plan impact, ordered state events, bounded opaque
security-scoped bookmarks, display names, destination policy, and attempt count.
It rejects unsafe paths, symlinks, missing or oversized bookmarks, duplicate
identities, forged state histories, stale timestamps, and resource-class claims
that disagree with the reviewed plan. Relaunch recovery moves running or
cancelling jobs to **Needs Review** rather than restarting them. The pure
scheduler preserves queue order, admits at most one video-heavy job, separately
bounds audio-heavy and zero-encode lightweight work, starts only one lightweight
job on battery, and starts nothing
under serious thermal pressure or while paused.

New queue file bookmarks also carry a path-free reviewed revision: file size,
millisecond-normalized modification time, and available filesystem file/system
identities. File capture and comparison reuse the same revision reader as the
trim and join stale-input guards. An unchanged-only resolver refuses a legacy
reference with no revision and any current file whose revision differs. Store
validation accepts omission for backward compatibility, rejects invalid revision
facts and any forged directory revision, and never persists a source path. The
current explicit execution bridge captures these revisions. A system-layer
admission coordinator now consumes the pure scheduler, requires an explicit
executor capability check, resolves every input through the unchanged-only
boundary, refuses an occupied or unsafe output, and only then transitions a job
to **Running**. Unsupported or stale work moves to **Needs Review**. The
coordinator scopes bookmark authority around the injected executor and durably
maps verified success, failure, cancellation, or re-review outcomes.

A native queue execution bridge now persists each saved-workflow plan and fresh,
narrow input/destination bookmarks before **Verify & Run** starts any media tool.
It shows ordered jobs, resource class, state, and attempts; supports pending
hold/resume/reorder/cancel; cooperatively cancels the active subprocess tree; and
requires failed or interrupted work to resolve its source, re-inspect, recompile,
and pass the plan review again before retry. A retry atomically replaces stale
bookmarks, destination, workflow snapshot, and reviewed plan while preserving
the job identity and attempt history. Queue recovery runs once per app launch,
so opening or refreshing the window cannot reclassify current work as
interrupted.

The first production automatic-execution subset is connected. After the user
reviews a supported saved workflow, **Add to Queue** persists it in **Waiting**
without forcing an immediate start. Supported inputs are either one primary
media file or that file plus one explicitly reviewed external SRT, ASS, or SSA
sidecar. On app launch, queue resume, and queue authoring, a macOS system adapter
reads the IOKit power-source state and `ProcessInfo` thermal state and invokes
the admission coordinator. Unknown power or thermal facts fail conservatively.
A supported job must still resolve unchanged bookmark authority, target an
unused safe output, re-inspect through the bundled tools, and recompile to the
same reviewed impact and ordered semantic stages. Random compilation-stage IDs
are ignored; mechanism, summary, order, and encode impact must match.

For an external-subtitle job, admission also resolves the sidecar's read-only
bookmark, requires its reviewed file revision, parses a fresh deterministic
preview, requires the original reviewed SHA-256, reapplies the exact stored set
of restored cleanup IDs, and reconstructs the track metadata. Cleanup remains
optional: a nil selection means reviewed original text, while a present array
means the cleanup card was reviewed. The compiler must reproduce the same plan,
and the normal mux executor rechecks the sidecar digest and semantically audits
the extracted subtitle before commit and after reopen. Any stale digest,
malformed review, missing sidecar, changed plan, or unsupported pairing moves
the job to **Needs Review** without creating an output. **Review Again** remains
interactive and replaces every review-bound input and plan fact atomically.

The executor retains the exact full-precision source revision from immediately
before inspection and checks it again after compilation, around temporary-output
production and verification, and immediately before atomic commit. A changed
source becomes **Needs Review**; no revision is silently refreshed. Verified
success, failure, cancellation, and re-review remain durable coordinator
outcomes, and successful automatic work receives the normal sanitized History
record. Per-job cancellation reaches the automatic task and its supervised
subprocess tree. The current explicit **Verify & Run** path remains an immediate
user start and is intentionally distinct from persisted automatic pause.

Standalone saved-workflow audio conversion uses the same automatic boundary and
occupies an audio-heavy scheduler slot. When deterministic preparation precedes
either video or audio conversion, one shared exact original-file revision guard
continues across the private intermediate, final generation, pre-commit check,
and committed reopen audit.

Portable common-media remux uses that automatic boundary as lightweight work.
The queued recipe persists only schema-v9 intent; each admission resolves fresh
stream and chapter facts, requires the same reviewed zero-encode plan, binds the
exact original revision, and invokes the verified MKV remux executor directly.

Portable common-input video conversion uses the same boundary as video-heavy
work. Queue reinspection must recognize the same MP4/M4V/MOV or WebM source,
resolve the same video and optional fused audio choices, reproduce one FFmpeg
stage, and retain the `.mkv` destination before execution. A condition that
skips video conversion on common-container input moves back to interactive review
instead of creating a misleading unchanged non-MKV copy.

Built-in quick-action queueing, multiple or image-based external subtitles,
automatic sidecar discovery, watched folders, scheduled wakes, a background
helper/daemon, continuous
power-state monitoring, long queue soak, and physical-Intel acceptance remain
open. A thermally or power-blocked queue is reconsidered at launch, resume, or
the next **Add to Queue** action.

The saved-workflow Save panel now exposes **Move original video file to Trash
after verified success** as an off-by-default option. Selecting it grants write
authority only to the primary media bookmark, not supplemental subtitle inputs.
The app moves the source only after the new output has been committed, reopened,
audited, and durably marked **Succeeded** in the queue. Failure to record queue
success prevents the move. Failure to move the source preserves the verified
output, leaves the original in place when macOS reports it still exists, and
surfaces a warning rather than misclassifying the media work as failed. Each
verified-success Trash follow-up now has a durable post-success result:
**applied**, **failed**, or **uncertain**. Queue validation replays that result
only after a genuine `Succeeded` transition and rejects forged, duplicate,
backwards-timestamped, or unrequested outcomes. On relaunch, a succeeded Trash
job without a result resolves its stored read/write primary bookmark and
completes the follow-up. If the source no longer resolves, the app records
**uncertain** and asks the user to check the original and Trash instead of
claiming an observed move. A durable result prevents later queue refreshes from
repeating the request. This is a safe recovery contract across the queue file
and Finder Trash, not a claim that those separate systems share one atomic
transaction.

Deliverables:

- Plain-language conditional workflow cards.
- Compilation/fusion preview and impact explanation.
- Portable `.mkvmagic-workflow` import/export and migrations.
- Durable pause/resume/retry/cancel/reorder behavior.
- Battery-aware and workload-aware concurrency.
- Filename cleanup steps.

Gate: saved workflows reproduce the same plans and survive export/import/version migration.

### M8 — Personal alpha and media-corpus hardening

Deliverables:

- Run the user's real media corpus through prioritized workflows.
- Capture every defect as an anonymized regression test or documented fixture gap.
- Tune AV1/HEVC/AAC defaults from measured time, bitrate, and quality.
- Complete accessibility, keyboard navigation, VoiceOver, reduced motion, and error-language pass.
- Measure launch time, idle memory, queue responsiveness, and cancellation.

The privacy-safe evidence path is implemented: new History records capture only
coarse, allowlisted input facts and encode counts, and the explicit History
export produces a bounded local JSON report without library-identifying fields.
The release-mode responsiveness probe now exercises synthetic 200-track workflow
compilation, 5,000-job queue scheduling, and typed cancellation-to-exit for a
fixed five-second `/bin/sleep` child with bounded workloads, stable machine-
readable output, and provisional p95 budgets. Its report contains no source
path, media title, hostname, timestamp, or private payload. On the current
10-logical-processor arm64 development Mac, the observed standard v2 run measured
0.479 ms p95 per workflow compilation, 1.456 ms p95 per queue schedule, and
0.499 ms p95 from cancellation request to synthetic child exit. These
observations do not claim M1-reference, Intel, UI rendering, private-corpus,
launch/memory, bundled media-tool cleanup, transcode, or soak acceptance.

The follow-on noninteractive app baseline builds and signs the actual Universal
app, launches its native slice with activation prohibited, creates no window,
and lays out the real main AppKit view before sampling current resident memory.
A separate bounded launcher measures process start through clean probe exit. On
the same arm64 development Mac, the seven-round release observation measured
588.0 ms p95 process round-trip, 157.3 ms p95 main-view readiness, and 77.8 MB
p95 resident memory, within provisional 2 s, 1 s, and 256 MiB budgets. This is
not a Finder-to-visible-window measurement, settled queue/tool initialization,
or physical M1/Intel acceptance.

The first keyboard/VoiceOver baseline fixes the previously unbound Command-O
menu item and adds intentional focus, Return/Escape review controls, and
explicit accessibility names/help across the main, Queue, History, and saved-
workflow review windows. Those windows use native AppKit and introduce no custom
motion. The follow-on workflow-editor slice adds its list/step/name/status/action
semantics, initial list focus, distinct Command-S save and Return preview, and an
explicit no-selected-media prerequisite. Automated accessibility-tree checks
are extended through the verified-output progress sheet: initial Cancel focus,
Escape cancellation, status/progress semantics, native value-change
notifications, and explicit atomic-commit cancellation closure. These checks
are not manual VoiceOver, keyboard-only, contrast, reduced-motion, localization,
or every-window acceptance; those broader passes remain open.

The every-window continuation assigns intentional first focus and explicit
assistive semantics to all 20 implemented AppKit window-controller surfaces,
including otherwise ambiguous join inclusion and track-mapping controls. Safe
modal cancellation uses Escape. An automatically discovered source gate now
requires focus and accessibility semantics for every window-controller file and
rejects custom UI animation APIs until they have an explicit Reduce Motion
policy and regression. This remains automated evidence rather than an observed
VoiceOver, visual-accessibility-settings, or physical-hardware pass.

The first error-language slice centralizes workflow save/import/export, Queue
mutation, History report export, and main-window History/Queue/workflow load
failures. Each migrated message names the failed action, safe or last-confirmed
state, concrete recovery, and a whitespace-normalized detail capped at 240
characters. This is a bounded foundation, not the complete contextual wording,
VoiceOver-announcement, localization, or representative-failure acceptance pass.

The follow-on source-level error-language pass applies that contract to every
remaining AppKit catch that previously displayed `error.localizedDescription`
directly, including media discovery, planning, trim, join, chapter, subtitle,
track, encoding-test, and queue-review surfaces. A validation gate rejects a
future direct bypass. This establishes consistent bounded wording in source and
automated UI regressions; observed VoiceOver announcement, localization, and
representative real-failure acceptance remain open.

The accessible-failure continuation centralizes AppKit status announcements and
optional recovery focus. Every directly presented actionable UI failure now
updates its visible status field and posts a native accessibility value-change
notification through one implementation; eligible validation and retry paths
return focus only after their recovery control is visible and enabled. Main
model failures are deduplicated across routine refreshes. Regression work also
found and fixed live workflow-name reloads clearing the selected workflow before
Save. The source gate rejects direct error-label assignments and one-off native
accessibility posts outside the shared presenter. This is automated runtime and
source evidence, not an observed VoiceOver announcement-order or representative
private-media failure walkthrough.

The Window-menu keyboard continuation adds stable native commands for the app's
recurring workspaces: Command-0 restores the main window, while Command-1
through Command-4 open Workflows, Queue, History, and Encoding Test. The same
menu includes standard Minimize, Zoom, and Bring All to Front actions and is
registered as AppKit's windows menu. Live menu regressions verify each selector,
target, modifier, and shortcut, plus restoration of a hidden main window. This
improves discoverable keyboard reachability but does not claim a complete Full
Keyboard Access traversal of every control.

The dynamic key-view-loop continuation puts the main window and all 20
implemented window-controller surfaces on one policy: each asks AppKit to own
automatic key-view-loop recalculation while preserving the intentional initial
keyboard target already assigned to the window. This covers surfaces with
dynamic Queue actions, encoding-test cancellation, workflow editing, trim,
join, track, subtitle, and chapter controls without maintaining a brittle
hand-linked responder chain. A live AppKit regression proves both policy
properties, and the auto-discovered source gate rejects future windows that
bypass it. Explicit Tab/Shift-Tab ordering with Full Keyboard Access on and off
remains manual M8 acceptance.

The adaptive-appearance foundation removes the only production conversion of a
semantic AppKit color directly into a one-shot layer color. Common-format video
and audio cards now share an appearance-aware native stack view that resolves
the system separator color against its effective Light or Dark appearance and
refreshes the border when that appearance changes. A runtime regression checks
both appearances, and the source gate rejects future unscoped semantic-color to
`CGColor` conversion outside that shared view. This is deterministic AppKit
evidence, not a claimed manual Increase Contrast, Reduce Transparency, or
visual contrast pass.

The standard Application-menu continuation registers a native Services submenu
with `NSApp`, adds Command-Option-H Hide Others and Show All, and retains the
existing About, explicit update check, Hide, and Quit commands. Live app launch
coverage verifies the services-menu identity, selectors, and modifier flags.
This provides expected macOS integration without a custom menu dispatcher or
network behavior.

The offline-help continuation registers a native Help menu and Command-? action
that opens a retained, lightweight AppKit window. It explains getting started,
verified-output safety, when encoding is avoided or required, saved workflows,
Queue and History, keyboard commands, and the local-only privacy contract. The
content is bundled as text and needs no browser, account, network connection,
telemetry, or LLM. Live app-launch coverage invokes the real menu command and
checks the visible window, initial accessible focus, minimum layout, and core
safety language.

The source-coverage continuation turns the hosted coverage artifact into a
regression gate. A dependency-free Swift/Foundation parser sums only files
inside the repository's production `Sources` tree, reports line, function, and
region coverage, and fails below conservative 65%, 68%, and 58% floors. Tests,
generated runners, Sparkle, and other dependencies cannot inflate the result.
The floors are tripwires against material erosion, not a claim that coverage
percentage alone establishes correctness or UX acceptance.

The public-beta continuation separately aggregates every production target
other than the AppKit executable and enforces at least 80% non-UI line coverage.
The current instrumented result is 87.64% (17,231 of 19,662 lines). The AppKit
target remains in the all-source floors and retains focused policy,
accessibility, launch, and manual UX acceptance rather than being excluded from
coverage reporting.

The first-beta release-notes continuation prepares `0.1.0` as a candidate
version without creating a tag. Signed-tag automation requires bounded regular
notes whose heading matches the exact semantic version; whose sections disclose
highlights, encoding/compatibility, safety/privacy, limitations, and
requirements; and whose text covers the Universal macOS floor, local
processing, original preservation, and image-subtitle OCR limitation. Fixture,
placeholder, linked, missing, mismatched, and unbounded notes fail before
runtime building or credential use.

Gate: agreed personal workflows complete safely and repeatably on the M1 server workflow and at least one Intel Mac.

### M9 — Public signed beta and v1

Deliverables:

- Complete licensing/source/notices review.
- Sign, notarize, staple, package, and independently verify artifacts.
- Publish source, checksums, release notes, supported-system policy, and troubleshooting guide.
- User-initiated signed Sparkle updater with automatic/background checks disabled.
- Run clean-account and clean-machine installation tests.
- Publish SBOM, build metadata, artifact-size evidence, notarization JSON, checksums, and provenance; download and independently reverify everything.

The licensing-UI continuation adds a native, offline Third-Party Software
viewer under Help. It reads only regular UTF-8 documents beneath the signed app
resources, bounds individual and aggregate input size, rejects symbolic links,
and includes the runtime's full license tree when bundled tools are present.
The package gate already requires the primary notices and app/Sparkle licenses;
the viewer does not replace legal review or downloaded-artifact acceptance.

The release-documentation continuation adds one canonical troubleshooting guide
for safe refusal recovery, file access, unavailable actions, queue state,
encoding, subtitles/chapters/trim/join, Trash recovery, and privacy-safe support
evidence. The exact document ships inside the app and as a checksummed release
asset; the offline Help window carries its shortest recovery path without
creating a second competing guide.

The published-release continuation uses one fail-closed downloaded-artifact
verifier before and after publication. It requires the exact checksummed asset
set, accepted notarization evidence, internally consistent size evidence, and
provenance bound to the release workflow, tag, repository, hosted runner, and
commit. The public release is downloaded into a new directory and reverified;
successful draft readback alone is not release acceptance.

Corresponding-source readback is part of that same boundary. The verifier opens
the source bundle, binds the Git archive commit to binary build metadata,
requires the exact eight checksum-matching dependency sources, validates the
shared source policy and safe archive layout, and proves the archived build
script contains every runtime version and checksum pin. The source bundler also
refuses a checkout whose commit or tree differs from binary build metadata.
Outer checksums and attestations cannot substitute for semantic source
contents.

The bundled-runtime layout continuation closes the copy boundary around the
manifest-backed tool tree. Unsigned trees have exactly four root entries;
signed trees may add only a structurally matching pre-sign build manifest per
architecture. Extra caches, tools, libraries, directories, symlinks, special
files, executable licenses, and unbounded license content fail before app
assembly or signing. A real ad-hoc package rehearsal launches every pinned tool
from both architecture selections in the mounted DMG.

The signed-fixture continuation closes the App Sandbox inheritance boundary.
Mounted release verification runs a fixed private Matroska fixture from both
the ARM64 and x86_64 app slices, exercising FFmpeg, FFprobe, `mkvmerge`,
`mkvpropedit`, and `mkvextract` while proving verified-copy output and original
preservation. Unsandboxed direct-helper tests cannot substitute for this
signed-parent execution path. A private `0.0.0` production rehearsal from exact
source commit `113526c` passed Developer ID signing, separate app and DMG Apple
notarization, stapling, Gatekeeper, and both architecture fixture paths. It was
not published and does not satisfy final-tag, clean-account, physical-Intel, or
prior-version update acceptance.

The two-phase publication continuation prevents a successful release build from
making itself public. Signed-tag automation ends at an independently verified
draft. A separate manual workflow must reverify the draft and match the exact
candidate DMG digest against clean-account Apple Silicon, clean-account Intel,
and prior-version updater acceptance before publication, then reverify a fresh
public download. The digest gate binds the operator's evidence to exact bytes;
it does not pretend automation observed physical hardware. Publication makes
the release assets and tag immutable. Public readback must verify GitHub's
release attestation and every downloaded asset against it; a readback failure
fails the workflow but cannot mutate the published release back into a draft.

The updater-acceptance continuation closes the reproducibility gap before that
manual digest entry. A production-only operator harness revalidates the
downloaded artifacts, exercises the pinned Sparkle driver against a disposable
prior-app copy, verifies that the local archive signature is the draft archive
signature, repeats Gatekeeper, stapling, and native-fixture checks on the
replaced copy, and emits the exact candidate DMG digest. The ordinary package
gate runs the same mechanism with disposable keys and proves wrong-key refusal
before successful replacement. The shipped app retains only its fixed public
feed.

A private production-key rehearsal from exact source commit `7a1fd82` has now
exercised that updater boundary: separately notarized build `20260825` replaced
a disposable copy of notarized build `20260824`, retained Gatekeeper and stapler
acceptance, and passed the native fixture on the physical Apple Silicon host.
The candidate was not published or downloaded from GitHub, did not include the
final corresponding-source set, and was not exercised on physical Intel
hardware, so none of the final publication gates are waived. The exact evidence
and artifact digests are recorded in
`docs/releases/M9_PRIVATE_SPARKLE_REPLACEMENT_REHEARSAL.md`.

Release `CFBundleVersion` values come from the signed annotated tag's Unix
tagger timestamp, not the GitHub workflow run counter. Derivation happens only
after signed-tag and exact-source validation, is stable across reruns, is
bounded to a positive signed 32-bit integer, and must be strictly newer than the
accepted private rehearsal build `20260825`. Lightweight tags and invalid or
non-increasing build values fail before source validation or credential use.

Gate: downloaded artifacts pass Gatekeeper, launch, locate bundled tools, process fixtures, and verify outputs on Intel and Apple Silicon.

## 13. Initial implementation backlog

The first engineering sequence should be:

1. `FND-001` Initialize the `mkv-magic` repository, create the `MKV Magic` project/app, add GPLv3, policies, ADRs, module layout, ignore rules, and dependency locks.
2. `FND-002` Add the shared local/hosted validation entry points: format/lint, tests and coverage, lockfile immutability, secret scan, Action pinning, dependency review, CodeQL, and sanitizers.
3. `SEC-001` Define app/helper entitlements, sandbox bookmarks, canonical path containment, local-only source guard, safe temporary directories, and signed-entitlement comparison tests.
4. `UPD-001` Pin Sparkle, add the manual-only update adapter and dedicated public key, test disabled automatic checks, and create disposable-key package fixtures.
5. `FND-003` Define pinned sidecar source/build manifests, signed-runtime resealing, third-party notices, SBOM, architecture/dynamic-library inventory, and exact-path selection.
6. `FND-004` Build/select/sign Intel and ARM sidecars and test with Homebrew paths absent.
7. `REL-001` Implement signed-tag validation, ephemeral credential handling, inside-out signing, app/DMG notarization and stapling, downloaded-artifact verification, checksums, size evidence, and provenance.
8. `REL-002` Perform the M0 Universal signing/notarization rehearsal using Apple Auth without copying or logging secrets.
9. `DOM-001` Implement rational media-time and normalized media/track models.
10. `INS-001` Implement the FFprobe JSON runner/parser.
11. `INS-002` Implement the MKVToolNix JSON runner/parser.
12. `UI-001` Implement sandboxed file intake, the main inspector, and responsive lazy background inspection.
13. `PLN-001` Define workflow intent, execution plan, impact, and verification contract.
14. `EXE-001` Implement safe absolute-path subprocess supervision, concurrent bounded output draining, progress, timeout, cancellation, and sanitized logs.
15. `SAF-001` Implement temporary-output transactions, same-volume atomic commit, original preservation, collision handling, and recoverable Trash.
16. `VER-001` Implement Standard verification and decode spot checks.
17. `TRK-001` Implement the track editor and role-based bulk matching.
18. `CLN-001` Implement the Clean MKV planner and zero-transcode preview.
19. `SUB-001` Implement SRT/ASS parsing, serialization, encoding/whitespace normalization, and existing ad rules.
20. `SUB-002` Implement the English OCR rule engine and review model.
21. `CHP-001` Implement the nested chapter tree and XML round trip before chapter UI.
22. `CHP-002` Implement chapter offset/trim/join/reparent algorithms with golden tests.
23. `UI-CHP-001` Implement the chapter outline/table and lazy thumbnail timeline editor.
24. `JON-001` Implement append compatibility, common-format proposals, and joined track mapping.
25. `TRM-001` Implement fast and exact trim planners.
26. `ENC-001` Implement encoder capability detection and the consent-based local benchmark. *(Implemented; physical Intel tuning remains under `PERF-001`.)*
27. `ENC-002` Implement filter fusion and single-generation invariant tests.
28. `HDR-001` Implement color/HDR contracts and verification.
29. `WFL-001` Implement the portable workflow schema, plain-language cards, compiler, and migrations.
30. `QUE-001` Implement durable queue scheduling, one-encode default concurrency, retry/recovery, and battery/thermal awareness.
31. `PERF-001` Establish M1/Intel responsiveness, memory, throughput, soak, and artifact-size baselines and enforce regression budgets.
32. `REL-003` Complete prior-version Sparkle update, clean-account, clean-machine, Intel, and Apple Silicon release acceptance.

Do not start with the complete chapter UI or transcoding preset surface. The first vertical slice should be:

```text
Drop MKV → Inspect → Edit one property → Preview zero-transcode plan
→ Run temporary output/edit → Verify → Optional Trash → History report
```

That slice establishes the safety and planning architecture every later feature depends on.

## 14. Source-analysis mapping

| Source | Capability or lesson carried into MKV Magic |
|---|---|
| `clean_mkv.py` | Recursive input, track filtering, attachment classification, tag/title cleanup, commentary normalization, subtitle flag policy, safe Trash option, filename normalization |
| `extractchapters.sh` | Batch chapter extraction; replaced by portable bundled-tool discovery and chapter studio |
| `muxmkvidx.command` | External VobSub/audio association; replaced by ranked deterministic matching |
| `muxmp4srt.command` | MP4-to-MKV muxing, language inference, forced-subtitle detection, recoverable source cleanup, movie naming |
| `other.txt` | Fast trim, subtitle extraction, TX3G conversion quick actions |
| `remove_yts_blocks.py` | Block-aware subtitle ad removal and renumbering |
| `setlangs.sh` | Bulk track selection, attachment/tag cleanup, recoverable replacement |
| JMkvpropedit | Drag/drop batch input; general title/chapter/tag controls; per-video/audio/subtitle enable/default/forced/name/language editing; attachment add/replace/delete; output log and advanced parameters. These are behavioral references; the archived Java implementation is not reused |
| MKVToolNix | Authoritative Matroska inspection, property editing, muxing, append, split, chapters, attachments, and extraction engine |
| FFmpeg | Cross-format inspection, stream copy, filters, thumbnails, analysis, audio/video encoding, and verification |
| HandBrake | Reference for scan-first UX, constant-quality presets, queue behavior, capability detection, and user-facing encoder choices; not a v1 runtime dependency |
| Record | Native modular Swift, immutable/recoverable media transactions, narrow system adapters, sandbox/bookmark policy, no-network main app, manual Sparkle XPC boundary, common local/hosted gates, sanitizer/CodeQL coverage, signed-tag release controls, ephemeral credentials, signed-entitlement verification, and downloaded-DMG acceptance |
| Podcast Visualizer | Bundled-runtime manifests and resealing, exact-path execution, symlink/path containment, full nested Mach-O inventory, SBOM/provenance/notarization evidence, refusal to overwrite release stages, artifact/delta size budgets, measured performance/soak evidence, privacy-safe recovery diagnostics, and regression tests across Swift and media pipelines |

## 15. Explicitly deferred or excluded

### Roadmap candidates

- Image-subtitle OCR and text conversion.
- Optional TMDB/TVDB lookup for naming assistance.
- Multiple final output variants from one workflow.
- Advanced custom FFmpeg arguments with a constrained safety model.
- Watched folders or scheduled automatic execution after the manual workflow system is proven.
- Additional subtitle languages and dictionaries.

### Excluded from product scope

- Generative or corrective LLM dependency.
- Video/audio crossfades, transitions, or nonlinear editing.
- Full media-library/server management.
- DRM removal or protected-disc circumvention.
- Arbitrary shell-script execution.
- Hidden analytics or automatic media upload.

## 16. References

- [JMkvpropedit repository](https://github.com/BrunoReX/jmkvpropedit)
- [MKVToolNix source](https://codeberg.org/mbunkus/mkvtoolnix)
- [mkvmerge documentation](https://mkvtoolnix.download/doc/mkvmerge.html)
- [mkvpropedit documentation](https://mkvtoolnix.download/doc/mkvpropedit.html)
- [FFmpeg source](https://github.com/FFmpeg/FFmpeg)
- [HandBrake source](https://github.com/HandBrake/HandBrake)
- [HandBrake VideoToolbox documentation](https://handbrake.fr/docs/en/latest/technical/video-videotoolbox.html)
- [HandBrake quality guidance](https://handbrake.fr/docs/en/latest/workflow/adjust-quality.html)
- [Record repository](https://github.com/aindaco1/record)
- [Podcast Visualizer repository](https://github.com/aindaco1/podcast-visualizer)
- [Jellyfin codec support](https://jellyfin.org/docs/general/clients/codec-support/)
- [Plex playback overview](https://support.plex.tv/articles/200430303-streaming-overview/)
- [GNU GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html)
