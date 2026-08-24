# M9 native release verification

This records engineering acceptance of one privacy-safe command that a release
operator can run from the packaged app on a clean account. It does not claim
that clean-account or physical Intel acceptance has occurred.

## Packaged command

The exact packaged executable accepts the otherwise hidden, argument-exact
`--run-native-release-verification` mode. It runs only when that is the sole
argument and emits one bounded JSON document. The command:

1. constructs and lays out the real main view without opening a window;
2. records architecture, macOS version, processor count, main-view readiness,
   resident memory, and root-view count;
3. verifies all five bundled tools through the manifest-backed exact-path
   catalog;
4. creates, inspects, edits, verifies, preserves, and extracts the fixed private
   Matroska fixture; and
5. binds all facts to the packaged app version and build number.

The report contains no paths, filenames, media titles, raw tool output, hardware
identifier, account name, or private content. Inconsistent architecture,
missing bundle metadata, unsafe version/build text, a missing tool, an invalid
fixture, a changed original, or an unusable main view fails closed without a
success report.

## Release integration

Mounted-DMG verification now runs this command explicitly under both ARM64 and
Rosetta x86_64 selection. The bundled-runtime CI job, signed candidate workflow,
draft/public download verifier, and manual publication workflow all use the
same command. The older narrow version and fixture modes remain available for
targeted diagnosis, but the release path does not duplicate them.

The source suite asserts report consistency, bounded packaged identity, exact
tool count, architecture agreement, original preservation, and path-free JSON.

An initial aggregate implementation tried to construct AppKit from an async
main-actor task after entering `dispatchMain()` and hung inside native button
sizing. A live sample identified the exact boundary. The final command performs
the synchronous AppKit construction on the startup main thread, then hands only
the subprocess work to a detached task.

A fresh Universal real-runtime app was assembled, sandbox-signed ad hoc,
packaged, mounted read-only, and verified after that correction. ARM64 and
Rosetta x86_64 each reported five tools, two root subviews, their selected
architecture, and the identical one-track fixture result: 1,104-byte preserved
source, 1,104-byte edited output, and 543-byte extraction. The observed resident
memory was 77,873,152 bytes for ARM64 and 30,552,064 bytes for x86_64. This is
deterministic package evidence, not physical Intel or production-notarized
acceptance. Production signing/notarization and native execution from the next
exact candidate remain required because this source change postdates the private
`113526c` production rehearsal.

The final complete local gate passed 513 tests with 33 intentional source-only
bundled-runtime skips and zero failures in ordinary, coverage,
AddressSanitizer, and ThreadSanitizer runs. Production-source coverage was
69.70% for lines, 73.82% for functions, and 62.83% for regions; the Universal
build and disposable signed package gate also passed.
