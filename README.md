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
and tag facts without modifying the source. The first executable action edits a
Matroska segment title on a temporary clone, verifies that tracks, chapters,
attachments, duration, tags, and segment identity stayed intact, then commits a
new output without replacing the original. Its sanitized queue lifecycle is
persisted atomically in the app's private Application Support container. Other
editing actions remain disabled until they meet the same transaction contract.
No public release is available yet. The canonical product and delivery plan is
[PRODUCT_SPEC.md](PRODUCT_SPEC.md).

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
