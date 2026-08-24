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
verification. A checksum-pinned libopus encoder is statically linked for stable
Opus audio output; AC-3, E-AC-3, and FLAC use FFmpeg's maintained encoders and
are likewise offered only after a local smoke encode. Statically linked dav1d
software decoding lets Macs without AV1 decode hardware reopen AV1 inputs and
MKV Magic outputs. Statically linked zimg provides the PQ-aware `zscale` filter
needed for locally verified HDR-to-SDR conversion without adding a dynamic
runtime dependency. If software AV1 cannot
complete the local encode probe, it is not offered; a verified hardware HEVC
path remains the preferred faster fallback on older Intel Macs.

The optional **Encoding Test…** performs a longer, three-second local comparison
of the verified AV1 and HEVC paths. It uses a generated 640×360 10-bit pattern,
never library media, and records only bounded speed, bitrate, and PSNR metrics in
the private app-support directory. The result is invalidated when the bundled
FFmpeg hash, running architecture, or active processor count changes. An
estimated 1080p AV1 speed below `0.5×` real time recommends verified HEVC as the
initial selection while leaving AV1 available. Physical Intel performance
acceptance remains required before the first public release.

Exact Trim and common-format Join can transcode a validated static HDR10 signal
through verified 10-bit AV1 or HEVC. They preserve BT.2020/PQ limited-range color,
matrix, mastering-display, and content-light metadata and reject output drift.
To preserve an HDR10 output, all sources in that joined video lane must carry
the same static metadata.
AV1 preserves the signal in its encoded stream and MKV; HEVC VideoToolbox is
guaranteed only for the MKV container metadata. Common-format Join can combine
BT.709 SDR and validated static HDR10 by tone-mapping only the HDR10 Parts to a
verified BT.709 SDR result. SDR-to-HDR conversion, HDR10+, HLG, and Dolby Vision
transcoding remain unavailable.

**Convert Video…** supports the same validated BT.709 SDR and static-HDR10
one-generation contract for the complete duration of an eligible Matroska MKV.
It currently requires one video track plus audio, preserves audio by default,
preserves attachments and the unchanged nested chapter tree, and creates MKV.
Subtitle/data tracks, multiple video tracks, source tags, non-MKV input/output,
and unsupported HDR families are refused before encoding.

Release acceptance requires native Apple Silicon verification and Rosetta
x86_64 verification in CI. Before the first public release, the downloaded app
must also be installed and exercised on physical Intel and Apple Silicon Macs.
