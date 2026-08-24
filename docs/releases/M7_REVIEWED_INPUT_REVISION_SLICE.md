# M7 reviewed input revision slice

This slice adds the file-identity boundary required before a future automatic
queue coordinator may trust durable bookmark authority. It does not start jobs
automatically.

## Durable revision contract

- Every new queued file reference records its file size, a
  millisecond-normalized modification date, and the filesystem file/system
  numbers available from macOS.
- The revision contains no path, media metadata, title, track facts, subtitle
  text, or content digest. The existing opaque security-scoped bookmark remains
  the only durable file authority.
- Destination-directory references never receive a file revision. Store
  validation rejects a forged directory revision, a negative file size, and a
  non-finite date.
- `reviewedRevision` is optional so version-one queue documents written before
  this slice continue to decode. Omission is never interpreted as unchanged.

## Unchanged-only resolution

The ordinary bookmark resolver still supports explicit user review and
post-success Trash recovery, where the current location must be inspected even
if the source changed. A separate unchanged-only file resolver:

1. requires a reviewed revision;
2. resolves and revalidates the security-scoped bookmark without UI;
3. reads the current file revision through the shared safe regular-file reader;
   and
4. returns the URL only when every recorded fact still matches.

A legacy reference, changed size/date/identity, stale bookmark, symlink, missing
file, directory, or unsafe URL all fail closed. The later
[queue-admission coordinator foundation](M7_QUEUE_ADMISSION_COORDINATOR_FOUNDATION_SLICE.md)
uses this resolver before admitting work and moves failed checks to **Needs
Review** instead of silently refreshing the revision.

## DRY boundary

The queue codec and the existing fast trim, exact trim, lossless join,
normalization, and final-assembly stale-source guards now use one
`MediaFileRevision` model and one `MediaFileRevisionReader`. Queue persistence
normalizes only the modification date to the JSON store's millisecond precision;
in-process executor checks retain the filesystem's full reported precision.

## Regression evidence

- Real bookmark tests prove revision capture for read-only and read/write files,
  no revision for a destination directory, unchanged resolution, ordinary
  resolution after mutation, and unchanged-only refusal after mutation or when
  a legacy reference omits the revision.
- Queue-store tests prove revision JSON round-trip without a path and reject
  negative file sizes and destination-directory revisions.
- The bundled-tool saved-workflow integration proves both the primary MKV and
  reviewed external subtitle receive revisions, both resolve unchanged, and the
  destination directory remains revision-free.
- Focused stale-source regressions for fast trim, exact trim, lossless join,
  join normalization, and final assembly remain green after consolidation onto
  the shared reader.
- Normal, coverage, AddressSanitizer, and final ThreadSanitizer runs each passed
  all 470 tests against the pinned Universal media runtime. The first full
  ThreadSanitizer pass exposed a fixed 0.1-second wait in an existing trim-window
  regression; that test now waits up to a bounded deadline for the actual UI
  state, passes in isolation, and passes in the repeated full sanitizer suite.
- Source validation built the release executable for `arm64` and `x86_64`. The
  isolated package gate passed app and Sparkle signature validation, update ZIP,
  appcast, metadata, notices, supported-systems record, CycloneDX SBOM,
  checksums, and independent DMG verification.

## Explicitly not accepted by this slice

- No production executor, battery adapter, thermal adapter, unattended start,
  watched folder, or built-in quick-action queueing is connected. A later slice
  adds the system coordinator contract without invoking it from the app.
- The stat-based revision is a bounded local change detector, not a cryptographic
  digest or proof against an adversary able to rewrite both file bytes and file
  metadata. Hashing multi-gigabyte inputs at queue time remains intentionally
  outside this lightweight slice.
- Local tests are not physical Intel, queue-soak, notarization, or public-release
  evidence.
