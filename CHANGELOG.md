# Changelog

All notable changes to MKV Magic will be documented here. Versions follow
semantic versioning; public release tags are immutable and signed.

## Unreleased

## 0.2.0 - 2026-08-29

- Replace the verified-output progress sheet's bouncing bar with determinate,
  accessible stage counts for bounded execution pipelines and item counts for
  batch workflow queueing and subtitle cleanup. Multi-file inspection also
  reports the current file and total.
- Stream MKVToolNix 101's stable `--gui-mode` progress records for `mkvmerge`
  rendering and selected `mkvextract tracks` work, and show that percentage
  within the current bounded stage without presenting it as whole-job time.
- Keep discovery, tool probes, workflow persistence, history export, thumbnail
  generation, queue work, and encoding benchmarks indeterminate where no honest
  duration, byte, frame, or item denominator is available yet.
- Centralize verified-output stage persistence in the history-execution context
  so every execution route uses one fail-closed recording boundary.
- Add a named common-user-flow regression suite covering intake and safe removal,
  metadata and track edits, subtitle cleanup, output naming, lossless join,
  one-generation planning, saved workflows and queue admission, History,
  destination collisions, progress, Help, and manual-only updates.

## 0.1.8 - 2026-08-26

- Add a custom black-and-white Nested Container app icon, install it in every
  assembled macOS bundle, and verify its complete 16 px through 1024 px ICNS
  representation set during source and package validation.
- Recognize MKVToolNix 101 track-statistics tags when they are flattened into
  per-track identification properties, and use exact extracted Matroska XML as
  the authority when reviewing and verifying removal.
- Consolidate repeated bundled-tool construction and bounded tool-error
  formatting behind shared helpers without changing any workflow behavior.

## 0.1.7 - 2026-08-26

- Let a lossless join continue when `mkvmerge` completes with warnings, while
  preserving the complete source-revision, track, packet, chapter, metadata,
  and final-reopen verification contract before commit.
- Add output-location Settings: save automatically beside each source by
  default, save automatically in one remembered security-scoped folder, or ask
  where to save every time. Automatic outputs use numbered collision-safe names
  and never overwrite an existing file.
- Route Delete and Forward Delete through the native media-table responder so
  every selected row can be removed together without touching source files.
- Export more specific privacy-safe categories for future lossless-join failures
  without including filenames, paths, or raw tool output.

## 0.1.6 - 2026-08-25

- Apply shared native spacing and content-width rules across every AppKit
  workflow surface, including properly inset progress sheets, a wider Inspector,
  readable History details in Dark Mode, and an uncluttered Activity section.
- Add true multi-selection to the inspected-media list. Delete removes every
  selected item from the app without touching source files, while standalone
  SRT/ASS/SSA cleanup and portable saved workflows can review and process a
  selected batch as independent, collision-safe jobs.
- Keep batch outputs beside each source by default, allow one alternate output
  folder, show per-file ready/no-change/blocked results, and keep each original
  unless the workflow explicitly opts into Trash after verified success.
- Export privacy-safe failure categories in support-report schema v2 and make
  the selected History lifecycle visibly readable without exposing raw tool
  output, paths, or media names in the report.
- Accept the same bounded 100 ms cross-container time-base rounding for chapter
  starts already allowed for duration and chapter ends, while retaining strict
  packet-copy, track, metadata, title, attachment, and segment-identity audits.

## 0.1.5 - 2026-08-25

- Add an editable first-run **Clean MKV** workflow modeled on the legacy Python
  cleaner. It combines English-library subtitle cleanup, segment-title and tag
  removal, image-attachment removal, commentary/forced/SDH role cleanup, and
  conservative filename normalization without encoding audio or video.
- Start newly created workflows from the same useful cleanup cards with fresh
  portable identifiers, while respecting an intentionally saved empty library.
- Prevent a combined workflow from scheduling metadata edits for tracks that
  the same reviewed plan removes.

## 0.1.4 - 2026-08-25

- Show an accessible activity indicator during file discovery, inspection,
  planning, queue mutations and execution, encoding tests, workflow saves,
  chapter analysis, thumbnail loading, history export, and every verified
  output operation.
- Add a per-file remove button and Delete-key action to the media list. Removing
  an item only changes MKV Magic's inspected list and never deletes or modifies
  the source file.
- Make the output-location contract explicit in every media save panel: the
  original file's directory is selected by default and the same panel can be
  used to choose any other accessible directory.
- Update the pinned Universal MKVToolNix runtime and corresponding source to
  version 101.0 using the upstream-published SHA-256 digests.

## 0.1.3 - 2026-08-25

