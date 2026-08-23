#!/usr/bin/env bash
set -euo pipefail

MKV_MAGIC_DMG_APP_NAME='MKV Magic.app'
MKV_MAGIC_DMG_APPLICATIONS_NAME='Applications'
MKV_MAGIC_DMG_APPLICATIONS_TARGET='/Applications'

validate_mkv_magic_dmg_layout() {
    local layout_root="$1"
    if [[ "$layout_root" != /* || ! -d "$layout_root" || -L "$layout_root" ]]; then
        echo "unsafe DMG layout root" >&2
        return 1
    fi
    local entries
    entries="$(find "$layout_root" -mindepth 1 -maxdepth 1 -print | sort)"
    local expected
    expected="$(printf '%s\n%s\n' \
        "$layout_root/$MKV_MAGIC_DMG_APPLICATIONS_NAME" \
        "$layout_root/$MKV_MAGIC_DMG_APP_NAME" | sort)"
    if [[ "$entries" != "$expected" ]]; then
        echo "DMG must contain exactly MKV Magic.app and Applications" >&2
        return 1
    fi
    if [[ ! -d "$layout_root/$MKV_MAGIC_DMG_APP_NAME" || \
          -L "$layout_root/$MKV_MAGIC_DMG_APP_NAME" ]]; then
        echo "DMG app entry is missing or unsafe" >&2
        return 1
    fi
    if [[ ! -L "$layout_root/$MKV_MAGIC_DMG_APPLICATIONS_NAME" || \
          "$(readlink "$layout_root/$MKV_MAGIC_DMG_APPLICATIONS_NAME")" != \
              "$MKV_MAGIC_DMG_APPLICATIONS_TARGET" ]]; then
        echo "DMG Applications link is missing or incorrect" >&2
        return 1
    fi
}
