# M7 queue admission coordinator foundation slice

This slice turns the pure queue scheduler and reviewed file revisions into one
fail-closed automatic-admission contract. It deliberately stops before an app
launch hook or production media executor is connected.

## Admission boundary

For every scheduler-selected waiting job, the coordinator:

1. asks the caller whether its exact workflow is supported automatically;
2. resolves every input through its unchanged-only security-scoped bookmark;
3. resolves and revalidates the destination-directory bookmark;
4. derives the output beneath that exact directory through the shared queue
   filename policy and refuses an existing output; and
5. transitions the job to **Running** only after every preflight succeeds.

Unsupported workflows move to **Needs Review** with
`automaticExecutionUnavailable`. Missing legacy revisions, changed inputs,
stale or unsafe bookmarks, unavailable destinations, unsafe output names, and
occupied output paths move to **Needs Review** with `staleReview`. None are
silently refreshed or sent to a media tool.

The coordinator reloads the durable queue after rejected work so a stale or
unsupported job does not consume a scheduler slot that a later eligible job can
use. The pure scheduler remains the sole source of queue order, pause, battery,
thermal, and resource-pool decisions.

## Execution lifecycle

- Input and destination security scopes remain active only around the injected
  executor callback and are balanced on every return or thrown error.
- After opening those scopes, the coordinator repeats the input revision,
  destination type/containment, and unused-output checks immediately before the
  callback. A change in the preflight-to-execution gap becomes **Needs Review**.
- The callback can report only **verified success**, **failed**, **cancelled**,
  or **needs review**. A thrown `CancellationError` becomes cancellation; another
  thrown error becomes failure.
- Verified success maps to **Succeeded**. Failure records the bounded
  `executionFailed` reason. Cancellation follows the cooperative
  **Running -> Cancelling -> Cancelled** path. Re-review records `staleReview`.
- Jobs already changed externally from **Running** or **Cancelling** are not
  overwritten when the callback returns. A process interruption still leaves a
  durable running state that the existing relaunch recovery converts to **Needs
  Review**.
- Eligible resource classes execute concurrently only after each job has been
  durably admitted. Queue-store mutation remains serialized by its actor.

## DRY and compatibility boundaries

- The output filename rules now live in one core policy shared by queue-store
  validation and admission URL derivation. The policy preserves the existing
  version-one 1,024-byte compatibility limit.
- Unchanged-only bookmark resolution now starts and balances its security scope
  while reading the revision, which is required after a sandboxed relaunch.
- `automaticExecutionUnavailable` is an additive enum value inside the existing
  queue schema. Existing version-one documents continue to decode.

## Regression evidence

- Resolver tests prove an unchanged input and unused destination resolve to the
  intended output, while an occupied output or later file mutation fails closed.
- Coordinator tests prove that fresh supported work alone reaches the executor;
  stale and unsupported work receives distinct durable review reasons.
- Outcome tests prove verified success, thrown failure, thrown cancellation, and
  explicit re-review map to the correct state and attempt count.
- A paused queue invokes no executor. The existing core scheduler regressions
  continue to cover queue order, active-capacity accounting, one video-heavy
  slot, separate audio/lightweight pools, reduced battery behavior, and serious
  thermal blocking.
- The complete local gate passed against the pinned Universal media runtime.
  Normal, coverage, AddressSanitizer, and ThreadSanitizer each executed all 474
  tests with zero failures. Source validation built the release executable for
  both `arm64` and `x86_64`.
- The isolated package gate passed app and nested Sparkle signature validation,
  update ZIP and appcast generation, package metadata, third-party notices,
  supported-systems record, CycloneDX SBOM, recorded checksums, and independent
  DMG verification.

## Explicitly not accepted by this slice

- The app does not invoke this coordinator, provide its media executor callback,
  author waiting jobs, or monitor system power/thermal changes yet.
- External-subtitle workflows are not automatically reconstructable from the
  current queue document because their reviewed text choices and track metadata
  are intentionally ephemeral. A production capability check must refuse them
  until a privacy-safe exact-intent design exists.
- No watched folder, scheduled launch, helper process, background daemon, or LLM
  is introduced.
- Local tests are not a queue soak, physical Intel acceptance, Developer ID
  notarization, or public-release artifact.
