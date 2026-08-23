# M5 native verified common-format Join slice

This records the first complete native path from an inspected incompatible MKV
group to one verified joined MKV. It supports the conservative SDR video and
AAC audio boundary already enforced by the normalization and final-assembly
cores. It does not claim manual mapping of ambiguous tracks, source-tag
preservation, executable subtitle conversion or subtitle gaps, HDR conversion,
join-boundary decode sampling, private-library beta acceptance, physical Intel
acceptance, or public release.

## User flow

1. Choose **Join Files…**, include and order complete MKVs, and explicitly choose
   one source chapter edition wherever multiple editions exist.
2. MKV Magic maps every track and first attempts the zero-encode lossless route.
3. If technical stream facts require normalization, the same review shows exact
   common-format targets from the active bundled-encoder probe and enables
   **Review Common Format…** only when the full supported path is executable.
4. Review the immutable video, audio, metadata, attachment, chapter, and
   one-generation impact summary. **Continue to Save…** remains disabled until
   the user explicitly approves every listed choice.
5. Choose one new MKV destination. The source paths are never output candidates.
6. Follow cancellable progress through normalization, final assembly, semantic
   verification, and commit. Cancellation is disabled only after verification
   has passed and the atomic commit begins.

## One-pass execution contract

- The native recommendation uses AV1 10-bit when its bundled software encoder
  passes the active probe. It falls back only to an actively verified local
  preset; the current bundled runtime selects HEVC 10-bit VideoToolbox when AV1
  is absent.
- Every required video transform is fused into one FFmpeg graph and one encoded
  generation. Each affected audio lane is converted once to AAC at the largest
  reviewed source layout and sample rate; no automatic downmix occurs.
- Compatible lanes remain packet copies. Explicitly reviewed attachments,
  track metadata, the first reviewed segment title, and one exact nested joined
  chapter edition are rendered during one final `mkvmerge` assembly.
- The verified normalized stream bundle exists only inside a private mode-0700
  temporary directory. It is never added to the library or History and is
  removed after success, cancellation, or failure.
- The final destination uses the normal verified-output transaction: it is
  re-inspected and semantically audited before commit, its complete nested
  chapter XML is re-extracted and canonically compared, and all audits repeat
  after reopening the committed path.
- History contains one job and one eight-state lifecycle for the user's final
  MKV. Internal normalization verification does not create a second user job or
  falsely imply that a final output has committed.

## Fail-closed preflight

The native review uses the same source-metadata policy as the final command
compiler, so unpreserved tags or container metadata stop before a long encode.
Unavailable encoders or filters, incomplete facts, missing video, mixed or
unsupported dynamic range, Dolby Vision, image subtitles, text-subtitle
conversion, subtitle gaps, unsafe channel layouts, unstable track identities,
ambiguous automatic mapping, and invalid chapter timelines also keep execution
disabled with a specific reason.

## Native and real-tool evidence

AppKit regressions cover enabled common-format routing after a verified probe,
HEVC fallback truthfulness, deterministic AAC recommendations, explicit
approval-before-save gating, nested chapter disclosure, minimum window bounds,
and visible native actions. A deterministic rendered review at the declared
620 by 460 point minimum was inspected for readable hierarchy, complete choice
text, and an unambiguous single approval step.

A bundled-tool app integration creates two real MKVs whose audio sample rates
differ, removes fixture tags to enter the supported boundary, inspects them
through the app model, approves the recommended 48 kHz AAC target, creates the
private normalized bundle once, assembles and verifies the final MKV, and
observes progress in the exact order normalization, assembly, verification,
commit. It proves the originals remain byte-identical, the output contains the
expected AAC stream and nested Part chapters, and History records exactly one
sanitized final-output lifecycle.

The standard validation completed 335 tests with zero failures and 22
intentional bundled-tool skips. The exact bundled runtime completed the same
335 tests with zero failures and zero skips. The complete local gate then passed
formatting, lockfile and local-only policy checks, coverage, AddressSanitizer,
ThreadSanitizer, the Universal build, app assembly, hardened signing and
entitlement validation, SBOM and checksum validation, ZIP/appcast inspection,
and DMG verification.

## Still pending

- Join-boundary decode spot checks and copied-stream fingerprints.
- Manual mapping for ambiguous track lanes.
- Source-tag preservation and executable text-subtitle conversion/gap support.
- HDR10-preserving normalization and explicit mixed SDR/HDR conversion choices.
- Private-library beta, physical Intel performance acceptance, and public release.

## Subsequent update

Boundary decode and direct copied-payload fingerprints were completed in
`M5_JOIN_OUTPUT_AUDIT_SLICE.md`. The manual mapping, preservation, HDR, beta,
Intel, and release limitations above remain current.
