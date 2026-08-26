#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/ci/tool-source-cache.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-source-cache-test.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT
cache_root="$test_root/cache"
sources="$test_root/SOURCES.json"
mkdir "$cache_root"

make_source() {
    local relative_path="$1"
    local content="$2"
    mkdir -p "$cache_root/$(dirname "$relative_path")"
    printf '%s\n' "$content" > "$cache_root/$relative_path"
    shasum -a 256 "$cache_root/$relative_path" | awk '{print $1}'
}

ffmpeg_hash="$(make_source ffmpeg-9.0.1/ffmpeg-9.0.1.tar.xz ffmpeg)"
nasm_hash="$(make_source nasm-3.02/nasm-3.02.tar.xz nasm)"
svtav1_hash="$(make_source svt-av1-4.1.0/SVT-AV1-v4.1.0.tar.gz svtav1)"
dav1d_hash="$(make_source dav1d-1.5.4/dav1d-1.5.4.tar.xz dav1d)"
opus_hash="$(make_source opus-1.6.1/opus-1.6.1.tar.gz opus)"
zimg_hash="$(make_source zimg-3.0.6/zimg-release-3.0.6.tar.gz zimg)"
mkv_hash="$(make_source mkvtoolnix-101.0/mkvtoolnix-101.0.tar.xz mkvtoolnix)"
qt_hash="$(make_source qtbase-6.11.1/qtbase-everywhere-src-6.11.1.tar.xz qtbase)"
jq -n \
    --arg ffmpeg "$ffmpeg_hash" --arg nasm "$nasm_hash" \
    --arg svtav1 "$svtav1_hash" --arg dav1d "$dav1d_hash" \
    --arg opus "$opus_hash" --arg zimg "$zimg_hash" \
    --arg mkv "$mkv_hash" --arg qt "$qt_hash" \
    '{
      ffmpeg: {version: "9.0.1", sha256: $ffmpeg},
      nasm: {version: "3.02", sha256: $nasm},
      svtav1: {version: "4.1.0", sha256: $svtav1},
      dav1d: {version: "1.5.4", sha256: $dav1d},
      opus: {version: "1.6.1", sha256: $opus},
      zimg: {version: "3.0.6", sha256: $zimg},
      mkvtoolnix: {version: "101.0", sourceSha256: $mkv},
      qtbase: {version: "6.11.1", sha256: $qt}
    }' > "$sources"

mkv_magic_verify_tool_source_cache "$cache_root" "$sources"
copied="$test_root/copied"
mkv_magic_copy_tool_source_cache "$cache_root" "$sources" "$copied"
mkv_magic_verify_tool_source_cache "$copied" "$sources"
if find "$copied" -type f | grep -q 'MKVToolNix-101.0-1-universal.dmg'; then
    echo "corresponding source cache unexpectedly copied the binary DMG" >&2
    exit 1
fi

printf 'tampered\n' > "$cache_root/ffmpeg-9.0.1/ffmpeg-9.0.1.tar.xz"
if mkv_magic_verify_tool_source_cache "$cache_root" "$sources" >/dev/null 2>&1; then
    echo "tool source cache verifier accepted tampered input" >&2
    exit 1
fi
echo "tool source cache tests passed"
