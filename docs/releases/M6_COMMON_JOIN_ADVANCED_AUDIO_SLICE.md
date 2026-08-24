# M6 common-format Join advanced audio slice

This slice extends the reviewed common-format Join sheet from AAC-only audio to
typed per-lane AAC, Opus, AC-3, E-AC-3, and lossless FLAC choices. AAC remains
the compatibility-first recommendation. If AAC is unavailable or cannot
represent a lane, the first locally verified compatible format is selected.

## User contract

Each encoded audio lane has one native Audio format popup. It contains only
encoders that passed the active local smoke and can represent the reviewed
channel count, channel layout, and target sample rate. Selecting a new format
immediately updates the final layout/rate/bitrate summary and resets approval.
Opus states its 48 kHz output; FLAC states lossless instead of inventing a
bitrate. A 7.1 lane, for example, can offer Opus and FLAC while hiding formats
whose tested layouts cannot represent that lane.

Join never downmixes. It retains the largest reviewed channel count. The only
permitted channel-order adaptation is the explicit six-channel 5.1 versus
5.1(side) mapping required for encoder-safe input and a stable reopened output.

## Planning, execution, and compatibility contract

The portable choice stores a typed audio preset. Legacy AAC choices containing
the old `codec` field still decode, while new encodings write the typed preset.
The resolver binds format, layout, sample rate, fixed recommended bitrate (or
lossless FLAC), silence approval, source facts, and active capabilities.

All affected audio and video lanes remain in one bounded FFmpeg graph and one
normalization invocation. The same shared audio compiler used by Exact Trim
emits encoder, rate, channel count, channel layout, bitrate, and bounded Opus
options directly to `Process`; there is no free-form shell or argument field.

The verified-output transaction reopens the temporary and committed files and
checks the selected codec, exact final layout/count, declared sample rate,
duration, stream inventory, and unchanged source revisions. A real bundled-tool
regression executes and decodes a stereo-plus-surround Join once for every audio
format and compares the source digests.

## Acceptance evidence

On 2026-08-23, the normal validation gate passed 415 tests with zero failures;
29 bundled-runtime tests were intentionally skipped when no tool root was
supplied. The complete local gate passed all 415 tests with the Universal bundled
runtime required and zero skips, including the five-format real Join transaction.
AddressSanitizer and ThreadSanitizer each passed all 415 tests. Coverage,
Universal release build, source validation, signed-package verification,
manifest checks, and DMG verification also passed.

## Still pending

- SDR-to-HDR conversion.
- Representative Jellyfin/Plex corpus tuning and physical Intel performance.
- Public Developer ID signing, notarization, publication, and downloaded-artifact
  verification.
