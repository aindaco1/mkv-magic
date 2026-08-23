# M5 join-boundary and copied-payload audit slice

This records engineering acceptance of the strict media-payload audit now used
by both lossless and common-format final joins. It does not claim full-file
decode, manual ambiguous-lane mapping, HDR conversion, private-library beta,
physical Intel acceptance, or public release.

## Verification contract

For both the private temporary MKV and the atomically committed path, MKV Magic
now performs these checks after the existing semantic and canonical nested
chapter audits:

1. Build one bounded window around every source boundary. The window reaches up
   to one second into each adjacent part and shrinks deterministically for very
   short parts.
2. Decode every inspected video and audio stream in each window with bundled
   FFmpeg using error escalation. A non-zero exit, any error-level diagnostic,
   or truncated diagnostics fails verification.
3. For every lane promised as a direct packet copy, stream the ordered encoded
   packet hashes from the reviewed inputs and final output through SHA-256.
   Packet count and the final sequence digest must both match.
4. Only after those checks pass may the verified-output transaction commit. The
   complete audit runs again against the reopened destination.

The packet listing never accumulates in memory. A shared cancellable process
runner validates each exact executable and timeout, drains output continuously,
canonicalizes one bounded hash line at a time, and retains only the incremental
digest and line count. Malformed output, an empty stream, non-zero tools,
oversized diagnostics, timeouts, and cancellation all fail closed.

## Codec-aware packet truthfulness

Audio, subtitle, and video codecs not known to require Matroska parameter-set
canonicalization use exact FFprobe packet-payload hashes. `mkvmerge` can
legitimately rewrite H.264/HEVC codec-parameter and access-unit-delimiter NAL
units without encoding the picture. For those two codecs, MKV Magic asks FFmpeg
to remove only the muxer-managed units, then streams per-packet SHA-256 hashes
of the retained encoded video bodies. This preserves a meaningful payload
identity check without falsely rejecting a valid Matroska remux.

Normalized lanes are not described as direct source packet copies. They retain
their existing one-generation semantic verification and are decoded at every
join boundary; only lanes explicitly compiled with the `packetCopy` mechanism
must match original packet payloads byte for byte under the codec-aware policy.

## Regression and real-tool evidence

- Streaming-runner tests cover multi-command digest continuation beyond the
  ordinary output-retention limit, canonical suffix removal, framehash header
  removal, malformed lines, and empty output.
- Focused auditor tests cover every calculated boundary, exact source order,
  HEVC canonical packet hashing, decode refusal before fingerprints, packet
  count changes, and payload changes.
- Executor tests prove both the temporary output and committed reopen traverse
  the audit while existing cancellation, stale-source, chapter, metadata, and
  committed-output failure contracts remain green.
- A bundled AAC lossless join passes exact packet hashing. A bundled HEVC
  lossless join passes codec-aware retained-payload hashing and boundary decode.
  A real mixed normalized-video/direct-copy-audio join and the native app-level
  common-format integration both pass without changing either source.

The standard validation completes all 343 tests with zero failures and 23
intentional bundled-tool skips, then builds the Universal `arm64`/`x86_64`
executable. The exact bundled runtime completes all 343 tests with zero skips
and zero failures.

The complete local gate also passes coverage, AddressSanitizer,
ThreadSanitizer, Universal compilation, inside-out app signature and entitlement
validation, SBOM and checksum verification, ZIP/appcast assembly, and verified
DMG packaging.

## Still pending

- Single-pass multi-lane fingerprint demux optimization for unusually large
  track counts; the current implementation is memory-bounded but scans once per
  copied lane.
- Manual mapping for ambiguous track lanes.
- Private-library beta, physical Intel performance acceptance, and public release.
