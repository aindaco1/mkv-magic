# Support diagnostics and reviewed reports

## User flow

If **Verify & Run** cannot start, its final error stays visible even if History
could not be created. Choose **Help > Report a Problem…** after reproducing it.
This window does not depend on History, the queue store, or tool discovery.

- **Export Local Diagnostics…** saves bounded structured events locally. Nothing
  is submitted. This is separate from History's fuller privacy-safe support export.
- Select a failure to inspect the exact sanitized issue JSON. **Send Reviewed
  Report** submits it directly and shows confirmation in the app. There is no
  second browser review. **View GitHub Issue** is an optional action after success.
- Manual system-crash import is no longer part of the reporting UI. Existing
  interrupted-operation diagnostics remain available without finding system files.

Reports become public issues in `aindaco1/mkv-magic`. The isolated reporting service
makes the connection; the relay uses connection information for abuse prevention.
No GitHub login or credential is embedded in MKV Magic. Opening the window sends
nothing. An unconfirmed request requires manual retry with the same report ID.

## Local architecture and privacy

`DiagnosticEvent` is a closed vocabulary, not a string-message logger. It carries
session/attempt UUIDs, app/build and event-time OS/architecture, relative monotonic
elapsed milliseconds, action, stage, outcome, typed failure, known tool, and exit
status. It cannot carry filenames, arguments, source contents, credentials,
bookmarks, raw standard output/error, or exact wall timestamps.

`DiagnosticContext` uses task-local correlation. The shared command supervisor
records tool launches/results; History's shared stage seam records verification
and commit checkpoints in order. Verify & Run also records selection/destination
rejection, queue admission, and its final result. Import, subtitle preparation,
Add to Queue, automatic queue execution, and verified-edit execution use the same
journal. Existing History remains the richer job/plan/media-facts record. This
does not promise capture of every UI click or recovery of events from older builds.

`DiagnosticJournal` serializes writes to two files under the app's private
Application Support `Diagnostics` directory: at most 256 KiB each. The directory
is `0700`, files `0600`. Final directory/files reject symlinks; files must be
regular and singly linked. Rotation bounds storage rather than retaining every
event indefinitely. Exports keep at most 400 recent validated events and report
omitted, malformed, and current-process dropped-write counts. Missing storage is
shown explicitly. OSLog receives the same closed action/stage/failure vocabulary
under subsystem `com.dustwave.mkvmagic`, category `diagnostics`. No log failure
changes media processing or weakens verified commit/original preservation.

Support exports use schema `mkv-magic-privacy-safe-support-v4`, adding optional
diagnostics. An unfinished previous-session execution is **interrupted**, not
proof of a crash. Cancelled/successful attempts and active tool failures awaiting
recovery are not offered as crashes. Terminal completion wins over late callbacks.

## App/service/relay boundary

The main app has no network entitlement. A separately sandboxed, signed Universal
XPC helper accepts only the revalidated 4 KiB projection and posts to the fixed
`https://crash.dustwave.xyz/v1/mkv-magic/reports` endpoint. It has no selected-file
or bookmark access. Both peers enforce code-signing requirements: the packaged
helper's designated signature and the fixed app identifier signed by the helper's
own team. Ad-hoc helpers fail closed; real helper acceptance uses a Developer ID build.
Redirects, cookies, credentials, caching, arbitrary URLs, and automatic retries
are disabled. Responses are bounded to 4 KiB and must identify the same attempt.
The optional issue link is constructed locally for the fixed repository.
See [ADR 0003](adr/0003-reviewed-in-app-reporting.md).

The existing `/mkv-magic/review` browser route remains available to older test.19
clients; new clients no longer use it. Relay validation and aggregation are shared.

The shared implementation lives in ASCII VJ Remix's `crash-relay`; it is not an
application dependency. `/v1/mkv-magic/reports` accepts at most 4 KiB, same-origin
JSON, strict enums/keys/numeric bounds, and a fixed destination repository. It
shares intake, GitHub authentication, serialized aggregation, and receipt storage
with Podcast Visualizer. Swift/JavaScript use a golden fingerprint fixture to
prevent key-order differences from splitting equivalent reports. Native offsets
include build/OS; operation symptoms group across patch versions. Grouping is not
proof of a common root cause.

Each fingerprint retains up to 1,000 duplicate receipts, 100 pending IDs, and 32
version/platform buckets. An uncertain provider result remains retryable with
the same ID; success is shown only after a validated receipt. See the relay README
for uncertain-create reconciliation and repository permission/deployment steps.

## Acceptance status (2026-09-07)

Private test.19 / build `1788785951` is built and Developer ID-signed, with native
Intel and Apple Silicon code and tools. It is not notarized or publicly released.
The mounted DMG passed layout/signature/entitlement/runtime checks and the native
Apple Silicon fixture preserved its original. The reporting window rendered
correctly; native UI automation timed out after closing it, so the graphical
MP4/SRT smoke and native Intel same-file retry remain separate acceptance steps.
See [test checklist](testing/DIAGNOSTICS_TEST_CHECKLIST.md).

The complete local gate passed 836 tests (one optional private-media skip),
source validation, 89.42% non-UI line coverage, both address/thread sanitizers,
package checks, and disposable updater acceptance. Twelve focused diagnostics
tests cover pre-History failure visibility, private bounded storage, crash
projection, cross-client fingerprints, and explicit browser consent.
The attached test.18 export lacks the new events, so the exact user's pre-start
failure is not proven. Regression tests reproduce a queue-admission error before
History and verify that it is now recorded and displayed.

The shared relay is enabled after the user granted repository access. Source
`254000f` passed 28 hosted tests and deployed in run `34125603567` as Worker
`78f9ca5e-7f72-46df-9e70-4fc7b57a5a4a`. The live browser returned an accepted issue
link. Synthetic issue #1 verified creation, same-ID retry deduplication, three
matching reports in one issue, and new-ID reopening. It is closed. No private
user report was used. Existing ASCII/Podcast malformed intake remains rejected.
That test.19 browser implementation is superseded by the reviewed XPC exception
above; the main app still has no network entitlement or automatic uploader.

Issue #2 localized the user's failure to queue admission. The user then confirmed
an output-folder access denial on Intel for both Movies and Desktop. The new
shared destination chooser distinguishes a save-file grant from the folder grant
needed for queue bookmarks and verified temporary copies. It requests missing
folder authority explicitly and remembers bounded folder bookmarks. Errors at
source-bookmark and destination-bookmark preparation retain their concrete stage.

Run `swift test --filter Diagnostic`, the normal `scripts/ci/validate.sh`, and the
complete local gate. Relay validation: `npm --workspace crash-relay test` and
`npm --workspace crash-relay run deploy:dry-run` in ASCII VJ Remix. Separate local
test success, deployment, live synthetic receipts, packaged fixture execution,
and native Intel acceptance in all release claims.
