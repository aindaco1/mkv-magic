#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_root="${1:-$repo_root/.build/tool-runtime}"
cache_root="${MKV_MAGIC_TOOL_CACHE:-$repo_root/.build/tool-sources}"
ffmpeg_version=9.0.1
ffmpeg_sha256=cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635
ffmpeg_url="https://ffmpeg.org/releases/ffmpeg-$ffmpeg_version.tar.xz"
nasm_version=3.02
nasm_sha256=87336eba53b4acfe917424ab5d500d2b0054d9f5148d35c2273ccf2cfb712f0d
nasm_url="https://www.nasm.us/pub/nasm/releasebuilds/$nasm_version/nasm-$nasm_version.tar.xz"
mkvtoolnix_version=100.0
mkvtoolnix_dmg_sha256=114e85cd42f3b0ea7ea0e194c5409d66dfdd49f4663a9d572009fd312dd279f1
mkvtoolnix_dmg_url="https://mkvtoolnix.download/macos/releases/$mkvtoolnix_version/MKVToolNix-$mkvtoolnix_version-1-universal.dmg"
mkvtoolnix_source_sha256=74480d07a261beeaa8baf898248e668ecc56335e2527bbffa841ef056dc028a1
mkvtoolnix_source_url="https://mkvtoolnix.download/sources/mkvtoolnix-$mkvtoolnix_version.tar.xz"
qt_version=6.11.1
qtbase_sha256=d9594a31228aa23ad6b531719a29b45f0f3989fe6c136d45767ea179f233c1ac
qtbase_url="https://download.qt.io/official_releases/qt/6.11/$qt_version/submodules/qtbase-everywhere-src-$qt_version.tar.xz"

