# M8 synthetic responsiveness baseline slice

This slice creates the first reproducible performance tripwire for MKV Magic's
pure workflow and production-queue paths. It deliberately measures no private
media and makes no physical-Intel, M1-reference, UI, or soak claim.

## What the probe measures

The release-mode executable warms both workloads and then records seven rounds:

1. Compile a four-card saved workflow 200 times per round against one synthetic
   Matroska model with 200 stable tracks. The cards exercise non-English
   subtitle removal, redundant English SDH removal, segment-title removal, and
   filename cleanup in one compiled plan.
2. Ask the production scheduler for eligible starts 200 times per round from a
   synthetic 5,000-job queue containing equal lightweight, audio-heavy, and
   video-heavy work.

Each metric reports nearest-rank median and p95 nanoseconds per operation. A
workload checksum keeps the measured results observable and fails the probe if
either workload unexpectedly produces no result.

## Privacy and safety boundary

- The workload is constructed entirely in memory. No user media, History,
  queue store, security bookmark, tool executable, network service, LLM, or
  destination is opened.
- JSON contains only its schema, architecture, macOS version components, active
  processor count, synthetic workload sizes, metric statistics, provisional
  budgets, and the workload checksum.
- It contains no paths, source URL, media or workflow title, hostname,
  persistent machine identifier, timestamp, or raw payload.
- Configuration is bounded to prevent accidental unbounded CPU or memory use.
  Unit tests cover those bounds, percentile semantics, enforcement state, and
  report-field privacy.

## Provisional budgets

Both paths use an initial 15 ms p95 budget. This is intentionally much looser
than the first Apple Silicon observation so the optional check catches a large
algorithmic regression without pretending to predict a slow Intel Mac. The
budget is not part of ordinary unit-test success; an operator opts into timing
enforcement with `--enforce`.

Run the standard probe:

```sh
./scripts/performance/benchmark-responsiveness.sh --enforce
```

Use the smaller three-round workload during development:

```sh
./scripts/performance/benchmark-responsiveness.sh --quick --enforce
```

## First observed baseline

On August 24, 2026, the standard release-mode probe passed on the current arm64
development Mac running macOS 26.6.2 with 10 active logical processors:

| Synthetic workload | Median | p95 | Provisional p95 budget |
| --- | ---: | ---: | ---: |
| 200-track saved-workflow compilation | 0.477 ms | 0.480 ms | 15 ms |
| 5,000-job production-queue scheduling | 1.384 ms | 1.396 ms | 15 ms |

The quick probe also passed, but it uses different 100-track and 1,000-job
workloads and is not the recorded standard baseline.

## Evidence and remaining work

- Three focused tests pass with zero failures.
- The standard and quick release probes both pass their provisional budgets.
- The complete local gate passes normal, coverage, AddressSanitizer, and
  ThreadSanitizer modes with 500 tests, 33 intentional source-only real-tool
  skips, and zero failures in each mode. It also passes the Universal app build
  and the isolated nested-signature, disposable-update, SBOM, checksum, notices,
  build-metadata, and independently verified DMG package gate.
- The executable is a separate Swift package product and is not embedded in the
  MKV Magic app or distributable.
- Still required: repeat the standard probe on the M1 server reference and a
  physical Intel Mac; measure cold/warm app launch, idle resident memory, real
  large-track rendering, inspection/thumbnail latency, cancellation, mux and
  encode throughput, artifact size, one-hour mixed queue behavior, and a
  multi-hour transcode.
