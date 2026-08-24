# M2 exact Matroska tag export and verified removal slice

This records engineering acceptance of complete tag XML export and clear-all
tag removal for one inspected Matroska file. It advances section 5.13 of the
product specification. It is not acceptance of per-entry editing/replacement,
tag import, batch, saved-workflow or queue execution, or a public release.

## User-facing scope

- **Tags…** is enabled for an inspected Matroska source when global and track
  tag counts are available and at least one tag is present. Its compact native
  chooser reports both counts.
- **Export XML…** saves the complete exact Matroska tag document as a separate
  `— Tags.xml` sidecar and never changes the MKV.
- **Review Removal…** is offered only when at least one global or track tag is
  present. Review states the exact clear-all scope and `0 video/audio encodes`.
  Save creates one `— Tags Removed.mkv`; the source is never modified,
  replaced, or moved to Trash.
- The direct action deliberately does not imply semantic tag cleanup. The user
  chooses exact export or removal of every tag entry.

## Safety and verification contract

1. Review re-inspects the complete `MediaAsset`, binds the exact regular-file
   revision, and extracts tags again before trusting the reported counts.
2. Bundled `mkvextract` and `mkvpropedit` receive exact executables and argument
   arrays, never shell commands. Execution has 120-second timeouts and 1 MiB
   output limits; truncated logs fail closed.
3. Extracted XML is capped at 16 MiB and must be UTF-8 with a `Tags` root. It
   rejects NUL bytes, malformed XML, unknown doctypes, entities, external
   resources, unexpected root elements, and global/track count mismatches.
   Only the known Matroska tags doctype is tolerated and removed before private
   parser validation.
4. Export repeats the reviewed extraction into the common exclusive
   verified-output transaction. It requires exact bytes, SHA-256 digest, and
   counts before commit and after reopen. Existing destinations are not
   overwritten and any pre-commit failure removes temporary output.
5. Removal clones the source once and runs `mkvpropedit --tags all:` on that
   clone. It requires non-empty Matroska output, unchanged container, duration,
   segment title, media tracks, nested chapters, attachments, writing facts,
   remaining metadata, and segment UID.
6. Removal independently extracts the candidate tags and requires zero global
   and track entries before commit. The complete verification and fresh
   extraction repeat after reopening the committed output.
7. Source revision is checked around review, extraction, mutation,
   verification, commit, and final audit. Both paths prove the source digest is
   unchanged. A rare post-commit audit failure names the saved file rather than
   claiming rollback.
8. History uses distinct built-in **Export Matroska tags** and **Remove
   Matroska tags** identities. Each stores the full eight-state lifecycle and
   zero video/audio encodes; support data contains only coarse operation and
   media facts, never XML, tag values, filenames, paths, or raw tool output.

## Verification evidence

- Core tests cover count policy, nested `Simple` handling, exact-byte
  preservation, malformed/unsafe XML, unsupported roots, count mismatches, and
  the 16 MiB limit.
- Executor tests cover exact preview/export, tag-free extraction behavior,
  clear-all mutation, source and extracted-document drift, unsafe or changed
  output, tool failure, truncated logs, exclusive commit, and post-commit
  reopen audits.
- Output-verifier regression coverage distinguishes the exact lowercase
  segment-title key from a case-conflicting user tag and permits only tag facts
  such as MKVToolNix statistics-derived bitrate to disappear.
- AppKit tests cover the disabled initial action, explicit output names,
  accessibility labels/help, compact layout, and separate exact-export versus
  verified-removal language.
- Bundled-tool integrations create global and track tags, extract and export
  the exact XML, clear all tags, preserve title/tracks/segment identity and the
  source digest, and record two distinct privacy-safe zero-encode eight-state
  History jobs without tag values or paths.
- The complete local gate passes 660 normal tests, the same 660 tests under
  AddressSanitizer, and the same 660 tests under ThreadSanitizer. Repository
  source coverage is 74.61% by line (32,309/43,305), with 88.50% non-UI line
  coverage (21,508/24,304).
- The release controls pass source validation and a Universal x86_64/arm64
  production build, sign and verify the app plus every nested Sparkle
  component, replace a prior signed build through Sparkle, verify the SBOM and
  checksums, and verify both ZIP and DMG artifacts.
- Visual acceptance covers the unclipped 1080 x 680 main window and the compact
  540 x 250 tag chooser. The visual pass moved the action cluster to the
  standard trailing position and removed unused height before acceptance.

## Still pending

- Per-entry global or track tag editing/replacement, tag import, batch,
  saved-workflow, and queue execution.
- Real-library beta acceptance and physical Intel/Apple Silicon user-flow
  acceptance.
- A public signed and notarized release.
