# M5 verified keyframe-aware Fast Trim executor slice

This records engineering acceptance of the non-UI Fast Trim path for inspected
Matroska MKVs with exactly one video track. It does not claim frame-exact trim,
a native trim window, multiple-video handling, ordered-edition support, generic
splitting, private-library acceptance, physical Intel acceptance, or a public
release.

## Truthful boundary review

- Bundled `ffprobe` scans only the primary video track, discards non-keyframes,
  emits bounded JSON, and is launched by absolute path with an argument array.
- The planner sorts and deduplicates exact integer-nanosecond keyframe times.
- A requested in or out point resolves to the first keyframe at or after that
  timestamp, matching MKVToolNix parts-splitting behavior. The physical source
  end is a valid adjusted out point.
- The immutable preview contains both requested and adjusted ranges. It exposes
  separate start/end adjustment facts and never describes the result as
  frame-exact.
- A full-file request, a range outside the media, a missing usable keyframe, or
  an adjustment that would retain the complete file fails before output work.

## Nested chapter recomposition

The complete source chapter XML is extracted through the same bounded shared
extractor used by chapter editing and join audits. Each retained atom is
intersected with the adjusted range, clipped at either boundary, rebased to
output time zero, and kept in its original hierarchy. Empty editions disappear;
retained edition and atom UIDs are regenerated for the new segment. Ordered
editions fail closed because physical cropping cannot safely preserve their
playback semantics.

The source filesystem revision and canonical original-chapter SHA-256 are bound
to preview. Both are checked repeatedly before, during, and after tool work.

## Zero-encode transaction

1. Reserve a non-existent private output on the destination volume.
2. Run one `mkvmerge --split parts:` command with the reviewed adjusted range,
   source chapters disabled, language normalization, and statistics-tag
   generation disabled. No FFmpeg encode or shell is involved.
3. Apply the already reviewed trimmed chapter document to that temporary MKV
   with `mkvpropedit`.
4. Reinspect and require non-empty Matroska, adjusted duration within the
   packet-remux tolerance, exact packet-copy stream identity/order/metadata,
   exact attachments, preserved non-provenance metadata/tag counts, reviewed
   top-level chapter count, and a new segment UID.
5. Re-extract and canonicalize the full nested chapter XML and require exact
   equality.
6. Commit atomically without overwrite, reopen the final path, and repeat the
   semantic and canonical chapter audits.

A changed source never commits. Tool, duration, stream, metadata, attachment,
chapter, or pre-commit cancellation failures remove the temporary output. A
post-commit audit failure truthfully reports the actual saved URL.

## Regression and bundled-tool evidence

Thirteen tests cover boundary rounding, physical edges, invalid/no-op ranges,
nested clipping/rebasing, empty and ordered editions, bounded keyframe parsing,
exact direct-argument command rendering, no-encode execution, revision changes
before and during splitting, tool/semantic/chapter failure, commit-stage truth,
source-byte preservation, and the two complete output audits.

The bundled integration creates a ten-second MPEG-4 MKV with two-second GOPs and
nested chapters. A requested 3–7 second range is reviewed as 4–8 seconds,
executed by the production transaction, decoded successfully, and re-extracted
with exact nested chapter equality while the source SHA-256 remains unchanged.

At acceptance of this slice, the suite contained 316 tests. The standard source
run passed with 19 intentional bundled-tool skips; the assembled Universal
runtime ran all 316 with zero skips and zero failures. Source validation also
passed formatting, security/static checks, and Universal `arm64`/`x86_64`
compilation.

## Still pending

- Native thumbnails plus numeric in/out fields and an explicit Fast/Exact mode
  switch.
- Multiple-video policy, selected-range splitting, Chapter Studio keyframe
  snapping, private-library beta, and physical Intel performance acceptance.

The one-generation Exact Trim executor was subsequently accepted separately in
`M5_EXACT_TRIM_EXECUTOR_SLICE.md`; that does not broaden this Fast Trim slice's
own claims.
