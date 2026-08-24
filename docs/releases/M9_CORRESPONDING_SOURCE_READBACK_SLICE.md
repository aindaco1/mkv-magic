# M9 corresponding-source readback

This records engineering acceptance of semantic corresponding-source
verification and a private local artifact rehearsal. It does not claim a
public release, GitHub attestation, public-download readback, or physical Intel
hardware acceptance.

## Gap found

The release builder already produced a GPL corresponding-source ZIP containing
the exact MKV Magic checkout and every source archive used for the bundled
runtime. The downloaded-release verifier, however, treated that ZIP as an
opaque checksummed asset. Any nonempty file with the expected name could pass a
synthetic fixture if its outer checksum and size evidence were regenerated.

That was insufficient readback. Checksums prove that bytes did not change after
publication; they do not prove that the named bytes contain the promised
source.

## Shared source contract

The runtime source-manifest policy now has one shared validator used by both
the bundled-tool tree and corresponding-source readback. It requires the exact
schema, bounded filename-safe versions, official HTTPS source boundaries,
license identities, network-disabled FFmpeg configuration, static AV1/Opus/zimg
linkage, and checksum-shaped source identities. This removes the previous
duplicate policy risk.

Downloaded release verification now opens the corresponding-source ZIP and
fails closed unless all of the following are true:

- `BUILD-METADATA.txt` has the exact expected fields, release version,
  Universal architectures, minimum macOS, commit, and source-tree identities;
- the outer ZIP has one bounded, path-safe, link-free exact root with only its
  README, `SOURCES.json`, dependency directory, and MKV Magic source archive;
- the dependency directory contains exactly the eight version-derived FFmpeg,
  NASM, SVT-AV1, dav1d, libopus, zimg, MKVToolNix, and Qt source archives;
- every dependency source SHA-256 equals its `SOURCES.json` identity;
- the inner source tarball has a bounded safe root and its Git archive commit
  header exactly equals the release metadata source commit;
- the source tree contains the GPL license, Swift package locks, canonical
  corresponding-source documentation, runtime build entry point, and release
  bundler without build caches, Git metadata, links, or special files;
- the outer README equals the documentation inside the archived source; and
- every runtime version and checksum identity appears in the archived runtime
  build script.

The source bundler also refuses to run unless the current clean checkout commit
and tree exactly match the already-generated build metadata. It cannot silently
attach source from a later or unrelated checkout to an older binary.

## Regression evidence

The downloaded-release fixture now constructs a real Git source archive and a
complete eight-dependency source bundle. The valid 14-asset release set passes.
Focused negative cases prove rejection when the release metadata names a
different source commit or a dependency source is changed even after all outer
size and checksum evidence is regenerated. Existing unexpected-asset,
symbolic-link, incomplete-checksum, rejected-notarization, and wrong-size cases
continue to fail.

The complete local gate passed 513 tests with 33 intentional source-only
bundled-runtime skips and zero failures in ordinary, coverage,
AddressSanitizer, and ThreadSanitizer runs. Production-source coverage remained
69.70% for lines, 73.82% for functions, and 62.83% for regions. The Universal
build, wrong-key updater refusal, successful disposable Sparkle replacement,
DMG verification, and package gate also passed.

## Private artifact rehearsal

The notarized private `0.0.0` candidate from source commit `7a1fd82` was paired
with a corresponding-source bundle created from a detached clean checkout of
that exact commit and the checksum-verified source cache used for its runtime.
The archive is 98,978,866 bytes with SHA-256:

`7c8dd6e03c02aa90772b51dcda6180b7d5d2d6c19de0dee055ecffd79f48eb59`

Artifact sizes and checksums were regenerated to include it. A separate local
14-file readback directory then passed the complete exact-asset contract and
the new semantic source verification. The notarized app, update ZIP, DMG, and
appcast bytes were unchanged.

This was a local copy, not a GitHub download, and the artifacts have no GitHub
build-provenance attestation because no tag or release exists. A final release
must repeat source bundling from the exact signed tag, verify GitHub's hosted
attestation and downloaded draft, complete both hardware gates, and repeat the
public-download readback after publication.
