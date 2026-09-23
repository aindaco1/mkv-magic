#!/usr/bin/env bash
set -euo pipefail

mkv_magic_verification_architectures() {
    if [[ $# -ne 1 ]]; then
        echo "usage: mkv_magic_verification_architectures <architecture-list>" >&2
        return 64
    fi
    case "$1" in
        arm64) printf 'arm64\n' ;;
        x86_64) printf 'x86_64\n' ;;
        'arm64 x86_64') printf 'arm64\nx86_64\n' ;;
        *)
            echo "verification architectures must be arm64, x86_64, or arm64 x86_64" >&2
            return 64
            ;;
    esac
}

mkv_magic_native_verification_architecture_for() {
    if [[ $# -ne 2 ]]; then
        echo "usage: mkv_magic_native_verification_architecture_for <machine-architecture> <arm64-capable>" >&2
        return 64
    fi
    local machine_architecture="$1"
    local arm64_capable="$2"
    if [[ "$arm64_capable" == 1 ]]; then
        printf 'arm64\n'
        return
    fi
    case "$machine_architecture" in
        arm64) printf 'arm64\n' ;;
        x86_64) printf 'x86_64\n' ;;
        *)
            echo "unsupported verification host architecture" >&2
            return 64
            ;;
    esac
}

mkv_magic_native_verification_architecture() {
    local arm64_capable
    arm64_capable="$(/usr/sbin/sysctl -in hw.optional.arm64 2>/dev/null || true)"
    mkv_magic_native_verification_architecture_for \
        "$(/usr/bin/uname -m)" "$arm64_capable"
}

mkv_magic_require_native_verification() {
    if [[ $# -ne 3 ]]; then
        echo "usage: mkv_magic_require_native_verification <architecture-list> <native-architecture> <allow-translated>" >&2
        return 64
    fi
    local architecture_list="$1"
    local native_architecture="$2"
    local allow_translated="$3"
    local architectures
    architectures="$(mkv_magic_verification_architectures "$architecture_list")" || return
    local architecture
    while IFS= read -r architecture; do
        if [[ "$architecture" != "$native_architecture" && \
              "$allow_translated" != 1 ]]; then
            echo "refusing translated $architecture verification on a $native_architecture host; use physical hardware or explicitly set MKV_MAGIC_ALLOW_TRANSLATED_VERIFICATION=1" >&2
            return 1
        fi
    done <<< "$architectures"
}

canonical_existing_path() {
    local input_path="$1"
    local directory
    directory="$(cd "$(dirname "$input_path")" && pwd -P)" || return 1
    printf '%s/%s\n' "$directory" "$(basename "$input_path")"
}

detach_exact_dmg_image() {
    local dmg_path="$1"
    local expected_path
    expected_path="$(canonical_existing_path "$dmg_path")" || return 0
    local current_image=''
    local line
    while IFS= read -r line; do
        if [[ "$line" == image-path*:* ]]; then
            local reported_path="${line#*: }"
            current_image="$(canonical_existing_path "$reported_path" 2>/dev/null || true)"
            continue
        fi
        if [[ "$current_image" == "$expected_path" && \
              "$line" =~ ^(/dev/disk[0-9]+)[[:space:]] ]]; then
            local whole_device="${BASH_REMATCH[1]}"
            hdiutil detach "$whole_device" -quiet 2>/dev/null || \
                hdiutil detach "$whole_device" -force -quiet 2>/dev/null
            return 0
        fi
    done < <(hdiutil info)
}

verify_mkv_magic_dmg_checksum() {
    local dmg_path="$1"
    local attempt
    for attempt in 1 2; do
        if hdiutil verify "$dmg_path"; then
            return 0
        fi
        if [[ "$attempt" == 1 ]]; then
            echo "DMG verification failed once; detaching only this image and retrying" >&2
            detach_exact_dmg_image "$dmg_path"
        fi
    done
    return 1
}
