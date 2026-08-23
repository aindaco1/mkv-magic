# M5 verified final common-format join executor slice

This records engineering acceptance of the non-UI final executor for the
supported common-format hard-join boundary. It does not claim native exact-choice
controls, source-tag preservation, subtitle conversion/gaps, HDR conversion,
join-boundary decode sampling, public release, or physical Intel acceptance.

## Revision-bound preview

- Every original and the committed normalized stream bundle is bound to file
  size, modification time, and stable filesystem identity.
- Preview validates the full joined duration and nested chapter document, writes
  canonical chapter XML in a private directory, and dry-compiles the exact final
  command. The resulting lane mechanisms, source track IDs, metadata sources,
  and attachment choices become immutable preview facts.
- A changed or replaced original/bundle before execution fails before
  `mkvmerge`. A change while `mkvmerge` runs removes the temporary output and
  cannot commit.

## Verified output transaction

1. Reserve a private non-existent working path on the destination volume.
2. Recompile and compare the exact reviewed lane/attachment facts.
3. Run one bounded direct-argument `mkvmerge` process.
4. Reopen the temporary MKV and verify:
   - non-empty Matroska and operation-bounded joined duration;
   - exact mapped track count/order and packet technical identity;
   - reviewed language, name, and disposition flags per lane;
   - exact retained attachment multiset;
   - reviewed segment title and zero unpreserved global/track tags;
   - expected top-level chapter count and a new segment identity.
5. Re-extract chapters with bundled `mkvextract`, parse safely within the 16 MiB
   bound, canonicalize nested XML, and require byte equality with the reviewed
   document.
6. Mark verified, atomically commit without overwrite, reopen the final path,
   and repeat the semantic and canonical chapter audits.

A post-commit audit failure is reported as a saved-but-failed audit with the
actual output URL. It is never mislabeled as if no output existed.

## Shared safety code

The exact Matroska chapter re-extraction/canonicalization logic is now one shared
auditor used by both lossless and normalized joins. The generic verified-output
pipeline now accepts asynchronous verification, allowing external payload audits
to run at both temporary and committed boundaries without duplicating the
transaction state machine.

## Regression evidence

Five executor tests cover one mux plus two chapter audits, sanitized stage
ordering, original/bundle byte preservation, changes before and during mux,
tool failure, wrong technical tracks, wrong reviewed metadata, wrong attachments,
unexpected tags, wrong canonical chapters, commit-boundary cancellation, and a
truthfully reported committed reopen failure. The pre-existing seven lossless
join executor tests remain green through the shared-auditor refactor.

The bundled mixed-lane test now uses the final executor rather than invoking the
command directly. It normalizes only mismatched video, appends AAC from the
originals, verifies HEVC/AAC identity and exact chapters before and after atomic
commit, and proves both originals remain byte-identical.

The current suite contains 303 tests. The standard run has 18 intentional
bundled-tool skips; the assembled-runtime run executes all 303 with zero skips.
The complete gate also covers coverage, AddressSanitizer, ThreadSanitizer,
Universal build, signatures/entitlements, SBOM/checksums, ZIP/appcast assembly,
and verified DMG packaging.

## Still pending

- Compact native controls for the exact file-specific choices and app-level
  progress/history execution wiring.
- Verified preservation of source tags and executable text-subtitle
  conversion/gap intermediates.
- Join-boundary decode checks, fast/exact trimming, private-library beta
  acceptance, and physical Intel performance acceptance.
