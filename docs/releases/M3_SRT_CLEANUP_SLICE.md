# M3 SRT-cleanup slice

This records engineering acceptance of the first deterministic text-subtitle
cleanup slice. ASS/SSA cleanup is accepted separately in
`M3_ASS_SSA_SLICE.md`, and OCR cleanup is accepted separately in
`M3_ENGLISH_OCR_SLICE.md`. This document is not acceptance of embedded-subtitle
extraction/remux, batch cleanup, or a public release. External SRT matching and
muxing is accepted separately in `M3_EXTERNAL_SUBTITLE_MUX_SLICE.md`.

## User-facing scope

- Selecting an inspected `.srt` file enables **Clean SRT…**.
- A compact native review sheet lists every suggested cue change with its exact
  timing and before/after text. Deterministic changes start selected; uncertain
  OCR spelling suggestions start unselected. Each can be individually changed
  before continuing.
- The first suggestions remove only whole cues containing the established
  `Official YIFY movies site` or `Downloaded from` patterns with a known
  `yts.mx`, `yts.lt`, or `yts.bz` domain. Ordinary dialogue containing unrelated
  `downloaded from` text is retained.
- Accidental leading and trailing horizontal whitespace is normalized per text
  line. Cue timing and optional timing settings are never changed.
- Structural normalization writes sequential cue numbers, comma millisecond
  separators, LF line endings, and UTF-8 without a byte-order mark.
- If no cleanup or normalization is needed, the app says so without offering a
  redundant output. If selected removals would leave no cues, Continue is
  disabled until at least one cue is restored.

## Safety and verification contract

1. Input must be a regular, non-symbolic-link SRT no larger than 16 MiB.
2. Decoding accepts UTF-8, BOM-marked UTF-8 or UTF-16, Windows-1252, and Latin-1;
   empty, null-containing, malformed, or unsupported subtitle data fails closed.
3. Each review cue has an in-memory identity that survives normalization and
   output renumbering. Review data is never persisted in job history.
4. Execution re-reads the input and requires its SHA-256 digest, parsed document,
   and deterministic suggestions to match the preview. Even a line-ending-only
   source change invalidates the preview.
5. The output must use an SRT destination and cannot replace the source or an
   existing item. It is first written to a private replacement directory.
6. Before commit, MKV Magic requires byte equality with the planned UTF-8 output
   and semantic equality of every cue's start, end, timing settings, and text.
7. After exclusive commit, the destination is reopened and the same byte and cue
   audit is repeated. The original is never edited, replaced, or sent to Trash.
8. History contains only display filenames and bounded lifecycle messages. It
   records no subtitle text, full personal path, source digest, or security scope.

## Observed evidence

- Parser tests cover BOM and CRLF removal, period-to-comma timestamp
  normalization, non-sequential and omitted sequence numbers, optional timing
  settings, Windows-1252 smart punctuation, malformed timings, and end-before-
  start refusal.
- Rule tests cover single-line and multiline YTS/YIFY patterns, false-positive
  resistance for unrelated dialogue, edge-whitespace changes, and restoration.
- Executor tests prove source SHA-256 preservation, exact UTF-8 output, cue
  renumbering, pre-commit cleanup after progress failure, stale semantic and
  byte-only preview refusal, all-cues-removed refusal, symbolic-link refusal,
  size bounds, destination-format refusal, and canonical no-op detection.
- An app-level test runs the actual cleanup transaction, reloads the atomic
  history document, observes the complete queued through succeeded lifecycle,
  and confirms history excludes subtitle text and the temporary personal path.
- AppKit construction and policy tests cover the compact resizable review sheet,
  output naming, long-duration timestamp display, and the keep-one-cue gate.
- A freshly packaged, ad-hoc-signed Universal app was launched on Apple Silicon
  with a three-cue SRT. The app inspected it, displayed both suggestions in the
  native sheet with meaningful accessibility labels, restored the ad cue when
  unchecked, showed the zero-encode pending plan, saved a verified copy, retained
  the source bytes, and displayed the succeeded Clean SRT subtitle history row.
- The complete source validation passes 122 tests with five bundled-tool tests
  conditionally skipped; running those five separately against the verified
  Universal tool runtime also passes.

## Still pending

- VoiceOver and full keyboard-only acceptance of the packaged review flow.
- Embedded subtitle extraction/cleanup/remux and corresponding workflow actions.
- Physical Intel smoke testing, real-library beta acceptance, and a public
  signed/notarized release.
