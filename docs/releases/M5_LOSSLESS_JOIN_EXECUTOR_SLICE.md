# M5 verified lossless join executor slice

This records engineering acceptance of the original non-UI, full-file hard-join
executor for a narrow class of already inspected Matroska sources. The later
native flow is recorded in `M5_NATIVE_LOSSLESS_JOIN_SLICE.md`. This executor
slice does not claim trimming, missing-track handling, attachment selection,
normalization/transcoding, decode spot checks, physical Intel acceptance, or a
public signed/notarized release.

## Execution boundary

The executor accepts only a strict `losslessCandidate` report with:

- Matroska inputs and one explicit video/audio/subtitle lane position for every
  source;
- no missing lane segments, unsupported tracks, attachments, ambiguous mapping,
  metadata confirmation, or incomplete required stream facts;
- a unique stable Matroska UID for every first-source output lane;
- known positive source durations whose overflow-checked sum exactly equals the
  reviewed joined chapter composition; and
- one `.mkv` destination that does not already exist.

Anything classified `confirmationRequired`, `normalizationRequired`, or
`unsupported` fails before command rendering. The executor does not silently
promote a reviewed warning into a lossless operation.

## Exact MKVToolNix plan

The direct argument array uses the bundled exact-path `mkvmerge` with:

- `--abort-on-warnings`, `--flush-on-close`, canonical language normalization,
  track-statistics preservation, and file-based append timing;
- explicit adjacent `--append-to` entries for every lane and every source after
  the first, including chains longer than two files;
- explicit first-source `--track-order` plus per-source video, audio, and
  subtitle selections;
- buttons, attachments, and input chapters disabled on every source;
- later-source global and track tags disabled so the first source remains the
  single metadata authority; and
- one canonical reviewed Matroska chapter XML document supplied globally.

No shell, ambient tool lookup, network request, LLM, source edit, intermediate
encode, or arbitrary command execution is involved. `mkvmerge` is a remuxer and
cannot introduce a hidden video/audio encode in this path.

## Transaction and verification

Every source is bound at preview time to size, modification date, file number,
and filesystem number. The complete set is checked immediately before the job,
after `mkvmerge`, before commit, and after the committed file is reopened. An
inspected size mismatch at preview is stale immediately.

The output is created at a private non-existent path on the destination volume.
Before the exclusive atomic commit, the app verifies:

- a nonempty Matroska output and an operation-bounded joined duration;
- exact output track count/order and the first source's technical, language,
  role, flag, title, UID, color/HDR, audio-layout, and non-provenance tag facts;
- no attachments, the expected top-level chapter count, first-source global and
  track tag counts, and a fresh segment UID; and
- canonical `mkvextract` chapter XML equality, including nested hierarchy, UIDs,
  flags, names, languages, and nanosecond timestamps.

The same inspection and exact chapter extraction run again after reopen. A
pre-commit mismatch removes the temporary output and leaves every source and
destination untouched. A post-commit mismatch reports the saved output path
truthfully instead of claiming success.

## Regression and real-tool evidence

Six focused unit tests cover the exact three-source adjacent command chain;
review/normalization and missing-UID refusal; source revision invalidation both
before and during `mkvmerge`; one-output commit with source preservation; and
wrong-duration or wrong-chapter failures that cannot commit.

A bundled-tool integration generates three independent one-second AAC Matroska
sources with FFmpeg, inspects them with FFprobe plus MKVToolNix, proposes and
analyzes their mapping, joins them with MKVToolNix 100.0, and reopens the output.
It observes one retained audio lane, the first source's stable track UID and
metadata, three nested source-part chapters, canonical chapter XML equality, and
unchanged SHA-256 digests for all inputs.

The current complete bundled-tool suite, including the later native app-model
join integration and common-format planner, passes all 262 tests with zero skips
and zero failures.

The current isolated complete local gate passes all 262 tests with 14 intentional
real-tool skips in source-only and sanitizer runs, both Universal architectures,
coverage collection, AddressSanitizer, ThreadSanitizer, inside-out package
signatures, entitlements, SBOM/checksums, ZIP/appcast assembly, and verified DMG
packaging.

## Still pending in M5

- Manual lane editing for ambiguous mappings and retry-from-History UI. Native
  include/order review, chapter-edition selection, output naming, progress, and
  pre-commit cancellation are implemented in the later native slice.
- Keyframe-aware fast trim and exact trim, including truthful adjusted-boundary
  disclosure and joined chapter recomposition for retained ranges.
- Explicit attachment selection and user-confirmed metadata/gap policies.
- Decode spot checks at start/middle/end and around every boundary, copied-stream
  fingerprints, malformed/VFR/delayed-stream fixtures, and strict verification.
- Common-format choice controls and the one-generation normalization execution
  path. A truthful preview is implemented in
  `M5_JOIN_NORMALIZATION_PLANNER_SLICE.md`.
- Private-library beta acceptance and physical Intel smoke testing.

Primary command reference: [mkvmerge append and `--append-to` documentation](https://mkvtoolnix.download/doc/mkvmerge.html#mkvmerge.description.append_to).
