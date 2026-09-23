# MKV Magic repository instructions

## Product and user-data contract

- Product name: **MKV Magic**. Repository/directory: `mkv-magic`. Swift package
  and executable: `MKVMagic`.
- Treat selected media, subtitles, workflows, completed outputs, and diagnostics
  as user-owned data. Never overwrite or delete a source before a verified,
  recoverable commit.
- Keep processing local. Do not add telemetry, accounts, uploads, remote media
  APIs, arbitrary network clients, or LLM dependencies.
- Explicit exception approved for support: users may review a bounded, sanitized
  report and explicitly send it in app through the isolated reporting XPC service
  to the fixed shared relay. Only this service and Sparkle's downloader may have
  network-client access. No automatic submission, main-app network entitlement,
  credentials, raw logs, or media uploads. See `docs/SUPPORT_DIAGNOSTICS.md`.

## Architecture and DRY boundaries

- `MKVMagicCore` owns stable media/workflow/plan/value types.
- `MKVMagicPlanning` owns deterministic lossless-first planning and the
  one-generation invariant.
- `MKVMagicSystem` owns exact-path tool discovery and subprocess supervision.
- `MKVMagicMedia` owns FFprobe/MKVToolNix adapters and normalization.
- `MKVMagic` owns AppKit, Sparkle, and user interaction.
- Keep system APIs behind narrow protocols. Do not import AppKit, Sparkle, or
  `Process` into domain/planning targets.
- Extract shared code only when behavior is stable and genuinely reused. Do not
  add Record or Podcast Visualizer as an application dependency.

## Security and execution

- Use absolute executable URLs and direct argument arrays. Never use `/bin/sh`,
  `bash -c`, `zsh -c`, `system`, `popen`, or an ambient `PATH` fallback.
- Reject traversal, unsafe identifiers, unexpected manifest fields, special
  files, and escaping, dangling, or absolute symlinks.
- Keep the app sandboxed with user-selected read/write access and app-scoped
  bookmarks. The main app must not have network client/server entitlements.
- Sparkle is manual-only and isolated to its reviewed XPC services. Never
  commit or log its private key.
- Never commit credentials, private media, local diagnostics, security
  bookmarks, Apple Auth material, or personal absolute paths.

## Verification

- `python3 scripts/test.py` is the default local development check: the existing
  source/Swift/Universal gate, Jev calibration, and fresh synthetic workflow
  evidence. `--offline` explicitly runs the deterministic subset; hosted CI uses
  that subset through `scripts/ci/validate.sh`.
- Jev is development tooling only. Never add it to app targets, media execution,
  entitlements, or release acceptance. Send only the registered synthetic test
  projections, never media, private fixtures, paths, raw logs, or diagnostics.
- Keep judge questions and the calibrated policy fixed while comparing changes.
  Missing evidence, model drift, and uncertain answers require review; Jev cannot
  override deterministic failures. See `docs/testing/JEV_EVALUATION.md`.
- Add a regression test for every defect and changed contract.
- Run the default local development check for normal changes, plus the complete
  local gate for high-risk or release changes. The default check includes
  `./scripts/ci/validate.sh`.
- Preserve entitlement, network, path, signature, runtime-manifest,
  original-preservation, and one-generation guards.
- Treat a build, notarization submission, upload, or visible release as partial
  evidence. Release success requires downloaded-artifact verification and real
  launch/fixture acceptance on Intel and Apple Silicon.