- Keep the ad-hoc package rehearsal isolated from production keychain, Team ID,
  notarization, certificate, and update-key paths during the release source gate.

## 0.1.2 - 2026-08-25

- Isolate the source/package rehearsal from release-only runtime paths so the
  production tool tree is required only after it has been built and verified.

## 0.1.1 - 2026-08-25

- Verify signed release-tag ancestry against freshly fetched `origin/main` so
  exact detached-tag checkouts do not depend on a runner-local `main` branch.
- Make the GitHub repository public, enable immutable releases, and activate a
  no-bypass `v*` tag ruleset that prevents release-tag deletion and movement.
- Keep the public macOS CI gates compatible with the pinned Xcode toolchain and
  install every command required to reproduce the bundled media runtime.
- Make signed-update acceptance publish its ephemeral loopback port through a
  private readiness file instead of depending on Python's server banner format.
- Establish the native Universal macOS architecture, local-only security
  boundary, deterministic workflow planner, FFprobe normalization, AppKit shell,
  signed manual updater policy, tests, CI, and release automation.
- Add recursive file/folder intake and a unified FFprobe plus MKVToolNix
  inspector for file, codec, track-role, HDR, chapter, attachment, and tag facts.
- Add deterministic media identifiers, an asynchronous inspector UI, secure
  macOS document opening, and partial-failure reporting for batch inspection.
- Add a typed queue lifecycle and fail-closed, versioned job-history store that
  cannot record success before verification and commit.
- Exercise the inspection path with the actual bundled media tools in hosted CI.
- Add the first executable metadata action: preview a zero-transcode segment-title
  edit, choose a new output, edit an APFS working clone with `mkvpropedit`, verify
  all unrelated structure, and commit without replacing the original.
- Replace blocking process waits with race-safe termination callbacks and a
  timeout escalation path after a sequential real-tool regression exposed a
  completed-process hang.
- Persist real edit progress through the fail-closed job lifecycle in a private
  atomic history document, with sanitized messages and no invented security
  bookmark or full media path.
- Make History a lightweight native report with recent-job columns and the
  selected job's complete sanitized lifecycle.
- Add a zero-transcode track editor for names, canonical language tags, default,
  forced, enabled, commentary, accessibility, and original-language flags. It
  addresses tracks by stable Matroska UID and shares the same verified-clone
  transaction and durable history path as segment-title edits.
- Keep macOS history writes atomic and private while removing Foundation's
  unsupported iOS file-protection option after a regression reproduced `EPERM`.
- Keep the AppKit entry point synchronous on the process main thread while the
  command-line bundled-tool verifier runs in its own detached task.
- Add stable-UID track removal through `mkvmerge`: retained streams keep their
  order and are independently verified with chapters, attachments, user
  metadata, codec/layout/HDR facts, and a fresh segment identity before commit.
- Add a native removal sheet and a deterministic English Library Clean MKV
  preview that proposes non-English or redundant SDH subtitle removals while
  preserving commentary and the sole useful English/unknown subtitle.
- Add an empty-output transaction mode for remux tools and normalize absent
  tool output to a controlled fail-closed state before any commit is possible.
- Add portable saved workflows with a compact native builder, private atomic
  persistence, strict versioned `.mkvmagic-workflow` import/export, step
  enablement and reordering, and file-specific compilation without saved media
  paths or Matroska track identifiers.
- Fuse English Library Cleanup and segment-title removal into one temporary
  remux/property pass followed by one verification and commit, with no video or
  audio encode and the saved workflow identity recorded in durable history.
- Add the first deterministic SRT cleanup path: bounded UTF-8, UTF-16, Windows-1252,
  and Latin-1 decoding; strict timing parsing; sequence, line-ending, separator,
  encoding, and whitespace normalization; block-aware YTS/YIFY ad suggestions;
  individual restoration; and a native review sheet that prevents removing every
  cue.
- Write subtitle cleanup to a new UTF-8 SRT through the verified-output
  transaction, reject a byte-changed source after preview, reopen and compare
  every timing/text cue before and after commit, preserve the original byte for
  byte, and record the sanitized lifecycle through the same DRY history path as
  MKV edits.
- Add deterministic external-SRT matching with conservative title, episode,
  language/role, and duration signals plus an explicit native confirmation
  sheet for editable language, name, default, forced, and SDH metadata.
- Normalize only the structural SRT representation in a private temporary file,
  append it last with `mkvmerge` without encoding, then verify every existing
  track and Matroska structure plus the new track before and after commit while
  preserving both selected inputs byte for byte.
- Add style-preserving ASS and SSA parsing, cleanup review, UTF-8 output, and
  external muxing through the same compact native subtitle flows. Preserve
  script/style/unknown sections, comments, override tags, timing, layer,
  speaker, margins, and effect fields while changing only reviewed dialogue
  text or removing recognized whole-event advertisements.
