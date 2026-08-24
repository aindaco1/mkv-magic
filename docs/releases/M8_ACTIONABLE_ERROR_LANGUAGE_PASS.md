# M8 actionable error-language pass

This follow-on slice applies the shared bounded error presentation to every
remaining AppKit catch that previously displayed `error.localizedDescription`
directly. It covers source-level wording and automated UI behavior; it does not
claim observed VoiceOver, localization, or private-corpus failure acceptance.

## Delivered contract

- Media discovery and inspection name the failed file action, skip or preserve
  it safely, and tell the user how to retry.
- Trim, lossless/common-format Join, workflow planning, Chapter Studio,
  subtitle cleanup/muxing, track editing/removal, Encoding Test, and Queue
  review errors distinguish a failed review from a failed media operation.
- Chapter mutations consistently keep and name the last valid in-memory draft.
- Stale join and trim reviews explicitly say that no output was created and
  require a fresh review.
- Failed Queue admission leaves the job or queue saved rather than implying it
  disappeared.
- Every migrated technical detail is whitespace-normalized and capped at 240
  Swift `Character` values by `UserFacingErrorPresentation`.

Plain validation guidance that does not expose a caught technical error remains
direct and contextual. The command-line bundled-tool verification mode writes
to standard error before AppKit launches and is outside this UI contract.

## Regression protection

- The existing formatter regression proves action, recovery, single-line,
  truncation, and fallback behavior.
- The Track Removal window now exercises a real invalid selection and proves
  the action, unchanged state, recovery, and bounded Details text are visible.
- The Exact Trim window regression now proves a failed asynchronous review
  reports that no output was created and keeps the controls available.
- `scripts/ci/check-user-facing-errors.sh` fails validation if any AppKit source
  bypasses the formatter with a direct `error.localizedDescription` display.
- The complete local gate passes normal, coverage, AddressSanitizer, and
  ThreadSanitizer modes with 504 tests, 33 intentional source-only real-tool
  skips, and zero failures in each mode. The Universal build and isolated
  package gate also pass, including nested signature, disposable update,
  checksums, notices, SBOM, archive, and independently verified DMG checks.

## Still required for M8 acceptance

- Trigger representative permission, disk-full, stale-bookmark, malformed-file,
  bundled-tool, cancellation, and committed-output audit failures with
  disposable fixtures and the private beta corpus.
- Observe VoiceOver announcement order and focus return for each major failure
  family in the packaged app.
- Review layout under larger display scaling, localization expansion, light and
  dark appearances, Increase Contrast, and Reduce Transparency.
- Repeat the agreed personal workflows on the M1 reference and a physical Intel
  Mac. No signed/notarized beta or public-release acceptance is claimed here.
