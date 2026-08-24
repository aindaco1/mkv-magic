# M7 Trash after verified success slice

This slice completes the first user-selectable queue source-disposition policy
for saved workflows. The option is intentionally off by default and does not
change built-in quick actions.

## User contract

- The Save panel says **Move original video file to Trash after verified
  success** and explains both the ordering and failure behavior before the user
  opts in.
- A new workflow defaults to **Keep original**. Review Again preserves the
  queued choice as the next review's default, while still letting the user turn
  it off before retry.
- Only the primary video input receives a read/write app-scoped bookmark when
  Trash is selected. External subtitle inputs remain read-only and are never
  source-disposition targets.

## Failure-safe ordering

1. The workflow creates one temporary output and performs its full audit.
2. The verified transaction exclusively commits the destination and reopens it.
3. Sanitized History records output success.
4. The durable production queue records **Succeeded**.
5. Only then does MKV Magic ask macOS to move the primary source to Trash.

If durable queue success cannot be recorded, the source is not moved. If the
Trash operation fails, the new output and successful queue record are preserved;
the app shows a warning and does not retry or delete the output. A successful
move removes the old source from the current inspector and reports that the
original is recoverable from Trash.

## Regression and integration evidence

- Presentation tests assert that the option is explicit, off by default, and
  describes the durable-success boundary and safe failure behavior.
- Commit-policy tests make the Trash action impossible for **Keep original** or
  before durable queue success.
- Bookmark tests cover both read-only and read/write file authorities while
  retaining symlink and resource-type refusals.
- A bundled-tool integration performs a reviewed subtitle cleanup and mux in one
  verified output transaction, records `waiting -> running -> succeeded`, proves
  the primary bookmark is read/write and the subtitle bookmark read-only, and
  observes exactly one post-success Trash request for the primary MKV.
- The Save-panel accessory passed a bounded-layout regression and visual
  inspection at `trash-after-verified-accessory.png` in the task visualization
  directory; the checkbox and failure-safe explanation are fully visible.
- Normal, coverage, AddressSanitizer, and ThreadSanitizer runs each executed 464
  tests with zero failures or skips against the pinned Universal media runtime.
  Final source validation repeated all 464 tests and built the `arm64` + `x86_64`
  release executable.
- The first disposable package verification exposed an orphaned `hdiutil`
  attachment after macOS returned `Resource temporarily unavailable`. The shared
  release verifier now retries once after identifying and detaching only the
  whole device whose canonical image path exactly matches its own DMG. Mocked
  regressions prove recovery and refusal to detach an unrelated image. The final
  isolated package gate passed app/Sparkle signature validation, checksums,
  appcast and metadata generation, CycloneDX SBOM generation, and two independent
  DMG checksum/layout verifications.

## Explicitly not accepted by this slice

- Automatic queue admission, built-in quick-action queueing, watched folders,
  and unattended execution remain open.
- The Trash request is user initiated and recoverable; permanent deletion is not
  offered.
- Queue success and Finder Trash are separate durable systems. A process or
  machine failure in the narrow interval after queue success but before the
  Trash request can conservatively leave the original in place; durable
  disposition-outcome recovery is a later queue slice.
- Local tests do not constitute notarization, public release, physical Intel,
  or long-duration queue-soak evidence.
