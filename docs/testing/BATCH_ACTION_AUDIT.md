# Batch actions: audit and implementation

## Approved scope

Folder-wide MP4-family video/text-subtitle remux, with all confidently matched
sidecars preselected and editable before queueing. Reuse discovery, matching,
language inference, output preferences, queue admission, and verified execution.
No sources are changed by discovery or review. Ambiguity must never be resolved
by file order, a filename prefix, or an assumed English language.

## Baseline findings

| Flow | Existing implementation | Gap |
|---|---|---|
| Folder intake | Recursive, sorted, filtered, symlink-safe discovery | Does not select/group the imported folder as a batch |
| MP4 + text subtitle | One reviewed pair; editable audio/subtitle languages; one zero-encode remux | Exactly two selected inputs; no folder pairing; one subtitle per video |
| Clean MKV and saved recipes | Compile independently and add ready jobs to the persistent queue | Mixed selections disable the Clean MKV shortcut; sidecar recipes refuse batches |
| Tags, subtitle cleanup, chapter suggestions | Shared batch review; independent verified outputs | Separate execution loops; only aggregate failure feedback; not durable queue jobs |
| Batch destinations | One chosen Settings folder is reused | Beside Source is not represented in the shared batch decision |
| Batch review | Ready / No changes / Blocked table | Cannot exclude an individual ready row or edit a pairing |
| Track metadata, extraction, trims | Single-file tools; recipe-based conversion can batch | General bulk track mapping/extraction/editing remains a larger feature |

The legacy `muxmp4srt.command` scans one hard-coded folder, matches the first
20 filename characters, appends every matching SRT, guesses English when unknown,
and trashes sources after the tool exits. It is a behavior reference only, not
an executable dependency or the safety standard for new batch behavior.

## Regression targets

- Folder import and multiple independent video/subtitle groups, including nested
  folders, duplicate titles, missing sidecars, orphan sidecars, and ambiguous cuts.
- Multiple languages and forced/SDH sidecars in one zero-encode output; each
  appended track must pass metadata, text/timing/style, and post-commit audits.
- Editable inferred languages; preserve known audio metadata; leave uncertain
  language/title words undetermined. Never turn a fuzzy suggestion into consent.
- Queue persistence, independent review-bound input hashes, stale sidecars,
  cancellation, retry identity, and partial failure without touching originals.
- Shared destinations honor chosen folder and Beside Source, reserve unique
  filenames, and retain the correct folder capabilities throughout each job.
- Mixed selections report ineligible/no-op rows; selecting a row is not consent
  to process it. Batch inclusion must be explicit and accessible.

Initial audit validation: 24 existing matcher, discovery, and common-flow tests
passed. This is source/test evidence, not a new packaged or Intel acceptance.

## Implemented in this pass

- Folder intake selects the imported files, including nested files, as a batch.
- A dedicated authoring coordinator uses shared matching and subtitle previews;
  it does not introduce a second execution engine. Strong unique matches include
  all sidecars; similar names and duplicate titles require explicit decisions.
- Edit each video to change its sidecar assignments, languages, names, and flags.
  No selected subtitles means an explicitly labeled video-only remux. Known
  source audio languages are retained; filename inference fills unknown values.
- One durable job per included video; all sidecars are appended in one MKVToolNix
  pass. Each payload is audited before and after commit. All source revisions
  and sidecar hashes are rechecked after queue restoration and before commit.
- Shared review now has Include, optional Edit Selected, and selectable full
  details. Existing cleanup/tag/chapter batches honor exclusions and per-source
  destinations. Clean MKV and subtitle cleanup accept mixed selections and
  explain ineligible rows.
- Preparation and queue admission reuse completed-item progress and cancellation.
  Cancelling admission retains already queued jobs and skips remaining items.

## Durable batch follow-up — 2026-09-07

- Tag removal, standalone SRT/ASS/SSA cleanup, and reviewed chapter suggestions
  now create independent durable jobs. Shared admission handles those operations
  and saved recipes, including exclusions, reserved filenames, retained folder
  access, cancellation, and actionable per-file admission failures.
- The queue reuses the existing verified tag, subtitle, and chapter executors.
  No second processing engine or background service was added. Pending jobs can
  run after relaunch; interrupted writes are not silently resumed.