- Re-extract every newly muxed ASS/SSA track before commit and compare its
  headers, style/layout fields, text, event count, and timing with the reviewed
  source. Refuse the transaction if Matroska round-tripping changes the payload;
  real bundled-tool tests cover both modern ASS and legacy SSA.
- Add deterministic local English OCR cleanup for SRT, ASS, and SSA. Select only
  unambiguous glyph corrections by default, leave possible spelling corrections
  unchecked for explicit review, preserve case and apostrophe style, protect
  markup/override tags/URLs/email, and skip the English rules when a filename has
  an explicit non-English language suffix.
- Add embedded SRT, ASS, and SSA cleanup for inspected Matroska files through
  the shared native review. Choose among multiple editable tracks, extract
  privately, and replace the reviewed track at its original position in one
  zero-encode remux while restoring its stable Matroska UID and all metadata
  flags.
- Verify embedded cleanup before commit and after reopen by re-extracting the
  exact payload and comparing all track, chapter, tag, attachment, duration, and
  segment facts. Preserve contiguous packet timelines at nanosecond precision;
  avoid MKVToolNix's timestamp override for gapped or non-contiguous retained
  cues because it would incorrectly extend a preceding subtitle.
- Add the Chapter Studio core: exact nested edition/atom models, nanosecond
  timestamp and language validation, bounded Matroska XML/simple-text codecs,
  localized display names, edition/chapter flags, fixed-interval generation,
  explicit Jellyfin leaf flattening, and a compact native outline editor.
- Preview chapters with `mkvextract`, bind edits to the source revision and
  canonical extracted tree, apply `mkvpropedit` only to a temporary clone, and
  re-extract exact chapters before commit and after reopen while independently
  verifying that tracks, duration, tags, attachments, metadata, and segment
  identity remain unchanged.
- Add cancellable offline chapter suggestions using one bounded FFmpeg filter
  graph for scene changes, black-frame ends, and silence ends. Merge nearby
  signals deterministically, exclude source edges and existing chapters, honor
  user-selected spacing, and cap the review list without modifying the source.
- Require an explicit native checklist review before adding suggestions to the
  selected edition. New core policy skips duplicate timestamps and boundaries
  inside explicitly closed chapter ranges, preserving manual nesting and exact
  validation for future workflow and batch reuse.
- Add lazy per-chapter frame previews at the exact displayed numeric time and
  five seconds before and after where available. Extract one bounded local JPEG
  at a time with bundled FFmpeg, reject stale or malformed results, and require
  an explicit native choice before changing the in-memory chapter start.
- Add the pure joined-chapter composition policy: explicitly selected source
  edition trees are trimmed, clamped, rebased to one output timeline, nested
  under source-part parents, assigned fresh identities, and validated as one
  bounded default edition. Chapterless sources receive numbered boundary
  children; no muxing or source write is implied by this policy slice.
- Add deterministic joined-track mapping and conservative lossless-append
  compatibility policy. Every video, audio, and subtitle track must appear
  exactly once; unique identity/language/role matches are proposed, ambiguous
  duplicates stay visibly unresolved, stream differences are classified as
  confirmation, normalization, or unsupported, and final codec compatibility
  remains gated on bundled MKVToolNix plus output verification.
- Add a verified full-file hard-join executor for gap-free lossless candidates.
  Render explicit adjacent `mkvmerge --append-to` mappings, inject one reviewed
  nested chapter document, suppress later-source structural metadata, bind all
  sources to filesystem revisions, and inspect plus re-extract the result before
  commit and after reopen without changing any source.
- Add the native strict **Join Files…** flow. Include/exclude and reorder complete
  inspected MKVs, explicitly select one source chapter edition, inspect proposed
  track lanes and every compatibility blocker, choose a deterministic MKV output,
  cancel the temporary append before commit, and record every source in sanitized
  History. Revalidate exact chapter documents before revision-bound execution.
- Add a fail-closed common-format join proposal to the same native review. Keep
  compatible lanes as packet copies; propose at most one AV1 10-bit video
  generation and one AAC conversion per affected audio lane; preserve the largest
  audio layout without automatic downmix; require an explicit mixed SDR/HDR
  choice; and reject unsafe Dolby Vision or image-subtitle normalization. This is
  a truthful planning preview only and cannot execute yet.
- Probe bundled FFmpeg encoder and filter declarations, then prove each offered
  video/audio path with a bounded one-frame local encode before recommending it.
  The current runtime verifies HEVC and H.264 VideoToolbox, ProRes, and AAC;
  because it does not contain an AV1 encoder, Join truthfully shows HEVC as the
  verified fallback while keeping AV1 as the future quality preference.
