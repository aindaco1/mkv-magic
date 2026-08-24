# Third-party software notices

This source tree and MKV Magic release artifacts include or are designed to
bundle the components below. A release is invalid unless the generated tool
manifest, build configuration, source links, checksums, license texts, and this
notice agree with the actual distributed bytes.

## Sparkle 2.9.5

- Project: https://github.com/sparkle-project/Sparkle
- License: MIT
- Purpose: user-initiated, signed application updates
- Distribution: `Sparkle.framework`, including its reviewed sandboxed updater
  services

The full Sparkle license is copied from the locked Swift package checkout into
every app bundle.

## FFmpeg 9.0.1

- Project: https://github.com/FFmpeg/FFmpeg
- License: GPL-3.0-or-later for MKV Magic's pinned GPLv3 configuration
- Purpose: media inspection, stream copy, filtering, encoding, thumbnails, and
  verification

MKV Magic builds FFmpeg from checksum-pinned source with network protocols and
ambient dependency discovery disabled. The exact configure flags and source
archive hash are recorded in each release's build metadata.

## SVT-AV1 4.1.0

- Project: https://gitlab.com/AOMediaCodec/SVT-AV1
- License: BSD-3-Clause-Clear and Alliance for Open Media Patent License 1.0
- Purpose: software AV1 10-bit encoding through the bundled FFmpeg
- Distribution: architecture-specific static library linked into `ffmpeg`

MKV Magic builds separate checksum-pinned ARM64 and x86_64 static libraries,
with native-machine optimization disabled and runtime CPU dispatch retained.
The software and patent license texts are included in every tool bundle, and
the matching source archive is included in corresponding source releases.

## dav1d 1.5.4

- Project: https://code.videolan.org/videolan/dav1d
- License: BSD-2-Clause
- Purpose: software AV1 decoding through the bundled FFmpeg
- Distribution: architecture-specific static library linked into `ffmpeg`

MKV Magic builds separate checksum-pinned ARM64 and x86_64 static libraries so
Macs without hardware AV1 decoding can reopen and process AV1 files, including
files created by MKV Magic. The license is included in every tool bundle, and
the matching source archive is included in corresponding source releases.

## libopus 1.6.1

- Project: https://opus-codec.org/
- License: BSD-3-Clause
- Purpose: stable Opus audio encoding through the bundled FFmpeg
- Distribution: architecture-specific static library linked into `ffmpeg`

MKV Magic builds separate checksum-pinned ARM64 and x86_64 static libraries and
does not expose FFmpeg's experimental native Opus encoder. The Opus license is
included in every tool bundle, and the matching source archive is included in
corresponding source releases.

## MKVToolNix 100.0

- Project: https://codeberg.org/mbunkus/mkvtoolnix
- License: GPL-2.0-or-later for the distributed command-line tools
- Purpose: Matroska inspection, property editing, muxing, chapters, attachments,
  and extraction

MKV Magic thins the checksum-pinned official Universal macOS build into exact
ARM64 and x86_64 runtime trees. The matching checksum-pinned source archive is
published with each MKV Magic release.

## Qt Core 6.11.1

- Project: https://www.qt.io/product/framework
- Source: https://download.qt.io/official_releases/qt/6.11/6.11.1/submodules/
- License: LGPL-3.0-only or GPL-2.0-only; MKV Magic distributes it under
  LGPL-3.0-only
- Purpose: runtime dependency of the bundled MKVToolNix command-line tools

The Qt Core dynamic library remains replaceable inside the app bundle. MKV
Magic does not apply DRM or contractual restrictions that prevent relinking or
replacement. Qt's license texts, matching checksum-pinned source, and relevant
third-party notices are included with every release.