if [[ "$output_root" != /* || "$output_root" == / || -e "$output_root" ]]; then
    echo "output root must be an absent absolute specific path" >&2
    exit 1
fi
if [[ "$cache_root" != /* || "$cache_root" == / || -L "$cache_root" ]]; then
    echo "unsafe tool cache root" >&2
    exit 1
fi

download_verified() {
    local url="$1"
    local expected="$2"
    local destination="$3"
    if [[ ! -f "$destination" ]]; then
        mkdir -p "$(dirname "$destination")"
        local partial="$destination.partial"
        if [[ -e "$partial" ]]; then
            echo "refusing existing partial download: $partial" >&2
            exit 1
        fi
        curl --fail --silent --show-error --location --output "$partial" "$url"
        local partial_hash
        partial_hash="$(shasum -a 256 "$partial" | awk '{print $1}')"
        if [[ "$partial_hash" != "$expected" ]]; then
            echo "download checksum mismatch: $url" >&2
            exit 1
        fi
        mv "$partial" "$destination"
    fi
    local actual
    actual="$(shasum -a 256 "$destination" | awk '{print $1}')"
    if [[ "$actual" != "$expected" || -L "$destination" ]]; then
        echo "cached source checksum mismatch: $destination" >&2
        exit 1
    fi
}

ffmpeg_archive="$cache_root/ffmpeg-$ffmpeg_version/ffmpeg-$ffmpeg_version.tar.xz"
nasm_archive="$cache_root/nasm-$nasm_version/nasm-$nasm_version.tar.xz"
mkvtoolnix_dmg="$cache_root/mkvtoolnix-$mkvtoolnix_version/MKVToolNix-$mkvtoolnix_version-1-universal.dmg"
mkvtoolnix_source="$cache_root/mkvtoolnix-$mkvtoolnix_version/mkvtoolnix-$mkvtoolnix_version.tar.xz"
qtbase_archive="$cache_root/qtbase-$qt_version/qtbase-everywhere-src-$qt_version.tar.xz"
download_verified "$ffmpeg_url" "$ffmpeg_sha256" "$ffmpeg_archive"
download_verified "$nasm_url" "$nasm_sha256" "$nasm_archive"
download_verified "$mkvtoolnix_dmg_url" "$mkvtoolnix_dmg_sha256" "$mkvtoolnix_dmg"
download_verified "$mkvtoolnix_source_url" "$mkvtoolnix_source_sha256" "$mkvtoolnix_source"
download_verified "$qtbase_url" "$qtbase_sha256" "$qtbase_archive"

build_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-tools.XXXXXX")"
mount_root="$build_root/mkvtoolnix-volume"
attached=0
cleanup() {
    local status=$?
    set +e
    if [[ "$status" -ne 0 ]]; then
        echo "tool runtime build failed with status $status" >&2
        for log_path in "$build_root"/*.log; do
            if [[ -f "$log_path" ]]; then
                echo "last lines of $(basename "$log_path"):" >&2
                tail -n 40 "$log_path" >&2
            fi
        done
        for config_log in "$build_root"/ffmpeg-*/ffbuild/config.log; do
            if [[ -f "$config_log" ]]; then
                echo "compiler diagnostics from $config_log:" >&2
                grep -A8 -B4 -E 'C11|error:|failed' "$config_log" | tail -n 80 >&2
            fi
        done
    fi
    if [[ "$attached" == 1 ]]; then
        hdiutil detach "$mount_root" -quiet 2>/dev/null || \
            hdiutil detach "$mount_root" -force -quiet 2>/dev/null
    fi
    /bin/rm -rf -- "$build_root"
    exit "$status"
}
trap cleanup EXIT

# Build the pinned assembler used only to preserve optimized x86_64 FFmpeg code.
tar -xJf "$nasm_archive" -C "$build_root"
nasm_source="$build_root/nasm-$nasm_version"
nasm_prefix="$build_root/nasm-install"
(
    cd "$nasm_source"
    ./configure --prefix="$nasm_prefix" >/dev/null
    make -j"$(sysctl -n hw.ncpu)" >/dev/null
    make install >/dev/null
)
nasm_binary="$nasm_prefix/bin/nasm"
if [[ ! -x "$nasm_binary" || "$($nasm_binary -v)" != "NASM version $nasm_version"* ]]; then
    echo "pinned NASM build failed" >&2
    exit 1
fi

mkdir -p "$output_root" "$output_root/Licenses"
for architecture in arm64 x86_64; do
    mkdir -p "$output_root/$architecture/libs"
done

# Thin the official, checksum-verified Universal MKVToolNix command-line tools.
mkdir "$mount_root"
hdiutil attach "$mkvtoolnix_dmg" -readonly -nobrowse -noautoopen \
    -mountpoint "$mount_root" -quiet
attached=1
mkvtoolnix_binary_root="$mount_root/MKVToolNix.app/Contents/MacOS"
for architecture in arm64 x86_64; do
    for tool in mkvmerge mkvpropedit mkvextract; do
        lipo "$mkvtoolnix_binary_root/$tool" -thin "$architecture" \
            -output "$output_root/$architecture/$tool"
        chmod 0755 "$output_root/$architecture/$tool"
        codesign --remove-signature "$output_root/$architecture/$tool" 2>/dev/null || true
    done
    lipo "$mkvtoolnix_binary_root/libs/libQt6Core.6.11.1.dylib" \
        -thin "$architecture" \
        -output "$output_root/$architecture/libs/libQt6Core.6.dylib"
    chmod 0755 "$output_root/$architecture/libs/libQt6Core.6.dylib"
    codesign --remove-signature \
        "$output_root/$architecture/libs/libQt6Core.6.dylib" 2>/dev/null || true
done
hdiutil detach "$mount_root" -quiet
attached=0

# Build static FFmpeg/FFprobe for each runtime architecture with no network
# protocols or ambient package discovery. The x86_64 build retains NASM paths.
sdk_root="$(xcrun --sdk macosx --show-sdk-path)"
clang="$(xcrun --sdk macosx --find clang)"
ar="$(xcrun --sdk macosx --find ar)"
nm="$(xcrun --sdk macosx --find nm)"
ranlib="$(xcrun --sdk macosx --find ranlib)"
strip="$(xcrun --sdk macosx --find strip)"
ffmpeg_flags=(
    --target-os=darwin
    --sysroot="$sdk_root"
    --cc="$clang"
    --host-cc="$clang"
    --host-cflags="-isysroot $sdk_root"
    --host-ldflags="-isysroot $sdk_root"
    --ar="$ar"
    --nm="$nm"
    --ranlib="$ranlib"
    --strip="$strip"
    --pkg-config=/usr/bin/false
    --disable-autodetect
    --disable-shared
    --enable-static
    --disable-debug
    --disable-doc
    --disable-ffplay
    --disable-network
    --disable-avdevice
    --enable-gpl
    --enable-version3
    --enable-videotoolbox
    --enable-audiotoolbox
    --enable-optimizations
    --enable-pic
)
for architecture in arm64 x86_64; do
    source_root="$build_root/ffmpeg-$architecture"
    mkdir "$source_root"
    tar -xJf "$ffmpeg_archive" -C "$source_root" --strip-components 1
    architecture_flags=(
        --arch="$architecture"
        --extra-cflags="-arch $architecture -mmacosx-version-min=13.0 -O2"
        --extra-ldflags="-arch $architecture -mmacosx-version-min=13.0"
    )
    if [[ "$architecture" == x86_64 ]]; then
        architecture_flags+=(--enable-cross-compile --x86asmexe="$nasm_binary")
    fi
    (
        cd "$source_root"
        PATH="$nasm_prefix/bin:/usr/bin:/bin" \
            ./configure "${ffmpeg_flags[@]}" "${architecture_flags[@]}" \
            > "$build_root/ffmpeg-$architecture-configure.log"
        PATH="$nasm_prefix/bin:/usr/bin:/bin" \
            make -j"$(sysctl -n hw.ncpu)" ffmpeg ffprobe \
            > "$build_root/ffmpeg-$architecture-build.log"
    )
    install -m 0755 "$source_root/ffmpeg" "$output_root/$architecture/ffmpeg"
    install -m 0755 "$source_root/ffprobe" "$output_root/$architecture/ffprobe"
    codesign --remove-signature "$output_root/$architecture/ffmpeg" 2>/dev/null || true
    codesign --remove-signature "$output_root/$architecture/ffprobe" 2>/dev/null || true
done

# Apple Silicon requires every executable code page to be signed. Apply a
# reproducible ad-hoc staging signature before calculating manifest hashes;
# release signing replaces it and reseals the manifests inside the app.
for architecture in arm64 x86_64; do
    codesign --force --sign - \
        "$output_root/$architecture/libs/libQt6Core.6.dylib"
    for tool in ffmpeg ffprobe mkvmerge mkvpropedit mkvextract; do
        codesign --force --sign - "$output_root/$architecture/$tool"
    done
done

# Copy source license evidence into the staged runtime.
tar -xOf "$ffmpeg_archive" "ffmpeg-$ffmpeg_version/COPYING.GPLv3" \
    > "$output_root/Licenses/FFmpeg-GPLv3.txt"
tar -xOf "$mkvtoolnix_source" "mkvtoolnix-$mkvtoolnix_version/COPYING" \
    > "$output_root/Licenses/MKVToolNix-GPL.txt"
mkdir "$output_root/Licenses/Qt"
tar -xJf "$qtbase_archive" -C "$output_root/Licenses/Qt" \
    --strip-components 1 "qtbase-everywhere-src-$qt_version/LICENSES"
chmod 0644 "$output_root/Licenses/FFmpeg-GPLv3.txt" \
    "$output_root/Licenses/MKVToolNix-GPL.txt"
find "$output_root/Licenses/Qt" -type f -exec chmod 0644 {} +

for architecture in arm64 x86_64; do
    architecture_root="$output_root/$architecture"
    ffmpeg_hash="$(shasum -a 256 "$architecture_root/ffmpeg" | awk '{print $1}')"
    ffprobe_hash="$(shasum -a 256 "$architecture_root/ffprobe" | awk '{print $1}')"
    mkvmerge_hash="$(shasum -a 256 "$architecture_root/mkvmerge" | awk '{print $1}')"
    mkvpropedit_hash="$(shasum -a 256 "$architecture_root/mkvpropedit" | awk '{print $1}')"
    mkvextract_hash="$(shasum -a 256 "$architecture_root/mkvextract" | awk '{print $1}')"
    qt_hash="$(shasum -a 256 "$architecture_root/libs/libQt6Core.6.dylib" | awk '{print $1}')"
    jq -n \
        --arg architecture "$architecture" \
        --arg ffmpegVersion "$ffmpeg_version" \
        --arg ffmpegURL "$ffmpeg_url" \
        --arg ffmpegHash "$ffmpeg_hash" \
        --arg ffprobeHash "$ffprobe_hash" \
        --arg mkvVersion "$mkvtoolnix_version" \
        --arg mkvURL "$mkvtoolnix_source_url" \
        --arg mkvmergeHash "$mkvmerge_hash" \
        --arg mkvpropeditHash "$mkvpropedit_hash" \
        --arg mkvextractHash "$mkvextract_hash" \
        --arg qtURL "$qtbase_url" \
        --arg qtHash "$qt_hash" \
        '{
          schema: "mkv-magic-tool-manifest-v1",
          platform: "macos",
          architecture: $architecture,
          tools: [
            {name: "ffmpeg", path: "ffmpeg", version: $ffmpegVersion, sha256: $ffmpegHash, license: "GPL-3.0-or-later", source: $ffmpegURL},
            {name: "ffprobe", path: "ffprobe", version: $ffmpegVersion, sha256: $ffprobeHash, license: "GPL-3.0-or-later", source: $ffmpegURL},
            {name: "mkvmerge", path: "mkvmerge", version: $mkvVersion, sha256: $mkvmergeHash, license: "GPL-2.0-or-later", source: $mkvURL},
            {name: "mkvpropedit", path: "mkvpropedit", version: $mkvVersion, sha256: $mkvpropeditHash, license: "GPL-2.0-or-later", source: $mkvURL},
            {name: "mkvextract", path: "mkvextract", version: $mkvVersion, sha256: $mkvextractHash, license: "GPL-2.0-or-later", source: $mkvURL}
          ],
          libraries: [
            {path: "libs/libQt6Core.6.dylib", sha256: $qtHash, license: "LGPL-3.0-only", source: $qtURL}
          ]
        }' > "$architecture_root/manifest.json"
    chmod 0644 "$architecture_root/manifest.json"
