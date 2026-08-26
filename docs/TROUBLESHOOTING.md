# MKV Magic troubleshooting

MKV Magic is intentionally conservative: when it cannot prove that an output
matches the reviewed plan, it refuses the result and keeps the original. Start
with the visible status in the app, then check the relevant section below.

## The app will not open

- MKV Magic requires macOS 13 Ventura or newer. Apple Silicon and Intel use the
  same Universal app.
- Install from the official DMG and move **MKV Magic.app** to Applications. Do
  not remove quarantine attributes or bypass Gatekeeper to make an unverified
  copy run.
- If macOS says the app is damaged or cannot be verified, download it again and
  verify the published `SHA256SUMS`. A valid public release must be signed,
  notarized, and stapled.
- MKV Magic does not need Homebrew, a separate FFmpeg, or a separate
  MKVToolNix. Reinstall the complete app if bundled tools are reported missing.

## A file or folder does not appear

- Use Command-O, **Choose Files…**, or drag and drop. macOS must grant access to
  the selected file or folder.
- Symbolic links, aliases that resolve unsafely, hidden files, special files,
  and unsupported extensions are skipped or refused. Select the real local
  file instead of a link.
- A single folder selection is limited to 10,000 supported files. Choose a
  smaller folder when that safety limit is reached.
- Common supported inputs include MKV, MP4, MOV, AVI, WebM, MPEG transport
  streams, common audio formats, SRT, ASS/SSA, VTT, and VobSub IDX/SUB pairs.

## A task is unavailable

Select one inspected file and read the explanation attached to the disabled
control. The most common prerequisites are:

- metadata, track, embedded-subtitle, and chapter editing require Matroska;
- track edits need stable Matroska track UIDs;
- track removal needs at least two stable tracks;
- Trim needs one video track and a known duration;
- Convert Video needs one MKV, MP4, M4V, MOV, or chapter-free WebM video with
  complete reviewed color/layout facts. MKV may preserve supported audio,
  subtitles, and attachments but must have no data tracks or source tags.
  Common input must have no subtitles or attachments, no ambiguous data or
  chapters, and only metadata MKV Magic can deliberately preserve or normalize;
- compatible Join needs at least two inspected Matroska files; and
- text cleanup supports SRT and editable ASS/SSA text. PGS and VobSub can be
  preserved, extracted, removed, or muxed unchanged, but image-to-text OCR is
  not in v1.

## Process more than one file

- Command-click or Shift-click rows in the inspected-media list to select a
  batch. Press Delete to remove all selected rows from the list; source files
  remain untouched.
- **Clean Subtitle…** is available when every selected item is a standalone
  SRT, ASS, or SSA file. Review the ready, no-change, and blocked results before
  creating one independently verified output per ready file.
- Open Workflows with multiple rows selected to compile a portable saved recipe
  separately for each source. Workflows that require choosing an external
  subtitle remain single-file operations because that pairing needs individual
  review.
- Batch output stays beside each source by default. The review sheet can choose
  one alternate folder for every ready output. Existing destinations are never
  overwritten and are reported as skipped.

## MKV Magic refuses an output

- Reinspect the source and review the plan again. A file changed after review
  is deliberately rejected.
- Choose a new destination. MKV Magic never silently overwrites an existing
  file.
- Confirm the destination volume has enough free space. Work is prepared on
  the destination volume so the verified commit can be atomic.
- Keep the original available until the app reports that the new output was
  verified, committed, and reopened. A tool exit alone is not success.
- When cancellation is still available, temporary output is removed and the
  original remains unchanged. Cancellation closes at the atomic commit boundary
  because interrupting that step would be less safe.

## Queue work is paused or needs review

- Open Window → Queue (Command-2) and read the selected job state.
- **Pause Automatic Starts** prevents new jobs from starting; work already in
  progress continues to its next safe boundary.
- Battery or serious thermal pressure can delay automatic work. The queue is
  reconsidered when the app launches, a job is resumed, or work is added.
- Interrupted, failed, stale, or changed-input jobs require review again. MKV
  Magic does not silently retry a plan whose inputs may have changed.
- Verify & Run remains an explicit immediate action after its current plan is
  reviewed.

## Encoding is unavailable or slow

- MKV Magic locally smoke-tests bundled encoders and offers only choices that
  actually work on the running Mac.
- AV1 is the quality/size preference, but software AV1 can be slow on older
  Intel hardware. Use Window → Encoding Test (Command-4) to compare a generated
  local AV1 sample with verified HEVC; no library media is used.
- HEVC VideoToolbox is the expected faster fallback on older Macs. If a codec
  or audio layout cannot be preserved by a selected encoder, choose packet copy
  or another offered format instead of forcing an unverified conversion.
- HDR10 preservation requires a validated static BT.2020/PQ signal. Dolby
  Vision, HDR10+, HLG, and SDR-to-HDR conversion are outside the v1 contract.
- Convert Video always creates a new MKV in this beta. Embedded subtitles from
  MKV are packet-copied and verified. Common-container subtitle input, chaptered
  WebM, MP4/MOV/WebM output, and subtitle conversion are not silently
  substituted. If common audio cannot be copied into Matroska, choose an offered
  audio conversion or leave the source unchanged.
- A saved-workflow audio card converts every retained audio track to one chosen
  format. By itself it packet-copies video and text subtitles; with a video card
  both conversions share one FFmpeg process. Use the default packet-copy behavior
  when any track's exact layout or sample rate is not accepted by the chosen
  audio format.
- **If needed: Convert video unless it is already AV1 or HEVC** intentionally
  skips both video and its dependent audio card for modern sources. Other
  applicable metadata, subtitle, or naming cards can still run without a video
  encode.

## Subtitle, chapter, trim, or join results are refused

- Subtitle cleanup keeps every uncertain spelling correction reviewable. If
  cleanup would remove every cue or event, restore at least one or cancel.
- Nested Matroska chapters are the default. Ordered editions and unsupported
  chapter structures may be refused rather than flattened silently.
- Fast Trim discloses keyframe-adjusted boundaries. Choose Exact Trim when the
  requested numeric boundary must be encoded exactly.
- Join uses hard boundaries only. If track layouts are ambiguous, resolve the
  native mapping table. Incompatible sources must be converted to one reviewed
  common format; video normalization is fused into one encoded generation.

## The original was moved to Trash

Trash-after-verified-success is always explicit and occurs only after the new
output has passed its verification contract. Use Finder's Trash to review or
restore the original. Do not empty Trash until the output has also passed your
Jellyfin/Plex playback checks.

## Collect privacy-safe support evidence

1. Open Window → History (Command-3).
2. Select the job and read its sanitized lifecycle.
3. Choose **Export Privacy-Safe Report…** and save the JSON locally.
4. Open the report yourself before sharing it.

The report is bounded and includes a fixed privacy-safe failure category for
failed jobs. It omits filenames, paths, media/track/chapter titles,
subtitle text, custom workflow names, raw tool output, security bookmarks,
credentials, persistent identifiers, and exact timestamps. It is never
uploaded automatically.

When reporting a defect, include the app version/build, macOS version,
architecture and broad Mac class, workflow type, coarse container/codec facts,
the exact visible status, whether the original and destination still exist, and
the privacy-safe report if you choose. Do not attach private media, subtitle
text, personal paths, credentials, or raw local History files to a public issue.

## Advanced downloaded-release verification

Keep `SHA256SUMS` beside the downloaded release assets and run:

```sh
shasum -a 256 -c SHA256SUMS
```

A checksum match proves byte identity with the published manifest; it does not
replace Gatekeeper, signature, notarization, stapling, launch, or real-workflow
acceptance.