- Consolidate private temporary workspaces for chapter edits, chapter frames,
  joins, and capability probes behind one restrictive, symlink-resistant helper.
- Bind common-format choices to the complete inspected joined-group facts and
  reject missing, stale, unavailable, malformed, or extraneous decisions before
  command rendering. Round odd video canvases safely and require explicit audio
  layout, bitrate, rate-control, metadata, attachment, gap, and silence choices.
- Compile every affected SDR video and audio lane into one bounded FFmpeg filter
  graph and one process, encoding each output lane once while leaving compatible
  packet-copy lanes for final assembly. Real bundled-tool fixtures prove HEVC
  fit-and-pad and stereo-to-surround AAC normalization, decode both outputs, and
  preserve every source byte.
- Execute the fused normalization command through a revision-bound verified
  transaction. Refuse missing timelines or sources changed before/during work;
  validate duration, lane count/order, codec, canvas, display size, bit depth,
  BT.709 SDR signaling, AAC layout/rate, and absent chapters/attachments before
  commit and after reopen; and cancel safely at every shared pipeline boundary.
- Add portable schema-v9 **Remux to MKV** workflow intent for compatible MP4,
  M4V, MOV, and chapter-free WebM inputs. Compile only current inspected stream
  and chapter facts, keep tool paths and media identity out of exported recipes,
  permit filename cleanup without another media pass, skip files already in
  MKV, and reject unsafe card combinations. Run the same exact packet/chapter
  verifier through immediate execution or the lightweight automatic queue.
- Add portable schema-v10 **If present: Remove all Matroska tags** intent.
  Compile it from reviewed global/track counts, skip tag-free MKVs, fuse it with
  segment-title cleanup into one mkvpropedit invocation, and compose it with
  existing track/subtitle remuxes or one final video/audio conversion. Require
  zero output tags plus unchanged unrelated structure before commit, persist no
  tag values in portable recipes or support history, and re-inspect/recompile
  the same zero-encode intent in the automatic queue.
- Add portable schema-v11 **If present: Remove image attachments** intent.
  Select only reviewed `image/*` MIME attachments, preserve fonts and unknown
  types, keep filenames/MIME/IDs/UIDs out of recipe JSON and count-only review,
  and fuse cleanup into an existing track/subtitle remux or one verified
  preparation pass before a single final conversion. Exclude FFprobe
  `attached_pic` cover-art projections from playable tracks, verify the exact
  retained attachment set before and after commit, preserve source bytes, and
  re-inspect/recompile the same conditional action in the automatic queue.
- Add portable schema-v12 **If useful: Mark commentary tracks** intent. Resolve
  clearly named audio/subtitle tracks to per-run stable UIDs, set only their
  Matroska commentary flag in the shared property pass, keep all names,
  languages, other flags, packets, and source bytes unchanged, and persist no
  track identity or private title in the recipe or sanitized queue history.
- Add portable schema-v13 **If useful: Normalize commentary names** intent.
  Number recognized audio and subtitle commentary tracks independently as
  `Commentary`, `Commentary #2`, and so on, skip already correct names, preserve
  every other field and packet, and merge simultaneous name/role edits by
  stable UID into the same single verified property pass.
- Add portable schema-v14 **If useful: Mark forced subtitles** intent. Match
  only the distinct word `forced` on currently unforced subtitle names, set
  only Matroska's forced flag, preserve defaults/enabled state and every other
  field and packet, and merge overlapping role/name intent into one edit per
  stable UID without persisting private track facts.
- Add portable schema-v15 **If useful: Mark SDH subtitles** intent. Match only
  distinct `SDH`, `CC`, or `hearing impaired` subtitle-name signals, set only
  Matroska's hearing-impaired flag, preserve every other field and packet, and
  merge overlapping commentary/name/forced/SDH intent into the existing single
  verified property pass without persisting private track facts.
- Add portable schema-v16 **If useful: Mark audio-description tracks** intent.
  Match only clear descriptive-audio or visual-impaired phrases on currently
  unmarked audio tracks, leave ambiguous `AD` labels untouched, set only
  Matroska's visual-impaired flag, and merge the result into the existing single
  verified property pass without persisting private track facts.
- Admit explicitly reviewed external SRT, ASS, and SSA saved workflows to the
  automatic queue. Keep portable recipes path- and review-free while a private
  queue intent binds two narrow bookmarks, revisions, the sidecar SHA-256, track
  metadata, format, and cleanup-restoration IDs. Reparse and recompile at
  admission, reuse one verified remux, and move stale or malformed sidecars to
  **Needs Review** without creating an output.
