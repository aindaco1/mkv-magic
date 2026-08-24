# M9 published-release readback

This records engineering acceptance of the public-release readback boundary. It
does not claim that a production release has been signed, notarized, published,
downloaded, or accepted on physical Intel and Apple Silicon hardware.

## One verifier for both sides of publication

`scripts/release/verify-downloaded-release.sh` is now the canonical downloaded
artifact verifier. The protected release workflow invokes it after downloading
the draft candidate and again from a new directory after making the release
public. The post-publication step first confirms that GitHub reports the exact
tag as non-draft. A successful draft readback alone no longer closes the
workflow. If that fresh public readback is skipped or fails after the publish
step succeeds, an `always()` recovery step returns the release to draft and
verifies the restored state. A runner or GitHub outage can still interrupt
recovery, so the workflow's final success remains the observed acceptance
record.

The verifier requires the exact release asset set. It rejects missing, empty,
symbolic-link, special, nested, and unexpected assets. `SHA256SUMS` must contain
one safe entry for every asset other than itself, with no omissions or
duplicates, and every digest must verify.

It also checks that both Apple evidence files report an accepted notarization
submission, and independently recomputes every byte count and SHA-256 digest in
`ARTIFACT-SIZES.json`.

## Provenance and distribution checks

The five build-provenance subjects are verified against:

- this exact GitHub repository;
- the repository's release workflow identity;
- a GitHub-hosted, rather than self-hosted, runner;
- the exact semantic-version tag reference; and
- the exact release commit digest supplied by the protected workflow.

The workflow itself must run from the exact release tag, and its GitHub source
digest must equal the commit resolved by that tag. A manual dispatch therefore
has to select the signed tag as its workflow ref; selecting a branch while
merely naming a tag is refused.

The downloaded DMG must then pass strict Developer ID and Gatekeeper checks,
stapling validation, reviewed signed-entitlement comparison, safe read-only DMG
layout inspection, both app architectures, and native ARM64 plus Rosetta x86_64
bundled-tool launch checks.

## Regression contract

The source gate exercises a valid synthetic release set and fail-closed cases
for an unexpected asset, a symbolic-link asset, an incomplete checksum
manifest, rejected notarization evidence, and internally inconsistent artifact
size evidence. ShellCheck covers both the verifier and its shared validation
library.

The exact final tree passes the complete local gate: 511 tests with 33
intentional bundled-tool skips and zero failures under ordinary, coverage,
AddressSanitizer, and ThreadSanitizer runs; 70.24% line, 73.97% function, and
63.16% region production-source coverage; Universal release build; and the
disposable signed ZIP, DMG, appcast, SBOM, metadata, checksum, and package gate.

Remaining M9 acceptance still requires production credentials, a signed tag,
Apple acceptance, successful workflow execution, clean-account installation,
fixture processing, prior-version Sparkle replacement, and physical Intel plus
Apple Silicon downloaded-artifact testing.
