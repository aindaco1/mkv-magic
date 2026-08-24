#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/dmg-verification.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-dmg-helper.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$fixture_root"
}
trap cleanup EXIT
dmg_path="$fixture_root/MKV-Magic-0.0.0-universal.dmg"
: > "$dmg_path"

verify_calls=0
detached_device=''
hdiutil() {
    case "$1" in
        verify)
            verify_calls=$((verify_calls + 1))
            [[ "$verify_calls" -gt 1 ]]
            ;;
        info)
            printf 'image-path      : %s\n/dev/disk91\tGUID_partition_scheme\t\n' "$dmg_path"
            ;;
        detach)
            detached_device="$2"
            ;;
        *)
            return 64
            ;;
    esac
}

verify_mkv_magic_dmg_checksum "$dmg_path"
if [[ "$verify_calls" -ne 2 || "$detached_device" != /dev/disk91 ]]; then
    echo "DMG verification retry did not detach exactly its own whole device" >&2
    exit 1
fi

verify_calls=0
detached_device=''
hdiutil() {
    case "$1" in
        verify)
            verify_calls=$((verify_calls + 1))
            return 1
            ;;
        info)
            printf 'image-path      : %s\n/dev/disk92\tGUID_partition_scheme\t\n' \
                "$fixture_root/Some-Other-App.dmg"
            ;;
        detach)
            detached_device="$2"
            ;;
        *)
            return 64
            ;;
    esac
}
if verify_mkv_magic_dmg_checksum "$dmg_path"; then
    echo "DMG verification unexpectedly accepted two failures" >&2
    exit 1
fi
if [[ "$verify_calls" -ne 2 || -n "$detached_device" ]]; then
    echo "DMG verification retry touched an unrelated image" >&2
    exit 1
fi
echo "DMG verification retry tests passed"
