#!/usr/bin/env bash

architecture_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/architecture.sh"
# shellcheck source=scripts/ci/architecture.sh
source "$architecture_script"

mkv_magic_require_exact_children() {
    local directory="$1"
    local context="$2"
    shift 2
    if [[ ! -d "$directory" || -L "$directory" ]]; then
        echo "missing or unsafe $context directory" >&2
        return 1
    fi
    local expected
    local actual
    expected="$(printf '%s\n' "$@" | LC_ALL=C sort)"
    actual="$({
        find "$directory" -mindepth 1 -maxdepth 1 -exec basename {} \;
    } | LC_ALL=C sort)"
    if [[ "$actual" != "$expected" ]]; then
        echo "$context layout contains missing or unexpected entries" >&2
        return 1
    fi
}

validate_mkv_magic_tool_tree_layout() {
    if [[ $# -ne 1 || "$1" != /* ]]; then
        echo "usage: validate_mkv_magic_tool_tree_layout <absolute-Tools-directory>" >&2
        return 64
    fi
    local tool_root="$1"
    mkv_magic_require_exact_children "$tool_root" "tool root" \
        Licenses SOURCES.json universal || return 1

    if [[ ! -s "$tool_root/SOURCES.json" || -L "$tool_root/SOURCES.json" ]]; then
        echo "tool source manifest is missing or unsafe" >&2
        return 1
    fi

    local runtime_root="$tool_root/universal"
    local runtime_children=(
        ffmpeg ffprobe libs manifest.json mkvextract mkvmerge mkvpropedit
    )
    if [[ -e "$runtime_root/build-manifest.json" ]]; then
        runtime_children+=(build-manifest.json)
    fi
    mkv_magic_require_exact_children "$runtime_root" \
        "Universal tool tree" "${runtime_children[@]}" || return 1
    mkv_magic_require_exact_children "$runtime_root/libs" \
        "Universal library tree" libQt6Core.6.dylib || return 1
    local relative_file
    for relative_file in \
        ffmpeg ffprobe manifest.json mkvextract mkvmerge mkvpropedit \
        libs/libQt6Core.6.dylib
    do
        if [[ ! -s "$runtime_root/$relative_file" || \
              -L "$runtime_root/$relative_file" ]]; then
            echo "tool layout file is missing or unsafe: universal/$relative_file" >&2
            return 1
        fi
    done
    if [[ -e "$runtime_root/build-manifest.json" && \
          (! -s "$runtime_root/build-manifest.json" || \
           -L "$runtime_root/build-manifest.json") ]]; then
        echo "build manifest is unsafe: universal/build-manifest.json" >&2
        return 1
    fi

    local license_root="$tool_root/Licenses"
    mkv_magic_require_exact_children "$license_root" "runtime license tree" \
        FFmpeg-GPLv3.txt MKVToolNix-GPL.txt Opus Qt SVT-AV1 dav1d zimg \
        || return 1
    mkv_magic_require_exact_children "$license_root/SVT-AV1" \
        "SVT-AV1 license tree" LICENSE.md PATENTS.md || return 1
    mkv_magic_require_exact_children "$license_root/dav1d" \
        "dav1d license tree" COPYING || return 1
    mkv_magic_require_exact_children "$license_root/Opus" \
        "Opus license tree" COPYING || return 1
    mkv_magic_require_exact_children "$license_root/zimg" \
        "zimg license tree" COPYING || return 1
    mkv_magic_require_exact_children "$license_root/Qt" \
        "Qt license tree" LICENSES || return 1

    local directory_path
    while IFS= read -r -d '' directory_path; do
        local relative_directory="${directory_path#"$license_root"/}"
        case "$relative_directory" in
            Opus | Qt | Qt/LICENSES | SVT-AV1 | dav1d | zimg) ;;
            *)
                echo "runtime license tree contains an unexpected directory" >&2
                return 1
                ;;
        esac
    done < <(find "$license_root" -mindepth 1 -type d -print0)

    local license_count=0
    local license_bytes=0
    local license_path
    while IFS= read -r -d '' license_path; do
        if [[ ! -f "$license_path" || -L "$license_path" || \
              ! -s "$license_path" || -x "$license_path" ]]; then
            echo "runtime license tree contains an unsafe document" >&2
            return 1
        fi
        local relative_license="${license_path#"$license_root"/}"
        case "$relative_license" in
            FFmpeg-GPLv3.txt | MKVToolNix-GPL.txt | \
            Opus/COPYING | SVT-AV1/LICENSE.md | SVT-AV1/PATENTS.md | \
            dav1d/COPYING | zimg/COPYING)
                ;;
            Qt/LICENSES/*.txt)
                if [[ ! "${relative_license##*/}" =~ ^[A-Za-z0-9._+-]+\.txt$ ]]; then
                    echo "Qt license document has an unsafe name" >&2
                    return 1
                fi
                ;;
            *)
                echo "runtime license tree contains an unexpected document" >&2
                return 1
                ;;
        esac
        local bytes
        bytes="$(stat -f '%z' "$license_path")"
        if [[ "$bytes" -gt 2097152 ]]; then
            echo "runtime license document exceeds the size limit" >&2
            return 1
        fi
        license_count=$((license_count + 1))
        license_bytes=$((license_bytes + bytes))
    done < <(find "$license_root" -type f -print0)
    if [[ "$license_count" -lt 8 || "$license_count" -gt 128 || \
          "$license_bytes" -gt 8388608 ]]; then
        echo "runtime license tree exceeds its count or aggregate size limit" >&2
        return 1
    fi

    local special_path
    while IFS= read -r -d '' special_path; do
        if [[ ! -d "$special_path" && ! -f "$special_path" ]]; then
            echo "tool tree contains a symbolic link or special file" >&2
            return 1
        fi
    done < <(find "$tool_root" -mindepth 1 -print0)
}
