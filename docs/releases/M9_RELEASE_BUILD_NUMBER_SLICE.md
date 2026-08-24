# M9 stable release build-number gate

This records engineering acceptance of the build-number ordering contract used
by the signed-tag release workflow. It does not claim that a public tag or
release exists.

## Failure mode closed

The workflow previously used GitHub's repository run counter as
`CFBundleVersion`. That counter is unrelated to the app's accepted update
history. The separately notarized private rehearsal already established builds
`20260824` and `20260825`, so an early GitHub run number would make the first
public candidate older than its permitted prior-version fixture. Sparkle would
correctly refuse that replacement.

## Signed-tag build contract

The release workflow now derives `CFBundleVersion` from the signed annotated
release tag's Unix tagger timestamp, after tag signature, format, source commit,
and `main` containment validation. The timestamp is part of the signed tag
object, remains identical when a workflow is rerun, and naturally orders tags
created at different times.

The derivation refuses lightweight or absent tags, malformed semantic-version
tags, non-decimal values, leading-zero lower bounds, values outside the positive
signed 32-bit range, and any value not strictly newer than `20260825`. The
exclusive floor preserves the accepted private rehearsal as the only allowed
prior-version fixture for the first public release. Later update acceptance must
use the previous public release.

## Regression evidence

The source gate creates an isolated Git repository whose commit timestamp and
annotated-tag timestamp deliberately differ. It proves the build comes from the
tag object, then rejects an equal lower bound, an out-of-range lower bound, a
larger-than-machine-integer lower bound, a lightweight tag, an absent tag, a
malformed tag, and a leading-zero lower bound. The signed-tag workflow no longer
references `GITHUB_RUN_NUMBER`.

The disposable package gate additionally assembles an app using fixture build
`1787702400`, generates its signed appcast, and exercises Sparkle replacement
from prior build `20260825`. This covers the same 10-digit numeric shape emitted
by a current signed release tag through bundle assembly and the actual pinned
updater, without production credentials or a public release.
