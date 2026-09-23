# Common user-flow regression matrix

This matrix gives MKV Magic one readable, executable pass over the journeys a
beta user is most likely to take. The high-level tests live in
`Tests/MKVMagicAppTests/CommonUserFlowRegressionTests.swift`; focused subsystem
tests remain the deeper authority for malformed inputs, tool failures,
cancellation, verification mismatches, accessibility, and release packaging.

The [September product/UX review](UX_PRODUCT_REVIEW_2026-09-05.md) adds shared
appearance/contrast coverage (`AppearanceUXTests`), live segment-title and
status-persistence checks (`NativeFlowUXTests`), and real-tool trim thumbnail
regressions (`TrimThumbnailUXTests`). It also distinguishes delivered flows from
larger original-spec goals and hardware/release acceptance still outstanding.

`AppHistoryConcurrencyTests` runs four real Clean MKV jobs from a single queue
start on AC and battery, checks every History lifecycle and unchanged original,
and verifies that rising thermal pressure leaves later jobs waiting without an
attempt. This covers refilling beyond one scheduler batch, not just admitting
several jobs at once.

The [native UX sweep](NATIVE_UX_SWEEP.md) adds real AppKit field-editor,
minimum-layout, long-list, validation-recovery, and cancellation coverage in
`NativeFlowUXTests`, and records which existing flow tests cover the other
surfaces. Run this alongside the high-level suite, not as a substitute for it.

The [batch-action audit](BATCH_ACTION_AUDIT.md) covers folder-wide remux and
shared batch inclusion/destinations. `ExternalSubtitleBatchMatcherTests` rejects
ambiguous cuts, dates, years, episodes, and duplicate titles. `BatchActionUXTests`
exercises mixed selections, editable active fields, cancellation, exclusions,
scrolling in Light/Dark, and per-source output locations.
`RealToolMKVRemuxTests.testMultipleSidecarsShareOneVerifiedRemuxAndAuditEachTrack`
checks multiple SRT/ASS payloads, styles, language/role flags, stale sidecars,
chapters, and original bytes in one zero-encode output.
`RealToolAppHistoryTests.testRestoredQueueRunsAllReviewedSidecarsAndPreservesMetadata`
executes a plural-sidecar job through a fresh app model and restored queue.

## High-level suite