done

jq -n \
    --arg ffmpegVersion "$ffmpeg_version" \
    --arg ffmpegURL "$ffmpeg_url" \
    --arg ffmpegSha256 "$ffmpeg_sha256" \
    --arg nasmVersion "$nasm_version" \
    --arg nasmURL "$nasm_url" \
    --arg nasmSha256 "$nasm_sha256" \
    --arg mkvVersion "$mkvtoolnix_version" \
    --arg mkvDMGURL "$mkvtoolnix_dmg_url" \
    --arg mkvDMGSha256 "$mkvtoolnix_dmg_sha256" \
    --arg mkvSourceURL "$mkvtoolnix_source_url" \
    --arg mkvSourceSha256 "$mkvtoolnix_source_sha256" \
    --arg qtVersion "$qt_version" \
    --arg qtURL "$qtbase_url" \
    --arg qtSha256 "$qtbase_sha256" \
    '{
      schema: "mkv-magic-tool-sources-v1",
      minimumMacOS: "13.0",
      ffmpeg: {version: $ffmpegVersion, url: $ffmpegURL, sha256: $ffmpegSha256, network: false, license: "GPL-3.0-or-later"},
      nasm: {version: $nasmVersion, url: $nasmURL, sha256: $nasmSha256, buildOnly: true, license: "BSD-2-Clause"},
      mkvtoolnix: {version: $mkvVersion, binaryURL: $mkvDMGURL, binarySha256: $mkvDMGSha256, sourceURL: $mkvSourceURL, sourceSha256: $mkvSourceSha256, license: "GPL-2.0-or-later"},
      qtbase: {version: $qtVersion, url: $qtURL, sha256: $qtSha256, license: "LGPL-3.0-only"}
    }' > "$output_root/SOURCES.json"
