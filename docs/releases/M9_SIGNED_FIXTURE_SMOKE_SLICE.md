# M9 signed bundled-fixture smoke

This records engineering acceptance of real media processing from the signed
app sandbox. It does not claim a public release, clean-account installation,
prior-version update replacement, or physical Intel hardware acceptance.

## Distribution boundary found during rehearsal

The exact pinned runtime passed all 511 real-tool tests before signing, and a
production-signed private rehearsal from commit `e460991` passed Developer ID
signature, Apple notarization, stapling, Gatekeeper, mounted-DMG, entitlement,
layout, checksum, and native ARM64 plus Rosetta x86_64 version-launch checks.

Running the same signed helper executables directly from XCTest was not a valid
distribution test. Media helpers carry the reviewed App Sandbox inheritance
entitlement, so macOS requires a sandboxed MKV Magic parent. An unsandboxed test
host cannot supply that inheritance chain and the helpers refuse real work.
The unsigned integration suite remains useful for exhaustive media behavior,
but it cannot by itself establish signed-app execution.

## App-context fixture smoke

The app now has an exact noninteractive release-verification mode that accepts
no paths or user input. Inside a private sandbox temporary directory it:

1. asks bundled FFmpeg to create a one-track AAC Matroska fixture;
2. inspects the result with bundled FFprobe and `mkvmerge`;
3. uses the production verified-output executor and bundled `mkvpropedit` to
   create an edited copy;
4. reinspects both files and proves the original digest and title are unchanged;
5. uses bundled `mkvextract` to extract the edited file's audio track; and
6. returns only path-free schema, architecture, byte-count, track-count, and
   original-preservation facts.

All files are fixed synthetic content beneath a private temporary directory and
are removed when the command finishes. No media path, title, user filename, or
tool output enters the successful JSON report.

## Release enforcement and evidence

Mounted-DMG verification can require the smoke under both the ARM64 and x86_64
app slices. The bundled-runtime CI job, production release workflow, and
post-publication downloaded-release verifier now require it in addition to all
five version launches. A public artifact cannot pass merely because its helpers
start; they must create, inspect, edit, verify, preserve, and extract media from
the app's real sandbox inheritance chain.

An isolated Universal real-runtime DMG was assembled and signed ad hoc after the
change. Both architecture selections completed the fixture with one AAC track,
a 1,104-byte preserved source, a 1,104-byte verified edited output, and a
543-byte extracted track. This established deterministic local engineering
behavior before production credential use.

## Private production rehearsal

A second private `0.0.0` rehearsal was built from exact source commit
`113526c9ab4e50b34896681340fed9b3415fb9db` with a clean worktree and the exact
pinned Universal runtime. Its app and DMG were signed with Developer ID,
independently returned `Accepted` from Apple notarization, stapled successfully,
and passed Gatekeeper assessment.

The finished DMG was mounted read-only and passed the strict app layout,
signature, reviewed-entitlement, bundled-tool inventory, version-launch,
checksum, and evidence checks. Its installed app-context fixture completed
under both explicit ARM64 and Rosetta x86_64 selection with the same one-track,
1,104-byte source, 1,104-byte edited output, 543-byte extraction, and preserved
original result. Eleven private evidence assets passed size and checksum
consistency checks. Credential names, values, identities, and private paths are
not recorded in the repository.

This is private production-pipeline evidence for that exact commit, not a public
release or user acceptance. It does not establish installation from a public
download, a clean macOS account, a physical Intel Mac, or update replacement
from an older public version. The final signed release tag must repeat the
entire production chain and downloaded-artifact verification.

The final complete local gate passed 512 tests with 33 intentional source-only
bundled-runtime skips and zero failures in ordinary, coverage,
AddressSanitizer, and ThreadSanitizer runs. Production-source coverage was
69.78% for lines, 73.83% for functions, and 62.92% for regions; the Universal
build and disposable package gate also passed.
