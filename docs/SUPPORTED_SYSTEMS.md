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
network request. The current runtime can expose statically linked SVT-AV1
10-bit software encoding, VideoToolbox H.264/HEVC, ProRes, and AAC after
verification. Statically linked dav1d software decoding lets Macs without AV1
decode hardware reopen AV1 inputs and MKV Magic outputs. If software AV1 cannot
complete the local encode probe, it is not offered; a verified hardware HEVC
path remains the preferred faster fallback on older Intel Macs.

Release acceptance requires native Apple Silicon verification and Rosetta
x86_64 verification in CI. Before the first public release, the downloaded app
must also be installed and exercised on physical Intel and Apple Silicon Macs.
