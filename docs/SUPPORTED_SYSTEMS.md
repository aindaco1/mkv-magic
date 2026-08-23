# Supported systems

MKV Magic currently targets macOS 13 Ventura or newer and ships as one
Universal application containing native `arm64` and `x86_64` slices.

- Apple Silicon: M1 or newer.
- Intel: any Mac capable of running macOS 13.
- Bundled tools: no Homebrew or separate FFmpeg/MKVToolNix install is required.
- Network: media work is local; only the separately sandboxed, user-invoked
  Sparkle updater may access the update feed.

Hardware encode availability varies by Mac model. MKV Magic reads the bundled
FFmpeg capability tables and then runs bounded one-frame local smoke encodes;
only paths that actively succeed on the running Mac are offered. The probe uses
generated raw fixtures in a private temporary directory, never user media or a
network request. The current runtime can expose VideoToolbox H.264/HEVC, ProRes,
and AAC after verification. AV1 decoding is bundled. Software AV1 encoding
remains a planned v1 runtime addition and is neither present nor claimed by the
current build.

Release acceptance requires native Apple Silicon verification and Rosetta
x86_64 verification in CI. Before the first public release, the downloaded app
must also be installed and exercised on physical Intel and Apple Silicon Macs.
