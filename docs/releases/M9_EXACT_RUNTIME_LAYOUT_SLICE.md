# M9 exact bundled-runtime layout

This records engineering acceptance of the bundled-runtime copy boundary. It
does not claim Developer ID signing, Apple notarization, publication, or
physical Intel and Apple Silicon acceptance.

## Defect found by package rehearsal

A real-runtime package rehearsal exposed that the tool validator proved every
required executable, library, manifest, architecture, dependency, and license,
but did not reject unrelated files elsewhere in the tool root. A stale local
runtime containing a SwiftPM scratch tree therefore passed validation and the
app assembler attempted to copy hundreds of megabytes of unrelated content.

The build stopped during attribute cleanup; no release was published. The
failed temporary package and contaminated local build runtime were moved to
Trash, and the working runtime was replaced with a clean, validated copy.

## Exact layout contract

The shared layout validator now requires exactly four unsigned runtime-root
entries: `SOURCES.json`, `Licenses`, `arm64`, and `x86_64`. Each architecture
contains exactly five tools, one manifest, and the single approved Qt runtime
library. Signing may add only `build-manifest.json`, which preserves the
pre-sign inventory while `manifest.json` is resealed to the signed bytes.

When that build manifest exists, the complete validator requires safe JSON,
the exact schema and architecture, valid hashes, and structural equality with
the resealed manifest after removing only hashes. Signing cannot silently
change versions, sources, licenses, paths, or inventory.

The runtime license root has an exact directory shape. Every document must be
regular, non-symbolic, non-executable, nonempty, safely named, at most 2 MiB,
and part of a tree bounded to 128 files and 8 MiB. Unexpected directories,
special files, top-level build caches, extra tools, and escaping content fail
before app assembly or signing.

## Verification

Focused regression fixtures accept both valid unsigned and resealed layouts and
reject an unexpected root file, extra architecture file, nested license
directory, executable license, and symbolic-link tool. ShellCheck covers the
new shared validator and tests.

After the fix, an isolated real-runtime rehearsal passed with the pinned
FFmpeg 9.0.1 and MKVToolNix 100.0 trees. The app and every nested executable
were ad-hoc signed inside-out, packaged into ZIP and DMG, checksum-verified,
mounted read-only, and launched successfully for both native ARM64 and Rosetta
x86_64 tool selections. The cleaned exact runtime also completed all 511 Swift
tests with zero skips and zero failures, including the real media-workflow
suite. This is local engineering evidence, not production distribution
acceptance.

The final complete local gate passed 511 tests with 33 intentional bundled-tool
skips and zero failures in each of the ordinary, coverage, AddressSanitizer,
and ThreadSanitizer runs. Coverage was 70.24% for lines, 73.97% for functions,
and 63.16% for regions; the Universal build and package gate also passed.