| Flow | Contract | Executable regression |
| --- | --- | --- |
| 01. Add and remove media | Recursive intake accepts supported media; removing an inspected item changes only app state and preserves source bytes. | `testFlow01FileIntakeAndRemovalPreservesSource` |
| 02. Edit metadata and tracks | Reviewed title and track-property edits use zero video and zero audio encodes. The compact track editor accepts active text entry, language selection, and every flag; live validation rejects unchanged or invalid values and recovers immediately when corrected. | `testFlow02MetadataAndTrackEditingRemainZeroEncode`, `AppPolicyTests.testTrackEditorWindowUsesCompactNativeLayout`, `AppPolicyTests.testTrackEditorPreviewsTextWhileTheFieldEditorIsStillActive`, `AppPolicyTests.testTrackEditorRefreshesPreviewForFlagsLanguageCorrectionAndTrackSelection`, `RealToolTrackMetadataEditTests.testRealToolsEditTrackMetadataOnVerifiedCloneAndPreserveOriginal` |
| 03. Clean a subtitle | Cleanup writes a distinct verified copy, removes the reviewed noise, and leaves the source unchanged. | `testFlow03SubtitleCleanupCreatesNewVerifiedCopy` |
| 04. Use quick actions | Suggested output names are distinct, MKV-safe, and free of traversal. | `testFlow04QuickActionOutputNamesAreDistinctAndSafe` |
| 05. Join media | Compatible segments stay lossless; an H.264 codec-initialization-only mismatch offers reviewed zero-encode header repair with strict packet and boundary audits before the one-generation fallback, including the disclosed HD untagged-AVC SDR path. Every join automatically places all retained source leaves in one player-compatible top-level chapter list and continues repeated consecutive numbered sequences without rewriting custom names. | `testFlow05CompatibleJoinStaysLossless`, `testFlow05CodecInitializationMismatchUsesOneGeneration`, `testFlow05UntaggedHDH264CanUseReviewedSDRCommonFormat`, `JoinedChapterComposerTests.testComposesFlatPlayerCompatibleListFromEveryJoinedLeafChapter`, `JoinedChapterComposerTests.testRenumbersRepeatedConsecutiveChapterSequencesAcrossRealPartCounts`, `JoinedChapterComposerTests.testLeavesMixedAndNonconsecutiveChapterTitlesUnchanged`, `AppPolicyTests.testLosslessJoinReviewExposesEverySourceChapterAtTheTopLevelByDefault`, `LosslessJoinExecutorTests.testHeaderNormalizedH264CommandCopiesEveryLaneAndRestoresVideoUID`, `RealToolLosslessJoinTests.testBundledToolsCommitReviewedCodecPrivateAppendOnlyAfterCleanAudit` |
| 06. Trim and convert | Exact trim plus conversion fuses video work into one generation. | `testFlow06ExactTrimAndConversionFuseToOneVideoGeneration` |
| 07. Clean, save, and queue an MKV workflow | The main Clean MKV action uses the complete shared recipe for one or many MKVs. Metadata-only cleanup remains available without subtitle removal; portable intent compiles without media paths, is queue eligible, and stays zero-encode. Concurrent jobs share one History writer and preserve every lifecycle and original. | `testFlow07SavedWorkflowPreviewIsPortableAndQueueEligible`, `NativeFlowUXTests.testCleanMKVIsAvailableWithoutSubtitleRemovalAndForMatroskaBatch`, `SavedWorkflowCompilerTests.testCleanMKVPresetAppliesMetadataCleanupWithoutSubtitleRemoval`, `AppHistoryConcurrencyTests` |
| 08. Review History | A verified job records the ordered planned, running, verifying, committing, and completed lifecycle. | `testFlow08HistoryRecordsTheVerifiedLifecycleInOrder` |
| 09. Save an output safely | An automatic destination requires a writable directory grant, otherwise the save panel obtains access; collision numbering never overwrites an existing output. | `testFlow09DestinationRequiresAccessAndNeverOverwrites` |
| 10. Read progress and Help | Bounded progress is determinate and accessible, including machine-reported MKVToolNix progress within a stage; Help preserves the local/original-safety contract; updates do not check automatically. | `testFlow10ProgressAndHelpRemainAccessibleAndLocal` plus `AppPolicyTests.testProgressSurfacesMeasureCommonJoinStagesAndBatchItems` |
| 11. Remux video with a sidecar | One compatible MP4-family/WebM source plus one SRT/ASS/SSA becomes one reviewed zero-encode MKV operation; conservative filename language defaults remain editable, both originals are preserved, and multiple independently reviewed pairs can wait in the queue without losing their language choices. An earlier automatic job may keep running while the user reviews and enqueues the next already-inspected pair, but immediate execution remains serialized. Cross-container duration rounding uses one shared 100 ms packet-copy bound with a strict rejection immediately beyond it. | `testFlow11DraggedMP4AndSRTBecomeOneEditableZeroEncodeRemux`, `testFlow12TwoReviewedMP4AndSRTJobsCanWaitTogether`, `AppPolicyTests.testAutomaticQueueExecutionKeepsReviewedQueueAuthoringAvailable`, `MKVRemuxOutputVerifierTests.testAppendedSubtitleUsesTheSharedPacketCopyDurationTolerance`, `OutputVerificationTests.testExternalSubtitleVerifierUsesTheSharedPacketCopyDurationTolerance`, `RealToolMKVRemuxTests.testBundledToolsRemuxMP4AndSRTInOneVerifiedZeroEncodePass`, `RealToolMKVRemuxTests.testSelectedRealMP4AndSRTIfProvided`, `RealToolAppHistoryTests.testAutomaticQueueRunsReviewedChapteredMP4AndSRTWorkflowWithoutEncoding` |
| 13. Suggest chapters for multiple files | Multi-selection uses one non-overlapping detector-options sheet, reviews every source-bound timestamp together, composes independent chapter documents, names every output distinctly, and leaves originals unchanged. | `testFlow13BatchChapterSuggestionsStayIndependentAndPreserveOriginals`, `AppPolicyTests.testChapterSuggestionOptionsFitWithoutOverlappingAtMinimumSize`, `AppPolicyTests.testBatchChapterSuggestionReviewKeepsFilesAndBoundariesTogether`, `AppPolicyTests.testMainFileListOffersVerifiedBatchTagRemovalForMultipleMKVs` |
| 14. Understand and retry a failed queued job | A failed automatic job preserves a shared privacy-safe category and last active stage, shows an actionable selectable explanation, survives queue persistence, and appears in optional support evidence without private names, paths, subtitle text, or raw errors. Fresh review keeps the job identity; each real execution start increments Tries and a later failure replaces the selected diagnosis. | `JobQueueTests.testPrivacySafeFailureClassifierIsSharedBoundedAndStoresNoRawDetails`, `MediaQueueAdmissionCoordinatorTests.testCoordinatorMapsExecutorOutcomesAndHonorsPauseWithoutCallingExecutor`, `JobQueueStoreTests.testAtomicMutationsPersistPauseHoldReorderRetryAndCancel`, `PrivacySafeSupportReportTests.testReportIncludesPrivacySafeQueueFailureWithoutNamesPathsOrRawErrors`, `AppPolicyTests.testQueueWindowKeepsNativeControlsReadableAtMinimumSize` |

