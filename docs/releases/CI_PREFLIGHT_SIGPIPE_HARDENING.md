# CI preflight SIGPIPE hardening

The complete local gate once stopped before validation or compilation with
status 141. Its preflight read the first line of `xcodebuild -version` through
`head` while `pipefail` was enabled. If `head` closed the pipe while
`xcodebuild` was still writing, the valid probe could be reported as a failed
pipeline.

The preflight now captures the complete, small version response and selects its
first line with Bash parameter expansion. It preserves the existing macOS and
Xcode minimum-version checks without an early-closing pipe or a suppressed
producer failure.

## Verification

- `shellcheck scripts/ci/preflight.sh` passes.
- Repeated preflight runs all report the same supported environment and exit
  successfully.
- The complete local gate passes normal, coverage, AddressSanitizer, and
  ThreadSanitizer modes with 504 tests, 33 intentional source-only real-tool
  skips, and zero failures in each mode. The Universal app build and isolated
  package gate also pass, including nested signature, disposable update,
  checksum, notices, SBOM, archive, and independently verified DMG checks.
