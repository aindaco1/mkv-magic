# M10 join warning, output destination, and multi-delete slice

This slice responds to the v0.1.6 Intel support report and hands-on file-list
feedback. It retains MKV Magic's local-only, sandboxed, verified-output
boundaries.

## Join investigation and correction

The privacy-safe report contains two three-input lossless joins that failed in
the running stage in under ten seconds. Every input is Matroska with one H.264
video, AAC stereo audio, SubRip subtitle, tags, and 42–46 chapters. The plan has
zero audio or video encodes. Because v0.1.6 intentionally omits raw tool output,
the report cannot disclose the exact warning text.

The reproduced three-input H.264/AAC/SubRip join passes with bundled
MKVToolNix 101.0 on Apple Silicon and with the x86_64 test bundle under Rosetta.
That rules out the generic three-file layout, tool version, and Intel command
shape. The remaining execution-only failure path was `--abort-on-warnings`,
which converted a completed `mkvmerge` warning into a fatal exit before MKV
Magic could inspect the output.

Lossless join now accepts `mkvmerge` exit code 1 as a warning completion. This
does not accept the output: the temporary file must still pass exact reviewed
track mapping, metadata, nested chapter, packet digest, unchanged-source, and
committed reopen audits. Exit code 2 or greater remains fatal. Future support
reports classify join source changes, tool failures, chapter mismatches, and
final-audit failures without exporting paths or raw output.

## Output and selection behavior

- **Beside each source automatically** is the default and opens no save panel.
- **In one chosen folder automatically** stores a narrow app-scoped directory
  bookmark and opens no save panel for media outputs.
- **Ask where to save every time** preserves the standard save-panel flow.
- Automatic destinations never overwrite. The first unused ` 2`, ` 3`, and so
  on suffix is chosen through one shared path-containment policy.
- Batch subtitle cleanup and batch workflow queueing inherit a remembered
  folder, while their existing review remains visible and overridable.
- Delete and Forward Delete use the media table's responder actions and remove
  every selected asset from app state. Source files remain byte-unchanged.

## Regression evidence

- Focused tests cover warning completion through every lossless-join audit,
  privacy-safe join failure mapping, default/remembered/ask output modes,
  collision numbering, Settings minimum-size layout, and multi-row removal
  through the real window responder path.
- A three-file H.264/AAC/SubRip fixture passes against bundled MKVToolNix 101.0
  on arm64 and x86_64 under Rosetta.
- The full source suite passes 726 tests with 52 intentional source-only
  real-tool skips and zero failures.

## Remaining acceptance

- Retry the three original MKVs and verify the resulting chapter hierarchy,
  subtitles, audio, and playback in Jellyfin/Plex.
- Confirm automatic beside-source writes for the user's normal Finder/open-panel
  intake paths and confirm the remembered-folder mode after relaunch.
- Complete clean-account Apple Silicon and physical Intel installation plus
  prior-version updater replacement against the exact candidate DMG digest
  before publication.
