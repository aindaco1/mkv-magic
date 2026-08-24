# M7 durable queue foundation slice

This slice establishes the persistence, recovery, and scheduling contracts for
the production queue. It is deliberately separate from sanitized execution
History and does not claim a queue window, background execution, or automatic
retry.

## Durable intent boundary

- Each queued job stores a saved-workflow snapshot or stable built-in workflow
  identity, the reviewed execution plan and derived resource class, ordered
  inputs, output display name, source disposition, and destination directory.
- File authority is represented only by bounded opaque security-scoped bookmark
  data and a display name. The schema has no absolute-path field.
- The private `job-queue.json` document is versioned, atomically replaced, and
  owner-readable/writable only. It is capped at 1,000 jobs and 32 MiB; each
  bookmark is capped at 256 KiB and each display name at 1 KiB.
- The store refuses unsafe document or parent paths, symlinks, special files,
  unsupported schemas, duplicate job/reference identities, empty or oversized
  bookmarks, empty or null-containing names, forged attempt counts, malformed
  transition histories, stale timestamps, and a resource class inconsistent
  with the reviewed plan.

## State and recovery contract

- Pending work may be held, resumed, reordered, or cancelled. Failed work may
  return to waiting only through an explicit retry transition. Starting an
  attempt increments its durable count exactly once.
- Running cancellation is a request state, not a success claim. Only an executor
  can subsequently mark the job cancelled, failed, or in need of another review.
- On relaunch, running and cancelling jobs become **Needs Review** with a bounded
  interruption reason. They never auto-run from a possibly stale inspection,
  destination, or review.
- Queue events persist enums and timestamps, never raw tool output or an
  unsanitized failure string.

## Scheduling contract

- Queue pause stops admission of new jobs; it does not pretend an external
  process can be safely suspended at an arbitrary write boundary.
- Plugged-in, thermally healthy defaults admit at most one video-heavy job, two
  audio-heavy jobs, and three zero-encode lightweight jobs, accounting for work
  already running.
- Battery mode admits no new audio/video encoding work and at most one
  lightweight job.
- Serious or critical thermal pressure admits no new work. Held, failed,
  cancelling, completed, and review-required jobs are never selected.
- Within eligible resource slots, pending order is deterministic. A blocked
  heavy job does not prevent a later lightweight job from using an independent
  slot.

## Regression evidence

- Domain tests cover retry attempt accounting, failure-reason enforcement,
  interruption recovery, exact pending-order validation, capacity consumption,
  pause, battery behavior, and thermal blocking.
- Store tests cover atomic mutation sequences, private permissions, restart
  recovery, symlink and unexpected-field refusal, bookmark validation,
  duplicate identities, and replay detection for forged attempts.
- App policy tests verify that queue data shares the existing private
  `com.dustwave.mkvmagic` Application Support directory.

## Verified local gate — 2026-08-23

- The normal source gate passed 454 tests with 31 intentional runtime-dependent
  skips, strict Swift formatting and source checks, and the Universal arm64 plus
  x86_64 build.
- With the exact pinned media-tool root required, all 454 tests passed with zero
  skips and zero failures, including the real metadata, subtitle, chapter, trim,
  join, and transcoding transactions.
- Code-coverage collection completed. AddressSanitizer and ThreadSanitizer each
  passed all 454 tests with zero failures.
- The package gate verified the Universal app and nested signatures, bundled
  tool inventory, notices, supported-systems document, SBOM, dependency lock,
  build metadata, appcast, ZIP, SHA-256 manifest, and DMG checksum. The complete
  local gate exited successfully.

## Explicitly not accepted by this slice

- No current Verify & Run action creates a production-queue record yet.
- No UI offers pause, resume, reorder, retry, cancel, or review-again controls.
- No bookmark resolver, executor coordinator, battery adapter, or thermal adapter
  is connected to the scheduler.
- No interrupted job can execute until a later slice resolves its bookmarks,
  re-inspects the source, recompiles/reviews the plan, and obtains fresh user
  approval where required.
- Local tests are not physical Intel queue acceptance, an hour-long soak,
  Developer ID notarization, or public-release evidence.
