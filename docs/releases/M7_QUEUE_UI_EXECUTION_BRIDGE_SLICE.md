# M7 queue UI and execution bridge slice

This slice makes saved-workflow execution visible and recoverable through the
durable production queue. It connects the existing reviewed workflow pipeline to
real sandbox bookmarks and a compact native Queue window without claiming the
later unattended scheduler.

## Verified execution boundary

- **Verify & Run** creates the queue job and transitions it to **Running** before
  launching MKVToolNix. It stores the portable saved-workflow snapshot, exact
  reviewed `ExecutionPlan`, derived resource class, output display name, and
  source-disposition policy.
- Each source and reviewed external subtitle receives a fresh read-only
  security-scoped bookmark. The selected destination directory receives a fresh
  read/write bookmark. Creation and resolution reject symlinks, stale bookmarks,
  wrong resource types, non-file URLs, and missing resources.
- The AppModel reuses one queue-store actor, avoiding competing read/modify/write
  sequences. Relaunch recovery runs once; later window refreshes load current
  state without converting active work to **Needs Review**.
- A verified commit transitions the job to **Succeeded**. Ordinary execution
  errors transition to **Failed** with a bounded enum reason. Cancellation first
  requests **Cancelling**, cancels the actual Swift task and supervised process
  tree, removes temporary work through the existing transaction, and records
  **Cancelled**. If verified commit won the race, the truthful terminal state is
  **Succeeded**.

## Native Queue window

- The six-column AppKit table shows order, portable workflow name, primary input
  display name, encode cost, current state, and attempt count.
- Pending work can be held, resumed, reordered, or cancelled. Running work can
  be cancelled. Failed or interrupted saved workflows expose **Review Again…**.
- Review Again resolves only the stored primary input authority, re-inspects the
  current file, asks again for any runtime-only external subtitle, recompiles the
  portable recipe, and returns through the normal explicit plan review. Approval
  atomically replaces all old file authority, destination, and plan facts before
  the next attempt.
- Queue changes refresh an already-open window. The layout remains readable at a
  700 x 420 minimum while the default 840 x 520 size shows all six columns and
  controls without horizontal scrolling.
- **Pause Automatic Starts** persists scheduler intent but explicitly does not
  block a user clicking **Verify & Run**. The explanatory copy makes that current
  distinction visible.

## Regression and integration evidence

- Domain tests cover fresh replan requirements and late cancellation after the
  verified commit boundary.
- Store tests cover atomic replan replacement alongside hold, reorder, retry,
  and cancel mutations.
- Bookmark tests create and resolve real temporary file/directory bookmarks and
  refuse symlinks and incorrect resource types.
- App tests prove one-time launch recovery, live current-work loading, compact
  native layout, column contents, explicit pause language, and presentation
  summaries.
- The bundled-tool integration creates a real MKV, cleans and adds a reviewed SRT
  in one verified transaction, preserves both source digests, and proves the
  durable queue contains the exact recipe, plan, bookmarks, output name, one
  attempt, and `waiting -> running -> succeeded` lifecycle.
- Visual inspection artifact:
  `durable-production-queue.png` in the task visualization directory.
- The complete local release gate passed with the pinned Universal tool runtime:
  the primary, coverage, AddressSanitizer, and ThreadSanitizer test invocations
  each executed 462 tests with zero failures or skips. Source validation produced
  an `arm64` + `x86_64` release executable. The isolated package gate then built
  and ad-hoc signed the app and Sparkle helpers, validated nested signatures,
  generated the update ZIP, DMG, appcast, checksums, package metadata, notices,
  supported-systems record, and CycloneDX SBOM, verified every recorded checksum,
  and independently verified the DMG image.

## Explicitly not accepted by this slice

- No coordinator automatically starts waiting jobs from the pure scheduler yet.
- Built-in quick actions do not create production-queue jobs yet.
- Pause, battery, and thermal policy are not yet connected to automatic executor
  admission; there is no unattended background or folder-watching mode.
- The queue source-disposition UI does not yet offer Trash after verified success.
- Local gates are not an hour-long queue soak, physical Intel acceptance,
  Developer ID notarization, or public-release evidence.
