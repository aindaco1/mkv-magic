# M2 segment-title editing slice

This records engineering acceptance of the first M2 executable action. It is
not acceptance of the complete track editor or Clean MKV milestone, and it is
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
   identity while matching the previewed title.
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

## Still pending in M2

- Persist execution progress into the queue/history store.
- Track language/role editing, track removal, bulk matching, `mkvmerge` remuxing,
  Clean MKV previews, optional verified-original Trash behavior, cancellation UI,
  and privacy-safe command/details reports.
