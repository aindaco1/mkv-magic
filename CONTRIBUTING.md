# Contributing

## Before changing code

Read `PRODUCT_SPEC.md` and the relevant architecture decision record. Preserve
user media and unrelated worktree changes. Do not add media, credentials,
security bookmarks, diagnostics, personal paths, or generated release outputs
to Git.

## Engineering rules

- Keep domain and planning behavior independent from AppKit and subprocesses.
- Launch tools by absolute path with argument arrays; never invoke a shell.
- Preserve originals until verified success and keep recovery paths explicit.
- Add a focused regression test for every bug or contract change.
- Do not weaken sandbox, entitlement, network, path, signature, manifest, or
  one-generation guards to make a change pass.
- Update the canonical specification or an ADR when a durable decision changes.

## Required checks

Run `python3 scripts/test.py` for local development before opening a pull request.
It reuses `./scripts/ci/validate.sh` and adds calibrated Jev review of public
synthetic workflow evidence. Use `--offline` explicitly for the deterministic
subset used by hosted CI. Setup, calibration, and interpretation are documented
in `docs/testing/JEV_EVALUATION.md`. Release-affecting
changes also require `scripts/ci/local-gate.sh`. The executable release procedure
is `.github/workflows/release.yml`, backed by `scripts/release/`; hardware
acceptance is tracked separately in `docs/testing/INTEL_TEST_CHECKLIST.md`.

## Local workspace retention

Keep the ignored development configuration, the verified runtime selected by
`MKV_MAGIC_TOOL_ROOT` or `.mkv-magic-development.json`, its corresponding source
cache, and the current Swift scratch directory. Keep the latest full Jev report
and its source-bound observations together; retain a failing run when it explains
a regression or calibration change. Keep exact installer evidence while its
acceptance or updater testing is still pending.

Old compiler intermediates, obsolete Swift build symlinks, superseded runtimes,
and redundant request previews may be removed after checking that no command
uses them. The packet-audit benchmark still defaults to `tool-runtime-m0-5`;
retain it unless the benchmark is explicitly pointed at another verified runtime.
Move conflicting source copies to a checksum-verified recovery archive instead
of treating them as disposable build output. Never use an indiscriminate
`git clean` on a development checkout.

Fetch and prune remote-tracking refs before reviewing branches. Delete only
branches whose work is retained in the target branch, with no open pull request
or active worktree. Keep release tags and any branch with unique work.
