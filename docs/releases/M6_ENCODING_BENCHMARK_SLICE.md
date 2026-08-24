# M6 local encoding recommendation slice

This records engineering acceptance of MKV Magic's consent-based, fully local
AV1-versus-HEVC benchmark and persisted initial-preset recommendation. It does
not claim representative private-library tuning, thermal/long-duration results,
physical Intel acceptance, HDR10 transcoding, or a public signed/notarized
release.

## User contract

- **Encoding Test…** is visible in the native sidebar but never runs at launch,
  during inspection, or before metadata/remux work. The user must click **Run
  Encoding Test** or **Run Again**.
- The window states the exact synthetic workload, local-only behavior, temporary
  CPU/GPU use, and AV1 time limit before work begins. It remains cancellable.
- The test never opens user media and never uses a network source. One generated
  three-second 640×360 P010 clip lives only in a `0700` temporary directory.
- Results show encoder FPS, a conservative estimated 1080p real-time factor,
  output bitrate, and average PSNR when the bundled filter succeeds.
- The recommendation changes only the initial selection. Every encoder that
  passed the active capability probe remains available in Trim and Join.

## Recommendation and persistence contract

- AV1 uses the same 10-bit constant-quality 30 and pinned SVT preset 8 policy as
  current one-generation SDR execution. HEVC uses the same 10-bit VideoToolbox
  path with a resolution-appropriate one-megabit test target.
- Measured 640×360 throughput is scaled by pixel count to estimate 1080p speed.
  AV1 remains quality-first at `0.5×` real time or better; below that threshold,
  a completed HEVC result becomes the initial choice. A failed or timed-out AV1
  attempt can therefore produce a truthful HEVC recommendation.
- The versioned JSON report is capped at 64 KiB, written atomically with `0600`
  permissions in the private app-support directory, rejects unknown fields and
  unsafe symlinks, and contains no filename, path, title, subtitle, or media
  identifier.
- A report is applied only when the exact FFmpeg SHA-256, process architecture,
  and active processor count match. Runtime or hardware drift restores the
  quality-first verified capability order until the user runs another test.

## Verification evidence

- Pure regressions cover fast AV1, impractically slow AV1, timeout fallback,
  unavailable encoders, exact environment matching, duplicate-safe policy, and
  capability reordering without choice removal.
- Persistence regressions cover versioned round trip, private permissions,
  missing-state behavior, unknown fields, unsupported schemas, unsafe symlinks,
  invalid metrics, and inconsistent recommendations.
- Command regressions inspect the exact AV1/HEVC arguments, private fixture
  lifetime, output bounds, bitrate/PSNR parsing, and cancellation/failure paths.
- The exact bundled Apple Silicon runtime completed both timed encodes and both
  quality comparisons. The app integration then consumed a matching persisted
  HEVC recommendation while retaining AV1 in the available choices.
- A native minimum-size AppKit regression and rendered-window inspection verify
  that the consent explanation, result hierarchy, scrollable metrics, Run,
  Cancel, and Close controls remain visible and unclipped.
- The normal source gate passed 376 tests with 26 intentional real-tool skips;
  the exact bundled-runtime suite passed all 376 tests with no skips.
- The complete local risk gate passed all 376 tests under both AddressSanitizer
  and ThreadSanitizer, then assembled and verified the Universal app, inside-out
  signatures, Sparkle update ZIP/appcast, CycloneDX SBOM, checksums, and mounted
  DMG.

## Still pending

- Repeat the benchmark and assess thermals on at least one physical Intel Mac.
- Tune the threshold and AV1/HEVC rate-control defaults against the private beta
  corpus rather than treating one synthetic clip as a quality verdict.
- Add user-facing advanced AV1 quality/speed controls after those measurements.
- Complete HDR10 transcode preservation and verification.
- Complete public Developer ID signing, Apple notarization, update testing, and
  downloaded-artifact verification.
