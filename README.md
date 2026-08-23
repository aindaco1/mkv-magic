# MKV Magic

MKV Magic is a local-first, lossless-first macOS application for inspecting,
cleaning, editing, muxing, joining, trimming, transcoding, and automating MKV
and other common media files.

The product is named **MKV Magic**. The repository and workspace directory are
named `mkv-magic`; the internal Swift package and executable are `MKVMagic`.

## Status

The release foundation and first local inspection vertical slice are in place.
The app can recursively discover media, inspect files with its bundled FFprobe
and MKVToolNix runtime, and present normalized file, track, chapter, attachment,
and tag facts without modifying the source. Executable metadata actions edit a
Matroska segment title or one track's name, language, playback flags, and roles
on a temporary clone. They verify every unrelated track and structure fact,
then commit a new output without replacing the original. Track removal remuxes
retained streams without encoding, preserves their order, chapters, tags, and
attachments, and uses the same verify-before-commit rule. A deterministic Clean
MKV preview can suggest English-library subtitle removals for individual review.
The native Workflows builder can name, duplicate, reorder, enable, save, import,
and export portable recipes. Its first reusable actions are English Library
Cleanup and segment-title removal. Workflows store intent rather than media
paths or track identifiers, compile against the selected inspection, show a
zero-encode impact preview, and share one verified output pipeline.
Selected SRT, ASS, and SSA files can also be decoded, structurally normalized,
and reviewed cue by cue for deterministic YTS/YIFY advertisement removal and
accidental edge whitespace. Cleanup preserves every timestamp and, for ASS/SSA,
the script sections, style definitions, override tags, layout fields, comments,
and unknown sections. It refuses to remove every event, detects a source changed
since preview, writes a new UTF-8 subtitle, and reopens the exact planned result
before commit while leaving the source intact.
For inspected Matroska video, **Add Subtitle…** accepts a reviewed external SRT,
ASS, or SSA file, ranks the filename and timing match, infers editable
language/forced/SDH metadata, and adds it as the last track in a new MKV without
encoding. Existing tracks, chapters, tags, and attachments are verified before
and after commit. Styled subtitles receive an additional `mkvextract` audit of
their header, styles, layout, timing, and text; both selected inputs remain
unchanged.
Every action's sanitized queue lifecycle is persisted atomically in the app's
private Application Support container and is available from the lightweight
History report. No public release is available yet. The canonical product and
delivery plan is [PRODUCT_SPEC.md](PRODUCT_SPEC.md).

## Design promises

- Avoid transcoding whenever metadata editing, remuxing, appending, or stream
  copying can satisfy the request.
- Encode video no more than once for each final output.
- Preserve originals until a result passes its declared verification contract.
- Process locally without telemetry, accounts, uploads, LLMs, or an ambient
  Homebrew/runtime dependency.
- Ship as a Universal Developer ID-signed and Apple-notarized macOS app.

## Development

Requirements:

- macOS 13 or newer
- Xcode 16 or newer with Swift 6
- `rg`, `shellcheck`, and standard Apple command-line developer tools

Run the supported source gate:

```sh
./scripts/ci/validate.sh
```

Build and launch the Swift executable during development:

```sh
swift run MKVMagic
```

Media tools are resolved only from an explicit development tool root or from
the packaged app. The runtime never silently uses `/opt/homebrew`,
`/usr/local`, or the process `PATH`.

## License

MKV Magic is licensed under GPL-3.0-or-later. Bundled components retain their
own licenses and notices; see `THIRD_PARTY_NOTICES.md` in release artifacts.
