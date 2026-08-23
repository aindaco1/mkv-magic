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
