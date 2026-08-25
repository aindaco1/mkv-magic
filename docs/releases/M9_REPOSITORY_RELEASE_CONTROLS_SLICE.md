# M9 repository release-control preflight

This records the fail-closed repository controls required before MKV Magic can
create its first public release. The controls are active; no release or release
tag exists yet.

## Observed repository state

On August 25, 2026, `aindaco1/mkv-magic` became public, enabled immutable
releases, and activated a repository tag ruleset for `refs/tags/v*`. The ruleset
has no bypass actors and blocks deletion and non-fast-forward updates. The live
repository preflight passes. GitHub release immutability applies to releases
created after the setting was enabled; no release existed at activation time.

Once a draft is published under that setting, its assets and tag are locked.
The publication workflow therefore performs every acceptance check before
publication and treats post-publication readback as an immutable observation,
not as a reversible trial publication.

## Executable release gate

The signed-tag workflow now fails before dependency installation, media-runtime
building, credential materialization, signing, or Apple submission unless live
GitHub API evidence proves all of the following:

1. the repository is public;
2. immutable releases are enabled; and
3. an active tag ruleset covers `refs/tags/v*` (or all tags), has no bypass
   actors or excluded refs, blocks deletion, and blocks force updates.

Checking the immutable-release setting requires repository-administration read
access, which is not one of the standard Actions-token permission switches. The
workflow therefore requires a fine-grained, repository-scoped,
Administration-read-only environment secret named
`RELEASE_CONTROLS_READ_TOKEN`; it must have no write permission and must not be
a broad personal token. That secret is not provisioned in the current release
environment, so the hosted release remains fail-closed even though the live
repository controls now pass. GitHub billing also currently prevents hosted
jobs from starting.

The same preflight can be run before creating a signed tag:

```sh
./scripts/release/verify-repository-release-controls.sh aindaco1/mkv-magic
```

GitHub documents that repository rulesets are available for public repositories
on GitHub Free and can control tag deletion and updates:
<https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository>.
GitHub's immutable-release documentation is:
<https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes>.

## Regression evidence

The source gate accepts a bounded public/immutable/no-bypass fixture and rejects
linked or oversized evidence, a private repository, mutable releases, an
inactive ruleset, a bypass actor, a missing deletion rule, a missing
force-update rule, and a tag pattern that does not cover semantic-version
release tags. Live API failures also stop the release workflow rather than being
treated as acceptance.
