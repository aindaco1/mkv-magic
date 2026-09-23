# Restored queue access regression

## Contract and cause

A reviewed, unchanged queued job must be able to read its inputs and create a
verified output after the app quits and relaunches, without another file picker.
Cancelled work must release its access and leave no committed output. A stale
bookmark, changed source, occupied destination, or unreviewed plan still fails
closed; this fix does not add automatic retries.

In test.16, a saved synthetic MP4 + Spanish SRT job passed parent-side revision
checks, then FFprobe received `Operation not permitted`. The queue resolver
temporarily starts and stops access while checking revisions and output
collisions. A later `.standardizedFileURL` mapping recreated the resolved URLs
without their attached security-scope capability on this path. Path equality
and successful file metadata checks did not prove child-process read access.

Test.17 preserves those already-validated URL values through the existing
coordinator's balanced start/defer-stop lifetime. No entitlements, helper
architecture, bookmark schema, tool arguments, verifier, or retry policy change.

## Automated regression

`MediaQueueAdmissionCoordinatorTests.testAdmissionPreservesOriginalScopedURLsWhileDeduplicatingAccesses`
checks that admission de-duplicates access without rewriting the URL values.
It fails with the former normalization and passes with the fix. It uses a
distinct relative URL representation as observable stand-in data: ordinary
unsandboxed XCTest cannot establish real security-extension inheritance.
Existing admission tests cover unchanged inputs, destination collisions,
rechecking the admission gap, Pause, executor outcomes, and cancellation.

Run:

```sh
swift test --disable-automatic-resolution --filter MediaQueueAdmissionCoordinatorTests
```

## Signed diagnostic evidence — September 5, 2026

A disposable Developer ID-signed, hardened, sandboxed diagnostic app used the
production main-app entitlements and the unchanged signed bundled tools. It
read only the previously created synthetic queue entry; the actual queue,
History, installed application, and private media were not modified.

Separate process launches established:

- The original saved bookmark resolves and FFprobe reads it successfully.
- The production admission resolver followed by the old normalization returns
  `false` from all three access starts; FFprobe exits 1 with a permission denial.
- The same resolver, inputs, destination, runner, tool, signature, and optimized
  build with the original URLs retained returns `true` for all three access
  starts; FFprobe exits 0 with complete inspection JSON.
- Direct and folder-created bookmarks, a start/stop cycle by itself, ordinary
  asynchronous subprocess execution, and a GUI cold restore by themselves pass.
  Those negative controls ruled out a need for broader entitlements or a new
  subprocess architecture.

The follow-up signed diagnostic linked the production coordinator, compiler,
inspector, runner, remux executor, and verified-output pipeline. It copied the
synthetic job into an isolated queue and used a new unique output name, leaving
the real queue and History untouched. In separate launches:

- Full restored MP4 + SRT remux succeeded, Tries 1, three verified tracks, zero
  encodes, and unchanged SHA-256 digests for both originals. FFprobe read the
  source before the parent read its contents, avoiding a warm-access false pass.
- Cancellation at verification ended Cancelled with Tries 1 and no committed
  output. The original inputs remained unchanged.
- After both outcomes, an unscoped FFprobe call was denied again. The explicit
  access was released; success did not rely on a leaked permission.
- A separate destination inside the diagnostic container also passed, so the
  source read did not depend on a broad grant to its containing output folder.
- Two simultaneous restored jobs sharing the same input bookmarks both
  succeeded with distinct outputs, Tries 1, three tracks, zero encodes, unchanged
  originals, and no retained source access after the batch.

Test.17 build `1788645545` passed signed DMG/native launch verification on arm64,
all five bundled-tool version checks, and the bundled preservation fixture.
The candidate is Developer ID-signed, hardened, sandboxed, unnotarized, and
unpublished. After a host restart, the Desktop DMG passed the same native
launch/tool/fixture verification again. Its extracted, signature-verified app
then passed the actual GUI cold-launch queue procedure on Apple Silicon:

