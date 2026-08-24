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
one-generation contract for the complete duration of eligible MKV, MP4, M4V,
MOV, and chapter-free WebM input and always creates MKV. Eligible MKV input may
preserve supported audio and subtitle tracks, attachments, and the unchanged
nested chapter tree. Common input requires one video, no subtitles or
attachments, unambiguous data/chapter facts, and only reviewed title/track
metadata plus known container provenance. MP4/MOV chapters become one default
nested Matroska edition. Compatible audio and MKV subtitles are packet-copied
and fingerprinted before commit and after reopen; other common audio must use an
offered layout-preserving conversion. Ambiguous data, chaptered WebM, multiple
video tracks, source tags on MKV, non-MKV output, incomplete color facts, and
unsupported HDR families are refused before encoding.

Portable saved workflows share this complete-file path. Common-container input
requires one applicable video-conversion card and may add only one fused
audio conversion plus filename cleanup. MKV-only edits are refused for that
source, the reviewed output name is forced to `.mkv`, and automatic queue
reinspection must reproduce the same one-generation plan. Compatible
Matroska-only operations remain governed by their individual feature boundaries.

**Extract Subtitle…** supports embedded SRT, ASS, and SSA tracks in inspected
Matroska files independently of video-encoder hardware. Bundled `mkvextract`
writes one selected track privately; MKV Magic repeats the extraction, compares
the exact bytes and parsed timing/style document, binds the source revision and
stable track UID through commit, and reopens the separate same-format sidecar.
The MKV remains unchanged. PGS and VobSub extraction is not included in this
single-file text-subtitle path.

**Attachments…** supports non-empty embedded Matroska attachments up to 512
MiB independently of video-encoder hardware. Bundled `mkvextract` writes one
selected attachment privately; MKV Magic repeats the extraction, compares the
exact byte count and streaming SHA-256 digest, binds the source revision and
stable attachment UID through commit, and reopens the separate regular file.
The MKV remains unchanged. Adding, replacing, batch-extracting, and
workflow-driven attachment operations are not included in this direct action.

**Remove Attachments…** supports explicit removal of one or more attachments
from an inspected Matroska file independently of video-encoder hardware.
Bundled `mkvmerge` creates a new zero-encode MKV containing only the retained
attachment IDs. MKV Magic binds the reviewed selection to stable unique UIDs,
checks the source revision throughout execution, and verifies every retained
attachment fact, media track, tag, nested chapter, duration, and metadata value
before commit and after reopen. Normal attachment-ID renumbering is allowed;
UID or content-fact drift is not. The original remains unchanged.

**Tags…** supports exact full-document XML export and clear-all tag removal for
inspected Matroska files independently of video-encoder hardware. Export uses
bundled `mkvextract`, is capped at 16 MiB, refuses unsafe XML constructs, and
requires the repeated bytes, digest, root, and global/track entry counts to
match before and after commit. Removal uses bundled `mkvpropedit` on a new MKV
clone, independently re-extracts the result to prove that no global or track
tag entry remains, and preserves the segment title, tracks, nested chapters,
attachments, duration, metadata outside the cleared tags, and segment UID. The
original remains byte-unchanged. Selected-entry editing/replacement and
workflow, queue, and batch tag actions are not included in this direct action.

**Convert MP4 Subtitle…** supports TX3G/`mov_text` tracks in inspected MP4,
M4V, and MOV files independently of video-encoder hardware. Bundled FFmpeg
converts one selected track to a separate UTF-8 ASS file; MKV Magic repeats and
compares the parsed conversion, binds the source revision through commit, and
reopens the result. The video remains unchanged. TX3G is not yet converted
inline during Remux to MKV or complete video conversion.

Release acceptance requires native Apple Silicon verification and Rosetta
x86_64 verification in CI. Before the first public release, the downloaded app
must also be installed and exercised on physical Intel and Apple Silicon Macs.
