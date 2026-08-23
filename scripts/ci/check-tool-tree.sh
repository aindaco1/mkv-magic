#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-Tools-directory>" >&2
    exit 64
fi
tool_root="$1"
if [[ ! -d "$tool_root" || -L "$tool_root" ]]; then
    echo "missing or unsafe tool root" >&2
    exit 1
fi
expected_tools=(ffmpeg ffprobe mkvmerge mkvpropedit mkvextract)
for architecture in arm64 x86_64; do
    architecture_root="$tool_root/$architecture"
    manifest="$architecture_root/manifest.json"
    if [[ ! -d "$architecture_root" || -L "$architecture_root" || \
          ! -f "$manifest" || -L "$manifest" ]]; then
        echo "missing or unsafe $architecture tool tree" >&2
        exit 1
    fi
    schema="$(jq -r '.schema' "$manifest")"
    manifest_architecture="$(jq -r '.architecture' "$manifest")"
    manifest_platform="$(jq -r '.platform' "$manifest")"
    keys="$(jq -r 'keys | sort | join(",")' "$manifest")"
    if [[ "$schema" != mkv-magic-tool-manifest-v1 || \
          "$manifest_architecture" != "$architecture" || \
          "$manifest_platform" != macos || \
          "$keys" != architecture,libraries,platform,schema,tools ]]; then
        echo "invalid $architecture tool manifest identity" >&2
        exit 1
    fi
    if [[ "$(jq '.tools | length' "$manifest")" -ne 5 ]]; then
        echo "$architecture tool manifest must contain exactly five tools" >&2
        exit 1
    fi
    for tool in "${expected_tools[@]}"; do
        tool_path="$architecture_root/$tool"
        if [[ ! -f "$tool_path" || -L "$tool_path" || ! -x "$tool_path" ]]; then
            echo "missing or unsafe $architecture tool: $tool" >&2
            exit 1
        fi
        manifest_path="$(jq -r --arg name "$tool" '.tools[] | select(.name == $name) | .path' "$manifest")"
        expected_hash="$(jq -r --arg name "$tool" '.tools[] | select(.name == $name) | .sha256' "$manifest")"
        if [[ "$manifest_path" != "$tool" || ! "$expected_hash" =~ ^[a-f0-9]{64}$ ]]; then
            echo "invalid manifest entry for $architecture/$tool" >&2
            exit 1
        fi
        actual_hash="$(shasum -a 256 "$tool_path" | awk '{print $1}')"
        if [[ "$actual_hash" != "$expected_hash" ]]; then
            echo "hash mismatch for $architecture/$tool" >&2
            exit 1
        fi
        tool_architectures="$(lipo -archs "$tool_path")"
        if [[ "$tool_architectures" != "$architecture" ]]; then
            echo "wrong architecture for $tool_path: $tool_architectures" >&2
            exit 1
        fi
        codesign --verify --strict "$tool_path"
    done
    while IFS= read -r library_path; do
        if [[ "$library_path" != libs/* || "$library_path" == *..* ]]; then
            echo "invalid library path in $architecture manifest" >&2
            exit 1
        fi
        library="$architecture_root/$library_path"
        expected_hash="$(
            jq -r --arg path "$library_path" \
                '.libraries[] | select(.path == $path) | .sha256' "$manifest"
        )"
        if [[ ! -f "$library" || -L "$library" || \
              ! "$expected_hash" =~ ^[a-f0-9]{64}$ ]]; then
            echo "missing or unsafe runtime library: $architecture/$library_path" >&2
            exit 1
        fi
        actual_hash="$(shasum -a 256 "$library" | awk '{print $1}')"
        library_architectures="$(lipo -archs "$library")"
        if [[ "$actual_hash" != "$expected_hash" || \
              "$library_architectures" != "$architecture" ]]; then
            echo "runtime library verification failed: $architecture/$library_path" >&2
            exit 1
        fi
    done < <(jq -r '.libraries[].path' "$manifest")

    for relative_binary in "${expected_tools[@]}" libs/libQt6Core.6.dylib; do
        binary="$architecture_root/$relative_binary"
        minimum_versions="$(
            otool -l "$binary" \
                | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; found=0}' \
                | sort -u
        )"
        if [[ "$minimum_versions" != 13.0 ]]; then
            echo "unexpected deployment target for $binary: $minimum_versions" >&2
            exit 1
        fi
        while IFS= read -r dependency; do
            case "$dependency" in
                /System/Library/*|/usr/lib/*) ;;
                @executable_path/libs/libQt6Core.6.dylib)
                    case "$relative_binary" in
                        mkvmerge|mkvpropedit|mkvextract) ;;
                        *) echo "unexpected Qt dependency for $binary" >&2; exit 1 ;;
                    esac
                    ;;
                @rpath/libQt6Core.6.dylib)
                    if [[ "$relative_binary" != libs/libQt6Core.6.dylib ]]; then
                        echo "unexpected Qt install name for $binary" >&2
                        exit 1
                    fi
                    ;;
                *)
                    echo "unpackaged dynamic dependency for $binary: $dependency" >&2
                    exit 1
                    ;;
            esac
        done < <(
            otool -L "$binary" | tail -n +2 \
                | sed -E 's/^[[:space:]]*//; s/[[:space:]]+\(compatibility.*$//'
        )
    done
done

while IFS= read -r -d '' link_path; do
    target="$(readlink "$link_path")"
    if [[ "$target" == /* ]]; then
        echo "tool tree contains an absolute symlink: $link_path" >&2
        exit 1
    fi
    if ! realpath "$link_path" >/dev/null 2>&1; then
        echo "tool tree contains a dangling symlink: $link_path" >&2
        exit 1
    fi
    resolved="$(realpath "$link_path")"
    case "$resolved" in
        "$tool_root"/*) ;;
        *) echo "tool tree contains an escaping symlink: $link_path" >&2; exit 1 ;;
    esac
done < <(find "$tool_root" -type l -print0)
