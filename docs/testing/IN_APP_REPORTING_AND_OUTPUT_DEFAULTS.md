# In-app reporting and app-wide output defaults

Private test.20 candidate. This changes the signed bundle by adding a Universal
reporting XPC service. The main-app and media-tool entitlements are unchanged.
Physical Intel acceptance of issue #2 is still required.

1. Choose an output folder in Settings. Repeat MP4 + SRT Verify & Run and Add to
   Queue. Expect no save dialog, a durable queue row, and a verified new MKV.
2. With Beside Source, allow the indicated folder once if macOS requests access.
   Repeat using another source in that folder and after relaunch. No recurring
   save/folder prompt should appear. Canceling authorization starts nothing.
3. Export chapters, tags, tracks, attachments, workflows, History support reports,
   and local diagnostics. The chosen default folder applies to all; automatic
   filenames must not replace any existing file. Source-less exports in
   Beside Source mode remember their own export folder without changing the media
   output setting. Ask Every Time remains an explicit opt-in to save dialogs.
4. Open Help > Report a Problem. Opening and selecting reports must send nothing.
   No browser continuation or system-crash import control should be present.
   Click Send Reviewed Report to submit only the displayed sanitized metadata.
   Success identifies a GitHub issue in app; View GitHub Issue is optional.
5. An offline/uncertain submission must remain unconfirmed, never claim success,
   and permit manual retry using the same ID. Changing selection/double-clicking
   must not initiate concurrent reports. Local diagnostic export remains usable.
6. Validate the packaged XPC peer and entitlement boundaries using native release
   verification. Its availability probe intentionally sends invalid empty data,
   which the service rejects before making any HTTP request.

Focused regressions: DiagnosticUserFlowTests, OutputSavePanelTests,
ReportSubmissionTests, SecurityScopedBookmarkCodecTests. Run the complete local
gate and signed native mounted-DMG acceptance; distinguish those checks from the
same-file Intel retry. Existing relay grouping is reused with no deployment change.

## Local test.20 acceptance (2026-09-07)

- Private Universal candidate: `0.3.0-test.20`, build `1788800050`. Developer ID
  signed app; not notarized, published, installed, or accepted on physical Intel.
- `MKV-Magic-0.3.0-test.20-universal.dmg`, 96,844,515 bytes. SHA-256:
  `0a78f3ab96f5a09995588fce53908276f4da162050036a55e650b755d28da711`.
- Mounted read-only DMG: native arm64 launch, five bundled tools, reporting XPC
  availability, and media fixture passed. The source remained unchanged.
- Signed, sandboxed reporting acceptance used the actual reporting client and
  packaged helper to retry the existing synthetic canary. It returned issue #1
  with a duplicate receipt; the issue remained closed and its count stayed at
  three. No browser continuation, new issue, or private media was involved.
- Small exports share an exclusive atomic commit: a late filename collision or
  dangling symlink cannot replace another file. Export confirmations share one
  formatter so the saved filename and folder appear consistently.
- Complete local gate passed: source validation, coverage, Address Sanitizer,
  Thread Sanitizer, packaging, and disposable updater replacement. The coverage
  and both sanitizer runs each reported 849 tests, one optional skip, zero
  failures. Non-UI line coverage was 88.98%. The initial normal run had 848 tests
  before the final export-confirmation regression was added; the later runs and
  signed handoff build include it.
- The skipped user-selected MP4/SRT acceptance test requires the reporter's exact
  inputs; bundled real-tool fixtures do not replace the same-file Intel retry.
