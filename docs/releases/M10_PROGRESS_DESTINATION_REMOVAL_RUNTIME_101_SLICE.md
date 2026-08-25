# M10 progress, destination, removal, and MKVToolNix 101 slice

This slice responds to hands-on beta feedback without changing MKV Magic's
verified-output or local-only boundaries.

## User-facing behavior

- The main footer now exposes one accessible indeterminate activity indicator
  for discovery, inspection, plan preparation, and execution. Every immediate
  verified output also opens a cancellable progress sheet whose text follows the
  model's current local stage.
- Queue mutations and active queue jobs, Encoding Test, workflow-library saves,
  Trim review, Chapter Studio analysis and thumbnails, and History report export
  expose their own compact native activity indicators.
- Every inspected-file row has a remove action, and the selected row also
  responds to Delete. The action only removes the asset and its inspected
  revision from in-memory app state. It never calls a filesystem deletion API.
- Every media output save panel selects the original file's directory by
  default and explicitly explains that the standard panel can select another
  directory. The save panel remains the security-scoped authorization boundary.

## Runtime update

The runtime builder pins the official Universal MKVToolNix 101.0 DMG and its
corresponding source archive. Both SHA-256 values match the upstream checksum
files. Qt Core remains at 6.11.1, matching the library embedded in the official
101.0 DMG.

The rebuilt `arm64` and `x86_64` tool trees each report MKVToolNix 101.0 and pass
the exact file hash, architecture, code-signature, deployment-target, packaged
dependency, license, and source-manifest checks.

## Regression evidence

- The AppKit policy suite covers busy-state messages, destination default and
  alternate-folder language, generic verified-output progress updates, and
  in-app removal.
- A UI regression clicks the new remove control against a real temporary source
  and proves that the source bytes remain unchanged.
- The complete test suite ran against the rebuilt MKVToolNix 101.0 and FFmpeg
  9.0.1 runtime: 711 tests passed with zero failures, including all real-tool
  inspection, metadata, subtitle, chapter, attachment, tag, trim, conversion,
  queue, and join paths.
