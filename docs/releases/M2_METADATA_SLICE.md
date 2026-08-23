# M2 metadata editing slice

This records engineering acceptance of the first M2 executable actions. It is
not acceptance of track removal, bulk editing, or the Clean MKV milestone, and it is
not a public release.

## Safety contract

1. The source must be a regular non-symbolic-link Matroska file.
2. The destination must be a new path selected by the user; existing files are
   never overwritten.
3. MKV Magic creates a same-volume item-replacement directory and uses an APFS
   clone when available, with a normal copy fallback provided by macOS.
4. `mkvpropedit` receives only the temporary clone through an executable plus
   argument array. The source path is never passed to the editing tool, and the
   internal clone uses a short ASCII-only name independent of the user's output
   filename.
5. The temporary output is re-inspected and must preserve container, duration,
   every track fact, chapter structure, attachments, unrelated tags, and segment
   identity while matching the previewed title or selected track properties.
6. Only a verified nonempty output can enter the exclusive commit state.
7. Any pre-commit error removes the working copy and leaves both the original
   bytes and destination untouched.

## Observed evidence

- Unit and fault tests prove commit-before-verification refusal, symbolic-link
  refusal, no-overwrite behavior, cleanup after verification failure, exact
  shell-free arguments, and unrelated-track change detection.
- A real-tool integration creates an MKV with bundled FFmpeg, edits only a clone
  with bundled `mkvpropedit`, verifies with bundled FFprobe and MKVToolNix, and
  confirms the original SHA-256 digest and title are unchanged.
- A second real-tool integration addresses an audio track by Matroska UID,
  changes its name, canonical language, forced flag, and commentary role, then
  proves the intended header changes, preserved technical facts, complete
  verify/commit stages, and an unchanged source SHA-256 digest.
- The inspection and edit integrations run sequentially after replacing a
  Foundation `waitUntilExit` hang with a race-safe termination callback. A
  32-command regression covers repeated process completion.
- A packaged-app acceptance run caught MKVToolNix truncating an em-dash output
  path under the `C` locale. The command environment now uses deterministic
  `C.UTF-8`, internal working-copy names are ASCII-only, and the real-tool edit
  regression uses the app's Unicode suggested filename.
- A rebuilt, ad-hoc-signed Universal app then completed the sandboxed UI flow:
  it previewed zero video encodes, created and reselected the Unicode-named
  verified copy, displayed the intended title, and reported the original
  unchanged. Independent bundled-tool inspection confirmed Matroska, one
  preserved track, and the new title; the source SHA-256 remained identical.
- The accepted UI state was visually inspected, and the relevant unified-log
  window contained no Auto Layout, error, or fault messages from MKV Magic.
- A real-tool app integration persists the complete queued, inspected, planned,
  ready, running, verifying, committing, and succeeded lifecycle for both title
  and track edits through atomic history updates. The document has private file
  and directory permissions, stores display names and sanitized messages instead
  of full paths, and leaves the bookmark reference empty until an actual security
  bookmark exists.
- A fault test refuses the committing transition from the progress observer and
  proves that failed progress persistence before commit removes the working copy
  while preserving the source and leaving no destination.
- A packaged, sandboxed app created a synthetic verified edit, then reopened it
  through the History sidebar button. Visual and accessibility-tree inspection
  observed the recent-job row and every sanitized lifecycle event; the history
  file mode was `0600`, contained no full test or user path, and the relevant
  unified-log window contained no layout, error, or fault messages.

## Still pending in M2

- Track removal, bulk matching/editing, `mkvmerge` remuxing, Clean MKV previews,
  optional verified-original Trash behavior, cancellation UI, and privacy-safe
  command/details reports.
