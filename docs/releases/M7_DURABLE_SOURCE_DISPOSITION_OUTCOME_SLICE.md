# M7 durable source-disposition outcome slice

This slice closes the earlier queue-success-to-Trash recovery gap without
pretending the private queue document and macOS Trash form one atomic system.
It applies only to the already opt-in **Move original video file to Trash after
verified success** policy for saved workflows.

## Durable outcome contract

- A Trash-selected job may record exactly one post-success result: `applied`,
  `failed`, or `uncertain`.
- The result has its own timestamp and advances the durable job and snapshot
  update time. It is not a lifecycle event and cannot turn successful media
  work into a failed encode.
- Domain transitions reject a result unless Trash was requested and the job is
  already **Succeeded**. They also reject a second result or a timestamp older
  than the verified state.
- Store validation rebuilds the lifecycle from the original waiting event,
  replays the result through those same rules, and compares the complete result.
  Hand-edited JSON therefore cannot forge a successful Trash claim.
- The field is optional, so queue documents written before this slice continue
  to decode. Absence means the post-success follow-up is genuinely pending, not
  that Trash succeeded.

## Relaunch recovery

On every queue load, after the one-time interrupted-work recovery, MKV Magic
finds only jobs that meet all three conditions:

1. the media job is durably **Succeeded**;
2. Trash was explicitly selected; and
3. no source-disposition result exists.

For each match, the app resolves the stored read/write bookmark for the primary
media source and asks macOS to move that source to Trash. It persists the
observed result atomically before a later refresh can act on the job again.
Supplemental subtitle bookmarks remain read-only and are never considered.

If macOS reports failure while the source still exists, the result is `failed`.
If the source is absent or its bookmark no longer resolves, the result is
`uncertain`; the app tells the user to check the original and Trash rather than
claiming where the file went. Multiple recovered jobs produce one aggregate
banner that preserves any uncertainty instead of allowing a later success to
hide it.

The Queue window renders these results as **Trashed**, **Trash failed**, and
**Check Trash**. A verified Trash job with no result is visibly **Trash pending**.
Failed, uncertain, and pending outcomes remain included in the Queue summary as
Trash follow-up items; an applied outcome does not.

## Regression evidence

- Domain tests enforce verified-success ordering, single assignment, requested
  policy, and timestamp advancement.
- Store tests prove atomic result persistence, backward-compatible absence of
  the optional field, and rejection of a forged result.
- App recovery tests use real macOS security-scoped bookmarks. They cover one
  recoverable source and one source removed after its bookmark was created,
  persist `applied` and `uncertain` respectively, and prove that another Queue
  load makes no second Trash request.
- Presentation tests cover all four visible states and the follow-up summary.
- The native Queue window passed its bounded-layout regression and visual
  inspection with all four outcomes visible at
  `durable-source-disposition-outcomes.png` in the task visualization directory.
- The bundled-tool saved-workflow integration observes a real verified output,
  queue `waiting -> running -> succeeded`, one primary-source Trash request, and
  a durable `applied` outcome.
- Normal, coverage, AddressSanitizer, and ThreadSanitizer runs each executed 468
  tests with zero failures or skips against the pinned Universal media runtime.
  Final source validation repeated all 468 tests and built the `arm64` +
  `x86_64` release executable.
- The isolated package gate passed app and Sparkle signature validation,
  generated and verified the update ZIP, appcast, package metadata, notices,
  supported-systems record, CycloneDX SBOM, SHA-256 manifest, and DMG, then
  independently reverified the DMG checksum and layout.

## Explicitly not accepted by this slice

- Finder Trash and `job-queue.json` still cannot commit as one atomic
  transaction. A crash after Finder accepts the move but before the result is
  written resolves conservatively to `uncertain` if the original has vanished.
- A disk failure that prevents the outcome record from being written leaves the
  follow-up pending and visible; the app never invents durability.
- Automatic scheduler admission, built-in quick-action queueing, watched
  folders, unattended execution, and permanent deletion remain open or out of
  scope as documented in the product specification.
- Local tests are not notarization, public-release, physical-Intel, or
  long-duration queue-soak evidence.
