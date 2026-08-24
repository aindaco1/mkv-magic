# M9 offline third-party software viewer

This slice closes the user-facing portion of the Third-Party Software screen
required by the release specification. It does not claim that the licensing
inventory has received final legal review or that a public artifact has passed
downloaded-release acceptance.

## Delivered contract

- **Help → Third-Party Software…** opens a retained native AppKit window; it
  does not require a browser, account, network entitlement, or remote service.
- A single labeled menu chooses among the packaged third-party notices, MKV
  Magic GPL license, Sparkle MIT license, and every license document in the
  bundled media-tool tree when that tree is present.
- The selected full text remains locally selectable and copyable in a standard
  scroll view. Escape closes the window.
- The picker is the intentional first responder, AppKit recalculates its key
  view loop, and the picker, document text, and close action expose explicit
  accessibility names and help.
- The existing offline Help text points directly to this viewer.

## Read boundary

The loader accepts only an absolute, non-symlink app-resource directory and
regular UTF-8 files below it. Each document is limited to 2 MiB and the full
set to 8 MiB. Symbolic links, special files, unreadable enumeration, invalid
UTF-8, size drift during the read, and missing required documents fail closed.
If a development or damaged app cannot load the packaged set, the viewer shows
bounded reinstall guidance without exposing an internal path or technical
error.

The release app-bundle gate continues to require the notices, MKV Magic GPL
license, Sparkle license, and supported-system document as regular non-symlink
files. Tool-tree verification separately requires the exact pinned FFmpeg,
MKVToolNix, SVT-AV1, dav1d, Opus, zimg, and Qt license inventory.

## Regression evidence

The focused loader/viewer regression creates a representative packaged tree,
checks deterministic document order and exact text, switches the native picker,
checks minimum-window layout, and proves that an escaping license symlink is
rejected. The live application-menu regression invokes the real Help command,
observes the visible viewer, and verifies its minimum size, initial focus, and
document accessibility semantics.

The complete current source suite passes with 511 tests, 33 intentional
missing-tool fixture skips, and zero failures in ordinary, coverage, Address
Sanitizer, and Thread Sanitizer modes. Repository production-source coverage is
70.24% lines, 73.97% functions, and 63.16% regions, above all enforced floors.
The Universal Xcode build and isolated package gate also pass, including nested
signatures, installed-app probing, ZIP, DMG, appcast, SBOM, notices, build
metadata, and checksums. The rendered viewer was inspected at its 560 by 420
minimum content size.

Still required before a public release: final license/source/notices review,
signed and notarized packaging with the real Universal tool runtime, downloaded
artifact re-verification, and clean Intel plus Apple Silicon acceptance.
