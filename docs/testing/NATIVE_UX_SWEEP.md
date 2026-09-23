# Native UX regression sweep

Scope: the macOS app's existing intake, editing, review, output, and recovery
flows. This is a usability/interaction pass, not a visual redesign or a change
to media-processing policy. User sources, language inference, verification,
queue serialization, and one-generation rules remain unchanged.

## Confirmed defects and shared fixes

`NativeFlowUXTests` first reproduced six failing groups (25 assertions):

| Surface | Reproduction | Fix and regression |
| --- | --- | --- |
| Video plus external subtitle review | Long filenames and fixed value columns forced the panel past its stated minimum width. | Flexible value columns with natural-width labels; compact field heights; minimum-width/height checks in both appearances. |
| Subtitle and attachment extraction | The fixed selector width forced each small picker wider than its advertised minimum. | Same labeled-grid helper for embedded cleanup, text extraction, TX3G conversion, and attachment extraction. |
| External subtitle options | Invalid audio/subtitle languages left Review enabled; typing did not refresh validation. | Text and combo selection events use the same options builder as acceptance. Messages identify the affected field; correction immediately restores Review. Active editing reaches the accepted options. |
| Chapter suggestion settings | Analyze stayed enabled for invalid, negative, nonfinite, and out-of-range spacing. | One validated options builder controls both availability and submission. Correction clears stale feedback; at least one detector remains required. |
| Track removal / Clean MKV | Long track titles expanded a 540-point panel beyond 2,300 points. Rows did not use a top-origin document. Empty and all-track selections left Preview enabled. | Width-bounded, top-origin scrolling choices and readiness from the existing removal validator. At least one playable track must remain. |
| Attachment removal | Long names expanded a 560-point panel beyond 1,300 points. An empty selection left Review enabled. | The same scrolling-choices helper and existing stable-UID removal validator. |
| Clean MKV availability | The main-window shortcut duplicated an older subtitle-only cleaner, so it was disabled when an MKV had no deterministic subtitle-removal suggestion even if its title, tags, attachments, role flags, or filename could be cleaned. | The shortcut now compiles the existing complete Clean MKV preset for one file or a multi-file selection. Any inspected MKV can be reviewed; no-op operations are omitted, and metadata-only cleanup remains zero-encode. |

Direct interaction then reproduced a seventh group: cancelling Chapter Studio
reset the main list to its first file. The common table refresh now preserves
selected asset identities, including multi-selection and shifted rows, and
ignores temporary selection notifications during reload. Real selection
changes still invalidate the old plan. Additional regressions protect typed
segment titles and reviewed plans from unrelated status refreshes while
ensuring they never carry over to another selected source.

`NativeFormLayout` shares only stable layout behavior: labeled grids, a
full-width status row above actions, and bounded checkbox lists. It does not
own domain validation or execution. Long names retain complete accessible
titles and hover text. The action footer no longer makes explanatory text
compete horizontally with Cancel and Review.

Additional tests cover overlong subtitle-name feedback without obscuring
actions, correction while editing, and cancellation completing exactly once
without accepting options. Both removal flows test 30 long-named rows and
selection transitions; selecting all tracks remains blocked.

## Flow coverage ledger

The automated pass includes the existing `AppPolicyTests`,
`CommonUserFlowRegressionTests`, and real-tool subsystem tests, plus the new
`NativeFlowUXTests`. Existing tests are retained rather than recreated in a
second parallel flow implementation.

| Flow family | Checks retained or strengthened in this sweep |
| --- | --- |
| Main window, sidebar, file intake | Native minimum layout, reachable destinations, multi-selection, identity-preserving refresh, draft/plan preservation on unrelated refreshes, Delete removes intake state only, MP4-plus-sidecar action recognition. |
| Segment and track metadata | No-op versus changed values, active field-editor text, combo selections, flags, correction, preview handoff; track-editor minimum layout. |
| Clean MKV and manual track removal | Complete shared Clean MKV recipe for subtitle and non-subtitle cleanup, single and multi-selection availability, metadata-only zero-encode planning, shared removal validation, no-selection/all-track recovery, long lists, safe stable-UID callback. |
| External subtitle remux | Editable inferred defaults, native input events, invalid-to-valid recovery, long names, cancel, reviewed options. |
| Subtitle cleanup and extraction | Shared SRT/ASS review, review action availability, embedded selection, TX3G conversion, minimum-size extraction pickers. |
| Tags and attachments | Explicit tag actions and batch review, attachment extraction/removal selection, long lists, output safety. |
| Chapter editing and suggestions | Inspector label geometry, nested actions, single/batch review, detector availability, spacing correction, thumbnails. |
| Join and track mapping | Source order, lossless/common-format readiness, approval invalidation, read-only review document width/resizing/selection, existing mapping and chapter policy tests. |
| Trim and video/audio conversion | Native minimum layouts, numeric input, preview invalidation, approved formats, reviewed one-generation execution. |
| Saved workflows and batch output | Name validation, selected-media prerequisites, reviewed compilation, batch destination and per-item results. |
| Queue, retry, and History | Native controls/details, authoring while automatic work runs, mutation failure visibility, retry identity/attempts, persistence and privacy-safe export. |
| Output progress and cancellation | Measured stages/items, commit boundary, cancellation/source preservation, collision-safe output contracts. |
| Settings, Help, and notices | Minimum-size settings; Help/menu navigation; readable, selectable, correctly sized Help/license documents. |

