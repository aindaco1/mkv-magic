# M3 embedded text-subtitle cleanup slice

This records engineering and local Apple Silicon UI acceptance of embedded SRT,
ASS, and SSA cleanup in Matroska files. It completes the text-subtitle
extraction, cleanup, and remux deliverable in M3. It is not acceptance of image
subtitle conversion, batch workflow actions, physical Intel testing,
real-library beta testing, or a public signed/notarized release.

## User-facing scope

- Selecting an inspected Matroska file enables **Clean Subtitle…** when at least
  one stable-UID `S_TEXT/UTF8`, `S_TEXT/ASS`, or `S_TEXT/SSA` track is present.
- A single editable track opens the shared cleanup review directly. Multiple
  editable tracks open a compact chooser showing order, format, language, name,
  and default/forced roles before review.
- The shared SRT/ASS/SSA review presents deterministic advertisement,
  whitespace, and English OCR suggestions. The selected track language—not the
  MKV filename—controls English OCR. Explicit non-English tracks skip it;
  English and unknown tracks use it.
- Continue creates one final MKV. It replaces only the selected track at its
  original position and performs zero video or audio encodes.
- The default output name is `<source> — Cleaned.mkv`. The source is never
  edited or automatically trashed.

## Safety and verification contract

1. Preview re-inspects a regular Matroska source, requires one unique stable
   track UID, extracts the text to a private replacement directory, and captures
   the source file revision, complete media snapshot, subtitle digest, parsed
   cleanup proposal, and exact FFprobe packet timeline.
2. Execution re-inspects, re-extracts, and re-probes. Any source revision,
   structure, track metadata, subtitle byte/semantic, cleanup-proposal, or packet
   timeline difference makes the preview stale before remux.
3. The reviewed subtitle and any exact timestamp sidecar exist only beside the
   private temporary output. Both are removed after the bundled tools finish.
4. One `mkvmerge` invocation copies retained streams, replaces the target at its
   original track order, and preserves its language, title, default, forced,
   enabled, commentary, hearing/visual-impaired, original, and text-description
   flags. One `mkvpropedit` invocation restores the original stable track UID.
5. Exact packet timestamps and durations are preserved when the retained packet
   sequence is contiguous, including the common case of removing trailing
   advertisement cues. MKVToolNix's timestamp override is deliberately omitted
   for gapped, overlapping, or non-contiguous retained packets because its
   timestamp-v2 model would extend one cue to the next packet. Those cases use
   the reviewed subtitle format's timestamps and the bounded SRT or ASS/SSA
   round-trip tolerance.
6. Before commit, the output must be a fresh nonempty Matroska segment with the
   exact original track order and stable UIDs, all target metadata restored,
   unrelated track technical facts unchanged, and chapters, tags, attachments,
   and duration preserved. The target is re-extracted and compared with the
   reviewed SRT or styled ASS/SSA payload. Exact timing plans also require
   nanosecond-equivalent FFprobe packet equality.
7. After exclusive commit, the app reopens the destination and repeats both the
   structural and payload/timing audits. A final audit failure is reported with
   the already committed output location for recovery; it is never called a
   success.
8. History stores only display filenames, workflow identity, and bounded
   lifecycle messages. Subtitle text, packet data, full paths, digests, and
   security scopes are excluded.

## Observed evidence

- The complete local gate passed 190 tests with nine intentional tool-dependent
  skips, strict formatting and security checks, coverage, AddressSanitizer,
  ThreadSanitizer, Universal release assembly, inside-out signing verification,
  checksums, SBOM, ZIP, appcast, and verified DMG. Re-running all 190 tests with
  the assembled Universal tool runtime executed every tool-dependent test with
  zero skips and zero failures.
- Core policy tests cover stable UID requirements, supported text codec IDs,
  SRT/ASS/SSA format mapping, and English/unknown versus explicit non-English
  OCR policy.
- Executor tests cover exact one-pass replacement arguments, every target flag,
  original track order, UID restoration, SRT and styled ASS cleanup, source
  revision and packet-timeline staleness, unsafe packet data, payload and exact
  timing audit failures, and cleanup of failed temporary output.
- A dedicated regression removes a middle advertisement cue and proves the
  executor does not apply a timestamp-v2 override that would stretch the prior
  cue across the removed interval.
- A bundled-tool integration creates fractional Matroska subtitle packets,
  chapters, an attachment, and a retained second subtitle. It removes a trailing
  advertisement, preserves the retained packets' exact FFprobe timing, source
  digest, track order and UIDs, target flags, chapters, and attachment, and
  re-extracts the corrected SRT.
- The real app-history integration adds an ASS track, cleans its embedded OCR
  error, preserves the track UID and style payload, and records the complete
  sanitized queued-through-succeeded lifecycle.
- A freshly built, tool-bundled, ad-hoc-signed Universal app was launched on
  Apple Silicon with an MKV containing English and French SRT tracks. The chooser
  showed both tracks, the review selected a high-confidence OCR correction and
  left a spelling suggestion unchecked, the user selected the second change,
  and the plan reported zero video encodes and one embedded track replacement.
  The save panel proposed `Embedded Review — Cleaned.mkv`; the committed output
  reopened, showed both reviewed corrections, kept the third cue unchanged, and
  retained the original track order, UIDs, names, tags, and source bytes.

## Still pending

- VoiceOver and full keyboard-only acceptance of the packaged chooser/review
  flow.
- Saved-workflow and batch actions for embedded cleanup.
- Image-subtitle pass-through/mux operations; image-to-text OCR remains roadmap.
- Physical Intel smoke testing, real-library beta acceptance, and the eventual
  signed/notarized public release.
