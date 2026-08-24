# MKV Magic corresponding source

This archive accompanies a binary MKV Magic release. It contains:

- the complete MKV Magic source tree for the exact release commit;
- checksum-pinned FFmpeg, SVT-AV1, dav1d, libopus, zimg, MKVToolNix, and Qt
  source archives corresponding to the distributed media runtime;
- the pinned NASM source used as a build-only dependency for x86_64 FFmpeg;
- `SOURCES.json`, which records versions, upstream URLs, hashes, licenses, and
  the network-disabled FFmpeg and static AV1, Opus, and zimg library boundaries.

The build entry point is `scripts/tools/build-runtime.sh` in the MKV Magic
source archive. Application assembly and release scripts are under
`scripts/release/`. No proprietary build service or private dependency is
required to build the distributed open-source code, although Apple-issued
credentials are required to reproduce the Developer ID signature and
notarization ticket.
