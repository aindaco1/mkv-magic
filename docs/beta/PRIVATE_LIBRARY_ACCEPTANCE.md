# Private-library acceptance

This is the operator loop for testing MKV Magic on private media without adding
the media or identifying library data to the repository. A generated support
report is evidence about what the app recorded; it is not proof of playback or
user acceptance by itself.

## Privacy boundary

Private media stays outside the checkout. `BetaReports/` and files matching the
default support-report name are ignored by Git. Do not commit media, subtitle
text, screenshots containing library names, raw History files, console output,
or generated reports without reviewing them first.

For jobs created by the current app, History stores coarse facts alongside the
local display names needed by the on-device UI. The export is constructed from
the coarse fields rather than by trying to redact raw History afterward. It
contains:

- app version, build, macOS version, architecture, and verified bundled-tool
  names, versions, and digests;
- built-in workflow class, or `savedOrUnknown` without the custom name;
- file-size and duration buckets, container and codec families, track counts,
  maximum audio channels, and HDR/chapter/attachment/tag/warning counts;
- planned video generations and encoded-audio-track count when the job recorded
  them; and
- lifecycle states, terminal result, last active stage, and an elapsed-time
  bucket.

It excludes filenames, every path, media/track/chapter titles, subtitle text,
custom workflow names, raw tool output, security bookmarks, job/input UUIDs,
exact timestamps, tool source URLs, and license text. Jobs created by an older
build remain readable but may have `null` coarse facts or plan facts.

The export stays local until the user opens History, clicks **Export
Privacy-Safe Report…**, and chooses a destination. The file is capped at the 500
newest jobs and one megabyte and is written with owner-only permissions.

## Prepare a private matrix

Keep the case list in a private location. Use opaque case labels such as `B001`;
do not put media names in repository documents. Select the smallest set that
covers the media actually used with Jellyfin and Plex:

- H.264, HEVC, and AV1 video; SDR and HDR10 where available;
- AAC plus representative 5.1 or 7.1 audio, including every mix that must be
  preserved;
- SRT, ASS/SSA, PGS, VobSub, forced, SDH, commentary, and no-subtitle cases;
- attachments, tags, multiple editions, nested chapters, and files without
  chapters;
- variable frame rate, delayed audio, unusual track order, and large files; and
- compatible joins, deliberately incompatible joins, and three-part joins with
  nested source chapters.

Do not manufacture a claim for a missing category. Mark it `not available` and
add a redistributable or generated fixture gap when possible.

## Run each case

1. Record the opaque case label, intended workflow, expected preservation, and
   whether the run is an ordinary operation, cancellation, or fault check in the
   private worksheet.
2. Open or drag the source into MKV Magic. Confirm the displayed container,
   tracks, roles, HDR status, attachments, tags, duration, and chapters before
   editing.
3. Review the proposed action and encode impact. A metadata edit should use no
   remux; track/subtitle/chapter changes should avoid video encoding; compatible
   joins should copy packets; a transcoding workflow should show at most one
   video generation.
4. Save to a new destination. Never reuse the only copy of a source during beta
   testing. If the app refuses the case, record the visible stage and wording;
   refusal can be the correct safe result.
5. Reopen the output in MKV Magic and compare tracks, flags, HDR facts,
   attachments, tags, nested chapters, and duration with the reviewed intent.
6. Play representative beginning, middle, end, trim points, and join boundaries
   in both the relevant Jellyfin client and Plex when the workflow affects them.
   Check audio mix, subtitle selection/timing/style, seeking, chapter navigation,
   and HDR behavior on the actual client.
7. Confirm the original still exists and was not changed. Exercise the optional
   Trash-after-verified-success behavior only on expendable duplicates until its
   complete recovery flow is accepted.
8. Open History and confirm the job reached the truthful terminal state. Export
   a privacy-safe report after a useful batch, open the JSON locally, and search
   for any private term before sharing it.

## Priority passes

Run implemented zero-encode paths first: inspection, metadata/track cleanup,
external and embedded text-subtitle cleanup/muxing, and nested chapter editing.
Then run Fast and Exact Trim, compatible lossless joins, and common-format joins.
Full AV1/HDR transcoding and production-queue soak acceptance remain separate
M6/M7 work; do not interpret this report feature as their completion.

For performance, record hardware model/class, architecture, macOS version,
workflow class, coarse input facts, wall time, peak memory, output size ratio,
responsiveness, cancellation latency, and thermal observations. Do not record
paths or titles. Use the checked-in packet-audit benchmark only on an unchanged
read-only source and keep its report separate from playback acceptance.

## Turn failures into durable coverage

For every defect:

1. preserve the private source outside Git;
2. record the opaque case, failed stage, observed result, and expected result;
3. reduce the behavior to generated or redistributable media when possible;
4. add a regression test at the lowest useful layer before changing the code;
5. rerun the exact workflow, source gate, bundled-tool suite, and proportionate
   package/security gate; and
6. record whether the private case passed afterward without adding identifying
   data to the commit.

M8 is accepted only when the agreed personal workflows pass repeatably on the
M1 server workflow and at least one physical Intel Mac. Apple Silicon-only local
tests, a green generated-fixture suite, or an exported JSON file do not satisfy
that gate.
