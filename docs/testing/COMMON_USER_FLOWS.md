# Common user-flow regression matrix

This matrix gives MKV Magic one readable, executable pass over the journeys a
beta user is most likely to take. The high-level tests live in
`Tests/MKVMagicAppTests/CommonUserFlowRegressionTests.swift`; focused subsystem
tests remain the deeper authority for malformed inputs, tool failures,
cancellation, verification mismatches, accessibility, and release packaging.

## High-level suite

| Flow | Contract | Executable regression |
| --- | --- | --- |
| 01. Add and remove media | Recursive intake accepts supported media; removing an inspected item changes only app state and preserves source bytes. | `testFlow01FileIntakeAndRemovalPreservesSource` |
| 02. Edit metadata and tracks | Reviewed title and track-property edits use zero video and zero audio encodes. | `testFlow02MetadataAndTrackEditingRemainZeroEncode` |
| 03. Clean a subtitle | Cleanup writes a distinct verified copy, removes the reviewed noise, and leaves the source unchanged. | `testFlow03SubtitleCleanupCreatesNewVerifiedCopy` |
| 04. Use quick actions | Suggested output names are distinct, MKV-safe, and free of traversal. | `testFlow04QuickActionOutputNamesAreDistinctAndSafe` |
| 05. Join compatible media | Compatible segments stay on the lossless join path with no encode. | `testFlow05CompatibleJoinStaysLossless` |
| 06. Trim and convert | Exact trim plus conversion fuses video work into one generation. | `testFlow06ExactTrimAndConversionFuseToOneVideoGeneration` |
| 07. Save and queue a workflow | Clean MKV stores portable intent, compiles without media paths, is queue eligible, and stays zero-encode. | `testFlow07SavedWorkflowPreviewIsPortableAndQueueEligible` |
| 08. Review History | A verified job records the ordered planned, running, verifying, committing, and completed lifecycle. | `testFlow08HistoryRecordsTheVerifiedLifecycleInOrder` |
| 09. Save beside a source | Automatic destination selection numbers collisions and never overwrites an existing output. | `testFlow09AutomaticDestinationNeverOverwrites` |
| 10. Read progress and Help | Bounded progress is determinate and accessible, including machine-reported MKVToolNix progress within a stage; Help preserves the local/original-safety contract; updates do not check automatically. | `testFlow10ProgressAndHelpRemainAccessibleAndLocal` plus `AppPolicyTests.testProgressSurfacesMeasureCommonJoinStagesAndBatchItems` |

Run the high-level pass with:

```sh
swift test --filter CommonUserFlowRegressionTests
```

## Deeper regression coverage

The complete `swift test` pass additionally covers:

- recursive discovery, FFprobe/MKVToolNix normalization, source revisions, and
  unsupported or unsafe inputs;
- segment titles, track flags and roles, track removal, tags, attachments,
  chapters, external subtitles, extraction, timed-text conversion, and cleanup;
- lossless and common-format joins, lossless and exact trims, audio/video
  conversion, HDR policy, encoder probing, and one-generation enforcement;
- workflow migration, editor behavior, portable compilation, batch review,
  queue admission and recovery, durable History, verified commit, and explicit
  Trash-after-success outcomes;
- output security scopes, collision handling, cancellation, actionable errors,
  keyboard and VoiceOver contracts, window layout, Help, third-party notices,
  manual Sparkle policy, and privacy-safe diagnostics.

Generated and bounded integration fixtures exercise the media adapters. Private
beta media is never committed. This automated matrix is not evidence of a
downloaded DMG install, a prior-version updater replacement, physical Intel or
Apple Silicon acceptance, or real-file Jellyfin/Plex playback.