chmod 0644 "$output_root/SOURCES.json"

"$repo_root/scripts/ci/check-tool-tree.sh" "$output_root"
for architecture in arm64 x86_64; do
    if [[ "$architecture" == arm64 ]]; then
        runner=(/usr/bin/arch -arm64)
    else
        runner=(/usr/bin/arch -x86_64)
    fi
    "${runner[@]}" "$output_root/$architecture/ffmpeg" -hide_banner -version >/dev/null
    "${runner[@]}" "$output_root/$architecture/ffprobe" -hide_banner -version >/dev/null
    "${runner[@]}" "$output_root/$architecture/mkvmerge" --version >/dev/null
    "${runner[@]}" "$output_root/$architecture/mkvpropedit" --version >/dev/null
    "${runner[@]}" "$output_root/$architecture/mkvextract" --version >/dev/null

    encoders="$("${runner[@]}" "$output_root/$architecture/ffmpeg" -hide_banner -encoders)"
    for encoder in aac aac_at h264_videotoolbox hevc_videotoolbox prores_ks; do
        if ! grep -Eq "[[:space:]]${encoder}[[:space:]]" <<< "$encoders"; then
            echo "missing required $architecture FFmpeg encoder: $encoder" >&2
            exit 1
        fi
    done
    filters="$("${runner[@]}" "$output_root/$architecture/ffmpeg" -hide_banner -filters)"
    for filter in aformat anullsrc aresample asetpts atrim channelmap concat format pad scale setpts setsar; do
        if ! grep -Eq "[[:space:]]${filter}[[:space:]]" <<< "$filters"; then
            echo "missing required $architecture FFmpeg filter: $filter" >&2
            exit 1
        fi
    done
    decoders="$("${runner[@]}" "$output_root/$architecture/ffmpeg" -hide_banner -decoders)"
    if ! grep -Eq '[[:space:]]av1[[:space:]]' <<< "$decoders"; then
        echo "missing required $architecture FFmpeg AV1 decoder" >&2
        exit 1
    fi
    protocols="$("${runner[@]}" "$output_root/$architecture/ffmpeg" -hide_banner -protocols)"
    if grep -Eq '^[[:space:]]*(http|https|tcp|udp|rtmp|srtp|sctp|tls)[[:space:]]*$' \
        <<< "$protocols"; then
        echo "$architecture FFmpeg unexpectedly enables network protocols" >&2
        exit 1
    fi
done
echo "$output_root"
