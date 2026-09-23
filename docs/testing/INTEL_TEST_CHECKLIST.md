# MKV Magic 0.3.0-test.21 — Intel test checklist

This is a private Universal test candidate for **macOS 13 Ventura or newer**.
It contains native Intel and Apple Silicon code and bundled media tools.
It is Developer ID-signed but **not notarized or publicly released**. Record
any macOS trust warning; do not disable Gatekeeper or remove quarantine flags.
Keep a copy of the previously installed app for rollback.

This candidate includes the reviewed folder-remux and durable batch follow-ups,
bulk metadata/text-subtitle extraction/relative trims, and background authoring.
Its version/build identifies the hardware test precisely. Do not downgrade
while new reviewed-edit jobs are pending; older apps may not understand them.

## Included generated samples

- `Sample.ENGLISH.mp4` and `Sample.es.srt`: a four-second generated video/audio
  clip and two short Spanish subtitle cues.
- `Second Sample.ENGLISH.mp4` and `Second Sample.es.srt`: independent copies for
  a second queue job. The media content is intentionally identical.
- `First Batch Sample.mkv` and `Second Batch Sample.mkv`: generated video/audio
  with an embedded Spanish subtitle and frequent keyframes for short batch trims.
- `SHA256SUMS`: input checksums. The originals should still match after testing.

No private media is included. Use distinct output names and keep all originals.
The short samples exercise remux/queue behavior, not long-run playback quality,
complex subtitles, HDR, or real-world join boundaries.

## Priority Intel pass

1. **Install and identify.** Quit MKV Magic, mount the test.21 DMG, and copy the
   app to Applications. Eject the DMG and launch the installed copy. Confirm
   About shows `0.3.0-test.21`; record its build, Mac model, and macOS version.
   No separate tool installation should be necessary.
2. **Review an MP4 + SRT pair.** Add the first pair together. Select both rows
   and choose **Remux Video + Subtitle…**. Confirm English audio and Spanish
   subtitles are proposed, both are editable, and the plan shows no encoding.
3. **Two jobs across relaunch.** Pause automatic starts in Queue. Review and
   add each sample pair as its own job, with different MKV output names. Expect
   two Waiting rows and Tries 0. Quit completely, reopen the installed app,
   and resume once without reselecting either input. Both jobs should finish
   Succeeded, Tries 1, with no pending work.
4. **Inspect and play outputs.** Each output should contain one video track,
   English audio, and Spanish subtitles. Confirm the subtitle cues display and
   the clip seeks/plays. Check History for each complete successful lifecycle
   and readable/selectable job details. Repeat with a representative personal
   file to assess actual playback quality; the generated clip is minimal.
5. **Review Again and Tries.** If a real job fails, record its diagnosis first.
   After correcting the cause, choose **Review Again** on that same row and
   approve a fresh plan. Opening review alone must not increment Tries; starting
   the next attempt must increment it. Old jobs whose temporary source files
   have disappeared are not suitable retry fixtures.
6. **Appearance and editing.** Check Settings → System / Light / Dark, readable
   History details, the sidebar, and the track editor at a compact window size.
   Change a name or flag, Preview Changes, and save a distinct verified copy.
7. **Clean MKV and a longer batch.** Use expendable copies of representative
   MKVs, including one without removable subtitles. Review every suggested
   change, especially language-based subtitle choices. Queue several jobs and
   confirm later batches start, History remains complete, and Pause blocks new
   automatic starts without destroying running work. Cancel a longer job
   before commit; the source must remain unchanged.
8. **New bulk tools.** Select both MKV samples. In Edit Matching Tracks, set
   Audio language to fr while leaving other fields unchanged. Review the per-track
   changes, exclude one file, and check only the included copy is queued. Repeat
   for both files. Extract Subtitles should offer one SRT per source. Trim
   Beginnings / Ends with 0.5 seconds at each end must disclose actual keyframe
   ranges and zero encodes. Check outputs and unchanged-source checksums.
9. **Background authoring.** While a longer automatic job runs, import and
   prepare another batch. Eligible controls remain enabled; foreground
   preparation temporarily blocks authoring. The second job must be picked up
   automatically. Repeat pause/relaunch with new reviewed-edit jobs pending.
10. **Report.** Export a fresh privacy-safe support report after the pass. Include
   the version/build, Mac/macOS details, passed steps, and screenshots of any
   failure. Keep private filenames and media out of public issue reports.

## Separate public-release gates

Passing this checklist on Intel does not automatically clear clean-account
Apple Silicon installation, prior-version updater replacement, extended mixed
queues, full accessibility/novice sessions, or real-library playback. An
unnotarized private installer is not the final notarized/hosted release artifact;
the final artifact requires its own checks on both architectures.
