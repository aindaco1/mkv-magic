# MKV Magic — Product Specification and Build Plan

**Status:** Scope locked for initial implementation

**Last updated:** 2026-08-23

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

- Same layout/different codecs: convert to AAC while retaining the layout.
- Stereo plus 5.1: continuous 5.1 AAC; stereo material occupies front left/right and other channels remain silent.
- 5.1 plus 7.1: continuous 7.1 AAC; unavailable channels remain silent during 5.1 material.
- Never downmix automatically.
- An optional secondary stereo compatibility track requires a separate audio encode and is clearly disclosed.

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

#### Audio presets

Audio is copied by default. Explicit AAC conversion uses Apple's AudioToolbox encoder when available and preserves sample rate and channel layout unless changed:

| Layout | Default AAC bitrate |
|---|---:|
| Mono | 96 kbps |
| Stereo | 192 kbps |
| 5.1 | 512 kbps |
| 7.1 | 640 kbps |

Opus, AC-3, E-AC-3, and lossless options remain available in Advanced settings when container compatibility permits.

#### Input and output containers

- Accept common FFmpeg-readable media as input, with Matroska-specific editing enabled only when the container supports it.
- Default every compatible conversion, join, and remux to MKV.
- Offer MP4/MOV and WebM output when the selected video, audio, subtitle, chapter, and attachment combination is valid for that container.
- Filter or explain invalid combinations instead of producing a file that nominally muxes but will not play reliably.
- Preserve a source container during a copy-only operation when the workflow requests it and all planned changes are supported.
- Treat less-common FFmpeg output containers as Advanced choices added only after fixture and playback validation; “any container” does not mean bypassing compatibility rules.

### 5.11 HDR and Dolby Vision safety

- Stream copy preserves the encoded stream and its metadata.
- HDR10 transcodes preserve 10-bit processing, BT.2020 primaries, PQ transfer, matrix information, mastering-display metadata, and content-light metadata when available.
- Verification compares expected color/HDR metadata with the output.
- A preservation workflow fails or warns instead of silently emitting incorrect colors.
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
→ Apply English Library Cleanup
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

Workflows can be named, duplicated, reordered, enabled/disabled step-by-step, and exported/imported as versioned human-readable `.mkvmagic-workflow` JSON.

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
- Support export redacts home-directory usernames and optionally hashes media filenames.
- The app displays tool versions, license texts, source links, configure flags, and checksums.
- Secret scanning, dependency review, CodeQL, locked-dependency checks, entitlement-policy tests, and a local-only source guard run in CI.
- The hardened runtime and an exact reviewed entitlement set are used for public releases. CI compares entitlements extracted from the signed app and signed helpers against the reviewed plist files.

### 9.1 Signed manual updates

- Use an exact, reviewed Sparkle 2 version; begin with the same proven 2.9.5 baseline as the reference apps unless compatibility testing requires a newer audited pin.
- `Check for Updates…` is visible and user initiated. Automatic checks, background checks, and automatic installation are disabled in `Info.plist` and asserted by tests.
- Sparkle's sandboxed Downloader and Installer XPC services own update networking. The appcast and update archive require a dedicated MKV Magic Ed25519 key pair; never reuse another app's private update key.
- Sign Sparkle's nested helpers inside out while preserving only the upstream Downloader entitlements, then sign the framework and app.
- Generate the signed appcast only from the final notarized and stapled ZIP. Exercise update replacement and relaunch from the prior public version before release.

### 9.2 Diagnostics boundary

Diagnostics remain local unless the user explicitly exports them. Reports include app/tool versions, architecture, sanitized plans, exit status, bounded tail output, verification results, and recovery state; they exclude media payloads, subtitle text by default, security bookmarks, credentials, full personal paths, and update keys. Logs are size-bounded and old logs are purged by a documented retention policy.

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