Run the high-level pass with:

```sh
swift test --filter CommonUserFlowRegressionTests
```

## Deeper regression coverage

Cold queue restoration also requires the two-process signed-app procedure in
[Restored queue access regression](RESTORED_QUEUE_ACCESS_REGRESSION.md).
`MediaQueueAdmissionCoordinatorTests.testAdmissionPreservesOriginalScopedURLsWhileDeduplicatingAccesses`
guards the URL-preservation contract; it is not a substitute for real sandbox,
subprocess, destination, and cancellation acceptance.

The complete `swift test` pass additionally covers:

- recursive discovery, FFprobe/MKVToolNix normalization, source revisions, and
  unsupported or unsafe inputs;
- segment titles, track flags and roles, track removal, tags, attachments,
  chapters, external subtitles, extraction, timed-text conversion, and cleanup;
- paired common-media and sidecar intake, editable filename-derived language
  defaults, one-pass track ordering, exact subtitle payload audit, and copied
  packet preservation;
- multi-selection tag removal with one batch review, measured item progress,
  collision-safe verified outputs, per-file failure isolation, and unchanged
  originals;
- multi-selection chapter analysis with shared validated settings, source-bound
  timestamp review, measured item progress, independent exact chapter writes,
  collision-safe outputs, and unchanged originals;
- durable reviewed tag, standalone SRT/ASS cleanup, and exact nested chapter
  jobs across a cold model/store reload; pause, queue drain, changed sources,
  changed cleanup-output contracts, independent completion, and failed/interrupted
  Review Again with the original job identity and increasing Tries;
- shared batch admission exclusions, reserved output names, per-file preparation
  failures, cancellation retaining already queued work, and balanced retry access;
- bulk metadata patches preserving unchosen fields and per-file identities;
  mixed/no-op review, exact trim-amount parsing and bounds, SRT/ASS extraction,
  and relative trims with chapter preservation across cold queue restoration;
- real held automatic-queue execution with continuing authoring/intake, restored
  selection, guarded foreground work, and a second job drained without restarting;
  native bulk forms in Light/Dark at minimum size with fixed visible actions;
- lossless and common-format joins, lossless and exact trims, audio/video
  conversion, HDR policy, encoder probing, and one-generation enforcement;
- workflow migration, editor behavior, portable compilation, batch review,
  queue admission and recovery, persisted privacy-safe queue failure details,
  durable History, verified commit, and explicit Trash-after-success outcomes;
- output security scopes, collision handling, cancellation, actionable errors,
  keyboard and VoiceOver contracts, window layout, Help, third-party notices,
  manual Sparkle policy, and privacy-safe diagnostics.

Generated and bounded integration fixtures exercise the media adapters. Private
beta media is never committed. This automated matrix is not evidence of a
downloaded DMG install, a prior-version updater replacement, physical Intel or
Apple Silicon acceptance, or real-file Jellyfin/Plex playback.