Read-only review geometry checks now accompany the existing text assertions
for Join, Common Format, Help, and licenses. Chapter Studio also checks the
actual inspector label widths after minimum-size layout. These checks did not
reproduce additional defects, so those production views were not rewritten.

## Running and interpreting the evidence

```sh
swift test --filter 'NativeFlowUXTests|AppPolicyTests|CommonUserFlowRegressionTests'
./scripts/ci/validate.sh
```

Set `MKV_MAGIC_TOOL_ROOT` to the verified local runtime to include bundled-tool
fixtures. The complete local gate additionally runs coverage, sanitizers, and
package/security contracts. Optional `MKV_MAGIC_UX_CAPTURE_DIRECTORY` saves
native test-window renders into an existing absolute temporary directory.

Native test-window renders and direct interaction with a local candidate are
separate evidence. This sweep is not a claim of exhaustive screen-reader
navigation, every display/text-size configuration, physical Intel acceptance,
or a published/notarized installer. Long-form real-media playback acceptance
remains separate from bounded integration fixtures.

The direct candidate check used generated two-second H.264/AAC media and a
subtitle: invalid language disabled Review, correction restored it, active
name/language edits reached the plan, and Verify & Run produced an MKV with
the reviewed metadata and both chapters. Independent source checksums were
unchanged. Native removal and chapter-spacing recovery were also exercised.

The final `0.3.0-test.11` candidate (build `1788509053`) was checked directly:
selecting the fourth source, typing a segment-title draft, opening Chapter
Studio, and cancelling retained both the source and the draft. Previewing the
draft then cancelling Chapter Studio again also retained the reviewed plan and
enabled Verify & Run. This draft was not executed.

## Validation record — 2026-09-04

- Ten new native UX regression tests; existing flow tests were extended rather
  than duplicated.
- The 804-test suite completed ordinary, coverage, AddressSanitizer, and
  ThreadSanitizer runs with zero failures and one optional private-media fixture
  skipped in each run.
- The complete local gate passed, including source validation and the
  package/security contracts.
- The Universal test app is Developer ID signed. The exact mounted DMG passed
  app-bundle checks and native Apple Silicon release verification, including all
  five bundled tools and the original-preserving extraction fixture.
- The Desktop copy's SHA-256 matches the verified artifact:
  `5a0a459169b3edbb55e07a7f88665ebd1eb77b97d3367bdeb2d97e800cda5210`.
- This is a local, unnotarized test candidate. It was not published or installed
  over the existing app, and physical Intel acceptance remains outstanding.

## Follow-up Clean MKV validation — 2026-09-04

- The main-window shortcut now invokes the complete shared Clean MKV workflow;
  the obsolete subtitle-only presentation and execution branch were removed.
- A native `0.3.0-test.12` run imported a folder containing an MKV with English
  audio, a segment title, and global/track tags, but no subtitle track. Clean MKV
  remained enabled and its review marked subtitle removal already satisfied
  while applying title, tag, and filename cleanup.
- Verify & Run produced a zero-encode output with the same audio track and
  duration, no segment title, and zero global/track tags. The source retained
  its original title and tags.
- The 806-test ordinary, coverage, AddressSanitizer, and ThreadSanitizer runs
  completed with zero failures and one optional private-media fixture skipped.
  Source/security and package gates also passed.
- The Developer ID-signed Universal candidate is build `1788582772`. Its mounted
  DMG passed native Apple Silicon release verification and bundled-fixture
  source-preservation checks. The Desktop copy's SHA-256 is
  `4f0f6eac58687f47b8fe36e0671dbfb45cc46321449070c4af67197463d503a1`.
  It remains unnotarized and unpublished; physical Intel acceptance is still
  separate.