1. Release only an immutable, signed, annotated `vMAJOR.MINOR.PATCH` tag that resolves to the reviewed `main` commit and validates against the repository's pinned allowed signers. Tag update and deletion are blocked.
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
12. Mount the finished DMG read-only in a private temporary directory and recheck layout, app and DMG signatures, signed entitlements, tool inventory, stapled tickets, Gatekeeper, bundled-tool launch, and a fixture smoke job.
13. Generate the Ed25519-signed Sparkle appcast from the final notarized ZIP. For releases after v1, fetch the previous archive only by pinned digest and generate a bounded signed delta when worthwhile.
14. Publish the DMG, update ZIP, appcast, checksums, dependency locks, release notes, source/build metadata, third-party notices, CycloneDX SBOM, artifact-size report, notarization evidence, and build-provenance attestations.
15. Download the published artifacts, verify their attestations and checksums, rerun DMG verification, install on clean Intel and Apple Silicon accounts, execute fixture media, and exercise the prior-version update path. Only this downloaded-artifact acceptance closes the release.

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

The repository contains only the Sparkle public key, reviewed entitlement plists, allowed tag signers, and non-secret expected signing identity metadata. No release job runs on an untrusted pull request or exposes secrets to forked code; release secrets live in an approval-protected environment.

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
current bundled runtime verifies HEVC/H.264 VideoToolbox, ProRes, and AAC, but
contains no AV1 encoder; the native review therefore recommends HEVC as its
verified fallback and does not imply that AV1 is executable. It fails closed for
incomplete copy facts, missing video, unavailable encoders/filters, Dolby Vision
transcodes, unsupported HDR, and image subtitle conversion. A revision-bound
choice resolver and pure FFmpeg compiler now turn exact SDR video and AAC layout
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
with one video generation. Audio is packet-copied by default; explicit AAC
conversion retains reviewed channel count, layout, and sample rate and encodes
each audio track once. Output-side seeking applies the in-point to copied audio,
avoiding the pre-in packets retained by input-side accurate seeking. The executor
preserves reviewed track metadata and attachments, replaces FFmpeg-generated
statistics tags only after requiring a tag-free source, installs the clipped and
rebased nested chapter tree, and verifies duration, streams, metadata,
attachments, tags, chapter count/XML, and segment identity before commit and
again after reopen. It currently fails closed for subtitle/data tracks, multiple
video tracks, source tags, ordered chapters, HDR/Dolby Vision, incomplete facts,
unavailable encoders, and non-MKV inputs. The native Trim sheet now samples five
local thumbnails, supports exact numeric in/out entry, defaults to disclosed
zero-encode Fast Trim, and offers one-generation Exact Trim choices only from the
active local capability probe. Save remains disabled until an immutable review
has resolved the actual output range, encoder, audio policy, and clipped nested
chapters. Both routes use shared cancellable verified-output progress, add the
reopened result to inspection, and persist a sanitized History lifecycle. The
native common-format Join route now enables only after the active capability
probe and the same fail-closed source-metadata policy used by final assembly.
It presents the exact resolved SDR video/AAC audio targets, packet-copy lanes,
attachments, metadata source, and nested chapter output; requires one explicit
approval; binds that approval to unchanged source and chapter revisions; creates
the verified normalized stream bundle only in private temporary storage; and
persists one final-output History lifecycle through final assembly, verification,
commit, and reopen. Both lossless and common-format final outputs now decode a
bounded window spanning every source boundary before commit and again after
reopen. Direct packet-copy lanes also receive streaming ordered payload
fingerprints: audio, subtitles, and other codecs use exact FFprobe packet hashes;
H.264/HEVC video removes only muxer-managed parameter-set units before hashing
the retained encoded packet bodies. This remains memory-bounded for long media
and fails on packet loss, reordering, or payload changes. Ambiguous automatic
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

### M7 — Workflow builder and production queue

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

Gate: agreed personal workflows complete safely and repeatably on the M1 server workflow and at least one Intel Mac.

### M9 — Public signed beta and v1

Deliverables:

- Complete licensing/source/notices review.
- Sign, notarize, staple, package, and independently verify artifacts.
- Publish source, checksums, release notes, supported-system policy, and troubleshooting guide.
- User-initiated signed Sparkle updater with automatic/background checks disabled.
- Run clean-account and clean-machine installation tests.
- Publish SBOM, build metadata, artifact-size evidence, notarization JSON, checksums, and provenance; download and independently reverify everything.

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
26. `ENC-001` Implement encoder capability detection and the first-run benchmark.
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
