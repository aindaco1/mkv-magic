# M9 first-beta release-notes gate

This records preparation and validation of MKV Magic 0.1.0 beta release notes.
It does not create a tag, draft, public release, or final version commitment.

## Honest capability boundary

The prepared notes are derived from executable UI and verifier paths in the
current source tree. They cover inspection, metadata and track editing,
deterministic text-subtitle cleanup and muxing, nested chapters, lossless and
common-format joins, fast and exact trims, portable workflows, queue/history,
AV1/HEVC policy, original preservation, and local-only privacy.

The limitations section distinguishes this beta from the broader v1 roadmap:
image-subtitle OCR, general-purpose standalone transcoding, non-MKV output,
unsupported HDR families, background folder watching, and unsupported complex
layouts are not presented as delivered.

## Fail-closed workflow contract

The signed-tag workflow validates the exact versioned notes before checking
repository controls, installing dependencies, materializing credentials,
building the runtime, or submitting anything to Apple. Version `0.0.0` remains
reserved for the disposable package fixture.

Validation requires:

- a bounded, regular, non-symbolic-link Markdown file;
- a first heading matching the exact semantic version;
- Highlights, Encoding and compatibility, Safety and privacy, Current
  limitations, and Requirements sections;
- explicit macOS 13, Universal Apple Silicon/Intel, local processing,
  original-preservation, and image-subtitle OCR disclosures; and
- no TODO, placeholder, or package-fixture language.

## Regression evidence

The normal source gate accepts the checked-in 0.1.0 notes and rejects a version
mismatch, missing limitations, placeholder text, a symbolic link, an oversized
file, the reserved fixture version, and an absent version. ActionLint and
ShellCheck cover the workflow and scripts.

The version is still a prepared candidate. Choosing and signing the final tag,
making the repository public, configuring immutable controls and the narrow
read token, fixing hosted billing, and completing hardware/Apple acceptance
remain separate gates.
