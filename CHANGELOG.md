# Changelog

All notable changes to MKV Magic will be documented here. Versions follow
semantic versioning; public release tags are immutable and signed.

## Unreleased

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
