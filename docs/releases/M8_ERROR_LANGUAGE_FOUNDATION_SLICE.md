# M8 error-language foundation slice

This slice establishes one deterministic, bounded error-language contract for
the app's central workflow, Queue, and History surfaces. It is not a claim that
every current or future error has completed manual wording review.

## Message contract

Every migrated message now contains, in order:

1. the action that could not complete;
2. what remains unchanged or which last-confirmed state remains visible;
3. a concrete retry or alternate-destination step; and
4. a single-line **Details** suffix capped at 240 user-perceived characters.

The shared formatter collapses newlines, tabs, and other whitespace while it
reads the detail and stops once the cap is reached. Empty details receive a
plain fallback. It does not invoke a shell, network service, LLM, log uploader,
or persistence layer, and it does not mutate the underlying error.

## Migrated surfaces

- saved-workflow library save, portable import, and portable export;
- production Queue mutations while retaining the last confirmed snapshot;
- privacy-safe History report export;
- main-window loading of History, Queue, and saved workflows.

The messages distinguish display failure from media-work failure. They do not
claim that a save, import, export, or queue mutation succeeded when its adapter
threw.

## Regression evidence

- A formatter regression supplies multiline, tabbed, oversized input and proves
  the failure, recovery, single-line, 240-character, and ellipsis contracts.
- A real Queue-window mutation regression throws from the persistence adapter
  and proves that the UI keeps and names the last confirmed snapshot, a retry
  action, and bounded technical detail.
- The complete local gate passes normal, coverage, AddressSanitizer, and
  ThreadSanitizer modes with 504 tests, 33 intentional source-only real-tool
  skips, and zero failures in each mode. It also passes the Universal app build
  and isolated nested-signature, disposable-update, SBOM, checksum, notices,
  build-metadata, update-feed, archive, and independently verified DMG package
  gate.

## Still required for M8 acceptance

- Review every remaining status, warning, validation, cancellation, tool,
  chapter, trim, join, subtitle, and encoding-test message in context.
- Observe VoiceOver announcements and focus return after real failures.
- Test representative disk-full, permission, stale-bookmark, corrupt-store,
  malformed-media, cancellation, and bundled-tool failures using disposable
  fixtures and the private beta corpus.
- Verify localization-safe layout and comprehension with the user. No
  physical-hardware, private-library, signed/notarized-build, or public-release
  acceptance is claimed here.
