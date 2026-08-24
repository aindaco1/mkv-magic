# M7 workflow-plan review slice

This slice makes Save & Preview a real approval boundary. It replaces the hidden
button-tooltip summary with a native review of every recipe card before a
compiled workflow can become the main window's pending plan. It does not add new
workflow actions, execution mechanisms, queue behavior, or media mutations.

## User contract

- Save & Preview evaluates the selected inspected file and opens a compact native
  sheet in recipe order.
- Every card is marked as one of:
  - green: the step will apply;
  - orange: the file already satisfies the step, so it will be skipped;
  - gray: the user disabled the step.
- The review states the workflow and source display names, video-transcode count,
  fused work passes, one-new-MKV contract, and unchanged-source guarantee.
- A runnable plan is installed only after **Use This Plan**. Cancel leaves no
  pending workflow. The existing **Verify & Run** gate remains separate.
- If every enabled step is already satisfied, the sheet explains each skip,
  states that no output will be created, and offers only Done.

## Compiler and safety contract

1. Preview and execution compilation share one validation and resolution path;
   preview does not reimplement cleanup policy or operation fusion.
2. Each outcome retains only the portable step ID, action, disposition, and a
   bounded plain-language detail. It does not persist or expose source paths,
   track UIDs, generated commands, or security bookmarks.
3. Applied summaries are derived from the same ordered outcomes attached to the
   immutable compiled workflow, avoiding a second divergent explanation path.
4. A preview with no operations has no `CompiledSavedWorkflow`; the established
   `compile` API still fails with `noApplicableChanges`, so callers cannot execute
   an empty plan.
5. Dismissing or cancelling the review clears the pending plan and stale button
   tooltip. Accepting also rechecks that the selected inspected asset has not
   changed.
6. Media execution remains the existing verified-output transaction. This slice
   adds no shell, network, LLM, file-write, or tool-launch behavior.

## Acceptance evidence

- Planning regressions prove applied, skipped, and disabled outcomes stay in
  recipe order, applied summaries derive from those outcomes, no-op preview has
  no compiled plan, and the legacy compile API still refuses no-op execution.
- AppKit regressions cover both an actionable mixed-outcome review and an
  already-satisfied review with no Use This Plan action.
- The actionable sheet was captured and visually inspected at its supported
  minimum size. Its headings, status icons, details, safety contract, Cancel,
  and Use This Plan controls fit without clipping.

### 2026-08-23 gate results

- The normal source gate passed all 423 tests with 30 intentional no-runtime
  skips, source validation, and the Universal application build.
- The exact pinned Universal runtime passed all 423 tests with zero skips.
- AddressSanitizer and ThreadSanitizer each passed all 423 tests. Coverage also
  passed.
- The package gate passed the Universal app, both architecture-specific media
  tool trees, nested signatures, Sparkle components, update feed, SBOM,
  corresponding source, third-party notices, checksums, ZIP, and mounted and
  verified DMG.
- The review sheet was rendered and inspected at its supported minimum size after
  correcting its scroll content to anchor at the top. All outcome rows and
  approval controls are readable without clipping.
- This is local engineering and ad-hoc signing evidence, not public Developer ID
  notarization, publication, downloaded-artifact verification, or private-library
  playback acceptance.

## Still pending

- Subtitle text-cleanup and subtitle-mux workflow cards.
- Broader conditional cards, filename cleanup, and portable schema migrations.
- Durable queue pause, resume, retry, cancel, reorder, and concurrency behavior.
- VoiceOver, keyboard-only, physical Intel, and private-library beta acceptance.
- Public Developer ID signing, notarization, publication, and downloaded-artifact
  verification.