- Selected a generated four-second MP4 and clean Spanish SRT through the native
  picker, reviewed English audio/Spanish subtitles and zero encodes, and added
  the job while automatic starts were paused. Queue showed Waiting, Tries 0.
- Quit completely, confirmed the process had exited, and launched the same
  candidate again. No files or output folder were reselected.
- Resumed once. Queue showed Succeeded, Tries 1, no active or pending jobs, and
  “Verified output completed successfully.” Before/after screenshots were
  captured and the final rendered state was inspected.
- Read-only inspection of the persisted History record confirmed every stage
  from queued through inspecting, planned, ready, running, verifying, committing,
  and succeeded. Both source SHA-256 checks passed. Independent output inspection
  found H.264 video, AAC English audio, and SubRip Spanish subtitles.

This GUI run used the existing source-folder destination policy, not a newly
selected separate destination. The separate-destination, concurrent-job, and
cancellation proofs above are signed diagnostic runs. After the success capture,
UI automation timed out while closing Queue and opening History, so a rendered
History-window acceptance is not claimed. Clean-account installation, physical
Intel execution, updater replacement, and real-file playback remain separate.

The Desktop copy is byte-identical to the verified DMG, 92,823,891 bytes, SHA-256:
`0d39fdf5c0348062b1c5fbda31103aa9e5e368101bdc4cd809c5d63208be63e0`.

Normal source validation ran 824 tests with one optional private-media skip and
no failures. The first coverage run exposed five nil-value assertions in one
existing conversion-review test: a fixed 100 ms delay elapsed before its
asynchronous callback under load. Its focused coverage rerun passed after using
the suite's existing bounded condition-wait helper. A later instrumented run
exposed the same assumption in the advanced AV1 and audio-format review tests;
those two confirmed cases now use the same helper. No conversion behavior or
assertions changed. Earlier failed/interrupted runs are not counted as green
gates. The host restart cleared their temporary logs; the observations above
record those failures, but raw logs are no longer available. The final full
local gate was restarted from the beginning with its log in persistent local
validation storage.

The post-restart normal, coverage, AddressSanitizer, and ThreadSanitizer runs
each completed 824 tests with one optional private-media skip and zero failures.
Non-UI source line coverage remained 89.34% (24,322 / 27,224 lines).
The complete local gate finished successfully, including source/security checks,
Universal packaging, artifact checksums, and the disposable-key Sparkle update
replacement/rejection exercise. That synthetic updater exercise is not proof
of an installed prior-version update to the final test.17 candidate.

## Follow-up review of current samples — September 5, 2026

The two older failed GUI jobs referenced temporary inputs that no longer
resolve. They are stale fixture records, not new test.17 failures. The current
generated MP4/SRT pair and its successful MKV output remain available in local
validation storage. Both source SHA-256 checks still pass. Independent packet
hash comparison found identical video and audio payloads between that MP4 and
its existing output; inspection confirmed English audio and Spanish subtitles.
The comparison covered 96 video packets and 189 audio packets, with no missing
packet hashes.
These are fresh checks of the existing output, not a newly executed GUI retry.

The focused queue/core/store/admission/native-controller/real-tool run passed
31 tests with no skips or failures. The existing minimum-size queue controller
test now also clicks Review Again and requires the exact selected failed job
to reach the review callback, no queue transition, preserved selection, and
Tries remaining 1 until a new attempt actually starts. Its focused rerun passed.
Existing core/store tests cover fresh-plan approval and the second started
attempt persisting Tries 2.
After the assertion was added, `./scripts/ci/validate.sh` passed all source
checks and 824 tests with one optional private-media skip and zero failures.
The complete sanitizer/package gate above predates this test-only addition;
it was not repeated, and the production binary did not change.

