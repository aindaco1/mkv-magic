#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-verified-tool-runtime>" >&2
    exit 64
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tool_root="$1"
release_root="${MKV_MAGIC_RELEASE_ROOT:-$repo_root/.build/release-artifacts}"
cache_root="${MKV_MAGIC_TOOL_CACHE:-$repo_root/.build/tool-sources}"
app_path="$release_root/MKV Magic.app"
if [[ ! -d "$tool_root" || -L "$tool_root" || \
      ! -f "$tool_root/SOURCES.json" || -L "$tool_root/SOURCES.json" || \
      ! -d "$app_path" || -L "$app_path" || \
      ! -d "$cache_root" || -L "$cache_root" ]]; then
    echo "source bundle inputs are missing or unsafe" >&2
    exit 1
fi
"$repo_root/scripts/ci/check-tool-tree.sh" "$tool_root"

version="$(plutil -extract CFBundleShortVersionString raw -o - \
    "$app_path/Contents/Info.plist")"
archive="$release_root/MKV-Magic-$version-corresponding-source.zip"
if [[ -e "$archive" ]]; then
    echo "refusing to replace source bundle: $archive" >&2
    exit 1
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-source-bundle.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$work_root"
}
trap cleanup EXIT
bundle_root="$work_root/MKV-Magic-$version-corresponding-source"
mkdir -p "$bundle_root/dependencies"
install -m 0644 "$tool_root/SOURCES.json" "$bundle_root/SOURCES.json"

copy_verified_source() {
    local cache_path="$1"
    local expected_hash="$2"
    if [[ "$cache_path" != "$cache_root"/* || ! -f "$cache_path" || \
          -L "$cache_path" || ! "$expected_hash" =~ ^[a-f0-9]{64}$ ]]; then
        echo "source cache input is missing or unsafe: $cache_path" >&2
        exit 1
    fi
    local actual_hash
    actual_hash="$(shasum -a 256 "$cache_path" | awk '{print $1}')"
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        echo "source cache checksum mismatch: $cache_path" >&2
        exit 1
    fi
    install -m 0644 "$cache_path" "$bundle_root/dependencies/$(basename "$cache_path")"
}

sources="$tool_root/SOURCES.json"
ffmpeg_version="$(jq -r '.ffmpeg.version' "$sources")"
nasm_version="$(jq -r '.nasm.version' "$sources")"
svtav1_version="$(jq -r '.svtav1.version' "$sources")"
dav1d_version="$(jq -r '.dav1d.version' "$sources")"
mkvtoolnix_version="$(jq -r '.mkvtoolnix.version' "$sources")"
qt_version="$(jq -r '.qtbase.version' "$sources")"
copy_verified_source \
    "$cache_root/ffmpeg-$ffmpeg_version/ffmpeg-$ffmpeg_version.tar.xz" \
    "$(jq -r '.ffmpeg.sha256' "$sources")"
copy_verified_source \
    "$cache_root/nasm-$nasm_version/nasm-$nasm_version.tar.xz" \
    "$(jq -r '.nasm.sha256' "$sources")"
copy_verified_source \
    "$cache_root/svt-av1-$svtav1_version/SVT-AV1-v$svtav1_version.tar.gz" \
    "$(jq -r '.svtav1.sha256' "$sources")"
copy_verified_source \
    "$cache_root/dav1d-$dav1d_version/dav1d-$dav1d_version.tar.bz2" \
    "$(jq -r '.dav1d.sha256' "$sources")"
copy_verified_source \
    "$cache_root/mkvtoolnix-$mkvtoolnix_version/mkvtoolnix-$mkvtoolnix_version.tar.xz" \
    "$(jq -r '.mkvtoolnix.sourceSha256' "$sources")"
copy_verified_source \
    "$cache_root/qtbase-$qt_version/qtbase-everywhere-src-$qt_version.tar.xz" \
    "$(jq -r '.qtbase.sha256' "$sources")"

git -C "$repo_root" diff --quiet -- .
git -C "$repo_root" diff --cached --quiet -- .
git -C "$repo_root" archive --format=tar.gz \
    --prefix="mkv-magic-$version/" HEAD \
    > "$bundle_root/MKV-Magic-$version-source.tar.gz"
install -m 0644 "$repo_root/docs/CORRESPONDING_SOURCE.md" \
    "$bundle_root/README.md"

COPYFILE_DISABLE=1 ditto --norsrc --noextattr -c -k --keepParent \
    "$bundle_root" "$archive"
echo "$archive"