- Private review state binds tags to their extracted document digest, subtitles
  to source and exact output digests plus restoration choices, and chapters to
  the exact desired document plus original chapter digest. Queue revisions,
  canonical structure, output extension, zero-encode impact, and unchanged plan
  are checked before execution. All three operations keep originals.
- Review Again refreshes tag/subtitle previews for explicit approval, retains
  source-file access through admission, and updates the same job without resetting
  Tries. Old chapter timestamps cannot be reapplied to a changed source: the user
  must analyze it again. No raw chapter document or subtitle contents are exported
  in support reports or portable recipes.
- Standalone subtitle cancellation now records Cancelled in History, matching
  the durable queue rather than incorrectly presenting an execution failure.

## Bulk editing, extraction, trimming, and background authoring — 2026-09-07

- **Edit Matching Tracks…** applies explicitly chosen name, language, and tri-state
  flag changes to all tracks of a chosen type. Each track retains its own unchosen
  fields. The shared inclusion review lists the actual changes per track; one
  clone and one existing property-edit pass handle each included MKV.
- **Extract Subtitles…** presents one includable output per embedded SRT/ASS/SSA
  track. Existing extraction audits preserve exact text, styles, timing, and
  format. Unsupported/image tracks and files are explained rather than converted.
- **Trim Beginnings / Ends…** takes the same removal amounts for every file,
  accepts seconds or timestamps, and resolves each range against that file's
  duration. Review discloses requested versus actual keyframe boundaries and
  retained chapters. This batch path is MKV Fast Trim only: it never opts into
  encoding. Use single-file Exact Trim for frame-accurate cuts.
- All three reuse the reviewed-edit intent, admission loop, durable scheduler,
  output preferences, and original-preserving executors. Metadata binds reviewed
  file-specific edits to the original track metadata hash; extraction binds the
  track UID/format and exact output hash; trim binds requested/adjusted ranges and
  the source chapter hash. All retain the reviewed file revision. Changed sources
  require a fresh review; old track identities/ranges are not reused on retry.
- Automatic queue draining and foreground import/preparation now have independent
  activity state. Eligible batch controls, file intake, and list removal remain
  usable during background work. Foreground preparation and immediate execution
  stay guarded. Queue status refreshes preserve selection and title drafts.
- Native options use one scrolling form and fixed action footer. Light and Dark
  minimum-size checks keep validation and Review/Cancel visible. Initial no-op
  settings cannot produce a job.

## Deliberate limits and remaining work

- Maximum 500 selected inputs, 32 sidecars per video, and 64 MB total subtitle
  preview data per batch. Discovery retains its separate 10,000-file bound.
  The new bulk media review also caps output rows at 1,024 and inspected-source
  facts plus subtitle preview bytes at 64 MB. Metadata changes
  support audio, subtitle, and video tracks; unsupported files are review rows.
- This plural-sidecar path accepts the existing common-container remux planner's
  supported MP4/M4V/MOV/WebM structures. It does not generalize to existing MKV
  subtitle additions or combine multiple sidecars with arbitrary cleanup or
  conversion recipes. Those paths retain single-sidecar behavior and reject
  unsupported plural plans instead of silently dropping tracks.
- New queue intents preserve old saved jobs. An older app may not understand
  newly created plural-sidecar/source-language/reviewed-edit jobs; do not downgrade
  with pending jobs from this candidate.
- Further scope: attachment/tag-document export batches, arbitrary elementary
  audio/video extraction, per-track inclusion inside a metadata edit, and batch
  frame-accurate encoding remain separate features. Existing single-file tools
  remain available; this pass does not silently broaden their contracts.
- A versioned test installer, native sandboxed folder-batch smoke, and physical
  Intel acceptance remain separate release work until explicitly recorded below.
- Rendering and generated media tests on this Apple Silicon host do not establish
  Intel hardware acceptance. No public release or installed-app update is implied.

## Validation — earlier remux pass (2026-09-07)

- Final `scripts/ci/validate.sh`: 863 tests, zero failures, one optional exact-user-
  media fixture skipped; Universal arm64/x86_64 release compilation passed.
- Coverage gate passed: 72.95% total source lines and 89.13% non-UI source lines.
  This run included 862 tests, before the additional test-only cancellation fixture.
