#!/usr/bin/env bash

mkv_magic_is_universal_architecture_set() {
    if [[ $# -ne 1 ]]; then
        echo "usage: mkv_magic_is_universal_architecture_set <lipo-architectures>" >&2
        return 64
    fi
    [[ "$1" == "arm64 x86_64" || "$1" == "x86_64 arm64" ]]
}

mkv_magic_require_universal_mach_o_inventory() {
    if [[ $# -ne 2 || "$1" != /* || ! -d "$1" || -L "$1" ]]; then
        echo "usage: mkv_magic_require_universal_mach_o_inventory <absolute-directory> <label>" >&2
        return 64
    fi
    local directory="$1"
    local label="$2"
    local binary_count=0
    local candidate
    while IFS= read -r -d '' candidate; do
        if file -b "$candidate" | grep -q 'Mach-O'; then
            local architectures
            architectures="$(lipo -archs "$candidate")"
            if ! mkv_magic_is_universal_architecture_set "$architectures"; then
                echo "$label contains a non-Universal Mach-O: $candidate ($architectures)" >&2
                return 1
            fi
            binary_count=$((binary_count + 1))
        fi
    done < <(find "$directory" -type f -print0)
    if [[ "$binary_count" -eq 0 ]]; then
        echo "$label contains no Mach-O code" >&2
        return 1
    fi
}
