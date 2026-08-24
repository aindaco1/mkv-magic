# M7 automatic saved-workflow queue slice

This slice connects the durable scheduler and fail-closed admission coordinator
to one intentionally narrow production executor. A user can review a portable
saved workflow, choose **Add to Queue**, and let MKV Magic start it when the
persisted pause, current power and thermal state, queue order, and resource slots
permit. No LLM, network service, shell script, background daemon, or ambient
Homebrew tool is involved.

## User path and scheduling triggers

- The main footer exposes **Add to Queue** only for a reviewed saved workflow
  whose execution can be reconstructed from one stored MKV input. The same
  shared policy drives authoring and execution, preventing UI/executor drift.
- The Save panel chooses the final output and the existing off-by-default
  Trash-after-verified-success policy. Queue authoring records a **Waiting** job;
  it does not bypass scheduler admission.
- MKV Magic evaluates waiting work after app launch, queue resume, and a new
  **Add to Queue** action. A single overlapping cycle is refused rather than
  racing the same durable queue.
- A native IOKit adapter detects internal-battery versus AC power. The system
  thermal state maps to nominal, fair, serious, or critical pressure. Unknown or
  unavailable facts are conservative: no heavy battery work and no starts under
  serious-equivalent pressure.
- The existing scheduler remains the only concurrency policy: at most one
  video-heavy job, two audio-heavy jobs, or three lightweight jobs when plugged
  in and thermally healthy; battery operation permits only one lightweight job.

## Re-review and source-integrity boundary

Only a current-schema saved workflow with exactly one input and no enabled
external-subtitle or external-subtitle-cleanup card is automatically supported.
Built-in jobs, legacy input references without a reviewed revision, and
interactive subtitle workflows move to **Needs Review** rather than guessing.

Before any media tool runs, admission requires unchanged security-scoped input
authority, a revalidated writable destination directory, a path-safe output name,
and an unused final output. Inside those active scopes, the coordinator repeats
the revision and destination/output checks. The production executor then:

1. records the exact full-precision source revision;
2. re-inspects the current source with bundled FFprobe and MKVToolNix;
3. recompiles the portable workflow against that current inspection;
4. requires the same reviewed encode impact and ordered stage mechanisms and
   summaries, while ignoring only freshly generated stage UUIDs;
5. rechecks the exact source revision after compilation; and
6. carries that revision through the verified output transaction, checking it
   before preparation, after production, after temporary verification, and
   immediately before commit.

Any mismatch becomes **Needs Review** or a failed-closed execution. A successful
temporary result must pass its declared verification, be atomically committed,
reopened, and audited before the coordinator records **Succeeded**. The normal
sanitized History lifecycle is also recorded. The source remains unchanged unless
the user separately selected Trash, which still runs only after durable verified
queue success and retains its durable recovery outcome.

## Cancellation and UI contract

- Automatically admitted resource classes execute concurrently within scheduler
  limits; queue-store mutation remains serialized by its actor.
- The coordinator owns a task per admitted job. Queue cancellation cancels that
  exact task, which propagates to the supervised process tree and the verified
  output transaction.
- A truthful late cancellation may still be **Succeeded** if verified commit won
  the race. Otherwise cancellation follows **Running -> Cancelling ->
  Cancelled** and temporary work is removed.
- **Verify & Run** remains an explicit immediate action and is not blocked by
  **Pause Automatic Starts**. Queue-window copy explains both paths.
- App launch owns and cancels its initial queue task explicitly, and tests inject
  a private queue model so launch coverage never touches a user's real queue.

## Regression evidence

- Focused policy tests cover the shared automatic-workflow subset, semantic plan
  equality, stage-mechanism/summary/impact drift, every known macOS thermal state,
  and an injected power/thermal snapshot.
- Coordinator tests cover unchanged admission, stale and unsupported review
  reasons, a second in-scope safety check, persisted outcome mapping, pause,
  concurrent-cycle refusal, and exact per-job cancellation.
- Executor coverage proves a stale reviewed source fails before any tool runs or
  output appears.
- App layout and launch tests prove the new control is present, initially safe,
  and isolated from the real Application Support queue.
- A bundled-tool integration creates a real MKV, authors a waiting job through
  `enqueueSavedWorkflow`, resumes the queue, re-inspects and recompiles, removes
  the reviewed segment title in one verified transaction, preserves the source
  digest, and records **Waiting -> Running -> Succeeded** plus sanitized History.
- The complete local gate passed against the pinned Universal media runtime.
  Normal, coverage, AddressSanitizer, and ThreadSanitizer each executed all 483
  tests with zero failures. Source validation built the release executable for
  both `arm64` and `x86_64`.
- The isolated package gate passed app and nested Sparkle signature validation,
  update ZIP and appcast generation, package metadata, third-party notices,
  supported-systems record, CycloneDX SBOM, recorded checksums, and independent
  DMG verification.

## Explicitly not accepted by this slice

- External-subtitle workflows still require ephemeral reviewed text and track
  metadata and therefore require interactive review.
- Built-in quick actions do not yet expose **Add to Queue**.
- There is no watched folder, scheduled wake, login item, helper process,
  background daemon, or continuous notification-based power/thermal monitor. A
  blocked job is reconsidered at the next launch, resume, or queue-authoring
  action.
- Local and synthetic tests are not a mixed-media queue soak, a multi-hour
  transcode, physical Intel acceptance, Developer ID notarization, or a public
  release artifact.
