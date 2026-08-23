# M3 saved-workflow slice

This records engineering acceptance of the first portable manual-workflow
slice. It is not acceptance of the full workflow action catalog, conditional
cards, batch queue execution, arbitrary generated-command display, or a public
release.

## User-facing scope

- The Workflows sidebar item opens a compact native AppKit builder.
- A workflow can be named, duplicated, deleted with confirmation, reordered,
  and enabled or disabled step by step.
- The first reusable actions are deterministic English Library Cleanup and
  segment-title removal.
- Save & Preview compiles intent against the currently selected inspection and
  shows the encode count and mechanisms before the existing Verify & Run gate.
- A workflow that has no applicable change reports that the selected file is
  already compliant and does not create an output.
- Workflows import and export as pretty-printed, sorted, versioned
  `.mkvmagic-workflow` JSON.

## Portability and safety contract

1. Saved intent contains no source or destination path, security bookmark,
   Matroska track ID, track UID, or generated command.
2. Stable UIDs for cleanup removals are resolved only while compiling against
   the selected `MediaAsset` and are never written back to the saved workflow.
3. Library JSON lives in the same private `0700` Application Support directory
   as history, is replaced atomically, and has mode `0600`.
4. Library and portable files have explicit schema, workflow-count, step-count,
   name-size, and document-size limits. Unknown fields, unknown actions,
   duplicate IDs, duplicate actions, symbolic links, special files, and unsafe
   paths fail closed.
5. Compilation refuses non-Matroska media, unstable track identity, a plan that
   would remove every playable track, no enabled steps, and no applicable
   changes.
6. When cleanup and metadata changes are both enabled, `mkvmerge` creates one
   temporary remux and `mkvpropedit` changes that same temporary file. The result
   is inspected once before commit and once after commit; the source is never
   edited or replaced.
7. Verification requires exactly the intended stable-UID removal and title
   change while preserving retained codec/layout/HDR facts, order, chapters,
   attachments, tags, and the bounded duration/remux contract.

## Observed evidence

- Domain tests compile the same portable workflow against two assets with
  different Matroska UIDs and prove that the resolved removals differ while the
  saved JSON contains neither UID nor source path.
- Store tests exercise private permissions, human-readable round trips,
  top-level and nested unknown-field refusal, malformed JSON, unknown actions,
  duplicate workflow/step/action identifiers, size limits, and symbolic-link
  refusal for both the library and imported files.
- A fault-oriented executor test observes exactly one `mkvmerge` call followed
  by one `mkvpropedit` call, then one shared verify/commit lifecycle; it confirms
  the original bytes remain unchanged.
- A real bundled-tool app integration creates audio and foreign text-subtitle
  tracks, compiles a saved Prepare for Jellyfin workflow, removes the subtitle
  and segment title without encoding, verifies and reopens the output, preserves
  the original SHA-256 digest, and records the saved workflow ID and complete
  sanitized lifecycle.
- AppKit construction tests cover the compact resizable builder and policy tests
  cover fresh identifiers when duplicating a workflow.

## Still pending

- Packaged visual and accessibility acceptance of the workflow builder on a
  logged-in macOS desktop session.
- Conditional workflow cards, subtitle cleanup/muxing actions, track-role
  normalization, chapters, trimming, joining, encoding presets, queue/batch
  execution, cancellation, and verified-original Trash behavior.
- Public signed/notarized release, updater publication, physical Intel smoke
  testing, and real-library beta acceptance.
