# MKV Magic app icon

The selected production artwork is the black-and-white **Nested Container**
concept. Its three nested rounded frames evoke Matroska's nested container
structure, the play mark identifies media, and the four-point sparkle carries
the MKV Magic identity.

## Files

- `MKVMagic-master-1024.png` is the transparent production master.
- `MKVMagic.iconset` contains the ten standard 16 px through 1024 px macOS icon
  representations.
- `MKVMagic.icns` is the compiled bundle resource installed by
  `scripts/release/build-app.sh`.

The icon source is raster artwork. Preserve the master and regenerate every
iconset representation from it with high-quality downsampling before rebuilding
the ICNS with Apple's `iconutil`. Do not independently edit smaller sizes.

Run `scripts/ci/check-app-icon.sh` to verify the master and all ten compiled
representations. `scripts/ci/check-app-bundle.sh` separately verifies that the
release app contains the icon declared by `CFBundleIconFile`.
