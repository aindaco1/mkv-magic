# M9 troubleshooting delivery

This slice supplies the canonical troubleshooting guide required for a public
MKV Magic release. It does not claim that a release has been signed, notarized,
published, downloaded, or accepted on physical Intel and Apple Silicon Macs.

## One source of truth

`docs/TROUBLESHOOTING.md` covers safe recovery without recommending destructive
resets or Gatekeeper bypasses. It documents:

- app installation and bundled-tool expectations;
- file/folder discovery and the 10,000-file safety limit;
- prerequisites for metadata, track, subtitle, chapter, Trim, and Join actions;
- source-revision, destination, verification, cancellation, and atomic-commit
  refusal behavior;
- durable Queue pause, power/thermal deferral, and review-again behavior;
- locally verified AV1/HEVC/audio choices and HDR boundaries;
- nested chapters, text versus image subtitles, trim boundaries, and join
  mapping;
- explicit Trash recovery precautions;
- the privacy-safe History report and safe public defect fields; and
- advanced checksum verification without overstating what a checksum proves.

The offline Help window carries only the shortest recovery path and points the
user toward the same concepts. It does not maintain a second full guide.

## Release delivery contract

The exact canonical Markdown file is copied into the app's signed Resources and
published as `TROUBLESHOOTING.md` beside release artifacts. App-bundle
validation requires a regular non-symlink embedded copy. The package gate
requires the embedded and standalone copies to be byte-identical, rejects a
personal path, and includes the document in `SHA256SUMS`. The release workflow
uploads the checksummed guide to the draft release, after which the existing
downloaded-asset checksum step verifies it independently.

## Verification evidence

The focused package gate passes with the guide present in the app, ZIP, mounted
DMG, and standalone evidence set. Its checksum is verified before the DMG is
mounted and independently inspected. Shell lint, pinned-Action validation, and
strict Swift formatting also pass.

The exact final tree passes the complete local gate: all 511 tests pass with 33
intentional missing-tool fixture skips and zero failures in ordinary, coverage,
Address Sanitizer, and Thread Sanitizer modes; repository production-source
coverage remains 70.24% lines, 73.97% functions, and 63.16% regions. The
Universal Xcode build and the repeated isolated package gate both pass.

Immediately before this slice, the exact pinned Universal tool runtime passed
all 511 current tests with zero skips and zero failures, including real local
FFmpeg/MKVToolNix inspection, editing, subtitle, chapter, trim, join, AV1,
HDR10, audio, queue, History, and reopen verification.

Remaining M9 work includes final content/legal review, production credential
use, notarization/stapling, publication, redownload verification, prior-version
Sparkle replacement, and clean-machine physical-hardware acceptance.
