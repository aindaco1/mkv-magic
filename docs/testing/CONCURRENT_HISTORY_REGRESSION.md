# Concurrent cleanup History regression

The 0.3.0-test.12 support report showed two queued lightweight jobs failing
with `historyWriteFailed`, one during running and one during committing. History
also had an incomplete lifecycle. This was separate from subtitle eligibility.

`AppModel.beginHistory` created a fresh `JSONJobHistoryStore` actor for each job.
Each actor serialized its own operations, but independent actors could read the
same file and overwrite another job's newly created record or transition.
Atomic file replacement prevented partial JSON, not lost read/modify/write
updates. Existing integration tests injected a singleton store and therefore
did not match production factory behavior.

`AppModel` now lazily owns one History recorder, just as it already owns one
queue recorder. All jobs and History reads use that recorder. No extra cache of
records, separate Clean MKV execution path, weakened failure handling, or
reduction in media-processing concurrency is introduced.

`AppHistoryConcurrencyTests` uses a factory that returns a fresh actor on every
invocation, matching the production factory, and asserts it is invoked only
once per model. It covers:

- Four simultaneous subtitle cleanups interleaved with History reads, full
  eight-state lifecycles, distinct outputs, and unchanged source bytes.
- Four queued real-tool Clean MKV jobs with titles/tags but no subtitles,
  parallel lightweight admission, one successful attempt each, complete
  History, removed metadata, zero encodes, and unchanged source hashes.

Both regressions failed before the fix. The real-tool queue reproduced lost
records and failed jobs; the parallel cleanup test threw `recordNotFound`.
Both passed after sharing the recorder. The privacy-safe report does not expose
the underlying store exception, so reproduction identifies a matching confirmed
defect rather than claiming access to the original raw exception.

Existing failed jobs require Review Again. Lost historical events are not
invented or reconstructed. This does not claim multi-process file locking or
physical Intel acceptance.

## Candidate validation

- The complete local gate passed: 808 tests, zero failures, and one optional
  private-media fixture skipped in each normal, coverage, AddressSanitizer,
  and ThreadSanitizer run. Source/security, Universal build, package, and
  disposable updater-replacement checks passed.
- `0.3.0-test.13`, build `1788585275`, is a Developer ID signed Universal app.
  Its mounted DMG passed layout, runtime-manifest, architecture, and native
  Apple Silicon release verification: five tools and an original-preserving
  bundled fixture, with the main view successfully constructed.
- DMG size: 92,821,439 bytes. SHA-256:
  `7bd60c3e3dd660b9009b18cf68ba6e9fc452fb15f67b68769dd163dc2a12b0ad`.
- This is a local, unnotarized, unpublished test candidate. The existing app
  installation was not replaced. Physical Intel retry and the user's original
  files remain acceptance work, not claims inferred from the local fixture.
