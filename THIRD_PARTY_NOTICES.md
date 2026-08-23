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
