#!/usr/bin/env bash
set -euo pipefail

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
