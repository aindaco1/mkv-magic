#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
icon_path="${1:-$repo_root/Assets/AppIcon/MKVMagic.icns}"
master_path="${2:-}"

if [[ "$icon_path" != /* || ! -f "$icon_path" || -L "$icon_path" ]]; then
    echo "missing or unsafe MKV Magic app icon: $icon_path" >&2
    exit 1
fi
if [[ -n "$master_path" && \
      ( "$master_path" != /* || ! -f "$master_path" || -L "$master_path" ) ]]; then
    echo "missing or unsafe MKV Magic app icon master: $master_path" >&2
    exit 1
fi

read_png_property() {
    local file_path="$1"
    local property="$2"
    /usr/bin/sips -g "$property" "$file_path" 2>/dev/null \
        | /usr/bin/awk -v key="$property:" '$1 == key { print $2 }'
}

if [[ -n "$master_path" ]]; then
    master_width="$(read_png_property "$master_path" pixelWidth)"
    master_height="$(read_png_property "$master_path" pixelHeight)"
    master_alpha="$(read_png_property "$master_path" hasAlpha)"
    if [[ "$master_width" != 1024 || "$master_height" != 1024 || \
          "$master_alpha" != yes ]]; then
        echo "app icon master must be a 1024 x 1024 PNG with alpha" >&2
        exit 1
    fi
fi

validation_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-icon.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$validation_root"
}
trap cleanup EXIT
expanded_iconset="$validation_root/MKVMagic.iconset"
/usr/bin/iconutil -c iconset "$icon_path" -o "$expanded_iconset"

names=(
    icon_16x16.png
    icon_16x16@2x.png
    icon_32x32.png
    icon_32x32@2x.png
    icon_128x128.png
    icon_128x128@2x.png
    icon_256x256.png
    icon_256x256@2x.png
    icon_512x512.png
    icon_512x512@2x.png
)
sizes=(16 32 32 64 128 256 256 512 512 1024)

for index in "${!names[@]}"; do
    representation="$expanded_iconset/${names[$index]}"
    if [[ ! -f "$representation" || -L "$representation" ]]; then
        echo "app icon is missing ${names[$index]}" >&2
        exit 1
    fi
    width="$(read_png_property "$representation" pixelWidth)"
    height="$(read_png_property "$representation" pixelHeight)"
    alpha="$(read_png_property "$representation" hasAlpha)"
    if [[ "$width" != "${sizes[$index]}" || \
          "$height" != "${sizes[$index]}" || "$alpha" != yes ]]; then
        echo "invalid app icon representation: ${names[$index]}" >&2
        exit 1
    fi
done

representation_count="$(find "$expanded_iconset" -type f -name '*.png' | wc -l | tr -d ' ')"
if [[ "$representation_count" != "${#names[@]}" ]]; then
    echo "app icon contains unexpected representations" >&2
    exit 1
fi

echo "app icon passed"
