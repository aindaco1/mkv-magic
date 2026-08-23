# M3 external-subtitle mux slice

This records engineering acceptance of deterministic external-SRT matching and
verified zero-encode Matroska muxing. It is not acceptance of directory-wide
automatic pairing, ASS/SSA or image-subtitle muxing, embedded-subtitle
extraction/remux, batch execution, or a public release.

## User-facing scope

- Selecting an inspected Matroska video enables **Add Subtitle…** and an
  SRT-only file picker.
- A compact native confirmation sheet shows the video, subtitle, match
  confidence and reasons. Language, track name, default, forced, and SDH flags
  remain editable before anything enters the plan.
- Matching uses deterministic filename, normalized title/year, episode,
  language/role suffix, and subtitle-end-time signals. A weak filename match or
  incompatible duration is shown as a warning and never auto-confirmed.
- Existing deterministic SRT cleanup suggestions are disclosed but not silently
  applied. The user must run **Clean SRT…** first to opt into text cleanup.
- The pending plan states `0 video encodes`, uses an MKV destination, and adds
  exactly one subtitle as the last track.

## Safety and verification contract

1. The source must be an inspected Matroska file and the external input must
   pass the existing regular-file, symbolic-link, 16 MiB, strict-parse, and
   stale-preview SRT checks.
2. Language is canonicalized as a bounded BCP 47 tag. Track names reject nulls
   and values larger than 4,096 UTF-8 bytes.
3. MKV Magic serializes the original reviewed SRT document—not proposed cleanup
   changes—to a UTF-8 private sidecar beside the temporary output. The sidecar
   is removed after the direct-argument `mkvmerge` invocation.
4. `mkvmerge` receives an exact absolute executable URL, `--abort-on-warnings`,
   disables newly generated track-statistics tags, receives explicit
   language/role flags, and a track order containing every existing
   non-attachment track followed by the new SRT. No shell or encoder is used.
5. Before commit and again after reopen, verification requires a nonempty
   Matroska output, expected duration, preserved user metadata/tags, nested
   chapters, attachments, and exact existing track order and technical/playback
   facts. It also requires one final S_TEXT/UTF8 track with the reviewed
   language, name, and flags, plus a fresh segment UID.
6. The video, external SRT, and destination are security-scoped only for the
   operation. Neither source is edited, replaced, deleted, or sent to Trash.
7. History records the two display filenames, output filename, stable workflow
   identity, and bounded verified lifecycle messages. It stores no full paths,
   subtitle text, digest, or security scope.

## Observed evidence

- Matcher tests cover high-confidence title/year and metadata suffix inference,
  episode matching, duration signals, and the false-positive case where a
  language word is part of the movie title.
- Muxer/executor tests cover exact direct arguments, source preservation,
  cleanup-suggestion non-application, private sidecar removal, stale-preview and
  non-MKV refusal before tool execution, and unsafe language/name rejection.
- Output-verifier tests accept only one reviewed SRT added last and reject a
  mutation to an existing track; shared fixtures also carry chapters and an
  attachment through the verification contract.
- A real bundled-tool test creates a Matroska source with FFmpeg, decodes a
  Windows-1252 SRT, remuxes its normalized temporary representation, verifies
  the new track metadata and source digests, and re-extracts UTF-8 `Café` with
  `mkvextract`.
- A real bundled-tool app integration records both input display names and the
  complete queued-through-succeeded lifecycle without persisting personal paths
  or subtitle text.
- AppKit construction and presentation tests cover the compact sheet, explicit
  weak-match/duration/cleanup warnings, canonical metadata, and MKV output name.
- The current full local gate passes 139 tests with six intentionally skipped
  bundled-tool tests, coverage enforcement, AddressSanitizer,
  ThreadSanitizer, Universal release compilation, source/security validation,
  nested signing checks, checksum/SBOM generation, update ZIP packaging, and
  DMG verification. All six bundled-tool integrations also pass separately
  against the packaged FFmpeg and MKVToolNix runtime.
- A freshly packaged Universal app passes nested code-signature and bundled-tool
  verification. The current desktop session did not expose an observable app
  window, so this evidence does not claim a completed packaged visual walkthrough.

## Still pending

- Packaged visual, VoiceOver, full keyboard-only, and physical Intel acceptance
  of the mux flow.
- Directory-wide candidate discovery/ranking and batch confirmation.
- ASS/SSA and image-subtitle muxing plus embedded subtitle
  extraction/cleanup/remux.
- Saved-workflow subtitle actions, real-library beta acceptance, and a public
  signed/notarized release.
