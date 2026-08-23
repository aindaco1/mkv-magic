# M5 copied-packet audit performance slice

This records engineering acceptance of the bounded, stream-family packet-hash
demultiplexer used by final Join verification. It removes the known
lane-multiplied FFprobe scan without weakening the copied-payload contract. It
does not claim private-library beta, physical Intel acceptance, full-file
decode, M6 transcoding completeness, or public release.

## Execution contract

- Exact packet-copy lanes are grouped by media kind. One FFprobe process scans
  all requested video, audio, subtitle, data, or attachment streams in that
  family for each source part and final output.
- Every emitted packet line carries its original stream index. The runner maps
  that command-local index to the reviewed output lane and continues a separate
  SHA-256 accumulator and packet count for each lane across source parts in
  order.
- Packet listings remain streamed and memory-bounded. Unrequested streams are
  ignored; a malformed line, missing requested lane, duplicate logical mapping,
  empty stream, tool failure, diagnostic overflow, timeout, or cancellation
  fails closed.
- H.264 and HEVC video remain on their existing codec-aware FFmpeg framehash
  route. Those lanes must remove only the muxer-managed units before comparing
  retained encoded payloads and therefore are not mixed into the exact FFprobe
  batch.
- Stream-family selection prevents an audio-only audit batch from spending CPU
  hashing unrelated video packets. Mixed families use one bounded scan per
  family, never one scan per lane.

For `S` source parts, `L` exact copied lanes in the same family, and both the
temporary and committed output audits, the FFprobe launch count changes from
`2 × (S + 1) × L` to `2 × (S + 1)`. The number of packet hash lines and the
per-lane comparison remain unchanged.

## Regression and real-tool evidence

- Runner tests prove two command-local stream-index maps continue two isolated
  logical lane digests in order while ignoring unrelated streams.
- Runner refusal tests cover an absent requested stream and two emitted tracks
  ambiguously targeting one logical lane.
- Auditor tests prove two copied audio lanes share one scan per source and one
  output scan, while count and payload mismatches still identify the failing
  lane.
- Bundled-tool tests pass the native two-audio-lane manual Join transaction,
  AAC lossless Join, mixed normalized-video/direct-copy-audio Join, and
  codec-aware HEVC Join. Every transaction performs the audit before commit and
  again after reopening the committed file.

The standard source validation completes all 352 tests with zero failures and
24 intentional bundled-tool skips, then builds the Universal `arm64`/`x86_64`
executable. The exact bundled runtime completes the same 352 tests with zero
skips and zero failures.

The complete local gate also passes coverage, AddressSanitizer,
ThreadSanitizer, Universal compilation, inside-out app signature and entitlement
validation, SBOM and checksum verification, ZIP/appcast assembly, and verified
DMG packaging.

## Reproducible benchmark

`scripts/performance/benchmark-join-packet-audit.sh` accepts a local unchanged
media file, one FFprobe stream-family selector, and the numeric tracks in that
family. It warms both paths, withholds the input path, and reports the former
per-track and current demultiplexed wall/user/system times plus exact process
counts. It uses only the manifest-hash-verified architecture-specific FFprobe
and rejects measurements if the source revision changes during the run.

Observed on the Apple M1 Max development Mac running macOS 26.6.2 with the
bundled arm64 FFprobe:

- Fixture: generated 60-second Matroska file with twelve mono AAC tracks,
  approximately 337 KB; five measured passes after warm-up.
- Former pattern: 60 FFprobe launches, 1.68 seconds wall time.
- Current pattern: 5 FFprobe launches, 0.78 seconds wall time.
- Observed change: 91.7% fewer FFprobe launches and approximately 53.6% less
  wall time for this synthetic high-track-count scan.

The tiny two-source/two-track end-to-end app fixture remained within timing
noise: eight isolated XCTest invocations measured 14.04 seconds at the prior
commit and 13.95 seconds with the optimization. That fixture is retained as
correctness evidence, not presented as a throughput win. Real-library and
physical-Intel measurements remain required.

## Still pending

- Private-library beta measurements on representative long, subtitle-heavy,
  mixed-codec, delayed, variable-rate, and malformed media.
- Physical Intel responsiveness, memory, throughput, and thermal acceptance.
- The M6 encoder benchmark, queue soak testing, and public release acceptance.
