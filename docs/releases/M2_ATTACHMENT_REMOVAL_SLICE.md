# M2 verified Matroska attachment-removal slice

This records engineering acceptance of direct removal for one or more reviewed
attachments in an inspected Matroska file. It advances section 5.13 of the
product specification. It is not acceptance of attachment add, replace,
multi-select extraction, saved-workflow or queue execution, selective tag
editing or replacement, or a public release.

## User-facing scope

- **Remove Attachments…** is a separate, explicit action from exact attachment
  extraction. It is enabled only when every inspected attachment has one stable
  unique UID and one unambiguous nonnegative ID.
- A compact resizable native sheet lists ID, filename, MIME type, and size with
  checkboxes. The user must select at least one attachment before Review.
- Review states the exact omission count and `0 video/audio encodes`. Save
  creates one new MKV; the source is never modified, replaced, or moved to
  Trash.
- Removing every attachment is supported when at least one media track remains.
  Unknown-size, empty, oversized, and uncommon attachment types can be removed
  because MKV Magic never loads their payload.

## Safety and verification contract

1. Review reads the exact regular-file revision, re-inspects every `MediaAsset`
   fact, and refuses source drift before binding the removed and retained sets.
2. Selection uses stable Matroska attachment UIDs. Duplicate or missing UIDs,
   duplicate or negative attachment IDs, missing selections, and non-Matroska
   input fail closed.
3. Bundled `mkvmerge` receives an exact executable and argument array, never a
   shell command. One explicit `--attachments` retained-ID list or
   `--no-attachments` selector is placed before the source, track order is
   explicit, warning abort is enabled, and execution time and logs are bounded.
4. Output uses the common exclusive verified-output transaction. Existing
   destinations are not overwritten; cancellation and any pre-commit failure
   remove temporary output.
5. Verification requires non-empty Matroska output, remux-bounded duration,
   exact media-track technical and user-facing facts, metadata other than
   expected remux provenance, global and track tag counts, and the complete
   nested chapter hierarchy.
6. Matroska remuxing normally renumbers attachment IDs, so ID changes alone are
   allowed. Retained UID, filename, MIME type, description, size, and order
   must match exactly, every selected UID must be absent, and the output must
   have one new segment identity.
7. Source revision is rechecked around production, verification, commit, and
   the final reopen audit. A rare post-commit audit failure names the committed
   file explicitly rather than claiming rollback.
8. History uses the built-in **Remove Matroska attachments** identity, records
   the full eight-state lifecycle and zero video/audio encodes, and exposes
   only the coarse operation kind and source attachment count in privacy-safe
   support data.

## Verification evidence

- Core tests cover deterministic order, one and all attachment removal, unknown
  and oversized removable facts, and refusal of unsupported, duplicate,
  missing, negative, empty-selection, missing-selection, and empty-output
  cases.
- Executor tests cover exact retained and no-attachment selectors, explicit
  track order, source preservation, full-snapshot and source-revision drift,
  mutation during verification, wrong retained output, tool failure, truncated
  logs, exclusive commit, and the verifying/committing stages.
- AppKit tests cover explicit multi-selection, refusal of an empty selection,
  native layout, accessibility labels and help, keyboard navigation, and the
  disabled initial-state action.
- A bundled-tool AppModel integration creates two binary attachments, removes
  one reviewed UID, proves the retained UID survived normal ID renumbering,
  proves the source digest remained unchanged, and verifies the zero-encode
  eight-state History record.
- The complete local gate passes 645 normal tests, the same 645 tests under
  AddressSanitizer, and the same 645 tests under ThreadSanitizer. Repository
  source coverage is 74.66% by line (31,533/42,234), with 88.61% non-UI line
  coverage (21,060/23,767).
- The release controls pass source validation and a Universal x86_64/arm64
  production build, sign and verify the app plus every nested Sparkle
  component, replace a prior signed build through Sparkle, verify the SBOM and
  checksums, and verify both ZIP and DMG artifacts.
- Visual acceptance covers the 1080 x 680 main window and the resizable 660 x
  460 attachment-removal sheet. The visual pass caught and fixed a clipped
  main-window action row and bottom-aligned attachment rows before acceptance;
  the final controls are unclipped, top-aligned, and readable.

## Still pending

- Attachment add, replace, batch extraction, saved-workflow and queue
  execution, and selective tag editing or replacement.
- Real-library beta acceptance and physical Intel/Apple Silicon user-flow
  acceptance.
- A public signed and notarized release.
