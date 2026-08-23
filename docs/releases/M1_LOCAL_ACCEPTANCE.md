# M1 local inspection acceptance

This records local acceptance of the M1 inspector vertical slice. It is not a
public MKV Magic release and does not claim physical Intel acceptance.

## Implemented

- Recursive, bounded file/folder discovery that skips hidden items, packages,
  and symbolic links.
- FFprobe JSON inspection for common media and MKVToolNix JSON identification
  for Matroska-specific structure.
- One normalized model for files, tracks, roles, codec/color/HDR facts,
  chapters, attachments, tags, and warnings.
- Asynchronous batch inspection with stable identifiers, partial-failure
  reporting, macOS document opening, and automatic first-result selection.
- A typed job-state lifecycle and versioned private job-history store. Persisted
  history is rejected unless its transitions replay through verification and
  commit before success.

## Observed local evidence

- The Swift suite passed 38 tests, with the real-tool test skipped only when no
  explicit tool root is provided.
- The real-tool integration created a Matroska fixture with the bundled FFmpeg,
  then inspected it with bundled FFprobe and MKVToolNix successfully.
- The complete local gate passed source validation, Universal compilation,
  coverage, Address Sanitizer, Thread Sanitizer, app assembly, signatures,
  entitlements, SBOM/checksum generation, ZIP creation, and DMG verification.
- A packaged sandboxed app opened a representative MKV through Launch Services
  and rendered its file, audio, attachment, tag, and segment-title facts. The
  main window remained usable and emitted no Auto Layout constraint warnings.

## Deliberately not claimed

- Editing and execution are not enabled. The preview button produces a plan;
  the run button remains disabled until temporary-output verification and safe
  commit are implemented in M2.
- The M1 UI has not yet been accepted on a physical Intel Mac.
- The current fixture set is engineering coverage, not the user's eventual
  real-world beta corpus.
