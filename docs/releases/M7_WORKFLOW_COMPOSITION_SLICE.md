# M7 workflow-composition slice

This slice turns the fixed workflow template into a small composable builder.
It adds native Add Step and Remove Step controls for the safe portable action
catalog already supported by compilation and execution. It does not change the
portable file schema, add workflow actions, or alter media execution.

## User contract

- Add Step lists the current granular conditional cards in a stable order:
  - If present: Remove non-English subtitles;
  - If redundant: Remove English SDH subtitles;
  - If present: Remove segment title.
- A card already in the recipe remains visible in the menu but is disabled, so
  the user can understand the catalog without accidentally creating duplicates.
- The legacy combined English Library Cleanup action remains importable and
  executable for compatibility, but it is not offered for new authoring.
- Selecting a card makes Remove Step and the valid movement direction available.
  Removing the last card is allowed while editing; Save & Preview continues to
  require at least one enabled card.
- A newly added card is enabled, appended to the recipe, selected, and marked as
  an unsaved change. Removal selects the nearest remaining card.

## Architecture and safety contract

1. One `WorkflowEditorPolicy.actionCatalog` drives both menu construction and
   duplicate prevention. View code does not maintain a second action list.
2. Policy mutations reject compatibility-only additions, duplicate actions, and
   invalid removal indexes without changing the workflow.
3. Card identity and order continue to use the existing portable intent model;
   no media path, track ID, track UID, subtitle text, or security bookmark is
   introduced.
4. Compilation, plan review, verified-output execution, and source-preservation
   contracts are unchanged.
5. This slice launches no media tool and adds no file, shell, network, LLM, or
   execution behavior.

## Acceptance evidence

- Policy regression coverage proves the catalog order, compatibility-action
  exclusion, duplicate rejection, bounded removal, and empty-recipe behavior.
- AppKit regression coverage drives the actual Add Step menu action, verifies
  that the card appears and becomes unavailable as a duplicate, then drives
  Remove Step and verifies that the card becomes available again.
- The builder was rendered and visually inspected at its supported minimum size.
  All three cards and Add Step, Remove Step, Move Up, Move Down, Import, Export,
  Save, and Save & Preview fit without clipping.

### 2026-08-23 gate results

- The normal source gate passed all 425 tests with 30 intentional no-runtime
  skips, source validation, and the Universal application build.
- The exact pinned Universal runtime passed all 425 tests with zero skips.
- AddressSanitizer and ThreadSanitizer each passed all 425 tests. Coverage also
  passed.
- The package gate passed the Universal app, both architecture-specific media
  tool trees, nested signatures, Sparkle components, update feed, SBOM,
  corresponding source, third-party notices, checksums, ZIP, and mounted and
  verified DMG.
- This is local engineering and ad-hoc signing evidence, not public Developer ID
  notarization, publication, downloaded-artifact verification, or private-library
  playback acceptance.

## Still pending

- Subtitle text-cleanup workflow cards and their interactive review inputs. The
  external subtitle input card shipped in the follow-up
  `M7_EXTERNAL_SUBTITLE_WORKFLOW_SLICE.md`.
- Broader conditional cards, filename cleanup, and future schema changes beyond
  the external-input v2 migration.
- Durable queue pause, resume, retry, cancel, reorder, and concurrency behavior.
- VoiceOver, keyboard-only, physical Intel, and private-library beta acceptance.
