# M9 Sparkle update replacement acceptance

This records engineering acceptance of a reproducible prior-version update
replacement path. It does not claim that a production candidate, clean account,
physical Intel Mac, public release, or final release version has been accepted.

## Shipped-app boundary

MKV Magic's production feed remains fixed to the public GitHub release appcast.
The app has no hidden feed override, arbitrary URL preference, ambient network
entitlement, automatic check, or automatic-install path. Update checks remain
explicit and Sparkle's sandboxed services retain the only shipped update network
boundary.

Acceptance instead builds Sparkle 2.9.5's own external updater driver from the
exact revision pinned in `Package.resolved`. It copies the prior app into a
private temporary directory, serves the exact candidate ZIP and a temporary
signed appcast only on `127.0.0.1`, and asks Sparkle to replace that disposable
copy. The installed prior app is never changed.

The harness requires a candidate build number greater than the prior build,
matching bundle identifiers and update public keys, the unchanged production
feed URL, strict signatures, and a Universal pinned updater driver. Its local
archive signature must equal the archive signature in the downloaded draft
appcast. After replacement it requires the candidate version and build,
candidate executable digest, strict signature, Gatekeeper and stapling checks,
and the packaged native fixture on the current physical architecture.

## Release operator command

After downloading and independently verifying every asset from the still-draft
release, run the following on each acceptance Mac. The Sparkle private-key file
must be a temporary owner-only file materialized from the offline credential
source; never place it in the checkout or shell history.

```sh
./scripts/release/accept-update-replacement.sh \
  "/absolute/path/to/downloaded-draft" \
  "/absolute/path/to/prior/MKV Magic.app" \
  vMAJOR.MINOR.PATCH \
  "/absolute/path/to/temporary-sparkle-private-key"
```

The script first repeats downloaded-asset checks and native DMG verification on
the current host architecture. A successful run prints the exact candidate DMG
SHA-256 that may be entered for updater acceptance in the separate publication
workflow. It must be run from the previous public release for later versions.
For the first public version only, the prior app may be the separately notarized
private rehearsal, provided its bundle identifier and update key match and its
build number is lower.

## Regression evidence

The disposable package gate now creates a prior app at the private-rehearsal
floor `20260825` and a candidate at signed-tag-shaped build `1787702400`, using
a one-time key. It proves that an appcast signed by a different key is rejected
without changing the prior app, then proves that the matching key replaces it
with the exact candidate archive. This exercises the production build-number
shape through app assembly, appcast generation, and Sparkle replacement. The
appcast archive signature is compared to the packaged feed before replacement.
The complete package gate passed on Apple Silicon using the Universal Sparkle
driver and left the shipped feed policy unchanged.

The final complete local gate passed 513 tests with 33 intentional source-only
bundled-runtime skips and zero failures in ordinary, coverage,
AddressSanitizer, and ThreadSanitizer runs. Production-source coverage remained
69.70% for lines, 73.82% for functions, and 62.83% for regions. The Universal
build and the disposable signed ZIP, DMG, appcast, metadata, checksums, and
replacement path all passed.
