# M9 published-release readback

This records engineering acceptance of the public-release readback boundary. It
does not claim that a production release has been signed, notarized, published,
downloaded, or accepted on physical Intel and Apple Silicon hardware.

## One verifier for both sides of publication

`scripts/release/verify-downloaded-release.sh` is now the canonical downloaded
artifact verifier. The protected release workflow invokes it after downloading
the draft candidate and again from a new directory after making the release
public. The post-publication step first confirms that GitHub reports the exact
tag as non-draft, verifies GitHub's cryptographically signed immutable-release
attestation, and verifies every downloaded asset against that attestation. A
successful draft readback alone no longer closes the workflow.

Immutable releases lock assets and the tag when the draft is published, so a
post-publication failure cannot be recovered by returning the release to draft.
Every byte, hardware, updater, Apple, signature, and provenance gate must pass
against the exact draft before publication. If public readback then fails, the
workflow fails and the immutable release remains available for investigation;
only a successful run is the observed public-distribution acceptance record.

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
