# Verified build reuse

## Outcome

The release pipeline no longer repeats the two most expensive computations that
already passed for its exact source commit. It reuses the Universal media
runtime from CI and treats successful CodeQL analysis for that commit as a
prerequisite, while preserving the release's signing, notarization, packaging,
readback, and native ARM64 and x86_64 verification.

## Baseline

The hosted `0.1.7` candidate run took 30 minutes 39 seconds. Its source gate
took 11 minutes 57 seconds and rebuilding the already-CI-verified media runtime
took another 13 minutes 36 seconds. The matching CodeQL run took 36 minutes 53
seconds and built both application architectures even though one analyzed
architecture is sufficient for Swift CodeQL extraction.

## Contract

- The bundled-runtime CI job still builds, packages, and executes both ARM64 and
  Intel tool lanes and runs the real-tool tests.
- CI caches only checksum-pinned upstream source archives. The runtime builder
  verifies every archive hash before extraction or execution; compiled outputs
  are never accepted from a cache.
- On successful `main` pushes, CI packages the runtime and the eight required
  source archives into an immutable, seven-day artifact and issues GitHub build
  provenance for the archive.
- Release requires successful `CI` and `CodeQL` push runs for the exact release
  commit on `main`. It downloads the exact named artifact from that CI run and
  verifies the signer workflow, source ref, commit digest, GitHub-hosted runner,
  run identity, Xcode version, build-script digest, runtime manifest, safe tar
  layout, binary layout and hashes, and all source-archive checksums.
- Release reruns the same fast source, workflow, formatting, shell, action-pin,
  dependency-lock, local-only, accessibility, error-language, and secret-scan
  contract used by CI. Expensive Swift tests, sanitizer and coverage suites,
  Universal compilation, and disposable package rehearsal are accepted only
  from the exact successful CI commit.
- CodeQL builds ARM64 once. Universal app and bundled-tool output remains a
  mandatory CI, package, signed-DMG, and release-readback invariant.

The artifact is an internal handoff, not a release asset. Corresponding source
is still generated for the signed candidate, hashed with the final artifacts,
uploaded to the draft release, downloaded again, and independently verified.

## Verification

- `./scripts/ci/validate.sh`
- `./scripts/ci/local-gate.sh`
- `scripts/ci/test-release-ci-provenance.sh`
- `scripts/ci/test-runtime-artifact-extraction.sh`
- `scripts/ci/test-tool-source-cache.sh`
- `scripts/ci/test-codeql-build-scope.sh`

The first hosted handoff attempt found that piping `xcodebuild -version` into a
short-lived `head` process can raise a broken-pipe exception in Xcode 26.3. The
workflows and packager now capture the complete bounded version output before
selecting its first line, and the provenance regression test rejects that pipe
pattern.

The optimized hosted durations must be recorded from the first successful push
before a time reduction is treated as measured rather than projected. A signed
tag and draft release are intentionally outside this slice.
