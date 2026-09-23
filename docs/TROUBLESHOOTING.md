# MKV Magic troubleshooting

## Verify & Run does nothing, or History has no failure

In builds with the new diagnostic journal, choose **Help > Report a Problem…**
after reproducing the problem. **Export Local Diagnostics…** works independently
of History and the media tools. Early errors are shown in the main window and
recorded with a typed failure category; older builds cannot reconstruct them.
You can optionally review a sanitized report and choose **Send Reviewed Report**
directly in the app. No browser or system crash-file import is required. Nothing is sent merely
by opening the window. See [support diagnostics](SUPPORT_DIAGNOSTICS.md) for
privacy, retention, and current relay availability.

## Saving asks again or access to Movies/Desktop is denied

Output settings apply to all media outputs and exports. Choose a default folder
in Settings to save there automatically, or use Beside Source. Only Ask Every Time
shows a save dialog. Source-less reports and workflows remember an export folder.

macOS distinguishes permission for one output file from permission for its folder.
Verified temporary copies and queued jobs need folder access. If prompted, select
the indicated output folder and choose **Allow Access**. This permission is
remembered for later saves. If access was revoked or the folder moved, choose it
again in Settings; do not grant broad Full Disk Access or disable the sandbox.
Automatic saves add a number when a filename is already present.

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
- The official Universal app runs natively on both Apple Silicon and Intel. If
  an Apple Silicon test Mac reports that MKV Magic includes an Intel-based
  component, confirm the app came from the official DMG and has not been forced
  to open with Rosetta. A maintainer's deliberate Rosetta verification can also
  leave this macOS warning behind; normal release verification no longer uses
  translated execution, and physical Intel hardware owns Intel acceptance.

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

For the direct sidecar flow, select or drag exactly one compatible MP4, M4V,
MOV, or chapter-free WebM and exactly one SRT, ASS, or SSA. Select both rows if
they were added separately, then choose **Remux Video + Subtitle…**. Review the
audio and subtitle language fields before running; filename inference is only a
default and never blocks manual correction.

## Preview and save a track edit

In **Edit a Track…**, choose the track, then change its name, language, or a
playback flag. Selecting a different track alone is not a change. Equivalent
language codes such as `eng` and `en` are also treated as unchanged.
**Preview Changes** becomes available as soon as a valid value differs from
the source. Correct any language error shown below the form; the feedback
updates while you type or choose a language.

After **Preview Changes**, use **Verify & Run** in the main window to create
and save a new verified MKV copy. Preview does not write to the source file.

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
- Output saves beside a source automatically only while macOS grants access to
  that directory. Otherwise the save panel asks before work starts. Use **MKV
  Magic → Settings…** to remember one default output folder or ask where to save
  every time. Batch review requires one selected or remembered output folder.
  Existing destinations are never overwritten; MKV Magic adds a numeric suffix
  to the new output name.

## MKV Magic refuses an output

- Reinspect the source and review the plan again. A file changed after review
  is deliberately rejected.
- Choose a new destination. MKV Magic never silently overwrites an existing
  file.
- If a job reached **Committing** and then stopped, choose a local writable
  folder through the save panel. A privacy-safe report distinguishes denied
  permission from a destination filesystem that cannot provide the required
  no-overwrite commit operation.
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
- **Tries** counts media executions, not review or destination prompts. A
  freshly reviewed retry keeps the existing row and advances the count when
  temporary-output creation starts.
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
  MKV Magic also compares the decoder initialization data that FFprobe reports.
  This catches streams whose visible H.264 or HEVC properties look identical but
  cannot be appended cleanly. When the only mismatch is H.264 initialization and
  frame cadence is preserved, **verified lossless repair** applies a packet-copy
  header filter in a private remux so every Part retains the headers it needs. No
  frames are encoded. Strict packet and boundary audits still reject the output
  before commit if repair is not clean; Common Format remains the fallback.

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

The report is bounded and includes fixed privacy-safe failure categories for
failed History and production-queue jobs. Queue entries also include their last
active coarse stage, attempt count, and state. A join-boundary decode failure
includes only the validated one-based boundary number so adjacent source parts
can be identified locally.
It omits filenames, paths, media/track/chapter titles,
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
