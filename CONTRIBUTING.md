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

Run `./scripts/ci/validate.sh` before opening a pull request. Release-affecting
changes also require the package and local release gates documented in
`docs/runbooks/release.md`.
