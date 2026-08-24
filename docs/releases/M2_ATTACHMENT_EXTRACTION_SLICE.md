# M2 exact Matroska attachment-extraction slice

This records engineering acceptance of direct extraction for one regular
attachment in an inspected Matroska file. It advances the attachment work in
section 5.13 of the product specification. It is not acceptance of attachment
add, replace, remove, batch, saved-workflow or queue execution, tag export, or a
public release.

## User-facing scope

- An inspected Matroska file enables **Attachments…** only when it contains at
  least one non-empty attachment no larger than 512 MiB with a stable unique
  UID and an unambiguous nonnegative attachment ID.
- A single eligible attachment proceeds directly. Multiple attachments open a
  compact native chooser showing attachment ID, filename, MIME type, and size.
- Review states `0 video/audio encodes`, exact attachment, and byte count. The
  Save panel suggests the embedded filename after removing path separators,
  control characters, hidden-only names, and overlong UTF-8 names while still
  allowing uncommon attachment extensions.
- The output is one separate regular file. The source MKV is never modified,
  replaced, remuxed, or moved to Trash.

## Safety and verification contract

1. Review re-inspects every `MediaAsset` fact before trusting an attachment ID:
   URL, container names, duration, size, bitrate, tracks, nested chapters,
   attachments, metadata/tag counts, segment UID, writing applications, and
   warnings.
2. The selected attachment is addressed by stable Matroska UID. Duplicate or
   missing selected UIDs, duplicate attachment IDs, non-Matroska input, empty
   payloads, unknown sizes, and sizes over 512 MiB fail closed before extraction.
3. Bundled `mkvextract` receives an exact absolute executable and argument
   array, never a shell command. It writes to private owner-only temporary
   storage, has bounded time and log output, and must create a nonsymlink regular
   file of exactly the inspected size. Truncated tool output is a failure.
4. Review streams the payload in 1 MiB chunks and binds the source revision,
   exact byte count, and SHA-256 digest without retaining the attachment in
   memory. Save re-inspects and re-extracts, requires every bound value to agree,
   and refuses source or tool drift.
5. Source revision is checked before verification, before atomic commit, and
   after final reopen. The committed file is streamed again and must equal the
   verified temporary result.
6. An existing destination is never silently overwritten. Cancellation and any
   pre-commit failure remove private output. A rare post-commit audit failure
   reports the committed filename explicitly instead of claiming rollback.
7. History uses the built-in **Extract Matroska attachment** identity, stores
   only user-facing display filenames plus bounded lifecycle states, and records
   zero video/audio encodes. Privacy-safe support export exposes only the coarse
   operation kind and source attachment count, not filenames, paths, UIDs,
   digests, payload bytes, or tool output.

## Verification evidence

- Core policy tests cover deterministic ID ordering plus refusal of
  non-Matroska input, duplicate IDs, duplicate known UIDs, missing selected
  UIDs, empty/unknown payloads, and oversized attachments.
- Executor tests cover exact direct arguments and bytes, streaming size/digest
  verification, private preview cleanup, source preservation, inspection and
  source-revision drift, repeated extraction drift, source mutation during
  verification, wrong size, tool failure, and truncated tool output.
- AppKit tests cover the compact chooser, accessibility labels, safe bounded
  output names, and the disabled initial-state action.
- A bundled-tool integration creates a binary attachment, muxes it into
  Matroska, inspects and extracts it through `AppModel`, proves exact payload
  bytes and an unchanged source digest, and verifies the zero-encode eight-state
  History record.
- The complete pinned-runtime local gate passed all 633 tests with zero
  failures or skips in the normal, AddressSanitizer, and ThreadSanitizer
  configurations. Coverage measured 74.76% of all lines and 88.63% of non-UI
  lines.
- The same gate passed the arm64 and x86_64 Universal build, source and release
  controls, nested Sparkle signing, update replacement, SBOM and checksum
  validation, and verified ZIP and DMG packaging.
- A captured 1080-by-680 main-window layout showed the new **Attachments…**
  action beside **Chapters…** and **Trim…** without clipping or overlap. The
  compact native chooser also passed programmatic layout and accessibility
  checks for bounded labels and keyboard navigation.

## Still pending

- Attachment add, replace, remove, multi-select extraction, saved-workflow and
  queue execution, and tag export or clearing.
- Real-library beta acceptance and physical Intel/Apple Silicon user-flow
  acceptance.
- A public signed and notarized release.
