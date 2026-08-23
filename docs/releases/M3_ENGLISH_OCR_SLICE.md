# M3 deterministic English OCR cleanup slice

This records engineering acceptance of the first entirely local English OCR
cleanup policy for external SRT, ASS, and SSA files. It is not acceptance of
image-subtitle OCR, a general-purpose grammar checker, batch execution,
real-library beta testing, or a public release. Embedded-track cleanup is
accepted separately in `M3_EMBEDDED_SUBTITLE_SLICE.md`.

## User-facing scope

- The existing native subtitle review includes high-confidence OCR corrections
  and possible spelling corrections alongside ad and whitespace cleanup.
- High-confidence changes start selected. They are limited to pronoun
  contractions commonly confused with lowercase L, digit one, or a vertical
  bar, and digit/letter words that resolve to exactly one entry in the embedded
  common-English lexicon.
- Curated letter-only confusions such as `Tbe` to `The` are visibly labeled as
  possible corrections and start unselected. The user must opt into each one.
- Case and straight or curly apostrophe style are preserved.
- SRT markup, ASS/SSA override blocks, URLs, and email addresses are excluded
  from OCR analysis. ASS/SSA structural and style preservation remains governed
  by the style-preserving cleanup contract.
- English OCR runs for `.en`, `.eng`, `.english`, or language-unspecified
  filenames. It is skipped for explicit common non-English language suffixes,
  including language-region/script forms such as `.pt-BR` or `.zh-Hans` and
  forms followed by role suffixes such as `.fr.forced`. Ordinary title words
  such as `The French Dispatch` are not treated as language suffixes.
- The policy is deterministic, embedded in the app, and uses no LLM, network,
  account, telemetry, or operating-system spell-check service.

## Safety and verification contract

1. OCR runs only after the existing bounded, fail-closed subtitle decoder and
   parser accept the file.
2. Advertisement removal remains higher priority. Edge whitespace is normalized
   before OCR analysis.
3. A cue or event with a deterministic change receives one restorable review
   item. A possible spelling-only change receives a separate unselected review
   item. This avoids silently coupling an uncertain edit to a selected change.
4. The filename-derived language policy is stored in the preview. Immediately
   before execution, MKV Magic re-reads the exact source and regenerates the
   cleanup with that same policy; a byte, parse, or proposal mismatch is stale.
5. Output still uses the existing verified subtitle transaction: a new UTF-8
   file is written privately, compared with the plan, parsed and audited before
   commit, committed without replacing the source, then reopened and audited
   again.
6. Job history remains sanitized and never stores subtitle text, OCR tokens,
   full paths, source digests, or security scopes.

## Observed evidence

- The complete local release gate passed 173 tests with eight intentional
  tool-dependent skips, strict formatting and security checks, coverage,
  AddressSanitizer, ThreadSanitizer, Universal release assembly, inside-out
  signing verification, checksums, SBOM, ZIP, appcast, and verified DMG.
- Re-running the same 173 tests with the assembled Universal tool bundle made
  every tool-dependent test execute: 173 passed, zero skipped, zero failed.
- Engine tests cover unique glyph-word resolution, lowercase-L and digit-one
  contractions, all-uppercase preservation, curly apostrophes, review-only
  letter confusions, ordinary names and numbers, ambiguous glyph refusal, and
  protected markup, override tags, URLs, and email addresses.
- SRT and ASS/SSA policy tests prove high-confidence and uncertain reasons remain
  distinct, restoration retains original text, English OCR can be disabled
  without disabling whitespace cleanup, and ASS override tags survive.
- Executor tests prove `.en` and unspecified English policy behavior, explicit
  `.fr`/`.es` skipping, and use of the stored language policy during stale
  preview validation.
- App policy tests prove possible spelling corrections are unselected by
  default, high-confidence changes are selected, the summary reflects the true
  selection count, and the interface explains when filename language disables
  OCR.
- A freshly built, tool-bundled, ad-hoc-signed Universal app was launched on
  Apple Silicon with a three-cue `.en.srt` fixture. The native review visibly
  selected `y0u`/`HE11O` correction, left `Tbe`/`modem` unchecked, updated the
  summary after the uncertain row was selected, showed zero video encodes, and
  committed and reopened a new UTF-8 copy. The output contained both reviewed
  corrections while retaining `Model 3` and `Alonso`; the app reported the
  original unchanged.

## Still pending

- Embedded-cleanup saved-workflow and batch actions.
- Additional curated OCR patterns informed by real-library false-positive and
  false-negative fixtures.
- Packaged VoiceOver, full keyboard-only, physical Intel, and real-library beta
  acceptance, plus the eventual signed/notarized public release.
