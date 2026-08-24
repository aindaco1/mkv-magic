# M9 two-phase publication gate

This records engineering acceptance of the boundary between creating a verified
release candidate and making it public. It does not claim that a public release
or physical-hardware acceptance has occurred.

## Failure mode closed

The signed-tag workflow previously created a draft, downloaded and verified its
assets, then immediately published it. That sequencing left no truthful place
to complete the required clean-account, physical Apple Silicon, physical Intel,
and prior-version Sparkle replacement checks against the exact candidate.

Release creation and publication are now separate workflows. A signed semantic
version tag can build, sign, notarize, staple, attest, upload, redownload, and
verify a candidate, but the workflow must leave the GitHub release in draft
state. It cannot make the release public.

## Exact-candidate publication contract

Publication is a separate manual workflow protected by the
`release-publication` environment. Before it can publish, it:

1. checks out and verifies the exact signed release tag;
2. requires the GitHub release to still be a draft;
3. downloads every candidate asset into a fresh directory;
4. repeats checksum, notarization-evidence, size-evidence, provenance,
   Gatekeeper, bundled-tool, and real fixture verification;
5. requires three independently entered copies of the candidate DMG's lowercase
   SHA-256 digest, one each for clean-account physical Apple Silicon acceptance,
   clean-account physical Intel acceptance, and prior-version Sparkle
   replacement acceptance;
6. requires the exact confirmation `publish-vMAJOR.MINOR.PATCH`;
7. publishes only after every digest matches the newly downloaded DMG; and
8. downloads the public assets into another fresh directory and repeats the
   complete verifier.

The repeated digest is intentionally not a generic checkbox: it binds each
operator acceptance statement to the exact bytes being published. It is still
manual evidence, so the operator must obtain each digest only after completing
the corresponding acceptance path. Repository automation cannot manufacture a
physical Intel or clean-account result.

## Regression evidence

The publication validator rejects missing acceptance, a digest from another
candidate, incorrect confirmation, unsafe naming, and symbolic-link input. The
normal source gate runs these fixtures and the repository's pinned-Action and
secret checks over both workflows. It also runs `actionlint` over every workflow,
matching the workflow-validation practice used by the Record and Podcast
Visualizer projects.

Remaining release acceptance requires actually running the hardware and updater
checks, configuring required reviewers for the `release-publication`
environment, choosing a real release version, and executing the two workflows.
