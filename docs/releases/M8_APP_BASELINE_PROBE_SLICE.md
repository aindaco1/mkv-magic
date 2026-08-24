# M8 noninteractive app baseline probe

This slice adds repeatable release-mode evidence for process startup, main-view
construction, and current resident memory without foregrounding MKV Magic or
opening a window. It complements the synthetic responsiveness probe; it does
not replace a physical Finder-launch or idle-soak walkthrough.

## Probe contract

- The benchmark builds the real Universal app and applies the repository's
  inside-out ad hoc signing path before execution.
- The native child recognizes only the explicit `--app-baseline-probe` mode,
  sets AppKit activation policy to prohibited, creates the real `AppModel` and
  `MainViewController`, completes initial layout, samples current resident
  memory through the Mach task API, emits one JSON sample, and exits.
- A separate launcher supervises three quick or seven standard child processes
  through the bounded command runner. It requires clean exit, bounded stdout,
  empty stderr, valid JSON, one native architecture, a populated root view, and
  zero application windows.
- The aggregate uses nearest-rank median and p95 values. Provisional release
  budgets are 2 seconds for process start through probe exit, 1 second from
  child entry through main-view readiness, and 256 MiB current resident memory.
- Reports contain only schema, architecture, coarse OS version, active processor
  count, rounds, timings, memory, and budgets. They contain no path, media fact,
  filename, hostname, timestamp, account, or payload.

The public entry point is:

```bash
./scripts/performance/benchmark-app-baseline.sh --enforce
```

`--quick` reduces the standard seven rounds to three. The wrapper uses a private
temporary release root and removes it on exit. Successful stdout is JSON only;
build and signing logs appear only if their stage fails.

## Observed development baseline

The standard seven-round signed-Universal run on the current 10-logical-
processor arm64 Mac running macOS 26.6.2 measured:

| Metric | Median | p95 | Provisional budget |
| --- | ---: | ---: | ---: |
| Process start through clean probe exit | 165.4 ms | 588.0 ms | 2,000 ms |
| Child entry through main-view readiness | 144.1 ms | 157.3 ms | 1,000 ms |
| Current resident memory after layout | 77.8 MB | 77.8 MB | 256 MiB |

All budgets passed. The disposable package gate also runs the quick enforced
probe after nested signing, so an app that cannot start this hidden native path,
emits diagnostics, creates a window, or exceeds a budget fails locally.

## Regression evidence and limits

- Unit tests prove nearest-rank aggregation, every budget boundary, rejection of
  visible/inconsistent samples, and path-free JSON.
- The existing responsiveness percentile implementation now reuses the same
  statistics helper, retaining its tested behavior without duplicate math.
- Strict formatting, local-only boundaries, secret scanning, action pinning,
  sanitizers, Universal compilation, and package verification remain in the
  complete gate.
- The complete local gate passes normal, coverage, AddressSanitizer, and
  ThreadSanitizer modes with 506 tests, 33 intentional source-only real-tool
  skips, and zero failures in each mode. Its signed Universal package stage
  passes the new hidden quick baseline before nested signatures, update archive,
  checksums, notices, SBOM, and independently verified DMG checks complete.

The probe deliberately skips `AppDelegate` window presentation, initial Queue
recovery, bundled-tool verification, media inspection, and transcoding. Current
resident memory is sampled immediately after main-view layout, not after a long
idle soak. Physical M1 and Intel measurements, Finder click to visible/key
window timing, Accessibility/VoiceOver observation, and private-corpus memory
behavior remain M8 acceptance work.