- Full address- and thread-sanitizer suites: 863 tests each, zero failures, one
  optional fixture skip each. The first local-gate attempt exposed an ARC versus
  release-on-close conflict in the new test's unowned host window. A focused
  zombie diagnostic identified that fixture; explicit ARC ownership corrected it,
  and both complete sanitizer suites were rerun successfully.
- Packaging gate passed: bundle/signature/entitlement checks, updater replacement,
  checksums, and verified DMG. This uses the disposable test package, not a
  distributable candidate with the bundled media runtime.
- The local-gate components were all completed; normal validation was repeated
  after the final matching guard and test-harness correction. Native minimum-size
  review/editor checks and generated SRT/ASS remux/queue-restoration fixtures passed.
- The installed test.20 application is unchanged. A versioned candidate, native
  sandboxed folder-batch smoke, and physical Intel acceptance remain release work.

## Validation — durable batch follow-up (2026-09-07)

- Added 15 regressions covering reviewed queue persistence and safe malformed-
  document refusal, source/cleanup-contract changes, pause and cold-start drain,
  exact nested chapter output, tag preservation, failure/cancellation/retry,
  admission exclusions/collisions, and balanced security-scope lifetimes.
- `scripts/ci/validate.sh` passed: 878 tests, zero failures, one optional exact-
  user-media fixture skipped; Universal arm64/x86_64 compilation passed.
- The complete `scripts/ci/local-gate.sh` passed, including normal validation,
  coverage, both full sanitizer suites, and packaging. Address and thread
  sanitizers each passed 878 tests with zero failures and the same optional skip.
- Coverage: 73.77% total source lines; 89.18% non-UI source lines.
- Packaging passed bundle/signature/entitlement, updater replacement, checksum,
  and DMG verification using its disposable test package. No installed app update,
  versioned test installer, public release, or Intel hardware acceptance is implied.

## Validation — bulk media and background authoring (2026-09-07)

- Added 13 regressions: field/flag preservation and clearing, exact trim amount
  parsing/bounds, canonical queue contracts, three new operation types restored
  from disk, source-change refusal, no-op/mixed inputs, cancellation, compact
  Light/Dark options, real held queue execution with ongoing authoring/intake,
  and source revision checks both before preparation and immediately before commit.
- Complete `scripts/ci/local-gate.sh` passed on the final code: 891 tests, zero
  failures, one optional exact-user-media fixture skipped in the normal, coverage,
  Address Sanitizer, and Thread Sanitizer suites. Universal compilation passed.
- Coverage: 73.98% total source lines and 89.42% non-UI source lines.
- Disposable package/signature/entitlement, updater replacement, checksum, and
  mounted-DMG gates passed. These checks do not establish Intel hardware or
  installed-app acceptance; a private candidate is recorded separately below.

## Private candidate — 0.3.0-test.21 (2026-09-07)

- Built Universal version `0.3.0-test.21`, build `1788818173`, from the local
  working tree. The bundle explicitly records that this is an uncommitted private
  candidate, not an immutable tagged release.
- The application and DMG are Developer ID signed. Mounted bundle, entitlement,
  signature, architecture, and DMG layout checks passed. Native Apple Silicon
  bundled-tool fixture smoke passed with the original preserved. No Intel-only
  helper was found in the Universal Mach-O inventory.
- Installer: `MKV-Magic-0.3.0-test.21-universal.dmg`, 96,625,658 bytes.
  SHA-256: `1bef2af2d648e21299490779c1e29024c1ff11ca9b247100a7649d01f0ade06b`.
- Generated-media test kit: `MKV-Magic-0.3.0-test.21-Intel-Test-Kit.zip`.
  SHA-256: `817a2f1b774afef9c77bdc928b97c0f0acb0efcc8f2f7cc462468cab5d581790`.
  Includes two MP4/SRT pairs, two MKV samples, checksums, and manual
  remux, metadata, extraction, trim, queue-restoration, and appearance checks.
  The archive was extracted and its contents verified before handoff.
- Desktop handoff copies match the verified artifacts byte for byte. This build
  is not notarized, installed, publicly released, or accepted on physical Intel
  hardware. Native sandboxed folder-batch and real-library acceptance remain
  separate from the mounted bundled-tool smoke and automated generated-media tests.
