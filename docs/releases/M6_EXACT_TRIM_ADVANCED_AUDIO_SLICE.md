# M6 Exact Trim advanced audio slice

This slice makes the verified advanced-audio runtime an explicit Exact Trim
choice. It does not change the safe initial state: every audio track is still
packet-copied unless the user chooses a conversion.

## User contract

The native Audio popup starts at **Preserve Audio Exactly (Packet Copy)**. It can
then show AAC, Opus, AC-3, E-AC-3, and lossless FLAC, but only when:

- that exact bundled encoder passed the active local smoke;
- every audio track has known channels, layout, and sample rate; and
- the chosen codec can represent each exact layout without an implicit downmix
  or rematrix.

Opus discloses its 48 kHz Matroska clock in the popup. Other accepted inputs
retain their sample rate. A 7.1 source, for example, can offer Opus and FLAC but
not AC-3/E-AC-3; AAC is hidden for a 7.1 layout that AudioToolbox would reopen as
7.0. Packet copy never goes through this conversion policy.

## Planning and execution contract

Audio intent is a typed, Codable Exact Trim policy. The planner binds the chosen
preset to the inspected tracks and available capabilities. The shared audio
argument compiler emits only bounded encoder, bitrate, sample-rate, channel-count,
and channel-layout arguments directly to `Process`; Opus receives only its typed
application and multichannel mapping options. There is no free-form argument or
shell surface.

All selected audio tracks are encoded in the same FFmpeg invocation as the one
required video generation. No workflow stage can transcode the audio or video a
second time. Encoder disappearance, changed source facts, an unrepresentable
layout/rate, invalid path, existing output, or command-size regression fails
before commit.

## Verification contract

The temporary output and committed reopen must match the selected codec, exact
channel count/layout, declared sample rate, track order and metadata, attachment
inventory, numeric duration, color/HDR signal, and clipped nested chapters. The
source remains unchanged. Any mismatch removes the uncommitted output.

Pure regressions cover all five argument sets, bitrate/lossless behavior, probe
availability, layout/rate rejection, selection binding, and the 7.1 safety
surface. A bundled-tool integration runs a verified Exact Trim transaction for
each format, reopens and audits every result, and compares the original digest.

## Acceptance evidence

On 2026-08-23, the normal validation gate passed 409 tests with zero failures;
29 bundled-runtime tests were intentionally skipped when no tool root was
supplied. The complete local gate then passed the same 409 tests with the
Universal bundled runtime required and zero skips, including all five real Exact
Trim audio conversions. AddressSanitizer and ThreadSanitizer each passed all 409
tests. Coverage, Universal release build, source validation, signed-package
verification, manifest checks, and DMG verification also passed.

## Still pending

- SDR-to-HDR conversion.
- Representative Jellyfin/Plex corpus tuning and physical Intel performance.
- Public Developer ID signing, notarization, publication, and downloaded-artifact
  verification.
