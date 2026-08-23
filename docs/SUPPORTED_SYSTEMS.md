# Supported systems

MKV Magic currently targets macOS 13 Ventura or newer and ships as one
Universal application containing native `arm64` and `x86_64` slices.

- Apple Silicon: M1 or newer.
- Intel: any Mac capable of running macOS 13.
- Bundled tools: no Homebrew or separate FFmpeg/MKVToolNix install is required.
- Network: media work is local; only the separately sandboxed, user-invoked
  Sparkle updater may access the update feed.

Hardware encode availability varies by Mac model. MKV Magic detects and
previews the chosen path before execution. VideoToolbox H.264/HEVC is preferred
when it meets the workflow's compatibility policy; unsupported operations fall
back only to an explicitly available software encoder. AV1 decoding is bundled.
Software AV1 encoding remains a planned v1 runtime addition and is not claimed
by the foundation build.

Release acceptance requires native Apple Silicon verification and Rosetta
x86_64 verification in CI. Before the first public release, the downloaded app
must also be installed and exercised on physical Intel and Apple Silicon Macs.
