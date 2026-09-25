# Shared desktop services migration

Source migration only; release and deployment acceptance remain separate.

- Consumer baseline: `1a122226b86af318ba4e2924648d95df1d3ad14f`.
- Previous Platform pin: `none (new submodule)`.
- New immutable commit and exact versions: [platform-desktop.json](../platform-desktop.json).
- Shared surface: Sparkle controller and bounded transport in the reporting XPC service.

Checks remain manual-only. The main app and domain/reporting model targets gain no general network client; only the reporting XPC links shared transport. Local schemas, sanitization and receipt rules stay in MKV Magic.

## Validation

Before: report and diagnostics characterization passed. After: `./scripts/ci/validate.sh` passed, including source guards, full Swift tests and the Universal release build, with existing optional integration skips. Source-archive fixtures verify embedded dependency source, Git provenance, overwrite refusal and pin-drift refusal.

All consumer gitlinks, exact package versions and retained Sparkle lockfile
revisions pass:

```sh
node shared/dust-wave-platform/scripts/check-desktop-consumer.mjs
```

Platform passes its JavaScript suite and clean-checkout recipe tests. Its seven
desktop Swift tests pass independently with Sparkle 2.9.5, 2.9.6 and 2.10.0.
App manifests retain their exact existing Sparkle revisions. Advancing the
full gitlink also carries existing Platform patches; product-owned tests
cover those dependencies.

## Independent rollback

Revert this repository's migration commit, then run
`git submodule update --init --recursive`. This restores the prior adapters,
dependency declaration, gitlink and build/CI configuration together. For a
newly added Platform submodule, Git may leave an untracked checkout directory;
it is no longer a build input after the revert.

No user data or relay storage migration is required. Other applications may
stay on their chosen Platform revisions. A reverse-patch check of the complete
migration records whether the source rollback applies cleanly.

Local source/build evidence does not establish notarization, a signed updater
replacement, physical hardware behavior or deployed GitHub delivery. Use the
existing release runbook before shipping.