Native UI automation still times out after a fresh connection reset. A process
sample found the candidate's main thread waiting normally in the AppKit event
loop, not blocked in media processing. The user also confirmed that the app was
visible and responsive while those automation calls failed. A new rendered
Review Again/History acceptance is therefore still outstanding; controller tests must not be
presented as that GUI proof. No production app code, installed application,
existing queue record, bookmark, or sandbox permission changed in this follow-up.

## Intel test candidate — 0.3.0-test.18

Build `1788652591` is a fresh private Universal candidate from the current local
working tree, not a signed-tag/hosted release. It carries the same production
fixes as test.17 and the follow-up Review Again regression coverage. No installed
application was replaced and no release, tag, or update feed was published.

The complete local gate was rerun after the test addition. Normal, coverage,
AddressSanitizer, and ThreadSanitizer each passed 824 tests with one optional
private-media skip and zero failures. Non-UI line coverage was 89.34%. Source,
Universal package, checksum, and disposable-key updater replacement/rejection
checks passed. The completed 0.3.0 compatibility/limitations notes also passed
the release-notes validator.

The app and DMG are Developer ID-signed; the app remains hardened and sandboxed.
Notarization was not performed. The packaged DMG and its byte-identical Desktop
copy passed read-only mounted-image validation, the full Universal Mach-O
inventory, all five bundled-tool checks, the original-preserving fixture, and
native arm64 release verification. No translated Intel execution was attempted.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `MKV-Magic-0.3.0-test.18-universal.dmg` | 92,834,231 | `fb2dd8c07935bbf9e98caec1e843e6530bce3f9a01dae7be8d8b83350e0fe6ff` |
| `MKV-Magic-0.3.0-test.18-Intel-Test-Kit.zip` | 15,166 | `28269a053b14dd8772c36827c8a305ce55741c1e2e5bb498607deead6c38d39b` |

The kit contains two independently named copies of the generated MP4/SRT pair,
input SHA-256 checksums, and the [Intel checklist](INTEL_TEST_CHECKLIST.md).
Archive integrity and all four sample checksums passed after extraction. Neither
kit availability nor static x86_64 slices constitute physical Intel acceptance.
The exact final notarized/hosted artifact still needs its own clean-account,
hardware, updater, and playback acceptance before public release.

## Repeatable signed-app acceptance procedure

Use generated media outside the app container, never a private library fixture.
Use an MP4 containing video and audio plus two short, clean SRT cues. Give each
input and output a distinct name; retain source SHA-256 digests. Include spaces
and a language token in filenames. Use the canonical signed Universal candidate
and its bundled tools; do not run translated Intel tools on Apple Silicon.

1. Pause automatic starts. Select the fixture through the native file picker.
   Review a zero-encode MP4 + SRT remux and its language choices. Add it to the
   queue using a selected output directory; confirm Waiting and Tries 0.
2. Quit the application completely, then launch the candidate again. Do not
   reselect any input or output folder before resuming the queue.
3. Resume once. Require inspection, remux, subtitle/packet verification, commit,
   and reopen to succeed. Require Tries 1, no pending job, three expected tracks,
   reviewed languages, unchanged source digests, and a complete History record.
4. Repeat with a different output directory and with multiple queued jobs. A
   same-session result does not replace the preceding cold-launch check.
5. Cancel another fixture job before commit. Require Cancelled, no committed
   output, unchanged inputs, and no retained explicit access after completion.
   Then cold-launch a new reviewed job to check recovery.
6. Modify a separate fixture after review, and separately occupy its intended
   output. Require review/collision rejection; never replace the source or the
   existing output. Existing automated tests cover these fail-closed branches.

Record exact candidate version/build, host architecture, signing state, queue
states/attempt counts, source preservation, output checks, and any sandbox
denial. Keep bookmarks, private queue documents, raw paths, and private logs out
of the repository and distributable evidence. Physical Intel and clean-account
Apple Silicon acceptance remain separate release gates.
